//
//  SessionHistoryManager.swift
//  Dojo
//
//  Manages comprehensive session history with storage, recording, and retrieval.
//  Supports both UI display and AI-queryable access.
//

import Foundation
import Combine

// MARK: - Storage Key Extension

private extension UserStorageKey {
    static let meditationSessions = UserStorageKey.sessionHistory
}

// MARK: - Session History Manager

final class SessionHistoryManager: ObservableObject {
    static let shared = SessionHistoryManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var sessions: [MeditationSession] = []
    
    // MARK: - Configuration
    
    private let maxStoredSessions = 500
    private let storageKey: UserStorageKey = .sessionHistory
    
    // MARK: - Initialization
    
    private init() {
        loadSessions()
        migrateFromLegacyIfNeeded()
    }
    
    // MARK: - Public Recording Methods
    
    /// Record a completed guided practice session
    func recordPracticeCompletion(
        audioFile: AudioFile,
        actualDurationSeconds: Int,
        completionRate: Double = 1.0,
        source: MeditationSessionSource = .explore
    ) {
        print("🧠 AI_DEBUG HISTORY recordPracticeCompletion called for '\(audioFile.title)'")
        
        let hrData = SessionHeartRateData.fromTracker()
        print("🧠 AI_DEBUG HISTORY hrData=\(hrData != nil ? "present" : "nil") hasValid=\(hrData?.hasValidData ?? false) start=\(Int(hrData?.startBPM ?? 0)) end=\(Int(hrData?.endBPM ?? 0))")
        
        let outcome: SessionOutcome = {
            if completionRate >= 1.0 { return .completed }
            if completionRate >= 0.95 { return .almostDone }
            if completionRate >= 0.75 { return .partial }
            return .abandoned
        }()
        
        let session = MeditationSession(
            sessionType: .guided,
            source: source,
            title: audioFile.title,
            description: audioFile.description,
            practiceId: audioFile.id,
            category: audioFile.tags.first,
            tags: audioFile.tags,
            plannedDurationSeconds: actualDurationSeconds,
            actualDurationSeconds: actualDurationSeconds,
            completionRate: completionRate,
            outcome: outcome,
            heartRate: hrData,
            context: SessionContext.current()
        )
        
        addSession(session)
        print("🧠 AI_DEBUG HISTORY recorded practice '\(audioFile.title)' hr=\(hrData != nil)")
        logger.infoMessage("SessionHistoryManager: Recorded practice '\(audioFile.title)' (\(actualDurationSeconds)s)")
    }
    
    /// Record a completed custom meditation session
    func recordCustomMeditationCompletion(
        title: String = "Custom Meditation",
        totalSeconds: Int,
        backgroundSoundId: String? = nil,
        backgroundSoundName: String? = nil,
        binauralBeatId: String? = nil,
        binauralBeatName: String? = nil,
        cueIds: [String] = [],
        cueNames: [String] = [],
        source: MeditationSessionSource = .timer
    ) {
        let hrData = SessionHeartRateData.fromTracker()
        
        let customConfig = SessionCustomConfig(
            backgroundSoundId: backgroundSoundId,
            backgroundSoundName: backgroundSoundName,
            binauralBeatId: binauralBeatId,
            binauralBeatName: binauralBeatName,
            cueIds: cueIds,
            cueNames: cueNames
        )
        
        let session = MeditationSession(
            sessionType: .custom,
            source: source,
            title: title,
            plannedDurationSeconds: totalSeconds,
            actualDurationSeconds: totalSeconds,
            completionRate: 1.0,
            outcome: .completed,
            heartRate: hrData,
            customConfig: customConfig,
            context: SessionContext.current()
        )
        
        addSession(session)
        logger.infoMessage("SessionHistoryManager: Recorded custom meditation '\(title)' (\(totalSeconds)s)")
    }
    
