//
//  OfflineAssetChecker.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-12-26
//
//  Utility to validate asset availability for offline playback.
//  Checks if meditation audio files are cached locally before playback.
//

import Foundation
import FirebaseStorage

/// Result of checking asset availability for a meditation
struct AssetAvailability {
    /// Whether all required assets are available locally
    let allAvailable: Bool
    
    /// List of asset URLs that are missing from local cache
    let missingAssets: [String]
    
    /// Whether this meditation can be played offline (all assets cached)
    var availableOffline: Bool { allAvailable }
    
    /// Static factory for when all assets are available
    static let allCached = AssetAvailability(allAvailable: true, missingAssets: [])
}

/// Validates asset availability for meditations before playback.
/// Use this to check if a meditation can be played offline.
enum OfflineAssetChecker {
    
    // MARK: - Guided Meditation Checks
    
    /// Check if a guided meditation's audio file is cached locally
    /// - Parameters:
    ///   - file: The AudioFile to check
    ///   - durationIndex: The selected duration index
    /// - Returns: AssetAvailability indicating if the file is cached
    static func checkGuidedMeditation(_ file: AudioFile, durationIndex: Int) -> AssetAvailability {
        guard durationIndex < file.durations.count else {
            return AssetAvailability(allAvailable: false, missingAssets: ["Invalid duration index"])
        }
        
        let duration = file.durations[durationIndex]
        let fileName = duration.fileName
        
        // Check if file is cached
        if isFileCached(urlString: fileName) {
            return .allCached
        } else {
            return AssetAvailability(allAvailable: false, missingAssets: [fileName])
        }
    }
    
    /// Convenience method to check if a guided meditation can be played offline
    static func canPlayOffline(guided file: AudioFile, durationIndex: Int) -> Bool {
        return checkGuidedMeditation(file, durationIndex: durationIndex).allAvailable
    }
    
    // MARK: - Timer Meditation Checks
    
    /// Check if all assets for a timer meditation are cached locally
    /// - Parameter config: The TimerSessionConfig to check
    /// - Returns: AssetAvailability indicating which assets are cached
    static func checkTimerMeditation(_ config: TimerSessionConfig) -> AssetAvailability {
        var missingAssets: [String] = []
        
        // Check background sound
        if !config.backgroundSound.url.isEmpty && config.backgroundSound.id != "None" {
            if !isFileCached(urlString: config.backgroundSound.url) {
                missingAssets.append(config.backgroundSound.url)
            }
        }
        
        // Check binaural beat
        if !config.binauralBeat.url.isEmpty && config.binauralBeat.id != "None" {
            if !isFileCached(urlString: config.binauralBeat.url) {
                missingAssets.append(config.binauralBeat.url)
            }
        }
        
        // Check all cues
        for setting in config.cueSettings {
            if !setting.cue.url.isEmpty {
                if !isFileCached(urlString: setting.cue.url) {
                    missingAssets.append(setting.cue.url)
                }
            }
        }
        
        return AssetAvailability(
            allAvailable: missingAssets.isEmpty,
            missingAssets: missingAssets
        )
    }
    
    /// Convenience method to check if a timer meditation can be played offline
    static func canPlayOffline(timer config: TimerSessionConfig) -> Bool {
        return checkTimerMeditation(config).allAvailable
    }
    
    // MARK: - Private Helpers
    
    /// Check if a file is cached locally using FileManagerHelper's prediction logic
    private static func isFileCached(urlString: String) -> Bool {
        guard !urlString.isEmpty else { return true } // Empty URL means no file needed
        
        // Predict the local filename using same logic as FileManagerHelper
        let predictedName = predictLocalFileName(for: urlString)
        let localURL = FileManagerHelper.shared.localFilePath(for: predictedName)
        
        return FileManagerHelper.shared.fileExists(at: localURL)
    }
    
    /// Predict what filename FileManagerHelper will use for a given URL
    /// This mirrors the logic in FileManagerHelper.ensureLocalFile()
    private static func predictLocalFileName(for urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return urlString
        }
        
        if url.scheme == "gs" {
            // Firebase Storage URL - use storage reference name
            let ref = Storage.storage().reference(forURL: urlString)
            return ref.name.isEmpty ? URL(fileURLWithPath: ref.fullPath).lastPathComponent : ref.name
        } else {
            // HTTP/HTTPS URL - decode and extract filename
            let decodedTail = url.lastPathComponent.removingPercentEncoding
            return decodedTail?.components(separatedBy: "/").last ?? url.lastPathComponent
        }
    }
}

