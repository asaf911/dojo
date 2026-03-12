//
//  CatalogsManager.swift
//  imagine
//
//  Fetches aggregated meditation catalogs from GET /catalogs server endpoint.
//
//  QA: Filter console logs by "[Server][Catalogs]" to trace server communication.
//

import Foundation

private let kCatalogsServerTag = "[Server][Catalogs]"

/// Server response format for GET /catalogs
private struct CatalogsResponse: Codable {
    let backgroundSounds: [BackgroundSoundItem]
    let binauralBeats: [BinauralBeatItem]
    let cues: [CueItem]
    let bodyScanDurations: [String: Int]
    let voices: [VoiceItem]?

    struct BackgroundSoundItem: Codable {
        let id: String
        let name: String
        let url: String
    }

    struct BinauralBeatItem: Codable {
        let id: String
        let name: String
        let url: String
        let description: String?
    }

    struct CueItem: Codable {
        let id: String
        let name: String
        let url: String
        let urlsByVoice: [String: String]?
    }

    struct VoiceItem: Codable {
        let id: String
        let name: String
    }
}

final class CatalogsManager: ObservableObject {
    static let shared = CatalogsManager()

    @Published private(set) var sounds: [BackgroundSound] = []
    @Published private(set) var beats: [BinauralBeat] = []
    @Published private(set) var cues: [Cue] = []
    @Published private(set) var voices: [VoiceItem] = []
    private(set) var bodyScanDurations: [String: Int] = [:]

    struct VoiceItem: Identifiable {
        let id: String
        let name: String
    }

    private init() {
        loadCachedCatalogs()
    }

    /// Fetch catalogs from GET /catalogs. On success, updates all properties and caches locally.
    /// On failure (e.g. offline), attempts to load from cache. Completion reports whether fresh data was fetched.
    /// - Parameter triggerContext: Optional identifier for QA tracing (e.g. "TimerCreationView|onAppear preload").
    func fetchCatalogs(triggerContext: String? = nil, completion: ((Bool) -> Void)? = nil) {
        let trigger = triggerContext ?? "unknown"
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("\(kCatalogsServerTag) fetchCatalogs: offline trigger=\(trigger) - using cache")
            loadCachedCatalogs()
            completion?(false)
            return
        }

        let url = Config.catalogsURL
        var request = URLRequest(url: url)
        request.setValue(trigger, forHTTPHeaderField: "X-Trigger")
        print("\(kCatalogsServerTag) fetchCatalogs: start trigger=\(trigger) server=\(Config.serverLabel) url=\(url.host ?? "server")/getCatalogs")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { completion?(false); return }
            if let httpResponse = response as? HTTPURLResponse {
                print("\(kCatalogsServerTag) fetchCatalogs: response trigger=\(trigger) status=\(httpResponse.statusCode)")
            }
            if let error = error {
                print("\(kCatalogsServerTag) fetchCatalogs: failure trigger=\(trigger) error=\(error.localizedDescription)")
                logger.errorMessage("CatalogsManager: Network error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.loadCachedCatalogs() }
                completion?(false)
                return
            }
            guard let data = data else {
                print("\(kCatalogsServerTag) fetchCatalogs: failure trigger=\(trigger) - no data received")
                DispatchQueue.main.async { self.loadCachedCatalogs() }
                completion?(false)
                return
            }
            do {
                let decoded = try JSONDecoder().decode(CatalogsResponse.self, from: data)
                let sounds = decoded.backgroundSounds.map { BackgroundSound(id: $0.id, name: $0.name, url: $0.url) }
                let beats = decoded.binauralBeats.map { BinauralBeat(id: $0.id, name: $0.name, url: $0.url, description: $0.description) }
                let cues = decoded.cues.map { Cue(id: $0.id, name: $0.name, url: $0.url, urlsByVoice: $0.urlsByVoice) }
                let voices = (decoded.voices ?? []).map { VoiceItem(id: $0.id, name: $0.name) }
                DispatchQueue.main.async {
                    self.sounds = sounds
                    self.beats = beats
                    self.cues = cues
                    self.voices = voices
                    self.bodyScanDurations = decoded.bodyScanDurations
                    self.cacheCatalogs(data: data)
                    print("\(kCatalogsServerTag) fetchCatalogs: success trigger=\(trigger) server=\(Config.serverLabel) sounds=\(sounds.count) beats=\(beats.count) cues=\(cues.count) voices=\(voices.count)")
                    logger.eventMessage("CatalogsManager: Loaded \(sounds.count) sounds, \(beats.count) beats, \(cues.count) cues")
                }
                completion?(true)
            } catch {
                print("\(kCatalogsServerTag) fetchCatalogs: failure trigger=\(trigger) decode error - \(error.localizedDescription)")
                logger.errorMessage("CatalogsManager: Decode error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.loadCachedCatalogs() }
                completion?(false)
            }
        }.resume()
    }

    private func cacheCatalogs(data: Data) {
        let url = localCacheURL()
        do {
            try data.write(to: url)
            print("\(kCatalogsServerTag) cacheCatalogs: saved to disk (\(data.count) bytes)")
        } catch {
            print("\(kCatalogsServerTag) cacheCatalogs: failed to save - \(error.localizedDescription)")
            logger.errorMessage("CatalogsManager: Failed to cache: \(error.localizedDescription)")
        }
    }

    private func loadCachedCatalogs() {
        let url = localCacheURL()
        guard let data = try? Data(contentsOf: url) else {
            print("\(kCatalogsServerTag) loadCachedCatalogs: cache miss - no cached data")
            return
        }
        do {
            let decoded = try JSONDecoder().decode(CatalogsResponse.self, from: data)
            sounds = decoded.backgroundSounds.map { BackgroundSound(id: $0.id, name: $0.name, url: $0.url) }
            beats = decoded.binauralBeats.map { BinauralBeat(id: $0.id, name: $0.name, url: $0.url, description: $0.description) }
            cues = decoded.cues.map { Cue(id: $0.id, name: $0.name, url: $0.url, urlsByVoice: $0.urlsByVoice) }
            voices = (decoded.voices ?? []).map { VoiceItem(id: $0.id, name: $0.name) }
            bodyScanDurations = decoded.bodyScanDurations
            print("\(kCatalogsServerTag) loadCachedCatalogs: loaded from cache - sounds=\(sounds.count) beats=\(beats.count) cues=\(cues.count) voices=\(voices.count)")
            logger.eventMessage("CatalogsManager: Loaded cached catalog with \(sounds.count) sounds, \(beats.count) beats, \(cues.count) cues")
        } catch {
            print("\(kCatalogsServerTag) loadCachedCatalogs: failed to decode cache - \(error.localizedDescription)")
            logger.errorMessage("CatalogsManager: Failed to load cache: \(error.localizedDescription)")
        }
    }

    private func localCacheURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalogs_cache.json")
    }

    /// Clears the catalogs cache file and in-memory state. Fresh data will be fetched on next fetchCatalogs.
    func clearCache() {
        let url = localCacheURL()
        try? FileManager.default.removeItem(at: url)
        sounds = []
        beats = []
        cues = []
        voices = []
        bodyScanDurations = [:]
        print("\(kCatalogsServerTag) clearCache: catalogs cache cleared")
        logger.eventMessage("CatalogsManager: Cache cleared. Fresh data will be fetched on next load.")
    }
}
