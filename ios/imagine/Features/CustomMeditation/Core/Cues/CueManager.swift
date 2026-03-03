//
//  CueManager.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-24
//

import Foundation
import FirebaseStorage

class CueManager: ObservableObject {
    static let shared = CueManager()
    
    @Published var cues: [Cue] = []
    // Dynamic durations for finite modules from catalogs (e.g., BS*, PB*, etc.)
    private(set) var bodyScanDurations: [String: Int] = [:]
    
    private let storage = Storage.storage()
    // Firebase Storage paths (single sources)
    // gs://imagine-c6162.appspot.com/modules/cues/cues_models.json
    // gs://imagine-c6162.appspot.com/modules/body_scan/body_scan_models.json
    // gs://imagine-c6162.appspot.com/modules/perfect_breath/perfect_breath_models.json
    // gs://imagine-c6162.appspot.com/modules/i_am_mantra/i_am_mantra_models.json
    // gs://imagine-c6162.appspot.com/modules/nostril_focus/nostril_focus_models.json
    private let cuesPath = "modules/cues/cues_models.json"
    private let bodyScanPath = "modules/body_scan/body_scan_models.json"
    private let perfectBreathPath = "modules/perfect_breath/perfect_breath_models.json"
    private let iAmMantraPath = "modules/i_am_mantra/i_am_mantra_models.json"
    private let nostrilFocusPath = "modules/nostril_focus/nostril_focus_models.json"
    
    /// Module IDs hidden from this app version. Kept in Firebase for older versions.
    private let deprecatedIds: Set<String> = ["MA"]
    
    private init() {
        loadCachedCues()
    }
    
