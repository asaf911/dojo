import Foundation
import FirebaseStorage

class BackgroundSoundManager: ObservableObject {
    static let shared = BackgroundSoundManager()
    
    @Published var sounds: [BackgroundSound] = []
    
    private let storage = Storage.storage()
    // Location in Firebase Storage for the JSON file (single source catalog)
    // gs://imagine-c6162.appspot.com/modules/background_music/background_music_models.json
    private let jsonFilePath = "modules/background_music/background_music_models.json"
    
    private init() {
        loadCachedSounds()
    }
    
    /// Fetch the background_music_models.json from Firebase Storage.
    func fetchBackgroundSounds(completion: ((Bool) -> Void)? = nil) {
        let storageRef = storage.reference(withPath: jsonFilePath)
        // Set a max size (e.g., 1MB) assuming the JSON file is small.
        storageRef.getData(maxSize: 1 * 1024 * 1024) { [weak self] data, error in
            if let error = error {
                logger.errorMessage("🧭 AI_DEBUG [BG]: Error fetching background_music_models.json: \(error.localizedDescription)")
                completion?(false)
                return
            }
            guard let data = data else {
                logger.errorMessage("🧭 AI_DEBUG [BG]: No data found in background_music_models.json")
                completion?(false)
                return
            }
            do {
                // Catalog format { version, models: [ { id, name, audio{url}, ... } ] }
                struct Catalog: Codable { let version: String?; let models: [Model] }
                struct Model: Codable { let id: String; let name: String; let audio: Audio; struct Audio: Codable { let url: String } }
                let catalog = try JSONDecoder().decode(Catalog.self, from: data)
                let decoded: [BackgroundSound] = catalog.models.map { BackgroundSound(id: $0.id, name: $0.name, url: $0.audio.url) }
                DispatchQueue.main.async {
                    self?.sounds = decoded
                    self?.cacheBackgroundSounds(data: data)
                    logger.eventMessage("🧭 AI_DEBUG [BG]: Loaded \(decoded.count) background sounds: \(decoded.map{ $0.id }.joined(separator: ", "))")
                    completion?(true)
                }
            } catch {
                logger.errorMessage("🧭 AI_DEBUG [BG]: Error decoding background_music_models.json: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }
    
    private func cacheBackgroundSounds(data: Data) {
        let url = localCacheURL()
        do {
            try data.write(to: url)
        } catch {
            logger.errorMessage("🧭 AI_DEBUG [BG]: Failed to cache background_music_models.json: \(error.localizedDescription)")
        }
    }
    
    private func loadCachedSounds() {
        let url = localCacheURL()
        if let data = try? Data(contentsOf: url) {
            do {
                // Support both catalog and legacy array cache
                struct CatalogCache: Codable { let version: String?; let models: [Model]; struct Model: Codable { let id: String; let name: String; let audio: Audio; struct Audio: Codable { let url: String } } }
                if let catalog = try? JSONDecoder().decode(CatalogCache.self, from: data) {
                    let list = catalog.models.map { BackgroundSound(id: $0.id, name: $0.name, url: $0.audio.url) }
                    self.sounds = list
                    logger.eventMessage("🧭 AI_DEBUG [BG]: Loaded cached catalog with \(list.count) sounds")
                } else {
                    let decoded = try JSONDecoder().decode([BackgroundSound].self, from: data)
                    self.sounds = decoded
                    logger.eventMessage("🧭 AI_DEBUG [BG]: Loaded cached legacy array with \(decoded.count) sounds")
                }
            } catch {
                logger.errorMessage("🧭 AI_DEBUG [BG]: Error loading cached background music: \(error.localizedDescription)")
            }
        }
    }
    
    private func localCacheURL() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("background_music_models_cache.json")
    }
}