    /// Record an AI-generated meditation session
    func recordAIMeditationCompletion(
        title: String,
        description: String?,
        totalSeconds: Int,
        backgroundSoundId: String?,
        backgroundSoundName: String?,
        binauralBeatId: String?,
        binauralBeatName: String?,
        cueIds: [String],
        cueNames: [String]
    ) {
        let hrData = SessionHeartRateData.fromTracker()
        
        let customConfig = SessionCustomConfig(
            backgroundSoundId: backgroundSoundId,
            backgroundSoundName: backgroundSoundName,
            binauralBeatId: binauralBeatId,
            binauralBeatName: binauralBeatName,
            cueIds: cueIds,
            cueNames: cueNames
        )
        
        let session = MeditationSession(
            sessionType: .aiGenerated,
            source: .aiChat,
            title: title,
            description: description,
            plannedDurationSeconds: totalSeconds,
            actualDurationSeconds: totalSeconds,
            completionRate: 1.0,
            outcome: .completed,
            heartRate: hrData,
            customConfig: customConfig,
            context: SessionContext.current()
        )
        
        addSession(session)
        logger.infoMessage("SessionHistoryManager: Recorded AI meditation '\(title)' (\(totalSeconds)s)")
    }
    
    // MARK: - Generic Session Recording
    
    /// Add a session directly (for custom use cases)
    func addSession(_ session: MeditationSession) {
        print("🧠 AI_DEBUG HISTORY addSession id=\(session.id) title='\(session.title)' hasHR=\(session.hasHeartRateData)")
        sessions.insert(session, at: 0) // Newest first
        trimSessions()
        saveSessions()
        
        // Upload to Firebase
        SessionFirebaseSync.shared.uploadSession(session)
        
        print("🧠 AI_DEBUG HISTORY after addSession total=\(sessions.count)")
    }
    
    // MARK: - Firebase Sync Integration
    
    /// Merge remote sessions from Firebase (used during sync)
    /// Adds sessions that don't exist locally, avoiding duplicates by UUID
    func mergeRemoteSessions(_ remoteSessions: [MeditationSession]) {
        let localIDs = Set(sessions.map { $0.id })
        let newSessions = remoteSessions.filter { !localIDs.contains($0.id) }
        
        guard !newSessions.isEmpty else {
            print("🔄 HISTORY_SYNC: No new sessions to merge - all already local")
            return
        }
        
        print("🔄 HISTORY_SYNC: Merging \(newSessions.count) new sessions from Firebase...")
        sessions.append(contentsOf: newSessions)
        sessions.sort { $0.createdAt > $1.createdAt }
        trimSessions()
        saveSessions()
        
        print("🔄 HISTORY_SYNC: Merge complete - total local sessions: \(sessions.count)")
    }
    
    // MARK: - Retrieval Methods
    
    /// Get all sessions sorted by date (newest first)
    func getAllSessions() -> [MeditationSession] {
        print("🧠 AI_DEBUG HISTORY getAllSessions called, count=\(sessions.count)")
        return sessions.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get sessions within a date range
    func getSessions(from startDate: Date, to endDate: Date) -> [MeditationSession] {
        return sessions.filter { $0.createdAt >= startDate && $0.createdAt <= endDate }
    }
    
    /// Get sessions from the last N days
    func getSessionsInLastDays(_ days: Int) -> [MeditationSession] {
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }
        return getSessions(from: startDate, to: Date())
    }
    
    /// Get sessions by type
    func getSessions(ofType type: MeditationSessionType) -> [MeditationSession] {
        return sessions.filter { $0.sessionType == type }
    }
    
    /// Get sessions with heart rate data
    func getSessionsWithHeartRate() -> [MeditationSession] {
        let filtered = sessions.filter { $0.hasHeartRateData }
        print("🧠 AI_DEBUG HISTORY getSessionsWithHeartRate total=\(sessions.count) withHR=\(filtered.count)")
        return filtered
    }
    
    /// Get total session count
    var totalSessionCount: Int {
        sessions.count
    }
    
