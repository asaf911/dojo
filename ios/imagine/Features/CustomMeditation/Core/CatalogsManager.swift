//
//  CatalogsManager.swift
//  imagine
//
//  Fetches aggregated meditation catalogs from GET /catalogs server endpoint.
//
//  QA: Filter console logs by "[CATALOGS_SERVER]" to trace server communication.
//

import Foundation

private let kCatalogsServerTag = "[CATALOGS_SERVER]"

/// Server response format for GET /catalogs
private struct CatalogsResponse: Codable {
    let backgroundSounds: [BackgroundSoundItem]
    let binauralBeats: [BinauralBeatItem]
    let cues: [CueItem]
    let bodyScanDurations: [String: Int]

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
    }
}

final class CatalogsManager: ObservableObject {
    static let shared = CatalogsManager()

    @Published private(set) var sounds: [BackgroundSound] = []
    @Published private(set) var beats: [BinauralBeat] = []
    @Published private(set) var cues: [Cue] = []
    private(set) var bodyScanDurations: [String: Int] = [:]

    private init() {
        loadCachedCatalogs()
    }

    /// Fetch catalogs from GET /catalogs. On success, updates all properties and caches locally.
    /// On failure (e.g. offline), attempts to load from cache. Completion reports whether fresh data was fetched.
    func fetchCatalogs(completion: ((Bool) -> Void)? = nil) {
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("\(kCatalogsServerTag) fetchCatalogs: offline - using cache")
            loadCachedCatalogs()
            completion?(false)
            return
        }

        let url = Config.catalogsURL
        print("\(kCatalogsServerTag) fetchCatalogs: starting request to \(url.host ?? "server")/getCatalogs")
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { completion?(false); return }
            if let httpResponse = response as? HTTPURLResponse {
                print("\(kCatalogsServerTag) fetchCatalogs: response status=\(httpResponse.statusCode)")
            }
            if let error = error {
                print("\(kCatalogsServerTag) fetchCatalogs: network error - \(error.localizedDescription)")
                logger.errorMessage("CatalogsManager: Network error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.loadCachedCatalogs() }
                completion?(false)
                return
            }
            guard let data = data else {
                print("\(kCatalogsServerTag) fetchCatalogs: no data received")
                DispatchQueue.main.async { self.loadCachedCatalogs() }
                completion?(false)
                return
            }
            do {
                let decoded = try JSONDecoder().decode(CatalogsResponse.self, from: data)
                let sounds = decoded.backgroundSounds.map { BackgroundSound(id: $0.id, name: $0.name, url: $0.url) }
                let beats = decoded.binauralBeats.map { BinauralBeat(id: $0.id, name: $0.name, url: $0.url, description: $0.description) }
                let cues = decoded.cues.map { Cue(id: $0.id, name: $0.name, url: $0.url) }
                DispatchQueue.main.async {
                    self.sounds = sounds
                    self.beats = beats
                    self.cues = cues
                    self.bodyScanDurations = decoded.bodyScanDurations
                    self.cacheCatalogs(data: data)
                    print("\(kCatalogsServerTag) fetchCatalogs: success - sounds=\(sounds.count) beats=\(beats.count) cues=\(cues.count)")
                    logger.eventMessage("CatalogsManager: Loaded \(sounds.count) sounds, \(beats.count) beats, \(cues.count) cues")
                }
                completion?(true)
            } catch {
                print("\(kCatalogsServerTag) fetchCatalogs: decode error - \(error.localizedDescription)")
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
            cues = decoded.cues.map { Cue(id: $0.id, name: $0.name, url: $0.url) }
            bodyScanDurations = decoded.bodyScanDurations
            print("\(kCatalogsServerTag) loadCachedCatalogs: loaded from cache - sounds=\(sounds.count) beats=\(beats.count) cues=\(cues.count)")
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
}
