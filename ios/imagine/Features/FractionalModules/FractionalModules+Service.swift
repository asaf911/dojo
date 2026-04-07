//
//  FractionalModules+Service.swift
//  Dojo
//
//  POST /postFractionalPlan — fetches a second-precision playback timeline
//  for a fractional module (e.g. Nostril Focus composed from atomic clips).
//
//  QA: Filter console logs by "[Fractional]" to trace the entire fractional flow.
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

    enum CodingKeys: String, CodingKey {
        case moduleId
        case durationSec
        case voiceId
        case bodyScanDirection
        case introShort
        case introLong
        case includeEntry
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
            _ triggerContext: String?
        ) async throws -> Plan
    }
}

// MARK: - Live

extension FractionalModules.Service {

    static let live = FractionalModules.Service(
        fetchPlan: { moduleId, durationSec, voiceId, bodyScan, triggerContext in
            let tag = "🧠 AI_DEBUG [Fractional][Service]"
            let trigger = triggerContext ?? "unknown"
            let bsLog: String = {
                guard let b = bodyScan else { return "nil" }
                return "\(b.direction) introShort=\(b.introShort) introLong=\(b.introLong) entry=\(b.includeEntry)"
            }()
            print("\(tag) fetchPlan: start trigger=\(trigger) server=\(Config.serverLabel) moduleId=\(moduleId) durationSec=\(durationSec) voiceId=\(voiceId) bodyScan=\(bsLog)")

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
                includeEntry: bodyScan.map { $0.includeEntry }
            )
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                print("\(tag) fetchPlan: failure trigger=\(trigger) - invalid response type")
                throw NSError(domain: "FractionalModules", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            if http.statusCode != 200 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                print("\(tag) fetchPlan: failure trigger=\(trigger) status=\(http.statusCode) body=\(String(bodyStr.prefix(200)))")
                throw NSError(domain: "FractionalModules", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"])
            }

            do {
                let plan = try JSONDecoder().decode(FractionalModules.Plan.self, from: data)
                print("\(tag) fetchPlan: success trigger=\(trigger) planId=\(plan.planId) items=\(plan.items.count)")
                return plan
            } catch {
                print("\(tag) fetchPlan: failure trigger=\(trigger) decode error - \(error.localizedDescription)")
                throw error
            }
        }
    )
}

// MARK: - Preview

extension FractionalModules.Service {

    static let preview = FractionalModules.Service(
        fetchPlan: { moduleId, durationSec, voiceId, bodyScan, _ in
            try await Task.sleep(nanoseconds: 300_000_000)

            let items: [FractionalModules.PlanItem]
            switch moduleId {
            case "IM_FRAC":
                items = [
                    FractionalModules.PlanItem(atSec: 0, clipId: "IM_C002", role: "instruction", text: "Begin repeating the following mantra in your mind.", url: "gs://preview/IM_C002.mp3"),
                    FractionalModules.PlanItem(atSec: 10, clipId: "IM_C003", role: "instruction", text: "I AM, I AM, I AM", url: "gs://preview/IM_C003.mp3"),
                    FractionalModules.PlanItem(atSec: 22, clipId: "IM_C006", role: "reminder", text: "Keep repeating the mantra.", url: "gs://preview/IM_C006.mp3"),
                ]
            case "BS_FRAC":
                let entry = bodyScan?.includeEntry == true
                let shortOn = bodyScan?.introShort != false
                let longOn = bodyScan?.introLong == true
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
            default:
                items = [
                    FractionalModules.PlanItem(atSec: 0, clipId: "NF_C001", role: "intro", text: "We will now begin a focus exercise.", url: "gs://preview/NF_C001.mp3"),
                    FractionalModules.PlanItem(atSec: 10, clipId: "NF_C002", role: "instruction", text: "Breathe normally through your nose and stay relaxed.", url: "gs://preview/NF_C002.mp3"),
                    FractionalModules.PlanItem(atSec: 22, clipId: "NF_C007", role: "reminder", text: "Keep your attention on the breath in your nose.", url: "gs://preview/NF_C007.mp3"),
                ]
            }

            return FractionalModules.Plan(
                planId: "preview-\(moduleId)-\(durationSec)",
                moduleId: moduleId,
                durationSec: durationSec,
                voiceId: voiceId,
                items: items
            )
        }
    )
}