    /// Get total meditation time in seconds
    var totalMeditationTimeSeconds: Int {
        sessions.reduce(0) { $0 + $1.actualDurationSeconds }
    }
    
    // MARK: - Clear / Delete
    
    /// Clear all local history (Firebase data remains untouched for re-sync)
    func clearHistory() {
        let performClear = { [weak self] in
            guard let self = self else { return }
            let countBefore = self.sessions.count
            print("📜 HISTORY_CLEAR: clearHistory() called - removing \(countBefore) sessions from local storage")
            self.objectWillChange.send()
            self.sessions.removeAll()
            self.saveSessions()
            print("📜 HISTORY_CLEAR: Local sessions cleared - count now \(self.sessions.count)")
            print("📜 HISTORY_CLEAR: Firebase data preserved - will sync on next app launch")
            logger.infoMessage("SessionHistoryManager: Cleared all local session history (\(countBefore) sessions)")
        }
        
        // Ensure we're on main thread for UI updates
        if Thread.isMainThread {
            performClear()
        } else {
            DispatchQueue.main.async {
                performClear()
            }
        }
    }
    
    /// Delete a specific session (local + Firebase)
    func deleteSession(id: UUID) {
        print("📜 HISTORY_DELETE: Deleting session \(id.uuidString.prefix(8))...")
        
        // Remove locally
        sessions.removeAll { $0.id == id }
        saveSessions()
        
        // Delete from Firebase
        SessionFirebaseSync.shared.deleteSession(id)
        
        print("📜 HISTORY_DELETE: Session deleted - remaining local: \(sessions.count)")
    }
    
    // MARK: - Update Methods
    
    /// Update heart rate data for a session (useful for late-arriving HR data)
    func updateSessionHeartRate(sessionId: UUID, heartRate: SessionHeartRateData) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            logger.debugMessage("SessionHistoryManager: Session \(sessionId) not found for HR update")
            return
        }
        
        sessions[index].heartRate = heartRate
        saveSessions()
        logger.infoMessage("SessionHistoryManager: Updated HR for session '\(sessions[index].title)'")
    }
    
    /// Update the most recent session's heart rate data
    func updateMostRecentSessionHeartRate() {
        guard let mostRecent = sessions.first else {
            logger.debugMessage("SessionHistoryManager: No sessions to update HR for")
            return
        }
        
        // Only update if we don't already have HR data
        guard mostRecent.heartRate == nil || !mostRecent.hasHeartRateData else {
            logger.debugMessage("SessionHistoryManager: Most recent session already has HR data")
            return
        }
        
        // Try to get current HR data from tracker
        guard let hrData = SessionHeartRateData.fromTracker() else {
            logger.debugMessage("SessionHistoryManager: No HR data available from tracker")
            return
        }
        
        updateSessionHeartRate(sessionId: mostRecent.id, heartRate: hrData)
    }
    
    /// Get the most recent session (useful for updating HR data after it arrives)
    func getMostRecentSession() -> MeditationSession? {
        return sessions.first
    }
    
    /// Get a session by its ID
    func getSession(by id: UUID) -> MeditationSession? {
        return sessions.first(where: { $0.id == id })
    }
    
    // MARK: - Storage
    
    private func saveSessions() {
        print("🧠 AI_DEBUG HISTORY saveSessions count=\(sessions.count)")
        SharedUserStorage.save(value: sessions, forKey: storageKey)
        print("🧠 AI_DEBUG HISTORY saveSessions complete")
    }
    
    private func loadSessions() {
        print("🧠 AI_DEBUG HISTORY loadSessions starting...")
        // Try loading new MeditationSession format first
        if let loaded = SharedUserStorage.retrieve(forKey: storageKey, as: [MeditationSession].self) {
            sessions = loaded
            print("🧠 AI_DEBUG HISTORY loadSessions success count=\(sessions.count)")
            logger.debugMessage("SessionHistoryManager: Loaded \(sessions.count) sessions")
        } else {
            sessions = []
            print("🧠 AI_DEBUG HISTORY loadSessions failed - no MeditationSession data found")
            logger.debugMessage("SessionHistoryManager: No sessions found, starting fresh")
        }
    }
    
    private func trimSessions() {
        if sessions.count > maxStoredSessions {
            sessions = Array(sessions.prefix(maxStoredSessions))
            logger.debugMessage("SessionHistoryManager: Trimmed to \(maxStoredSessions) sessions")
        }
    }
    
    // MARK: - Migration
    
    private func migrateFromLegacyIfNeeded() {
        // Check if we already have MeditationSession data - if so, skip migration
        guard sessions.isEmpty else {
            print("🧠 AI_DEBUG HISTORY migration skipped - already have \(sessions.count) sessions")
            return
        }
        
        // Try to load legacy SessionRecord data directly from storage
        // (SessionRecord is the old MVP model that was stored in .sessionHistory)
        guard let legacySessions = SharedUserStorage.retrieve(forKey: .sessionHistory, as: [SessionRecord].self),
              !legacySessions.isEmpty else {
            print("🧠 AI_DEBUG HISTORY migration skipped - no legacy SessionRecord data found")
            return
        }
        
        print("🧠 AI_DEBUG HISTORY migrating \(legacySessions.count) legacy sessions...")
        logger.infoMessage("SessionHistoryManager: Migrating \(legacySessions.count) legacy sessions...")
        
        for legacy in legacySessions {
            let migrated = MeditationSession(from: legacy)
            sessions.append(migrated)
        }
        
        // Sort by date
        sessions.sort { $0.createdAt > $1.createdAt }
        
        saveSessions()
        print("🧠 AI_DEBUG HISTORY migration complete - \(sessions.count) sessions")
        logger.infoMessage("SessionHistoryManager: Migration complete - \(sessions.count) sessions")
    }
    
    // MARK: - Force Reload (for testing)
    
    func reloadFromStorage() {
        loadSessions()
    }
}

