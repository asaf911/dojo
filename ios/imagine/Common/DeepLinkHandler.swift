//
//  DeepLinkHandler.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-27
//

import Foundation
import SwiftUI

class DeepLinkHandler {

    /// Opens the timer player from a decoded portable plan (`pz` query, `pf=z1` fragment, or legacy `plan=` query).
    private static func presentPortableTimerPlan(
        _ planDocument: PortableTimerDeepLinkPlanV1,
        durationMinutes: Int,
        queryItems: [URLQueryItem],
        navigationCoordinator: NavigationCoordinator
    ) {
        guard planDocument.v == PortableTimerDeepLinkCodec.currentSchemaVersion, !planDocument.items.isEmpty else {
            logger.timerDeepLinkError("plan_reject reason=invalid_schema_or_empty v=\(planDocument.v) items=\(planDocument.items.count)")
            return
        }
        let bsID = queryItems.first(where: { $0.name == "bs" })?.value ?? "None"
        let bbID = queryItems.first(where: { $0.name == "bb" })?.value ?? "None"
        let backgroundSound = MeditationConfiguration.backgroundSound(forID: bsID)
        let binauralBeat: BinauralBeat = {
            if bbID == "None" {
                return BinauralBeat(id: "None", name: "None", url: "", description: nil)
            }
            return MeditationConfiguration.binauralBeat(forID: bbID)
                ?? BinauralBeat(id: "None", name: "None", url: "", description: nil)
        }()
        let title = queryItems.first(where: { $0.name == "af_sub1" })?.value.flatMap { raw -> String? in
            let once = raw.removingPercentEncoding ?? raw
            return once.removingPercentEncoding ?? once
        }
        let timerConfig = planDocument.toTimerSessionConfig(
            durationMinutes: durationMinutes,
            backgroundSound: backgroundSound,
            binauralBeat: binauralBeat,
            title: title,
            description: nil
        )
        let preview = planDocument.items.prefix(8).map { "\($0.clipId)@\($0.atSec)s" }.joined(separator: ",")
        logger.timerDeepLink(
            "plan_apply durMin=\(durationMinutes) bs=\(backgroundSound.id) bb=\(binauralBeat.id) items=\(planDocument.items.count) playbackSec=\(planDocument.playbackDurationSec.map(String.init) ?? "nil") preview=\(preview)"
        )
        navigationCoordinator.showPlayerFromDeepLinkedTimerConfig(timerConfig)
    }
    
