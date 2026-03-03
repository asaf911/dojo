import Foundation
import CoreBluetooth

/// Heart rate provider for Fitbit devices via Bluetooth Low Energy.
/// Uses the standard BLE Heart Rate Profile:
///   - Service:        0x180D (Heart Rate)
///   - Characteristic: 0x2A37 (Heart Rate Measurement)
///
/// On start(): if a device UUID is already saved from a prior pairing session,
/// connects directly. Otherwise scans for peripherals advertising 0x180D
/// whose name contains "fitbit".
final class FitbitHRProvider: NSObject, HeartRateProvider {

    // MARK: - HeartRateProvider

    let priority: Int = 3

    /// Available when HR monitoring is enabled AND the user either has a previously bonded
    /// device (fast reconnect) or has the Fitbit app installed (may enable HR on Equipment).
    var isAvailable: Bool {
        let hrEnabled = SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false)
        guard hrEnabled else { return false }
        let hasKnownDevice = SharedUserStorage.retrieve(forKey: .fitbitDeviceUUID, as: String.self) != nil
        return hasKnownDevice || FitbitDetector.isFitbitAppInstalled
    }

    /// Logs the current BLE and pairing state for diagnostics.
    func logDiagnostics() {
        let uuid = SharedUserStorage.retrieve(forKey: .fitbitDeviceUUID, as: String.self)
        let name = SharedUserStorage.retrieve(forKey: .fitbitDeviceName, as: String.self)
        if let uuid, let name {
            HRDebugLogger.log(.fitbit, "Previously bonded device: '\(name)' UUID=\(uuid)")
        } else {
            HRDebugLogger.log(.fitbit, "No previously bonded device — will scan for any BLE HRM (0x180D)")
            HRDebugLogger.log(.fitbit, "Enable HR on Equipment on your Fitbit Charge 6 or Pixel Watch to connect")
        }
        HRDebugLogger.log(.fitbit, "isAvailable=\(isAvailable) isRunning=\(isRunning)")
        if let peripheral {
            HRDebugLogger.log(.fitbit, "Peripheral state: \(peripheral.state.rawValue) name=\(peripheral.name ?? "nil")")
        }
    }

    private(set) var lastSampleDate: Date?

    /// True when we have an active BLE connection to the Charge 6 this session.
    /// Used by the UI to show the "Enable HR on Equipment" prompt in real time
    /// rather than relying on historical pairing status.
    var isBLEConnected: Bool {
        isRunning && peripheral?.state == .connected
    }

    // MARK: - BLE Constants

    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementUUID = CBUUID(string: "2A37")

    // MARK: - Private State

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var isRunning = false
    private var activeSessionId: String?

    // MARK: - HeartRateProvider Methods

    func start(sessionId: String) {
        guard !isRunning else {
            HRDebugLogger.log(.fitbit, "Already running — ignoring start")
            return
        }

        HRDebugLogger.log(.fitbit, "Starting for session \(sessionId)")
        isRunning = true
        activeSessionId = sessionId

        // CBCentralManager must be created on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.centralManager = CBCentralManager(delegate: self, queue: .main)
            // centralManagerDidUpdateState will trigger scan/connect once powered on
        }
    }

    func stop(sessionId: String) {
        guard isRunning else {
            HRDebugLogger.log(.fitbit, "Not running — ignoring stop")
            return
        }

        HRDebugLogger.log(.fitbit, "Stopping")
        isRunning = false
        activeSessionId = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.centralManager?.state == .poweredOn {
                self.centralManager?.stopScan()
            }
            if let p = self.peripheral {
                self.centralManager?.cancelPeripheralConnection(p)
            }
            self.peripheral = nil
            // Nil out the manager so it is fully deallocated between sessions.
            // This prevents stale Bluetooth state from a previous session (e.g. a Watch
            // session) from interfering when a new Fitbit session starts.
            self.centralManager = nil
        }
    }

    // MARK: - Private BLE Setup

    private func connectOrScan(using manager: CBCentralManager) {
        if let uuidString = SharedUserStorage.retrieve(forKey: .fitbitDeviceUUID, as: String.self),
           let uuid = UUID(uuidString: uuidString) {
            let deviceName = SharedUserStorage.retrieve(forKey: .fitbitDeviceName, as: String.self) ?? uuidString
            let known = manager.retrievePeripherals(withIdentifiers: [uuid])
            if let p = known.first {
                HRDebugLogger.log(.fitbit, "Known device '\(deviceName)' found in cache — connecting directly (no scan needed)")
                peripheral = p
                peripheral?.delegate = self
                manager.connect(p, options: nil)
                return
            }
            HRDebugLogger.warn(.fitbit, "Known UUID \(uuidString.prefix(8))... not in range — falling back to scan")
        } else {
            HRDebugLogger.log(.fitbit, "No previously bonded device — will scan all BLE peripherals and match by service or name")
            HRDebugLogger.log(.fitbit, "Enable HR on Equipment on Fitbit Charge 6 or Pixel Watch before or during this scan")
        }

        // Scan for ALL peripherals — Fitbit Charge 6 does NOT include 0x180D in its
        // advertisement packet; it only reveals the HR service after GATT connection.
        HRDebugLogger.log(.fitbit, "Scanning for ALL BLE peripherals (Charge 6 omits 0x180D from advertisements)...")
        manager.scanForPeripherals(withServices: nil, options: nil)
    }

    // MARK: - BLE HRM Characteristic Parsing

    /// Parses a BLE Heart Rate Measurement notification per the Bluetooth spec.
    /// Byte 0 flags: bit 0 = 0 → BPM is UInt8 (byte 1); bit 0 = 1 → BPM is UInt16 (bytes 1–2, little-endian).
    private func parseBPM(from data: Data) -> Double? {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        let bpm: Double
        if flags & 0x01 == 0 {
            bpm = Double(data[1])
        } else {
            guard data.count >= 3 else { return nil }
            bpm = Double(UInt16(data[1]) | (UInt16(data[2]) << 8))
        }
        return bpm > 0 ? bpm : nil
    }
}

