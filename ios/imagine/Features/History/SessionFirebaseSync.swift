//
//  SessionFirebaseSync.swift
//  Dojo
//
//  Handles 2-way sync between local session history and Firebase Firestore.
//  Uses smart sync to minimize network usage - only downloads when needed.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Sync Metadata

/// Lightweight metadata for quick sync comparisons
struct SessionSyncMetadata {
    let sessionCount: Int
    let lastSessionAt: Date?
    let lastSyncedAt: Date
    
    init(sessionCount: Int, lastSessionAt: Date?, lastSyncedAt: Date = Date()) {
        self.sessionCount = sessionCount
        self.lastSessionAt = lastSessionAt
        self.lastSyncedAt = lastSyncedAt
    }
    
    init?(from data: [String: Any]) {
        guard let count = data["sessionCount"] as? Int else { return nil }
        self.sessionCount = count
        self.lastSessionAt = (data["lastSessionAt"] as? Timestamp)?.dateValue()
        self.lastSyncedAt = (data["lastSyncedAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}

// MARK: - Session Firebase Sync Manager

final class SessionFirebaseSync {
    static let shared = SessionFirebaseSync()
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Upload a single session to Firebase after meditation completion.
    /// Also updates the sync metadata.
    func uploadSession(_ session: MeditationSession) {
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("🔄 HISTORY_SYNC: No network - skipping upload for session \(session.id)")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🔄 HISTORY_SYNC: No user logged in - skipping upload")
            return
        }
        
        print("🔄 HISTORY_SYNC: Uploading session '\(session.title)' (id: \(session.id.uuidString.prefix(8))...)")
        
        let sessionRef = db.collection("users")
            .document(userId)
            .collection("sessions")
            .document(session.id.uuidString)
        
        let data = session.toFirestoreData()
        
        sessionRef.setData(data, merge: true) { [weak self] error in
            if let error = error {
                print("🔄 HISTORY_SYNC: Upload ERROR - \(error.localizedDescription)")
            } else {
                print("🔄 HISTORY_SYNC: Upload SUCCESS - session \(session.id.uuidString.prefix(8))...")
                // Update metadata after successful upload
                self?.updateSyncMetadata(userId: userId)
            }
        }
    }
    
    /// Delete a session from Firebase permanently
    func deleteSession(_ sessionId: UUID) {
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("🔄 HISTORY_SYNC: No network - session \(sessionId.uuidString.prefix(8))... deleted locally only")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🔄 HISTORY_SYNC: No user logged in - session deleted locally only")
            return
        }
        
        print("🔄 HISTORY_SYNC: Deleting session \(sessionId.uuidString.prefix(8))... from Firebase")
        
        let sessionRef = db.collection("users")
            .document(userId)
            .collection("sessions")
            .document(sessionId.uuidString)
        
        sessionRef.delete { [weak self] error in
            if let error = error {
                print("🔄 HISTORY_SYNC: Delete ERROR - \(error.localizedDescription)")
            } else {
                print("🔄 HISTORY_SYNC: Delete SUCCESS - session removed from Firebase")
                self?.updateSyncMetadata(userId: userId)
            }
        }
    }
    
    /// Smart sync: checks metadata first, only downloads if remote has more sessions.
    /// Called on app launch - network efficient for single-device users.
    func smartSync(completion: (() -> Void)? = nil) {
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("🔄 HISTORY_SYNC: [smartSync] No network - skipping")
            completion?()
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🔄 HISTORY_SYNC: [smartSync] No user logged in - skipping")
            completion?()
            return
        }
        
        print("🔄 HISTORY_SYNC: [smartSync] Starting for user \(userId.prefix(8))...")
        
        // 1. Fetch remote metadata (single small document read)
        fetchSyncMetadata(userId: userId) { [weak self] remoteMetadata in
            guard let self = self else {
                completion?()
                return
            }
            
            let localCount = SessionHistoryManager.shared.totalSessionCount
            let remoteCount = remoteMetadata?.sessionCount ?? 0
            
            print("🔄 HISTORY_SYNC: [smartSync] Local: \(localCount) sessions, Remote: \(remoteCount) sessions")
            
            // 2. Compare: does remote have more sessions?
            if remoteCount > localCount {
                // 3a. Download missing sessions (only those newer than our latest)
                let localLatest = SessionHistoryManager.shared.getMostRecentSession()?.createdAt
                print("🔄 HISTORY_SYNC: [smartSync] Remote has MORE - downloading delta...")
                
                self.downloadSessions(userId: userId, newerThan: localLatest) { remoteSessions in
                    print("🔄 HISTORY_SYNC: [smartSync] Downloaded \(remoteSessions.count) new sessions from Firebase")
                    if !remoteSessions.isEmpty {
                        SessionHistoryManager.shared.mergeRemoteSessions(remoteSessions)
                    }
                    // Upload any local sessions that might not be on server
                    self.uploadPendingLocalSessions(userId: userId, completion: completion)
                }
            } else if localCount > remoteCount {
                // 3b. Local has more - upload pending sessions
                print("🔄 HISTORY_SYNC: [smartSync] Local has MORE - uploading to Firebase...")
                self.uploadPendingLocalSessions(userId: userId, completion: completion)
            } else {
                // 3c. Counts match - nothing to do
                print("🔄 HISTORY_SYNC: [smartSync] COMPLETE - counts match, no sync needed")
                completion?()
            }
        }
    }
    
    /// Full sync: uploads all local sessions, then downloads all remote sessions.
    /// Called after login (especially on new device).
    func performFullSync(completion: (() -> Void)? = nil) {
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("🔄 HISTORY_SYNC: [fullSync] No network - skipping")
            completion?()
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🔄 HISTORY_SYNC: [fullSync] No user logged in - skipping")
            completion?()
            return
        }
        
        print("🔄 HISTORY_SYNC: [fullSync] Starting FULL sync for user \(userId.prefix(8))...")
        print("🔄 HISTORY_SYNC: [fullSync] Local sessions before sync: \(SessionHistoryManager.shared.totalSessionCount)")
        
        // 1. Upload all local sessions first
        uploadAllLocalSessions(userId: userId) { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            
            // 2. Download all remote sessions
            self.downloadAllSessions(userId: userId) { remoteSessions in
                print("🔄 HISTORY_SYNC: [fullSync] Fetched \(remoteSessions.count) sessions from Firebase")
                if !remoteSessions.isEmpty {
                    SessionHistoryManager.shared.mergeRemoteSessions(remoteSessions)
                }
                
                // 3. Update metadata
                self.updateSyncMetadata(userId: userId)
                
                print("🔄 HISTORY_SYNC: [fullSync] COMPLETE - Local sessions after sync: \(SessionHistoryManager.shared.totalSessionCount)")
                completion?()
            }
        }
    }
    
