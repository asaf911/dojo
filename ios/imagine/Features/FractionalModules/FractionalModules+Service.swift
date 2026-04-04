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
}

// MARK: - Service (struct of closures)

extension FractionalModules {

    struct Service {
        var fetchPlan: (
            _ moduleId: String,
            _ durationSec: Int,
            _ voiceId: String,
            _ triggerContext: String?
        ) async throws -> Plan
    }
}

// MARK: - Live

extension FractionalModules.Service {

    static let live = FractionalModules.Service(
        fetchPlan: { moduleId, durationSec, voiceId, triggerContext in
            let tag = "🧠 AI_DEBUG [Fractional][Service]"
            let trigger = triggerContext ?? "unknown"
            print("\(tag) fetchPlan: start trigger=\(trigger) server=\(Config.serverLabel) moduleId=\(moduleId) durationSec=\(durationSec) voiceId=\(voiceId)")

            var request = URLRequest(url: Config.fractionalPlanURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(trigger, forHTTPHeaderField: "X-Trigger")

            let body = PostFractionalPlanRequestBody(
                moduleId: moduleId,
                durationSec: durationSec,
                voiceId: voiceId
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
        fetchPlan: { moduleId, durationSec, voiceId, _ in
            try await Task.sleep(nanoseconds: 300_000_000)
            return FractionalModules.Plan(
                planId: "preview-\(moduleId)-\(durationSec)",
                moduleId: moduleId,
                durationSec: durationSec,
                voiceId: voiceId,
                items: [
                    FractionalModules.PlanItem(atSec: 0, clipId: "NF_C001", role: "intro", text: "We will now begin a focus exercise.", url: "gs://preview/NF_C001.mp3"),
                    FractionalModules.PlanItem(atSec: 10, clipId: "NF_C002", role: "instruction", text: "Breathe normally through your nose and stay relaxed.", url: "gs://preview/NF_C002.mp3"),
                    FractionalModules.PlanItem(atSec: 22, clipId: "NF_C007", role: "reminder", text: "Keep your attention on the breath in your nose.", url: "gs://preview/NF_C007.mp3"),
                ]
            )
        }
    )
}