    /// Fetch cues_models.json, body_scan_models.json, perfect_breath_models.json, and i_am_mantra_models.json from Firebase Storage and merge.
    func fetchCues(completion: ((Bool) -> Void)? = nil) {
        let cuesRef = storage.reference(withPath: cuesPath)
        let bodyRef = storage.reference(withPath: bodyScanPath)
        let pbRef = storage.reference(withPath: perfectBreathPath)
        let imRef = storage.reference(withPath: iAmMantraPath)
        let nfRef = storage.reference(withPath: nostrilFocusPath)

        let group = DispatchGroup()
        var cuesData: Data?
        var bodyData: Data?
        var pbData: Data?
        var imData: Data?
        var nfData: Data?
        var cuesError: Error?

        group.enter()
        cuesRef.getData(maxSize: 2 * 1024 * 1024) { data, error in
            if let error = error { cuesError = error }
            cuesData = data
            group.leave()
        }

        group.enter()
        bodyRef.getData(maxSize: 2 * 1024 * 1024) { data, _ in
            bodyData = data
            group.leave()
        }

        group.enter()
        pbRef.getData(maxSize: 2 * 1024 * 1024) { data, _ in
            pbData = data
            group.leave()
        }

        group.enter()
        imRef.getData(maxSize: 2 * 1024 * 1024) { data, _ in
            imData = data
            group.leave()
        }

        group.enter()
        nfRef.getData(maxSize: 2 * 1024 * 1024) { data, _ in
            nfData = data
            group.leave()
        }

        group.notify(queue: .global()) { [weak self] in
            guard let self = self else { completion?(false); return }
            if let error = cuesError {
                logger.errorMessage("🧭 AI_DEBUG [CUES]: Error fetching cues_models.json: \(error.localizedDescription)")
                completion?(false)
                return
            }
            guard let cuesData = cuesData else {
                logger.errorMessage("🧭 AI_DEBUG [CUES]: No data found in cues_models.json")
                completion?(false)
                return
            }
            do {
                struct Catalog: Codable { let version: String?; let models: [Model] }
                struct Model: Codable {
                    let id: String
                    let name: String
                    let audio: Audio
                    let duration_minutes: Int?
                    struct Audio: Codable { let url: String }
                }

                let cuesCatalog = try JSONDecoder().decode(Catalog.self, from: cuesData)
                var models = cuesCatalog.models
                var durations: [String: Int] = [:]
                if let bodyData = bodyData, let bodyCatalog = try? JSONDecoder().decode(Catalog.self, from: bodyData) {
                    models.append(contentsOf: bodyCatalog.models)
                    for m in bodyCatalog.models {
                        if let d = m.duration_minutes { durations[m.id] = d }
                    }
                }
                if let pbData = pbData, let pbCatalog = try? JSONDecoder().decode(Catalog.self, from: pbData) {
                    models.append(contentsOf: pbCatalog.models)
                    for m in pbCatalog.models {
                        if let d = m.duration_minutes { durations[m.id] = d }
                    }
                }
                if let imData = imData, let imCatalog = try? JSONDecoder().decode(Catalog.self, from: imData) {
                    models.append(contentsOf: imCatalog.models)
                    for m in imCatalog.models {
                        if let d = m.duration_minutes { durations[m.id] = d }
                    }
                    logger.eventMessage("🧭 AI_DEBUG [CUES]: I AM Mantra catalog merged: \(imCatalog.models.count) modules")
                }
                if let nfData = nfData, let nfCatalog = try? JSONDecoder().decode(Catalog.self, from: nfData) {
                    models.append(contentsOf: nfCatalog.models)
                    for m in nfCatalog.models {
                        if let d = m.duration_minutes { durations[m.id] = d }
                    }
                    logger.eventMessage("🧭 AI_DEBUG [CUES]: Nostril Focus catalog merged: \(nfCatalog.models.count) modules")
                }

                // Map to Cue list, dedupe by id, and filter deprecated modules
                var seen = Set<String>()
                let mapped: [Cue] = models.compactMap { m in
                    if seen.contains(m.id) { return nil }
                    seen.insert(m.id)
                    if self.deprecatedIds.contains(m.id) { return nil }
                    return Cue(id: m.id, name: m.name, url: m.audio.url)
                }

                // Cache merged catalog for offline
                let mergedCatalog = Catalog(version: "merged", models: models)
                let cacheData = try JSONEncoder().encode(mergedCatalog)

                DispatchQueue.main.async {
                    self.cues = mapped
                    self.bodyScanDurations = durations
                    self.cacheCues(data: cacheData)
                    let durSummary = durations.keys.sorted().map { id in "\(id)=\(durations[id] ?? 0)m" }.joined(separator: ", ")
                    logger.eventMessage("🧭 AI_DEBUG [CUES]: Loaded \(mapped.count) cues (merged). IDs: \(mapped.map{ $0.id }.joined(separator: ", "))")
                    if !durations.isEmpty { logger.eventMessage("🧭 AI_DEBUG [CUES]: Module durations: \(durSummary)") }
                    completion?(true)
                }
            } catch {
                logger.errorMessage("🧭 AI_DEBUG [CUES]: Error decoding merged catalogs: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }
    
    private func cacheCues(data: Data) {
        let url = localCacheURL()
        do {
            try data.write(to: url)
        } catch {
            logger.errorMessage("🧭 AI_DEBUG [CUES]: Failed to cache merged cues catalogs: \(error.localizedDescription)")
        }
    }
    
    private func loadCachedCues() {
        let url = localCacheURL()
        if let data = try? Data(contentsOf: url) {
            do {
                struct Catalog: Codable { let models: [Model] }
                struct Model: Codable {
                    let id: String
                    let name: String
                    let audio: Audio
                    let duration_minutes: Int?
                    struct Audio: Codable { let url: String }
                }
                let catalog = try JSONDecoder().decode(Catalog.self, from: data)
                self.cues = catalog.models
                    .filter { !deprecatedIds.contains($0.id) }
                    .map { Cue(id: $0.id, name: $0.name, url: $0.audio.url) }
                // Rebuild durations from cache as well
                var durations: [String: Int] = [:]
                for m in catalog.models { if let d = m.duration_minutes { durations[m.id] = d } }
                self.bodyScanDurations = durations
                logger.eventMessage("🧭 AI_DEBUG [CUES]: Loaded cached merged catalog with \(self.cues.count) cues")
                if !durations.isEmpty { logger.eventMessage("🧭 AI_DEBUG [CUES]: Body scan durations (cached): \(durations.keys.sorted().map{ "\($0)=\(durations[$0]!)m" }.joined(separator: ", "))") }
            } catch {
                logger.errorMessage("🧭 AI_DEBUG [CUES]: Error loading cached merged catalogs: \(error.localizedDescription)")
            }
        }
    }
    
    private func localCacheURL() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cues_and_body_scan_cache.json")
    }
}
