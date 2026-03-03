//
//  BinauralBeatManager.swift
//  Dojo
//
//  Created by Assistant on 2025-10-01
//

import Foundation
import FirebaseStorage

class BinauralBeatManager: ObservableObject {
    static let shared = BinauralBeatManager()
    
    @Published var beats: [BinauralBeat] = []
    
    private let storage = Storage.storage()
    // Firebase Storage path for catalog JSON
    // gs://imagine-c6162.appspot.com/modules/binaural_beats/binaural_beats_models.json
    private let jsonFilePath = "modules/binaural_beats/binaural_beats_models.json"
    
    private init() {
        loadCachedBeats()
    }
    
    func fetchBinauralBeats(completion: ((Bool) -> Void)? = nil) {
        let storageRef = storage.reference(withPath: jsonFilePath)
        storageRef.getData(maxSize: 1 * 1024 * 1024) { [weak self] data, error in
            if let error = error {
                logger.eventMessage("🧠 AI_DEBUG [BB]: Error fetching binaural_beats_models.json: \(error.localizedDescription)")
                completion?(false)
                return
            }
            guard let data = data else {
                logger.eventMessage("🧠 AI_DEBUG [BB]: No data found in binaural_beats_models.json")
                completion?(false)
                return
            }
            do {
                struct Catalog: Codable { let version: String?; let models: [Model] }
                struct Model: Codable { let id: String; let name: String; let description: String?; let audio: Audio; struct Audio: Codable { let url: String } }
                let catalog = try JSONDecoder().decode(Catalog.self, from: data)
                let decoded: [BinauralBeat] = catalog.models.map { BinauralBeat(id: $0.id, name: $0.name, url: $0.audio.url, description: $0.description) }
                DispatchQueue.main.async {
                    self?.beats = decoded
                    self?.cacheBeats(data: data)
                    logger.eventMessage("🧠 AI_DEBUG [BB]: Loaded \(decoded.count) binaural beats: \(decoded.map{ $0.id }.joined(separator: ", "))")
                    completion?(true)
                }
            } catch {
                logger.eventMessage("🧠 AI_DEBUG [BB]: Error decoding binaural_beats_models.json: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }
    
    private func cacheBeats(data: Data) {
        let url = localCacheURL()
        do {
            try data.write(to: url)
        } catch {
            logger.eventMessage("🧠 AI_DEBUG [BB]: Failed to cache binaural_beats_models.json: \(error.localizedDescription)")
        }
    }
    
    private func loadCachedBeats() {
        let url = localCacheURL()
        if let data = try? Data(contentsOf: url) {
            do {
                struct CatalogCache: Codable { let version: String?; let models: [Model]; struct Model: Codable { let id: String; let name: String; let description: String?; let audio: Audio; struct Audio: Codable { let url: String } } }
                let catalog = try JSONDecoder().decode(CatalogCache.self, from: data)
                let list = catalog.models.map { BinauralBeat(id: $0.id, name: $0.name, url: $0.audio.url, description: $0.description) }
                self.beats = list
                logger.eventMessage("🧠 AI_DEBUG [BB]: Loaded cached catalog with \(list.count) beats")
            } catch {
                logger.eventMessage("🧠 AI_DEBUG [BB]: Error loading cached binaural beats: \(error.localizedDescription)")
            }
        }
    }
    
    private func localCacheURL() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("binaural_beats_models_cache.json")
    }
}