    // Handles incoming URLs and navigates to the appropriate screen.
    static func handleIncomingURL(_ url: URL, source: String = "universalLink", eventName: String = "deep_link_open", navigationCoordinator: NavigationCoordinator) {
        let absLen = url.absoluteString.count
        logger.timerDeepLink("open urlLen=\(absLen) source=\(source) hasFragment=\(url.fragment != nil) queryLen=\(url.query?.count ?? 0)")
        
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = urlComponents?.queryItems
        
        // Check if the URL uses abbreviated deep link parameters ("dur" key)
        if let _ = queryItems?.first(where: { $0.name == "dur" })?.value {
            logger.timerDeepLink("route abbreviated_timer_query (dur=…)")
            // Ensure catalogs are loaded before decoding so ids (bs, bb, cues) resolve to models
            let group = DispatchGroup()
            group.enter()
            CatalogsManager.shared.fetchCatalogs(triggerContext: "DeepLinkHandler|incoming link resolve") { _ in group.leave() }
            group.notify(queue: .main) {
                guard let queryItems = urlComponents?.queryItems,
                      let durValue = queryItems.first(where: { $0.name == "dur" })?.value,
                      let durationMinutes = Int(durValue)
                else {
                    logger.timerDeepLinkError("abort reason=missing_dur_after_prefetch")
                    return
                }

                // `pz` query: zlib+base64url — survives OneLink / redirects that strip `#fragment`.
                if let pzRaw = TimerDeepLinkURLHelpers.rawPZParameter(from: url) {
                    let rawLen = pzRaw.count
                    let normLen = PortableTimerDeepLinkCodec.normalizeEncodedPlanToken(pzRaw).count
                    logger.timerDeepLink("decode_try path=pz rawLen=\(rawLen) normLen=\(normLen)")
                    switch PortableTimerDeepLinkCodec.decodeZlibPortablePlan(pzRaw) {
                    case .success(let planDocument):
                        logger.timerDeepLink("decode_ok path=pz items=\(planDocument.items.count)")
                        presentPortableTimerPlan(planDocument, durationMinutes: durationMinutes, queryItems: queryItems, navigationCoordinator: navigationCoordinator)
                        return
                    case .failure(let err):
                        logger.timerDeepLinkError("decode_fail path=pz err=\(err.localizedDescription)")
                    }
                } else {
                    logger.timerDeepLink("decode_skip path=pz reason=no_pz_param")
                }

                // `pf=z1` + URL fragment: zlib+JSON base64url after `#` (older shares).
                if queryItems.first(where: { $0.name == "pf" })?.value == "z1",
                   let fragment = url.fragment?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !fragment.isEmpty {
                    logger.timerDeepLink("decode_try path=fragment len=\(fragment.count)")
                    switch PortableTimerDeepLinkCodec.decodeZlibPortablePlan(fragment) {
                    case .success(let planDocument):
                        logger.timerDeepLink("decode_ok path=fragment items=\(planDocument.items.count)")
                        presentPortableTimerPlan(planDocument, durationMinutes: durationMinutes, queryItems: queryItems, navigationCoordinator: navigationCoordinator)
                        return
                    case .failure(let err):
                        logger.timerDeepLinkError("decode_fail path=fragment err=\(err.localizedDescription)")
                    }
                }

                // Legacy: portable plan in query `plan=` (raw JSON base64url, not zlib).
                if let planRaw = queryItems.first(where: { $0.name == "plan" })?.value {
                    let decodedPlanValue = PortableTimerDeepLinkCodec.percentDecodePlanQueryValue(planRaw)
                    logger.timerDeepLink("decode_try path=plan_query len=\(decodedPlanValue.count)")
                    if let planDocument = try? PortableTimerDeepLinkCodec.decodePlan(fromBase64URL: decodedPlanValue) {
                        logger.timerDeepLink("decode_ok path=plan_query items=\(planDocument.items.count)")
                        presentPortableTimerPlan(planDocument, durationMinutes: durationMinutes, queryItems: queryItems, navigationCoordinator: navigationCoordinator)
                        return
                    }
                    logger.timerDeepLinkError("decode_fail path=plan_query")
                }

                guard let meditationConfiguration = MeditationConfiguration(queryItems: queryItems) else {
                    logger.timerDeepLinkError("fallback_fail MeditationConfiguration(queryItems:) returned nil — no portable plan and no cu=")
                    return
                }
                let bbId = meditationConfiguration.binauralBeat?.id ?? "None"
                logger.timerDeepLink(
                    "fallback_ok path=cu_only dur=\(meditationConfiguration.duration) bs=\(meditationConfiguration.backgroundSound.id) bb=\(bbId) cues=\(meditationConfiguration.cueSettings.count)"
                )
                navigationCoordinator.showPlayerFromDeepLink(meditationConfiguration: meditationConfiguration)
            }
            return
        }
        
        // Fallback: check for practiceId deep links (unchanged)
        if let practiceId = queryItems?.first(where: { $0.name == "practiceId" })?.value {
            logger.eventMessage("Extracted Practice ID: \(practiceId)")
            DispatchQueue.main.async {
                // First navigate to main view
                navigationCoordinator.navigateTo(.main)
                
                findAudioFile(by: practiceId) { audioFile in
                    if let audioFile = audioFile {
                        logger.eventMessage("Audio file found for deep link: \(audioFile.id)")
                        
                        // Check if we're already in player view
                        if case .player(let currentFile, _, _) = navigationCoordinator.currentView {
                            // We're already in the player - update the current view instead of navigating again
                            logger.eventMessage("Already in player view with file: \(currentFile.id), updating to: \(audioFile.id)")
                            // Fade out background music before updating player
                            GeneralBackgroundMusicController.shared.fadeOutForPractice()
                            navigationCoordinator.currentView = .player(audioFile: audioFile, durationIndex: 0, isDownloading: true)
                        } else {
                            // Navigate to player normally
                            // Fade out background music before navigating to player
                            GeneralBackgroundMusicController.shared.fadeOutForPractice()
                            navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
                        }
                    } else {
                        logger.eventMessage("No audio file found for Practice ID: \(practiceId)")
                    }
                }
            }
        } else {
            logger.eventMessage("No valid practiceId found in deep link URL.")
        }
    }
    
    // Handles deep links from push notifications with retargeting support.
    static func handleDeepLinkFromPushNotification(_ url: URL, navigationCoordinator: NavigationCoordinator) {
        logger.eventMessage("Handling push notification deep link: \(url.absoluteString)")
        handleIncomingURL(url, source: "pushNotification", eventName: "push_deep_link_open", navigationCoordinator: navigationCoordinator)
    }

    // Finds an audio file by its practiceId, searching both regular audio files and Path steps.
    static func findAudioFile(by practiceId: String, completion: @escaping (AudioFile?) -> Void) {
        // First search in regular audio files
        AppFunctions.loadAudioFiles { audioFiles in
            if let foundAudioFile = audioFiles.first(where: { $0.id == practiceId }) {
                completion(foundAudioFile)
                return
            }
            
            // If not found in regular audio files, search in Path steps
            findPathStepAudioFile(by: practiceId, completion: completion)
        }
    }
    
    // Finds a Path step by its practiceId and converts it to AudioFile.
    private static func findPathStepAudioFile(by practiceId: String, completion: @escaping (AudioFile?) -> Void) {
        // First try to use cached Path steps from PathProgressManager (MainActor)
        Task { @MainActor in
            let cachedPathSteps = PathProgressManager.shared.pathSteps
            if !cachedPathSteps.isEmpty {
                if let foundPathStep = cachedPathSteps.first(where: { $0.id == practiceId }) {
                    let audioFile = foundPathStep.toAudioFile()
                    completion(audioFile)
                    return
                }
                // If not found in cache, return nil
                completion(nil)
                return
            }
            
            // If no cached data, fetch Path steps from server
            FirestoreManager.shared.fetchPathSteps { response in
                guard let steps = response?.steps else {
                    logger.eventMessage("No Path steps found for Practice ID: \(practiceId)")
                    completion(nil)
                    return
                }
                
                if let foundPathStep = steps.first(where: { $0.id == practiceId }) {
                    let audioFile = foundPathStep.toAudioFile()
                    logger.eventMessage("Path step found for deep link: \(foundPathStep.id)")
                    completion(audioFile)
                } else {
                    logger.eventMessage("No Path step found for Practice ID: \(practiceId)")
                    completion(nil)
                }
            }
        }
    }
}
