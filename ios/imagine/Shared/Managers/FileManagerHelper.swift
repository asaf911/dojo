//
//  FileManagerHelper.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-11
//

import Foundation
import FirebaseStorage

class FileManagerHelper {

    static let shared = FileManagerHelper()
    private init() {}

    func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func localFilePath(for fileName: String) -> URL {
        return getDocumentsDirectory().appendingPathComponent(fileName)
    }

    func fileExists(at url: URL) -> Bool {
        let exists = FileManager.default.fileExists(atPath: url.path)
        return exists
    }

    func downloadFile(from url: URL, setDownloading: @escaping (Bool) -> Void, completion: @escaping (URL?) -> Void) {
        setDownloading(true)
        if url.scheme == "gs" {
            // Use decoded URL: Swift's URL encodes spaces as %20, but Firebase Storage expects the actual path (spaces, not %20)
            let gsUrlString = url.absoluteString.removingPercentEncoding ?? url.absoluteString
            let storageRef = Config.storage(for: url.absoluteString).reference(forURL: gsUrlString)
            // Derive a stable, clean filename from the storage reference
            let cleanName = storageRef.name.isEmpty
                ? URL(fileURLWithPath: storageRef.fullPath).lastPathComponent
                : storageRef.name
            let destinationURL = self.localFilePath(for: cleanName)
            // Write directly to file to avoid HTTPS signed URL filename ambiguity
            storageRef.write(toFile: destinationURL) { _, error in
                setDownloading(false)
                if let err = error {
                    print("[Server][FileManager] Download failed (gs) url=\(url.absoluteString) error=\(err.localizedDescription)")
                    completion(nil)
                } else {
                    completion(destinationURL)
                }
            }
        } else {
            downloadFromURL(url, setDownloading: setDownloading, completion: completion)
        }
    }

    private func downloadFromURL(_ url: URL, setDownloading: @escaping (Bool) -> Void, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            if let err = error {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[Server][FileManager] Download failed (https) url=\(url.absoluteString) status=\(statusCode) error=\(err.localizedDescription)")
                setDownloading(false)
                completion(nil)
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("[Server][FileManager] Download failed (https) url=\(url.absoluteString) status=\(http.statusCode)")
                setDownloading(false)
                completion(nil)
                return
            }
            guard let localURL = localURL else {
                print("[Server][FileManager] Download failed (https) url=\(url.absoluteString) no localURL")
                setDownloading(false)
                completion(nil)
                return
            }
            do {
                // Prefer server-suggested filename when available
                let suggested = response?.suggestedFilename
                // Decode Firebase signed URL lastPathComponent to recover the original filename
                let decodedTail = url.lastPathComponent.removingPercentEncoding
                let decodedLastComponent = decodedTail?.components(separatedBy: "/").last
                let finalName = suggested ?? decodedLastComponent ?? url.lastPathComponent
                let destinationURL = self.localFilePath(for: finalName)
                if self.fileExists(at: destinationURL) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: localURL, to: destinationURL)
                setDownloading(false)
                completion(destinationURL)
            } catch {
                setDownloading(false)
                completion(nil)
            }
        }
        task.resume()
    }

    // MARK: - Convenience: Ensure local cache for a remote asset

    /// Ensures a local cached file exists for the given remote URL.
    /// If already cached, returns immediately with the cached URL. Otherwise downloads and caches it.
    /// If offline and file not cached, returns nil immediately to prevent hanging downloads.
    func ensureLocalFile(for remoteURL: URL, setDownloading: @escaping (Bool) -> Void, completion: @escaping (URL?) -> Void) {
        // Predict a clean filename for cache hit check prior to download
        let predictedName: String = {
            if remoteURL.scheme == "gs" {
                let gsUrlString = remoteURL.absoluteString.removingPercentEncoding ?? remoteURL.absoluteString
                let ref = Config.storage(for: remoteURL.absoluteString).reference(forURL: gsUrlString)
                return ref.name.isEmpty ? URL(fileURLWithPath: ref.fullPath).lastPathComponent : ref.name
            } else {
                let decodedTail = remoteURL.lastPathComponent.removingPercentEncoding
                return decodedTail?.components(separatedBy: "/").last ?? remoteURL.lastPathComponent
            }
        }()
        let destinationURL = localFilePath(for: predictedName)
        if fileExists(at: destinationURL) {
            completion(destinationURL)
            return
        }
        
        // Early exit if offline - prevents hanging download attempts
        guard NetworkMonitor.shared.isConnected else {
            print("FileManagerHelper: Skipping download - device is offline")
            completion(nil)
            return
        }
        
        downloadFile(from: remoteURL, setDownloading: setDownloading, completion: completion)
    }

    /// Convenience that accepts a URL string. Returns nil if the string is not a valid URL.
    func ensureLocalFile(forRemoteURLString urlString: String, setDownloading: @escaping (Bool) -> Void, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            completion(nil)
            return
        }
        ensureLocalFile(for: url, setDownloading: setDownloading, completion: completion)
    }
}
