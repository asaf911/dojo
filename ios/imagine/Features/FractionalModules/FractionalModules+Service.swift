//
//  FractionalModules+Service.swift
//  Dojo
//
//  POST /postFractionalPlan — second-precision `Plan` JSON for NF_FRAC, IM_FRAC, MV_*_FRAC, BS_FRAC.
//  BS_FRAC request fields: `bodyScanDirection`, `introShort`, `introLong`, `includeEntry` (see server doc
//  `docs/body-scan-tier-composer.md`). Logs: filter "[Fractional]".
//

import Foundation

// MARK: - Request Model

private struct PostFractionalPlanRequestBody: Encodable {
    let moduleId: String
    let durationSec: Int
    let voiceId: String
    let bodyScanDirection: String?
    let introShort: Bool?
    let introLong: Bool?
    let includeEntry: Bool?
    let atTimelineStart: Bool

    enum CodingKeys: String, CodingKey {
        case moduleId
        case durationSec
        case voiceId
        case bodyScanDirection
        case introShort
        case introLong
        case includeEntry
        case atTimelineStart
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moduleId, forKey: .moduleId)
        try container.encode(durationSec, forKey: .durationSec)
        try container.encode(voiceId, forKey: .voiceId)
        try container.encodeIfPresent(bodyScanDirection, forKey: .bodyScanDirection)
        try container.encodeIfPresent(introShort, forKey: .introShort)
        try container.encodeIfPresent(introLong, forKey: .introLong)
        try container.encodeIfPresent(includeEntry, forKey: .includeEntry)
        try container.encode(atTimelineStart, forKey: .atTimelineStart)
    }
}

// MARK: - Service (struct of closures)

extension FractionalModules {

    struct Service {
        var fetchPlan: (
            _ moduleId: String,
            _ durationSec: Int,
            _ voiceId: String,
            _ bodyScan: (direction: String, introShort: Bool, introLong: Bool, includeEntry: Bool)?,
            _ atTimelineStart: Bool,
            _ triggerContext: String?
        ) async throws -> Plan
    }
}

// MARK: - Live

extension FractionalModules.Service {