    // MARK: - Private: Metadata Operations
    
    private func fetchSyncMetadata(userId: String, completion: @escaping (SessionSyncMetadata?) -> Void) {
        let metaRef = db.collection("users")
            .document(userId)
            .collection("syncMetadata")
            .document("sessions")
        
        metaRef.getDocument { snapshot, error in
            if let error = error {
                print("🔄 HISTORY_SYNC: Error fetching metadata - \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = snapshot?.data() else {
                print("🔄 HISTORY_SYNC: No metadata found (new user or fresh install)")
                completion(nil)
                return
            }
            
            let metadata = SessionSyncMetadata(from: data)
            print("🔄 HISTORY_SYNC: Metadata fetched - remote count: \(metadata?.sessionCount ?? 0)")
            completion(metadata)
        }
    }
    
    private func updateSyncMetadata(userId: String) {
        let localSessions = SessionHistoryManager.shared.getAllSessions()
        let sessionCount = localSessions.count
        let lastSessionAt = localSessions.first?.createdAt
        
        let metaRef = db.collection("users")
            .document(userId)
            .collection("syncMetadata")
            .document("sessions")
        
        var data: [String: Any] = [
            "sessionCount": sessionCount,
            "lastSyncedAt": Timestamp(date: Date())
        ]
        
        if let lastAt = lastSessionAt {
            data["lastSessionAt"] = Timestamp(date: lastAt)
        }
        
        metaRef.setData(data, merge: true) { error in
            if let error = error {
                print("🔄 HISTORY_SYNC: Error updating metadata - \(error.localizedDescription)")
            } else {
                print("🔄 HISTORY_SYNC: Metadata updated - sessionCount: \(sessionCount)")
            }
        }
    }
    
    // MARK: - Private: Download Operations
    
    private func downloadSessions(userId: String, newerThan date: Date?, completion: @escaping ([MeditationSession]) -> Void) {
        var query: Query = db.collection("users")
            .document(userId)
            .collection("sessions")
            .order(by: "createdAt", descending: true)
        
        // If we have a date, only fetch sessions newer than it
        if let date = date {
            query = query.whereField("createdAt", isGreaterThan: Timestamp(date: date))
            print("🔄 HISTORY_SYNC: Downloading sessions newer than \(date)")
        } else {
            print("🔄 HISTORY_SYNC: Downloading ALL sessions (no local data)")
        }
        
        query.getDocuments { snapshot, error in
            if let error = error {
                print("🔄 HISTORY_SYNC: Download ERROR - \(error.localizedDescription)")
                completion([])
                return
            }
            
            let sessions = snapshot?.documents.compactMap { doc in
                MeditationSession.fromFirestoreData(doc.data())
            } ?? []
            
            print("🔄 HISTORY_SYNC: Downloaded \(sessions.count) sessions from Firebase")
            completion(sessions)
        }
    }
    
    private func downloadAllSessions(userId: String, completion: @escaping ([MeditationSession]) -> Void) {
        print("🔄 HISTORY_SYNC: Downloading ALL sessions from Firebase...")
        
        db.collection("users")
            .document(userId)
            .collection("sessions")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("🔄 HISTORY_SYNC: Download all ERROR - \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let sessions = snapshot?.documents.compactMap { doc in
                    MeditationSession.fromFirestoreData(doc.data())
                } ?? []
                
                print("🔄 HISTORY_SYNC: Downloaded \(sessions.count) total sessions from Firebase")
                completion(sessions)
            }
    }
    
