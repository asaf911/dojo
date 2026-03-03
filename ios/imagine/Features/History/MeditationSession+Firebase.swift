//
//  MeditationSession+Firebase.swift
//  Dojo
//
//  Firestore conversion extensions for MeditationSession and related types.
//  Isolated here to keep the main model file clean.
//

import Foundation
import FirebaseFirestore

// MARK: - MeditationSession Firestore Conversion

extension MeditationSession {
    
    /// Convert to Firestore-compatible dictionary
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "createdAt": Timestamp(date: createdAt),
            "sessionType": sessionType.rawValue,
            "source": source.rawValue,
            "title": title,
            "plannedDurationSeconds": plannedDurationSeconds,
            "actualDurationSeconds": actualDurationSeconds,
            "completionRate": completionRate,
            "outcome": outcome.rawValue,
            "tags": tags,
            "metadata": metadata,
            "syncedAt": Timestamp(date: Date())
        ]
        
        // Add app version for debugging
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            data["appVersion"] = appVersion
        }
        
        // Optional fields
        if let description = description {
            data["description"] = description
        }
        if let practiceId = practiceId {
            data["practiceId"] = practiceId
        }
        if let category = category {
            data["category"] = category
        }
        
        // Nested objects
        if let hr = heartRate {
            data["heartRate"] = hr.toFirestoreData()
        }
        if let config = customConfig {
            data["customConfig"] = config.toFirestoreData()
        }
        if let ctx = context {
            data["context"] = ctx.toFirestoreData()
        }
        
        return data
    }
    
    /// Create from Firestore document data
    static func fromFirestoreData(_ data: [String: Any]) -> MeditationSession? {
        // Required fields
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let createdTimestamp = data["createdAt"] as? Timestamp,
              let sessionTypeRaw = data["sessionType"] as? String,
              let sessionType = MeditationSessionType(rawValue: sessionTypeRaw),
              let sourceRaw = data["source"] as? String,
              let source = MeditationSessionSource(rawValue: sourceRaw),
              let title = data["title"] as? String,
              let plannedDuration = data["plannedDurationSeconds"] as? Int,
              let actualDuration = data["actualDurationSeconds"] as? Int,
              let outcomeRaw = data["outcome"] as? String,
              let outcome = SessionOutcome(rawValue: outcomeRaw)
        else {
            print("AI_DEBUG SYNC: Failed to parse MeditationSession from Firestore data")
            return nil
        }
        
        // Optional nested objects
        let heartRate: SessionHeartRateData? = (data["heartRate"] as? [String: Any])
            .flatMap { SessionHeartRateData.fromFirestoreData($0) }
        
        let customConfig: SessionCustomConfig? = (data["customConfig"] as? [String: Any])
            .flatMap { SessionCustomConfig.fromFirestoreData($0) }
        
        let context: SessionContext? = (data["context"] as? [String: Any])
            .flatMap { SessionContext.fromFirestoreData($0) }
        
        return MeditationSession(
            id: id,
            createdAt: createdTimestamp.dateValue(),
            sessionType: sessionType,
            source: source,
            title: title,
            description: data["description"] as? String,
            practiceId: data["practiceId"] as? String,
            category: data["category"] as? String,
            tags: data["tags"] as? [String] ?? [],
            plannedDurationSeconds: plannedDuration,
            actualDurationSeconds: actualDuration,
            completionRate: data["completionRate"] as? Double ?? 1.0,
            outcome: outcome,
            heartRate: heartRate,
            customConfig: customConfig,
            context: context,
            metadata: data["metadata"] as? [String: String] ?? [:]
        )
    }
}

// MARK: - SessionHeartRateData Firestore Conversion

extension SessionHeartRateData {
    
    /// Convert to Firestore-compatible dictionary
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "readingCount": readingCount
        ]
        
        if let v = startBPM { data["startBPM"] = v }
        if let v = endBPM { data["endBPM"] = v }
        if let v = averageBPM { data["averageBPM"] = v }
        if let v = minBPM { data["minBPM"] = v }
        if let v = maxBPM { data["maxBPM"] = v }
        if let v = changePercent { data["changePercent"] = v }
        if let v = source { data["source"] = v }
        
        // Convert samples array
        data["samples"] = samples.map { sample in
            [
                "minuteOffset": sample.minuteOffset,
                "bpm": sample.bpm
            ]
        }
        
        return data
    }
    
    /// Create from Firestore document data
    static func fromFirestoreData(_ data: [String: Any]) -> SessionHeartRateData {
        let samples: [HeartRateSamplePoint] = (data["samples"] as? [[String: Any]] ?? []).compactMap { sampleData in
            guard let offset = sampleData["minuteOffset"] as? Double,
                  let bpm = sampleData["bpm"] as? Double else {
                return nil
            }
            return HeartRateSamplePoint(minuteOffset: offset, bpm: bpm)
        }
        
        return SessionHeartRateData(
            startBPM: data["startBPM"] as? Double,
            endBPM: data["endBPM"] as? Double,
            averageBPM: data["averageBPM"] as? Double,
            minBPM: data["minBPM"] as? Double,
            maxBPM: data["maxBPM"] as? Double,
            changePercent: data["changePercent"] as? Double,
            readingCount: data["readingCount"] as? Int ?? 0,
            source: data["source"] as? String,
            samples: samples
        )
    }
}

// MARK: - SessionCustomConfig Firestore Conversion

extension SessionCustomConfig {
    
    /// Convert to Firestore-compatible dictionary
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "cueIds": cueIds,
            "cueNames": cueNames
        ]
        
        if let v = backgroundSoundId { data["backgroundSoundId"] = v }
        if let v = backgroundSoundName { data["backgroundSoundName"] = v }
        if let v = binauralBeatId { data["binauralBeatId"] = v }
        if let v = binauralBeatName { data["binauralBeatName"] = v }
        
        return data
    }
    
    /// Create from Firestore document data
    static func fromFirestoreData(_ data: [String: Any]) -> SessionCustomConfig {
        return SessionCustomConfig(
            backgroundSoundId: data["backgroundSoundId"] as? String,
            backgroundSoundName: data["backgroundSoundName"] as? String,
            binauralBeatId: data["binauralBeatId"] as? String,
            binauralBeatName: data["binauralBeatName"] as? String,
            cueIds: data["cueIds"] as? [String] ?? [],
            cueNames: data["cueNames"] as? [String] ?? []
        )
    }
}

// MARK: - SessionContext Firestore Conversion

extension SessionContext {
    
    /// Convert to Firestore-compatible dictionary
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "watchConnected": watchConnected,
            "airpodsConnected": airpodsConnected
        ]
        
        if let v = timeOfDay { data["timeOfDay"] = v }
        if let v = dayOfWeek { data["dayOfWeek"] = v }
        
        return data
    }
    
    /// Create from Firestore document data
    static func fromFirestoreData(_ data: [String: Any]) -> SessionContext {
        return SessionContext(
            timeOfDay: data["timeOfDay"] as? String,
            dayOfWeek: data["dayOfWeek"] as? Int,
            watchConnected: data["watchConnected"] as? Bool ?? false,
            airpodsConnected: data["airpodsConnected"] as? Bool ?? false
        )
    }
}