// MARK: - CBCentralManagerDelegate

extension FitbitHRProvider: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateLabel: String
        switch central.state {
        case .poweredOn:      stateLabel = "poweredOn"
        case .poweredOff:     stateLabel = "poweredOff"
        case .unauthorized:   stateLabel = "unauthorized"
        case .unsupported:    stateLabel = "unsupported"
        case .resetting:      stateLabel = "resetting"
        case .unknown:        stateLabel = "unknown"
        @unknown default:     stateLabel = "unhandled(\(central.state.rawValue))"
        }
        HRDebugLogger.log(.fitbit, "Bluetooth state: \(stateLabel)")

        switch central.state {
        case .poweredOn:
            if isRunning { connectOrScan(using: central) }
        case .poweredOff:
            HRDebugLogger.warn(.fitbit, "Bluetooth is off — turn on Bluetooth to connect Fitbit")
        case .unauthorized:
            HRDebugLogger.error(.fitbit, "Bluetooth unauthorized — add NSBluetoothAlwaysUsageDescription to Info.plist and grant permission")
        case .unsupported:
            HRDebugLogger.error(.fitbit, "BLE not supported on this device")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "(unnamed)"

        // Extract advertised service UUIDs from both primary and overflow slots
        let primaryServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
        let overflowServices = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let allServices = primaryServices + overflowServices
        let advertisesHRM = allServices.contains(heartRateServiceUUID)

        // Known Fitbit/Pixel Watch name patterns — Charge 6 advertises as "Charge 6 XXXX"
        let nameLower = name.lowercased()
        let isFitbitDevice = advertisesHRM
            || nameLower.contains("charge")
            || nameLower.contains("pixel watch")
            || nameLower.contains("fitbit")
            || nameLower.contains("sense")
            || nameLower.contains("versa")

        // Log every discovered peripheral so we can diagnose scan issues
        HRDebugLogger.log(.fitbit, "Discovered: '\(name)' RSSI=\(RSSI) services=[\(allServices.map { $0.uuidString.prefix(8) }.joined(separator: ","))] advertisesHRM=\(advertisesHRM) isFitbit=\(isFitbitDevice)")

        guard isFitbitDevice else { return }

        HRDebugLogger.log(.fitbit, "Fitbit device matched — stopping scan and connecting to '\(name)'")
        central.stopScan()
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        HRDebugLogger.log(.fitbit, "Connected to '\(peripheral.name ?? peripheral.identifier.uuidString)' — discovering Heart Rate service")

        // Persist device UUID for future sessions
        SharedUserStorage.save(
            value: peripheral.identifier.uuidString,
            forKey: .fitbitDeviceUUID
        )
        if let name = peripheral.name {
            SharedUserStorage.save(value: name, forKey: .fitbitDeviceName)
        }

        peripheral.discoverServices([heartRateServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        HRDebugLogger.error(.fitbit, "Failed to connect to '\(peripheral.name ?? "unknown")': \(error?.localizedDescription ?? "no error")")
        if isRunning {
            HRDebugLogger.log(.fitbit, "Retrying scan after connection failure")
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if let error {
            HRDebugLogger.warn(.fitbit, "Disconnected from '\(peripheral.name ?? "unknown")': \(error.localizedDescription)")
        } else {
            HRDebugLogger.log(.fitbit, "Disconnected from '\(peripheral.name ?? "unknown")' cleanly")
        }
        guard isRunning else { return }
        HRDebugLogger.log(.fitbit, "Session still active — reconnecting")
        central.connect(peripheral, options: nil)
    }
}

// MARK: - CBPeripheralDelegate

extension FitbitHRProvider: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            HRDebugLogger.error(.fitbit, "Service discovery failed: \(error.localizedDescription)")
            return
        }
        let found = peripheral.services?.map { $0.uuid.uuidString } ?? []
        HRDebugLogger.log(.fitbit, "Services discovered: \(found)")
        guard let service = peripheral.services?.first(where: { $0.uuid == heartRateServiceUUID }) else {
            HRDebugLogger.error(.fitbit, "Heart Rate Service (180D) not found in: \(found)")
            return
        }
        HRDebugLogger.log(.fitbit, "Heart Rate Service found — discovering characteristic 2A37")
        peripheral.discoverCharacteristics([heartRateMeasurementUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            HRDebugLogger.error(.fitbit, "Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        let found = service.characteristics?.map { $0.uuid.uuidString } ?? []
        HRDebugLogger.log(.fitbit, "Characteristics discovered: \(found)")
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == heartRateMeasurementUUID }) else {
            HRDebugLogger.error(.fitbit, "Heart Rate Measurement (2A37) not found in: \(found)")
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
        HRDebugLogger.log(.fitbit, "Subscribed to Heart Rate Measurement (2A37) — waiting for BPM notifications")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            HRDebugLogger.error(.fitbit, "Notification subscription error for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        HRDebugLogger.log(.fitbit, "Notification state for \(characteristic.uuid): isNotifying=\(characteristic.isNotifying)")
        if !characteristic.isNotifying {
            HRDebugLogger.warn(.fitbit, "Notifications NOT active — Fitbit may not support this characteristic")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            HRDebugLogger.warn(.fitbit, "Characteristic update error: \(error.localizedDescription)")
            return
        }
        guard characteristic.uuid == heartRateMeasurementUUID else { return }
        guard let data = characteristic.value else {
            HRDebugLogger.warn(.fitbit, "Received notification with nil data")
            return
        }
        guard let bpm = parseBPM(from: data) else {
            HRDebugLogger.warn(.fitbit, "Could not parse BPM from data: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
            return
        }

        let now = Date()
        lastSampleDate = now

        HRDebugLogger.logBPM(.fitbit, bpm: bpm, age: 0, source: peripheral.name ?? "Fitbit")
        HeartRateRouter.shared.ingestFitbit(bpm: bpm, at: now)
    }
}