    static let live = FractionalModules.Service(
        fetchPlan: { moduleId, durationSec, voiceId, bodyScan, atTimelineStart, triggerContext in
            let trigger = triggerContext ?? "unknown"
            let bsLog: String = {
                guard let b = bodyScan else { return "nil" }
                return "\(b.direction) introShort=\(b.introShort) introLong=\(b.introLong) entry=\(b.includeEntry)"
            }()
            #if DEBUG
            let tag = "🧠 AI_DEBUG [Fractional][Service]"
            print("\(tag) fetchPlan: start trigger=\(trigger) server=\(Config.serverLabel) moduleId=\(moduleId) durationSec=\(durationSec) voiceId=\(voiceId) atTimelineStart=\(atTimelineStart) bodyScan=\(bsLog)")
            #endif

            var request = URLRequest(url: Config.fractionalPlanURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(trigger, forHTTPHeaderField: "X-Trigger")

            let body = PostFractionalPlanRequestBody(
                moduleId: moduleId,
                durationSec: durationSec,
                voiceId: voiceId,
                bodyScanDirection: bodyScan?.direction,
                introShort: bodyScan?.introShort,
                introLong: bodyScan?.introLong,
                includeEntry: bodyScan.map { $0.includeEntry },
                atTimelineStart: atTimelineStart
            )
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                #if DEBUG
                print("🧠 AI_DEBUG [Fractional][Service] fetchPlan: failure trigger=\(trigger) - invalid response type")
                #endif
                throw NSError(domain: "FractionalModules", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            if http.statusCode != 200 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                #if DEBUG
                print("🧠 AI_DEBUG [Fractional][Service] fetchPlan: failure trigger=\(trigger) status=\(http.statusCode) body=\(String(bodyStr.prefix(200)))")
                #endif
                throw NSError(domain: "FractionalModules", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"])
            }

            do {
                let plan = try JSONDecoder().decode(FractionalModules.Plan.self, from: data)
                #if DEBUG
                print("🧠 AI_DEBUG [Fractional][Service] fetchPlan: success trigger=\(trigger) planId=\(plan.planId) items=\(plan.items.count)")
                #endif
                return plan
            } catch {
                #if DEBUG
                print("🧠 AI_DEBUG [Fractional][Service] fetchPlan: failure trigger=\(trigger) decode error - \(error.localizedDescription)")
                #endif
                throw error
            }
        }
    )
}

// MARK: - Preview

extension FractionalModules.Service {

    static let preview = FractionalModules.Service(
        fetchPlan: { moduleId, durationSec, voiceId, bodyScan, atTimelineStart, _ in
            try await Task.sleep(nanoseconds: 300_000_000)

            let framingIntroAllowed = durationSec >= 300 || atTimelineStart

            let items: [FractionalModules.PlanItem]
            switch moduleId {
            case "IM_FRAC":
                items = [
                    FractionalModules.PlanItem(atSec: 0, clipId: "IM_C002", role: "instruction", text: "Begin repeating the following mantra in your mind.", url: "gs://preview/IM_C002.mp3"),
                    FractionalModules.PlanItem(atSec: 10, clipId: "IM_C003", role: "instruction", text: "I AM, I AM, I AM", url: "gs://preview/IM_C003.mp3"),
                    FractionalModules.PlanItem(atSec: 22, clipId: "IM_C006", role: "reminder", text: "Keep repeating the mantra.", url: "gs://preview/IM_C006.mp3"),
                ]
            case "INT_FRAC":
                items = [
                    FractionalModules.PlanItem(atSec: 7, clipId: "INT_GRT_106", role: "instruction", text: "Welcome", url: "gs://preview/INT_GRT_106.mp3"),
                    FractionalModules.PlanItem(atSec: 14, clipId: "INT_ARR_122", role: "instruction", text: "Get comfortable", url: "gs://preview/INT_ARR_122.mp3"),
                    FractionalModules.PlanItem(atSec: 23, clipId: "INT_ORI_140", role: "instruction", text: "Observe the breath", url: "gs://preview/INT_ORI_140.mp3"),
                ]
            case "PB_FRAC":
                let pbOpen = durationSec > 60 && framingIntroAllowed
                if pbOpen {
                    items = [
                        FractionalModules.PlanItem(atSec: 0, clipId: "PBV_OPEN_000_INTRO_ASAF", role: "intro", text: "Perfect breath intro", url: "gs://preview/PBV_OPEN.mp3"),
                        FractionalModules.PlanItem(atSec: 12, clipId: "PBV_BREATH_100", role: "instruction", text: "Prep inhale", url: "gs://preview/100.mp3"),
                    ]
                } else {
                    items = [
                        FractionalModules.PlanItem(atSec: 0, clipId: "PBV_BREATH_100", role: "instruction", text: "Prep inhale", url: "gs://preview/100.mp3"),
                    ]
                }
            case "BS_FRAC":
                let entry = bodyScan?.includeEntry == true
                let shortOn = framingIntroAllowed && (bodyScan?.introShort != false)
                let longOn = framingIntroAllowed && (bodyScan?.introLong == true)
                var t = 0
                var list: [FractionalModules.PlanItem] = []
                if shortOn {
                    list.append(FractionalModules.PlanItem(atSec: t, clipId: "BS_SYS_000_INTRO_SHORT_ASAF", role: "intro", text: "We will now begin a body scan", url: "gs://preview/intro-short.mp3"))
                    t += 5 + 7
                }
                if longOn {
                    list.append(FractionalModules.PlanItem(atSec: t, clipId: "BS_SYS_010_INTRO_LONG_ASAF", role: "intro", text: "Long intro", url: "gs://preview/intro-long.mp3"))
                    t += 5 + 7
                }
                if entry {
                    list.append(FractionalModules.PlanItem(atSec: t, clipId: "BS_SYS_020_ENTRY_TOP_MACRO_ASAF", role: "entry", text: "Relax your head face and neck", url: "gs://preview/entry.mp3"))
                    t += 5 + 7
                }
                list.append(FractionalModules.PlanItem(atSec: t, clipId: "BS_MAC_120_CHEST_BELLY_ASAF", role: "instruction", text: "Relax your chest and belly", url: "gs://preview/m2.mp3"))
                t += 5 + 20
                list.append(FractionalModules.PlanItem(atSec: t, clipId: "BS_MAC_140_LEGS_FEET_ASAF", role: "instruction", text: "Relax your legs and feet", url: "gs://preview/m3.mp3"))
                items = list
            case "MV_KM_FRAC":
                items = [
                    FractionalModules.PlanItem(atSec: 0, clipId: "MVK_C001", role: "instruction", text: "Mind's eye", url: "gs://preview/MVK_C001.mp3"),
                    FractionalModules.PlanItem(atSec: 12, clipId: "MVK_C004", role: "instruction", text: "Begin your day", url: "gs://preview/MVK_C004.mp3"),
                    FractionalModules.PlanItem(atSec: 28, clipId: "MVK_C010", role: "outro", text: "Return to breath", url: "gs://preview/MVK_C010.mp3"),
                ]
            case "MV_GR_FRAC":
                items = [
                    FractionalModules.PlanItem(atSec: 0, clipId: "MVG_C001", role: "instruction", text: "Mind's eye", url: "gs://preview/MVG_C001.mp3"),
                    FractionalModules.PlanItem(atSec: 12, clipId: "MVG_C004", role: "instruction", text: "Gratitude", url: "gs://preview/MVG_C004.mp3"),
                    FractionalModules.PlanItem(atSec: 30, clipId: "MVG_C010", role: "reminder", text: "Feel gratitude", url: "gs://preview/MVG_C010.mp3"),
                ]
            default:
                if framingIntroAllowed {
                    items = [
                        FractionalModules.PlanItem(atSec: 0, clipId: "NF_C001", role: "intro", text: "We will now begin a focus exercise.", url: "gs://preview/NF_C001.mp3"),
                        FractionalModules.PlanItem(atSec: 10, clipId: "NF_C002", role: "instruction", text: "Breathe normally through your nose and stay relaxed.", url: "gs://preview/NF_C002.mp3"),
                        FractionalModules.PlanItem(atSec: 22, clipId: "NF_C007", role: "reminder", text: "Keep your attention on the breath in your nose.", url: "gs://preview/NF_C007.mp3"),
                    ]
                } else {
                    items = [
                        FractionalModules.PlanItem(atSec: 0, clipId: "NF_C002", role: "instruction", text: "Breathe normally through your nose and stay relaxed.", url: "gs://preview/NF_C002.mp3"),
                        FractionalModules.PlanItem(atSec: 22, clipId: "NF_C007", role: "reminder", text: "Keep your attention on the breath in your nose.", url: "gs://preview/NF_C007.mp3"),
                    ]
                }
            }

            /// Matches `FRACTIONAL_FIRST_SPEECH_OFFSET_SEC` on the server (INT_FRAC already encodes this in its timeline).
            let firstSpeechLeadInSec = (atTimelineStart && moduleId != "INT_FRAC") ? 7 : 0
            let shiftedItems: [FractionalModules.PlanItem] = firstSpeechLeadInSec == 0
                ? items
                : items.map {
                    FractionalModules.PlanItem(
                        atSec: $0.atSec + firstSpeechLeadInSec,
                        clipId: $0.clipId,
                        role: $0.role,
                        text: $0.text,
                        url: $0.url,
                        parallel: $0.parallel
                    )
                }

            return FractionalModules.Plan(
                planId: "preview-\(moduleId)-\(durationSec)",
                moduleId: moduleId,
                durationSec: durationSec,
                voiceId: voiceId,
                items: shiftedItems
            )
        }
    )
}