// MARK: - Lightweight Card Model for UI

struct HistoryCardModel: Identifiable {
    let id: UUID
    let title: String
    let description: String?
    let date: Date
    let durationSeconds: Int
    let sessionType: MeditationSessionType
    let practiceId: String?  // For guided meditations - used to reopen in player
    let startBPM: Int?
    let endBPM: Int?
    let samples: [HeartRateSamplePoint]  // Individual sample points for graph rendering
    
    var hasHeartRateData: Bool {
        startBPM != nil && endBPM != nil && startBPM! > 0 && endBPM! > 0
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: date)
    }
    
    var formattedDuration: String {
        let minutes = durationSeconds / 60
        if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(durationSeconds)s"
        }
    }
    
    /// Create from MeditationSession
    init(from session: MeditationSession) {
        self.id = session.id
        self.title = session.title
        self.description = session.description
        self.date = session.createdAt
        self.durationSeconds = session.actualDurationSeconds
        self.sessionType = session.sessionType
        self.practiceId = session.practiceId
        self.startBPM = session.heartRate?.startBPM.map { Int($0) }
        self.endBPM = session.heartRate?.endBPM.map { Int($0) }
        self.samples = session.heartRate?.samples ?? []
    }
    
    /// Create from legacy SessionRecord (for backward compatibility)
    init(from legacy: SessionRecord) {
        self.id = legacy.id
        self.title = legacy.title
        self.description = legacy.description
        self.date = legacy.completedAt
        self.durationSeconds = legacy.durationSeconds
        self.sessionType = legacy.sessionType == .practice ? .guided : .custom
        self.practiceId = legacy.practiceId
        self.startBPM = legacy.startBPM
        self.endBPM = legacy.endBPM
        self.samples = []  // Legacy sessions don't have sample data
    }
}

// MARK: - History Card Provider Extension

extension SessionHistoryManager {
    /// Get lightweight card models for UI display
    func getHistoryCards() -> [HistoryCardModel] {
        return getAllSessions().map { HistoryCardModel(from: $0) }
    }
}