    // MARK: - Private: Upload Operations
    
    private func uploadPendingLocalSessions(userId: String, completion: (() -> Void)? = nil) {
        let localSessions = SessionHistoryManager.shared.getAllSessions()
        
        guard !localSessions.isEmpty else {
            print("🔄 HISTORY_SYNC: No local sessions to upload")
            completion?()
            return
        }
        
        print("🔄 HISTORY_SYNC: Checking which local sessions need upload...")
        
        // First, get list of session IDs already on server
        db.collection("users")
            .document(userId)
            .collection("sessions")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion?()
                    return
                }
                
                if let error = error {
                    print("🔄 HISTORY_SYNC: Error checking remote sessions - \(error.localizedDescription)")
                    completion?()
                    return
                }
                
                let remoteIds = Set(snapshot?.documents.map { $0.documentID } ?? [])
                
                // Find local sessions not on server
                let pendingSessions = localSessions.filter { !remoteIds.contains($0.id.uuidString) }
                
                guard !pendingSessions.isEmpty else {
                    print("🔄 HISTORY_SYNC: All \(localSessions.count) local sessions already on Firebase")
                    completion?()
                    return
                }
                
                print("🔄 HISTORY_SYNC: Uploading \(pendingSessions.count) pending sessions to Firebase...")
                self.batchUpload(sessions: pendingSessions, userId: userId, completion: completion)
            }
    }
    
    private func uploadAllLocalSessions(userId: String, completion: @escaping () -> Void) {
        let localSessions = SessionHistoryManager.shared.getAllSessions()
        
        guard !localSessions.isEmpty else {
            print("🔄 HISTORY_SYNC: No local sessions to upload")
            completion()
            return
        }
        
        print("🔄 HISTORY_SYNC: Uploading all \(localSessions.count) local sessions to Firebase...")
        batchUpload(sessions: localSessions, userId: userId, completion: completion)
    }
    
    private func batchUpload(sessions: [MeditationSession], userId: String, completion: (() -> Void)?) {
        let batch = db.batch()
        
        for session in sessions {
            let ref = db.collection("users")
                .document(userId)
                .collection("sessions")
                .document(session.id.uuidString)
            batch.setData(session.toFirestoreData(), forDocument: ref, merge: true)
        }
        
        batch.commit { [weak self] error in
            if let error = error {
                print("🔄 HISTORY_SYNC: Batch upload ERROR - \(error.localizedDescription)")
            } else {
                print("🔄 HISTORY_SYNC: Batch upload SUCCESS - \(sessions.count) sessions uploaded")
                self?.updateSyncMetadata(userId: userId)
            }
            completion?()
        }
    }
}

