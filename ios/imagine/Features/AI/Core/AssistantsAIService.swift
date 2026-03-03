import Foundation

// MARK: - OpenAI Assistants API Models (v2)

private struct AssistantsThreadResponse: Codable {
    let id: String
}

private struct AssistantsRunResponse: Codable {
    let id: String
    let status: String
}

private struct AssistantsListMessagesResponse: Codable {
    struct Message: Codable {
        struct Content: Codable {
            struct Text: Codable {
                let value: String
            }
            let type: String
            let text: Text?
        }
        let id: String
        let role: String
        let content: [Content]
    }
    let data: [Message]
}

// MARK: - Dojo Assistant Response Envelope (optional multi-mode)

private struct AssistantResponseEnvelope: Codable {
    enum ResponseType: String, Codable { case meditation, clarify, explain }
    let responseType: ResponseType
    let message: String?
    let suggestions: [String]?
    let meditation: AIGeneratedTimer?
    let sourceTitles: [String]?
}

// MARK: - Assistants-based AI Meditation Service

final class AssistantsAIService {
    // TODO: Load from secure config (e.g. xcconfig in .gitignore) - never commit API keys
    private let apiKey = ""
    private let baseURL = "https://api.openai.com/v1"
    private let assistantId = "asst_84zH7QceqJJBmWeUEbSnYdD5"
    private var threadId: String?
    // Expose current thread id for analytics correlation when available
    public var currentThreadId: String? { threadId }
    // Shared resource load task to avoid duplicate Firebase fetches across requests
    private static var resourceLoadTask: Task<Void, Never>?
    // Extra guardrails to reinforce retrieval-only explain answers
    // Build dynamic grounding instructions from Firebase catalogs (backgrounds + cues + binaural beats)
    private func buildGroundingInstructions() -> String {
        let backgrounds: String = {
            let list = CatalogsManager.shared.sounds
            if list.isEmpty { return "- None: No Background" }
            return list.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        }()
        let cuesList = CatalogsManager.shared.cues
        let cuesAsList: String = cuesList.isEmpty ? "- SI: Settling In" : cuesList.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        let cueEnum: String = cuesList.map { "\"\($0.id)\"" }.joined(separator: ", ")
        let beatsList: String = {
            let beats = CatalogsManager.shared.beats
            if beats.isEmpty { return "- BB2: 2 Hz (Sleep)\n- BB4: 4 Hz (Imagination)\n- BB6: 6 Hz (Future Vision)\n- BB10: 10 Hz (Relaxation)\n- BB14: 14 Hz (Focus)\n- BB40: 40 Hz (Gratitude)" }
            return beats.map { beat in
                "- \(beat.id): \(beat.name)"
            }.joined(separator: "\n")
        }()

        return """
ROLE
You are Dojo's meditation architect. Keep generation simple; the app enforces exact scheduling and validation.

OUTPUT POLICY
- Return ONE JSON object that matches the schema exactly. No prose or code fences.
- Keep total output compact. Prefer short titles and descriptions.

ROUTING
- responseType = "meditation" when the user asks to create/make/build a session or mentions a duration.
- responseType = "clarify" when ambiguous; include exactly ONE concrete suggestion and end with a short yes/no question.
- responseType = "explain" when the user asks about meditation/Dojo or asks about benefits/effectiveness (e.g., "will this help my anxiety?"). You MAY consult provided files and must cite up to 3 titles in sourceTitles. Keep message ≤ 120 words.

TOOLS POLICY (latency critical)
- For "meditation" and "clarify": DO NOT use tools. Produce JSON immediately from your knowledge and rules below.
- For "explain": You MAY use File Search to consult provided files; cite up to 3 relevant file titles in sourceTitles. Keep message ≤ 120 words.
- Never call tools just to choose background sound or schedule cues.

AVAILABLE BACKGROUNDS (from Firebase; choose exactly one)


\(backgrounds)

        AVAILABLE CUES (from Firebase; only use these ids)

\(cuesAsList)

AVAILABLE BINAURAL BEATS (from Firebase; select exactly one when relevant)

\(beatsList)

SCHEMA (ids restricted to the dynamic cue list)
{
  "name": "dojo_response",
  "strict": true,
  "schema": {
    "type": "object",
    "additionalProperties": false,
    "required": ["responseType","message","suggestions","sourceTitles","meditation"],
    "properties": {
      "responseType": { "type": "string", "enum": ["meditation","clarify","explain"] },
      "message": { "type": ["string","null"] },
      "suggestions": { "type": ["array","null"], "items": { "type": "string" } },
      "sourceTitles": { "type": ["array","null"], "items": { "type": "string" } },
      "meditation": {
        "type": ["object","null"],
        "additionalProperties": false,
        "required": ["duration","backgroundSoundId","segments","cues","title","description"],
        "properties": {
          "duration": { "type": "integer", "minimum": 1, "maximum": 180 },
          "backgroundSoundId": { "type": "string", "minLength": 1 },
          "segments": {
            "type": ["array","null"],
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["type","id","length","cueAudio","quietSpan"],
              "properties": {
                "type": { "type": "string", "enum": ["finite","cue"] },
                "id": { "type": "string", "enum": [\(cueEnum)] },
                "length": { "type": ["integer","null"], "minimum": 0 },
                "cueAudio": { "type": ["integer","null"], "minimum": 0 },
                "quietSpan": { "type": ["integer","null"], "minimum": 0 }
              }
            }
          },
          "cues": {
            "type": "array",
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["id","trigger"],
              "properties": {
                "id": { "type": "string", "enum": [\(cueEnum)] },
                "trigger": { "type": "string", "pattern": "^(start|end|[1-9][0-9]*)$" }
              }
            }
          },
          "title": { "type": "string", "minLength": 1 },
          "description": { "type": "string", "minLength": 1 }
        }
      }
    }
  }
}

        GENERATION GUIDELINES
- Duration: default 10 minutes if not provided.
- Background music: choose exactly one for the entire session (no toggling).
- Finite modules: SI (1m), PB (2m), BS or BS1–BS10 (1–10m), IM2–IM10 (2–10m I AM Mantra), NF1–NF10 (1–10m Nostril Focus). Prefer a single guided BS. Sleep → longer; focus → shorter. If unsure, output "BS".
- SI always at "start".
- If PB is included, it starts at minute "1" (immediately after SI).
- If BS is included, it starts immediately after the previous block (contiguous).
- IM (I AM Mantra) and NF (Nostril Focus) are finite focus modules placed in the focus phase (50-75%). Use only ONE per session unless user explicitly requests both. Select variant based on available time (e.g., IM3 or NF3 for 3 minutes).
- Open-ended cues (OH, VC, RT) mark a focus period. Place the cue at the start minute; the app fills the quiet span.
- GB for non-sleep: set at "end". Omit GB for sleep.
- Triggers: only SI uses "start"; only GB uses "end"; all others use whole-minute strings ("1","2", …).
- Segments (optional but recommended):
  - type = "finite": use length = minutes.
  - type = "cue": use cueAudio = minutes and quietSpan = minutes.

BINAURAL BEATS SELECTION RULES
- Choose at most one binaural beat that aligns with the user's intent. If not relevant, omit.
- Sleep/bedtime/deep sleep → use BB2 (2 Hz delta - deep sleep).
- Imagination/visualization/creativity/inner exploration → use BB4 (4 Hz theta).
- Future vision/intention/transformation → use BB6 (6 Hz theta/alpha).
- Relaxation/stress relief/calm → use BB10 (10 Hz alpha).
- Focus/concentration/productivity → use BB14 (14 Hz beta).
- Gratitude/compassion/heart-opening → use BB40 (40 Hz gamma).

AMBIGUITY HANDLING
- If constraints feel tight or unclear, set responseType = "clarify" and suggest exactly ONE concrete adjustment (e.g., "extend duration by 5m"), then end with a single yes/no question.
"""
    }

    // Entry point to generate a meditation or conversational response
    func generateMeditation(prompt: String, conversationHistory: [ChatMessage] = [], variationSeed: Int? = nil, lastMeditation: AITimerResponse?) async throws -> AIMeditationResult {
        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: generateMeditation start. Prompt=\(prompt)")
        // Reuse a thread where possible; batch-seed on first use
        if let existing = threadId {
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Reusing thread \(existing)")
            logger.aiChat("OPENAI_ASSISTANTS thread_reuse id=\(existing)")
            do {
                try await addMessage(threadId: existing, role: "user", content: prompt)
            } catch {
                // If a previous run is still active on this thread, OpenAI returns 400. Start a new thread.
                logger.errorMessage("🧭 AI_DEBUG [ASSISTANT]: addMessage failed on existing thread (likely active run). Spawning new thread. Error=\(error)")
                let batchedMessages = trimHistory(conversationHistory) + [(role: "user", content: prompt)]
                let created = try await createThreadWithMessages(batchedMessages)
                self.threadId = created
                logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Created new thread \(created) after reuse failure")
                logger.aiChat("OPENAI_ASSISTANTS thread_new id=\(created) msg_count=\(batchedMessages.count)")
            }
        } else {
            let batchedMessages = trimHistory(conversationHistory) + [(role: "user", content: prompt)]
            let created = try await createThreadWithMessages(batchedMessages)
            self.threadId = created
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Created new thread \(created)")
            logger.aiChat("OPENAI_ASSISTANTS thread_new id=\(created) msg_count=\(batchedMessages.count)")
        }

        let effectiveThread = self.threadId! // set above

        // Simple classifier hint: only force meditation when there's a clear request
        let lower = prompt.lowercased()
        // If user greets with a short message, steer to a single friendly question
        let isGreeting = ["hi","hello","hey","yo","sup","hola"].contains(lower.trimmingCharacters(in: .whitespacesAndNewlines))
        let hasExplicitDuration: Bool = {
            // digits + (min|minute|minutes) or word "minute" nearby
            let patterns = ["\\b[0-9]{1,3}\\s*(min|mins|minute|minutes)\\b", "\\bminute\\b"]
            return patterns.contains { (pat) -> Bool in
                (try? NSRegularExpression(pattern: pat, options: .caseInsensitive))?
                    .firstMatch(in: lower, options: [], range: NSRange(location: 0, length: lower.utf16.count)) != nil
            }
        }()
        let strongCreateVerb = lower.contains("create") || lower.contains("make") || lower.contains("build") || lower.contains("craft") || lower.contains("generate")
        let sessionWords = lower.contains("session") || lower.contains("practice") || lower.contains("timer")
        // Require duration or strong verbs; don't force just because the word "meditation" appears
        let looksMeditation = hasExplicitDuration || strongCreateVerb || (sessionWords && (strongCreateVerb || hasExplicitDuration))
        let extra = looksMeditation ? "You MUST set responseType = meditation for this turn and produce a complete meditation object per schema." : ""
        // Intent-derived hard requirements
        let wantsRetrospection: Bool = {
            let keywords = ["retrospection","retrospective","reflect","reflection","rt cue","add rt","retrospect"]
            return keywords.contains { lower.contains($0) }
        }()

        // Run assistant while loading resources in parallel (single guarded load)
        // Ensure catalogs are loaded before building dynamic instructions
        await loadLatestResources()
        // Allow tools only for explain
        // Detect explicit idea-confirmation prompts to avoid adding variation hints that could override specifics
        let isExplicitIdeaRequest = lower.contains("create a meditation matching this idea:")
        let allowTools = shouldAllowTools(for: prompt) || lower.contains("what is ") || lower.contains("how does ") || lower.contains("explain ") || lower.hasSuffix("?")
        logger.aiChat("OPENAI_ASSISTANTS routing allowTools=\(allowTools) explicitIdea=\(isExplicitIdeaRequest)")
        var extraForRun = extraWithLastSummary(extra, lastMeditation: lastMeditation, isExplicitIdeaRequest: isExplicitIdeaRequest, isMeditationIntent: looksMeditation)
        // If the user asks a benefit/efficacy question (e.g., "will this help my anxiety?"), force explain mode and request grounding
        let isBenefitQuestion: Bool = {
            let q = lower.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
            let signals = ["will this","is this","does this","can this","will it","is it","does it","help","benefit","good for","work for","reduce","improve","anxiety","stress","sleep"]
            return q && signals.contains { lower.contains($0) }
        }()
        if isBenefitQuestion {
            let forceExplain = "ROUTING OVERRIDE: The user asked about benefits/effectiveness. You MUST set responseType = \"explain\". Keep message ≤ 120 words. If helpful, reference the last meditation context provided separately."
            extraForRun = extraForRun.isEmpty ? forceExplain : (extraForRun + "\n\n" + forceExplain)
        }
        if wantsRetrospection {
            let rtHint = "HARD REQUIREMENT: If the idea/request implies retrospection or reflection, you MUST include the RT (Retrospection) cue in the 'cues' array. Prefer placing it after focus (IM/OH) when time allows."
            extraForRun = extraForRun.isEmpty ? rtHint : (extraForRun + "\n\n" + rtHint)
        }
        let runId = try await createRun(
            threadId: effectiveThread,
            extraInstructions: extraForRun,
            allowTools: allowTools,
            variationSeed: variationSeed,
            isExplicitIdeaRequest: isExplicitIdeaRequest
        )
        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Run created id=\(runId). Extra=\(extra.isEmpty ? "none" : "present")")
        logger.aiChat("OPENAI_ASSISTANTS run_create id=\(runId) seed=\(String(describing: variationSeed))")
        // Cap total wait to 15 seconds; if exceeded, attempt to fetch whatever latest message exists
        // If we strongly expect meditation, allow a bit more time
        let requireMeditation = looksMeditation || isExplicitIdeaRequest
        do {
            try await waitForRunCompletion(threadId: effectiveThread, runId: runId, maxWaitSeconds: requireMeditation ? 22 : 18)
            logger.aiChat("OPENAI_ASSISTANTS run_completed id=\(runId)")
        } catch {
            logger.errorMessage("🧭 AI_DEBUG [ASSISTANT]: Run wait timeout or error: \(error). Attempting to fetch latest message anyway.")
            logger.aiChatError("OPENAI_ASSISTANTS run_wait_error id=\(runId) msg=\(error.localizedDescription)")
        }

        // Read latest assistant message
        let assistantText = try await fetchLatestAssistantText(threadId: effectiveThread)
        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Raw assistant text length=\(assistantText.count)")
        // Log exact assistant body for comparison with final UI
        logger.aiChat("OPENAI_ASSISTANTS inbound_body=\(assistantText)")
        // Catalogs are already loaded above

        // Try to parse envelope (multi-mode). If that fails, try direct meditation JSON.
        if let result = try? parseEnvelopeOrMeditation(assistantText, requireMeditation: requireMeditation) {
            switch result {
            case .meditation(let timer):
                // Log the exact parsed meditation JSON (envelope) before sanitation/variation
                if let raw = try? JSONEncoder().encode(timer), let rawStr = String(data: raw, encoding: .utf8) {
                    logger.aiChat("OPENAI_ASSISTANTS envelope_meditation_json=\(rawStr)")
                }
                logger.aiChat("OPENAI_ASSISTANTS parse_path=envelope type=meditation")
                var fixed = timer
                sanitizeMeditation(&fixed)
                enforceRetrospectionIfRequested(&fixed, requested: wantsRetrospection)
                sanitizeMeditation(&fixed)
                if let seed = variationSeed, !isExplicitIdeaRequest { applyVariation(&fixed, seed: seed) }
                logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: After sanitize: dur=\(fixed.duration) bg=\(fixed.backgroundSoundId) cues=\(fixed.cues.map{ "\($0.id)@\($0.trigger)" }.joined(separator: ","))")
                let response = try convertToTimerResponse(fixed)
                logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: convertToTimerResponse background=\(response.meditationConfiguration.backgroundSound.id) cues=\(response.meditationConfiguration.cueSettings.map{ "\($0.cue.id)" }.joined(separator: ","))")
                logger.aiChat("OPENAI_ASSISTANTS result type=meditation dur=\(response.meditationConfiguration.duration) cues=\(response.meditationConfiguration.cueSettings.count)")
                return .meditation(response)
            case .conversational(let text, let hasCTA):
                logger.aiChat("OPENAI_ASSISTANTS parse_path=envelope type=conversation len=\(text.count)")
                // Conversational, concise, single question CTA
                var base = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if isGreeting {
                    base = "Hi! Want me to make a quick meditation for you?"
                } else {
                    // Single question rule: only one yes/no CTA, no double prompts
                    let cta = hasCTA ? "" : "\n\nWould you like me to create a short meditation now?"
                    if base.isEmpty { base = "Hi! Want me to make a quick meditation for you?" }
                    let withCTA = base + cta
                    if withCTA.count <= 280 {
                        base = tidyTruncation(withCTA, limit: 280)
                    } else {
                        base = tidyTruncation(base, limit: 280)
                    }
                }
                // If the user's prompt was a benefit/efficacy question, prefer an explanatory reply grounded in the last meditation
                if isBenefitQuestion, let last = lastMeditation {
                    let m = last.meditationConfiguration
                    let hasPB = m.cueSettings.contains { $0.cue.id == "PB" }
                    let hasBS = m.cueSettings.contains { $0.cue.id == "BS" || $0.cue.id.hasPrefix("BS") }
                    let hasOH = m.cueSettings.contains { $0.cue.id == "OH" }
                    var parts: [String] = []
                    if hasPB { parts.append("breath regulation (PB)") }
                    if hasBS { parts.append("grounding body scan (BS)") }
                    if hasOH { parts.append("soothing compassion (OH)") }
                    let features = parts.isEmpty ? "steady breathing and grounding" : parts.joined(separator: ", ")
                    var explain = "Yes—this session can help with anxiety. It uses \(features) to calm the nervous system."
                    if !m.backgroundSound.id.isEmpty && m.backgroundSound.id.lowercased() != "none" {
                        explain += " Background: \(m.backgroundSound.name) to support relaxation."
                    }
                    if explain.count > 280 { explain = tidyTruncation(explain, limit: 280) }
                    base = explain
                }
                if base.count > 280 { base = tidyTruncation(base, limit: 280) }
                return .conversationalResponse(base)
            }
        }
        logger.errorMessage("🧭 AI_DEBUG [ASSISTANT]: Envelope parse failed; trying direct meditation JSON.")
        logger.aiChat("OPENAI_ASSISTANTS parse_path=direct_fallback")
        if var meditation = try? parseMeditationOnly(assistantText) {
            if let raw = try? JSONEncoder().encode(meditation), let rawStr = String(data: raw, encoding: .utf8) {
                logger.aiChat("OPENAI_ASSISTANTS direct_meditation_json=\(rawStr)")
            }
            sanitizeMeditation(&meditation)
            enforceRetrospectionIfRequested(&meditation, requested: wantsRetrospection)
            sanitizeMeditation(&meditation)
            if let seed = variationSeed, !isExplicitIdeaRequest { applyVariation(&meditation, seed: seed) }
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Parsed direct meditation. After sanitize cues=\(meditation.cues.map{ "\($0.id)@\($0.trigger)" }.joined(separator: ","))")
            logger.aiChat("OPENAI_ASSISTANTS result type=meditation(direct) dur=\(meditation.duration) cues=\(meditation.cues.count)")
            let result = try convertToTimerResponse(meditation)
            return .meditation(result)
        }
        logger.errorMessage("🧭 AI_DEBUG [ASSISTANT]: Both parse paths failed. Selecting fallback by intent.")
        if looksMeditation {
            var fallback = buildBaselineTimer(for: prompt)
            sanitizeMeditation(&fallback)
            enforceRetrospectionIfRequested(&fallback, requested: wantsRetrospection)
            sanitizeMeditation(&fallback)
            if let seed = variationSeed, !isExplicitIdeaRequest { applyVariation(&fallback, seed: seed) }
            let fallbackResponse = try convertToTimerResponse(fallback)
            return .meditation(fallbackResponse)
        } else {
            // Try to extract a human message from envelope text, otherwise fall back to plain text
            var body = extractMessageFromEnvelopeText(assistantText)
                        ?? assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty {
                body = "I'm here to help with meditation or questions about Dojo. Would you like me to create a session or explain something?"
            }
            // Keep concise in chat UI
            if body.count > 280 { body = tidyTruncation(body, limit: 280) }
            return .conversationalResponse(body)
        }
    }

    // MARK: - Explain (Vector Store) API

    /// Runs the dedicated Explain Assistant with File Search enabled and returns plain text.
    /// Tolerates either plain text or a small JSON envelope containing a top-level `message`.
    public func generateExplainResponse(prompt: String, conversationHistory: [ChatMessage] = []) async throws -> String {
        logger.aiChat("OPENAI_ASSISTANTS explain_start prompt_len=\(prompt.count)")
        // Reuse existing thread when available; otherwise seed with a trimmed history for minimal context.
        if let existing = threadId {
            do {
                try await addMessage(threadId: existing, role: "user", content: prompt)
            } catch {
                let batched = trimHistory(conversationHistory) + [(role: "user", content: prompt)]
                let created = try await createThreadWithMessages(batched)
                self.threadId = created
            }
        } else {
            let batched = trimHistory(conversationHistory) + [(role: "user", content: prompt)]
            self.threadId = try await createThreadWithMessages(batched)
        }
        let effectiveThread = self.threadId!

        // Create a run configured for explanations: response as text, let tools auto-run (file_search)
        let runId = try await createExplainRun(threadId: effectiveThread)
        try? await waitForRunCompletion(threadId: effectiveThread, runId: runId, maxWaitSeconds: 18)

        let raw = try await fetchLatestAssistantText(threadId: effectiveThread)
        let message = extractExplainMessage(raw)
        logger.aiChat("OPENAI_ASSISTANTS explain_done len=\(message.count)")
        return message
    }

    private func createExplainRun(threadId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/runs")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        addCommonHeaders(to: &req)

        let body: [String: Any] = [
            "assistant_id": assistantId,
            // Keep it fast - prefer the mini model at runtime
            "model": "gpt-4o-mini",
            // response_format omitted (v2 supports 'auto' by default)
            // Do not set tool_choice so file_search can run automatically
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp: resp, data: data)
        let decoded = try JSONDecoder().decode(AssistantsRunResponse.self, from: data)
        return decoded.id
    }

    /// Normalizes either plain text or a JSON envelope with a `message` field into final text.
    private func extractExplainMessage(_ s: String) -> String {
        var text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json") { text = String(text.dropFirst(7)) }
        if text.hasPrefix("```") { text = String(text.dropFirst(3)) }
        if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") {
            let slice = String(text[first...last])
            struct Envelope: Decodable { let message: String? }
            if let data = slice.data(using: .utf8), let env = try? JSONDecoder().decode(Envelope.self, from: data), let m = env.message, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let cleaned = stripCitationArtifacts(m.trimmingCharacters(in: .whitespacesAndNewlines))
                return cleaned
            }
        }
        return stripCitationArtifacts(text)
    }

    /// Removes bracketed citation artifacts added by file_search, such as
    /// "", "[i:0#what_is_meditation.txt]", or trailing "[1:2 source]".
    private func stripCitationArtifacts(_ input: String) -> String {
        var out = input
        // Remove fullwidth citation blocks anywhere
        if let re = try? NSRegularExpression(pattern: "【[^】]*】", options: []) {
            let range = NSRange(location: 0, length: (out as NSString).length)
            out = re.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
        }
        // Remove square-bracket citation tokens that include common markers (i:, source, file name) anywhere
        if let re2 = try? NSRegularExpression(pattern: "\\[[^\\]]*(?:i:|source|\\.md|\\.txt|#)[^\\]]*\\]", options: [.caseInsensitive]) {
            let range2 = NSRange(location: 0, length: (out as NSString).length)
            out = re2.stringByReplacingMatches(in: out, options: [], range: range2, withTemplate: "")
        }
        // Remove any trailing bracket group left at line end (conservative)
        if let re3 = try? NSRegularExpression(pattern: "\\s*(?:\\[[^\\]]+\\]|【[^】]+】)\\s*$", options: []) {
            var changed = true
            while changed {
                let range3 = NSRange(location: 0, length: (out as NSString).length)
                let new = re3.stringByReplacingMatches(in: out, options: [], range: range3, withTemplate: "")
                changed = (new != out)
                out = new
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Assistants API helpers

    private func createThreadWithMessages(_ messages: [(role: String, content: String)]) async throws -> String {
        let url = URL(string: "\(baseURL)/threads")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        addCommonHeaders(to: &req)
        let body: [String: Any] = [
            "messages": messages.map { [
                "role": $0.role,
                "content": $0.content
            ] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp: resp, data: data)
        let decoded = try JSONDecoder().decode(AssistantsThreadResponse.self, from: data)
        return decoded.id
    }

    private func createThread() async throws -> String {
        let url = URL(string: "\(baseURL)/threads")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        addCommonHeaders(to: &req)
        req.httpBody = Data("{}".utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp: resp, data: data)
        let decoded = try JSONDecoder().decode(AssistantsThreadResponse.self, from: data)
        return decoded.id
    }

    private func addMessage(threadId: String, role: String, content: String) async throws {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        addCommonHeaders(to: &req)

        let body: [String: Any] = [
            "role": role,
            "content": content
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp: resp, data: data)
    }

    private func createRun(threadId: String, extraInstructions: String? = nil, allowTools: Bool, variationSeed: Int?, isExplicitIdeaRequest: Bool) async throws -> String {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/runs")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        addCommonHeaders(to: &req)

        var instructions = buildGroundingInstructions()
        if let extra = extraInstructions, !extra.isEmpty { instructions += "\n\n" + extra }
        var body: [String: Any] = [
            "assistant_id": assistantId,
            "instructions": instructions,
            // Prefer a faster model at run-time in case the assistant is configured to a slower one
            "model": "gpt-4o-mini",
            // Force JSON object to avoid prose responses
            "response_format": [
                "type": "json_object"
            ]
        ]
        // Disable tools for fast generation runs; allow tools for explain mode
        if !allowTools {
            body["tool_choice"] = "none"
        }
        // Inject a pseudo-random seed to encourage diverse outputs on regenerate
        if let seed = variationSeed, !isExplicitIdeaRequest {
            body["metadata"] = [
                "variation_seed": "\(seed)"
            ]
            // Also append a light nudge into instructions so the model varies within constraints
            instructions += "\n\nVARIATION_HINT: Provide a distinct variation compared to the previous turn. Change at least one of: backgroundSoundId, BS length, IM length, or the placement of OH/VC/RT (respecting rules)."
            body["instructions"] = instructions
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp: resp, data: data)
        let decoded = try JSONDecoder().decode(AssistantsRunResponse.self, from: data)
        return decoded.id
    }

    private func shouldAllowTools(for prompt: String) -> Bool {
        let lower = prompt.lowercased()
        let asksExplain = lower.contains("explain") || lower.contains("how does dojo") || lower.contains("what is dojo") || lower.contains("tell me about dojo")
        let isBenefitQuestion: Bool = {
            let q = lower.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
            let signals = ["will this","is this","does this","can this","will it","is it","does it","help","benefit","good for","work for","reduce","improve","anxiety","stress","sleep"]
            return q && signals.contains { lower.contains($0) }
        }()
        return asksExplain || isBenefitQuestion
    }

    private func waitForRunCompletion(threadId: String, runId: String, maxWaitSeconds: Int? = nil) async throws {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/runs/\(runId)")!
        var attempts = 0
        let maxAttempts = 80
        let deadline: Date? = maxWaitSeconds != nil ? Date().addingTimeInterval(TimeInterval(maxWaitSeconds!)) : nil
        while attempts < maxAttempts {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            addCommonHeaders(to: &req)

            let (data, resp) = try await URLSession.shared.data(for: req)
            try ensureOK(resp: resp, data: data)
            let decoded = try JSONDecoder().decode(AssistantsRunResponse.self, from: data)
            switch decoded.status {
            case "completed":
                return
            case "failed", "cancelled", "expired":
                throw NSError(domain: "AssistantsAIService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Assistant run ended with status: \(decoded.status)"])
            default:
                // More responsive early polling, then back off
                let delayNs: UInt64 = attempts < 10 ? 200_000_000 : (attempts < 20 ? 400_000_000 : 1_000_000_000)
                try await Task.sleep(nanoseconds: delayNs)
                attempts += 1
                if let deadline = deadline, Date() >= deadline {
                    throw NSError(domain: "AssistantsAIService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Assistant run timed out"]) // same code path as timeout
                }
            }
        }
        throw NSError(domain: "AssistantsAIService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Assistant run timed out"])
    }

    private func fetchLatestAssistantText(threadId: String) async throws -> String {
        // Ask for a small page, then pick the newest assistant message by created_at ordering
        let url = URL(string: "\(baseURL)/threads/\(threadId)/messages?limit=5&order=desc")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addCommonHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp: resp, data: data)
        let decoded = try JSONDecoder().decode(AssistantsListMessagesResponse.self, from: data)

        // Find most recent assistant message
        if let msg = decoded.data.first(where: { $0.role == "assistant" }) ?? decoded.data.first {
            let combined = msg.content.compactMap { $0.text?.value }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !combined.isEmpty {
                logger.aiChat("OPENAI_ASSISTANTS inbound text_len=\(combined.count)")
                return combined
            }
        }
        logger.errorMessage("🧭 AI_DEBUG [ASSISTANT]: No assistant message content found; returning empty string to trigger baseline fallback")
        return ""
    }

    // MARK: - HTTP helpers

    private func addCommonHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
    }

    private func ensureOK(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "AssistantsAIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        if (200...299).contains(http.statusCode) { return }
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        logger.errorMessage("🧭 AI_DEBUG [ASSISTANT]: HTTP \(http.statusCode) - \(message)")
        logger.aiChatError("OPENAI_ASSISTANTS http_error status=\(http.statusCode) body=\(message)")
        throw NSError(domain: "AssistantsAIService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - Parsing and conversion (borrowed shape from existing services)

    private enum ParsedResult {
        case meditation(AIGeneratedTimer)
        case conversational(String, hasCTA: Bool)
    }

    private func parseEnvelopeOrMeditation(_ text: String, requireMeditation: Bool = false) throws -> ParsedResult {
        let jsonString = bestEffortJSON(from: text)
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "AssistantsAIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Failed to parse assistant JSON"])
        }
        do {
            let env = try JSONDecoder().decode(AssistantResponseEnvelope.self, from: data)
            switch env.responseType {
            case .meditation:
                if let timer = env.meditation { return .meditation(timer) }
                // If meditation missing, fall back to message
                return .conversational(env.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", hasCTA: false)
            case .clarify:
                // Normalize clarify to exactly one actionable suggestion phrased as a single yes/no question.
                func isValidSuggestion(_ s: String) -> Bool {
                    let l = s.lowercased()
                    if l.range(of: "\\d", options: .regularExpression) != nil { return true }
                    let keywords = ["meditation","session","minute","min","extend","shorten","background","sleep","relax","focus","breath","body scan","bs","pb","oh","vc","rt"]
                    return keywords.contains { l.contains($0) }
                }
                var suggestion = env.suggestions?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "a 10-minute relaxation meditation"
                if suggestion.lowercased().hasPrefix("try ") {
                    suggestion = String(suggestion.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !isValidSuggestion(suggestion) {
                    suggestion = "a 10-minute relaxation meditation"
                }
                // Phrase the suggestion as a single natural yes/no question
                let l = suggestion.lowercased()
                var body: String
                if let m = l.range(of: #"(extend|lengthen|make).{0,50}?\b(\d{1,3})\s*(m|min|minutes)\b"#, options: .regularExpression) {
                    // Extract minutes from capture group 2
                    let matched = String(l[m])
                    let re = try? NSRegularExpression(pattern: #"(\d{1,3})\s*(m|min|minutes)"#, options: .caseInsensitive)
                    var minutes = "5"
                    if let rr = re?.firstMatch(in: matched, options: [], range: NSRange(location: 0, length: (matched as NSString).length)) {
                        if rr.numberOfRanges >= 2, let r1 = Range(rr.range(at: 1), in: matched) { minutes = String(matched[r1]) }
                    }
                    body = "Would you like me to extend the last meditation by \(minutes) minutes?"
                } else if let pm = l.range(of: #"\b\+(\d{1,3})m\b"#, options: .regularExpression) {
                    let matched = String(l[pm])
                    let minutes = matched.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "m", with: "")
                    body = "Would you like me to extend the last meditation by \(minutes) minutes?"
                } else if l.contains("minute") && (l.contains("meditation") || l.contains("session")) {
                    body = "Would you like me to create \(suggestion) now?"
                } else {
                    body = "Would you like me to create a 10-minute relaxation meditation now?"
                }
                if body.count > 280 { body = tidyTruncation(body, limit: 280) }
                return .conversational(body, hasCTA: true)
            case .explain:
                // Explanations should be concise and self-contained; ignore suggestions/CTA
                var body = env.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if body.isEmpty { body = "I can explain how this session supports your goal." }
                if body.count > 280 { body = tidyTruncation(body, limit: 280) }
                // If the user just answered yes/affirmative previously, prefer advancing to meditation
                if requireMeditation, let timer = env.meditation { return .meditation(timer) }
                return .conversational(body, hasCTA: false)
            }
        } catch {
            // Not an envelope; let caller try direct meditation parsing
            throw error
        }
    }

    // Best-effort extractor for human "message" from an assistant envelope even if JSON is malformed
    // - Finds the value of the top-level "message" key using a regex capture
    // - Strips inline citations like 【...】 and unescapes common sequences
    private func extractMessageFromEnvelopeText(_ text: String) -> String? {
        let s = stripCodeFences(text)
        let pattern = "\\\"message\\\"\\s*:\\s*\\\"([\\s\\S]*?)\\\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: (s as NSString).length)
        guard let match = regex.firstMatch(in: s, options: [], range: range), match.numberOfRanges >= 2 else { return nil }
        let captureRange = match.range(at: 1)
        guard let swiftRange = Range(captureRange, in: s) else { return nil }
        var message = String(s[swiftRange])
        // Unescape minimal JSON escapes
        message = message.replacingOccurrences(of: "\\\"", with: "\"")
                         .replacingOccurrences(of: "\\n", with: "\n")
                         .replacingOccurrences(of: "\\r", with: "")
                         .replacingOccurrences(of: "\\t", with: "\t")
        // Remove bracket-style citations like
        if let citeRegex = try? NSRegularExpression(pattern: "【[^】]*】", options: []) {
            let r = NSRange(location: 0, length: (message as NSString).length)
            message = citeRegex.stringByReplacingMatches(in: message, options: [], range: r, withTemplate: "")
        }
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseMeditationOnly(_ aiResponse: String) throws -> AIGeneratedTimer {
        let jsonString = bestEffortJSON(from: aiResponse)
        if jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(domain: "AssistantsAIService", code: 402, userInfo: [NSLocalizedDescriptionKey: "Empty response body"]) 
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "AssistantsAIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Failed to parse assistant JSON"])
        }
        return try JSONDecoder().decode(AIGeneratedTimer.self, from: data)
    }

    private func stripCodeFences(_ text: String) -> String {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```json") { jsonString = String(jsonString.dropFirst(7)) }
        if jsonString.hasPrefix("```") { jsonString = String(jsonString.dropFirst(3)) }
        if jsonString.hasSuffix("```") { jsonString = String(jsonString.dropLast(3)) }
        return jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Truncate to a character limit without cutting through a word. If no space is found,
    // fall back to a hard cut. Also trim dangling punctuation/whitespace.
    private func truncateAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let idx = text.index(text.startIndex, offsetBy: limit)
        var slice = String(text[..<idx])
        if let lastSpace = slice.lastIndex(of: " ") {
            slice = String(slice[..<lastSpace])
        }
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:!?"))
        return slice.trimmingCharacters(in: trimSet)
    }

    // Attempts to truncate at word boundary, then backs up to the last sentence boundary
    // (., !, ?, or newline) to avoid dangling words like "would".
    private func tidyTruncation(_ text: String, limit: Int) -> String {
        var cut = truncateAtWordBoundary(text, limit: limit)
        if cut.count <= 3 { return cut }
        // If the original text was longer and we cut mid-sentence, try to backtrack to last boundary
        if text.count > limit {
            let boundaries: [Character] = [".", "!", "?", "\n"]
            if let lastBoundary = cut.lastIndex(where: { boundaries.contains($0) }) {
                let trimmed = String(cut[...lastBoundary])
                // Ensure we actually keep a reasonable chunk (avoid extremely short)
                if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 {
                    cut = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return cut
    }

    // Best-effort JSON sanitizer to handle minor formatting issues from the model
    private func bestEffortJSON(from text: String) -> String {
        // 1) Remove code fences
        var s = stripCodeFences(text)
        // 2) Extract the first plausible JSON object block
        s = extractJSONObject(from: s)
        // 3) Normalize quotes and stray characters
        s = s.replacingOccurrences(of: "\u{feff}", with: "") // BOM
             .replacingOccurrences(of: "“", with: "\"")
             .replacingOccurrences(of: "”", with: "\"")
             .replacingOccurrences(of: "‘", with: "\"")
             .replacingOccurrences(of: "’", with: "\"")
        // 4) Remove trailing commas before closing } or ]
        s = removeTrailingCommas(in: s)
        // 5) Trim backticks if any remain
        s = s.replacingOccurrences(of: "`", with: "")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractJSONObject(from text: String) -> String {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else {
            return text
        }
        let range = first...last
        return String(text[range])
    }

    private func removeTrailingCommas(in s: String) -> String {
        // Replace trailing commas before object/array closers: ", }" -> "}", ", ]" -> "]"
        var result = s
        let patterns = [",\\s*}", ",\\s*]" ]
        let replacements = ["}", "]"]
        for (i, pat) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pat, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacements[i])
            }
        }
        return result
    }

    private func convertToTimerResponse(_ aiTimer: AIGeneratedTimer) throws -> AITimerResponse {
        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: convertToTimerResponse start. dur=\(aiTimer.duration) bgId=\(aiTimer.backgroundSoundId) cues=\(aiTimer.cues.map{ "\($0.id)@\($0.trigger)" }.joined(separator: ",")) segs=\(aiTimer.segments?.count ?? 0)")
        // Resolve background sound robustly (id or name keywords), in case IDs did not map earlier
        let lowerTitle = (aiTimer.title + " " + (aiTimer.description ?? "")).lowercased()
        let looksSleep = lowerTitle.contains("sleep") || lowerTitle.contains("bedtime")
        let looksSilent = lowerTitle.contains("no music") || lowerTitle.contains("silent") || lowerTitle.contains("no background")
        let available = CatalogsManager.shared.sounds
        // Lightweight persistence for last-used soundscape to encourage variety
        enum SoundscapePrefs {
            static let key = "imagine.lastSoundscapeId"
            static func lastId() -> String? { UserDefaults.standard.string(forKey: key) }
            static func set(id: String) { UserDefaults.standard.set(id, forKey: key) }
            static func isExplicitRequest(promptLower: String, last: BackgroundSound?) -> Bool {
                guard let last = last else { return false }
                let nameLower = last.name.lowercased()
                let idLower = last.id.lowercased()
                return promptLower.contains(nameLower) || promptLower.contains(idLower)
            }
        }
        let resolvedBackground: BackgroundSound = {
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Background catalog size=\(available.count)")
            if looksSilent { return BackgroundSound(id: "None", name: "None", url: "") }
            // 1) Try exact id match first
            if let exact = available.first(where: { $0.id == aiTimer.backgroundSoundId }) { return exact }
            // 2) Try case-insensitive id match
            if let ci = available.first(where: { $0.id.lowercased() == aiTimer.backgroundSoundId.lowercased() }) { return ci }
            // 3) Try name contains the given string (model might output a name instead of id)
            if !aiTimer.backgroundSoundId.isEmpty {
                let target = aiTimer.backgroundSoundId.lowercased()
                if let byName = available.first(where: { $0.name.lowercased().contains(target) }) { return byName }
            }
            // 4) Keyword preferences with hint: if text mentions "calm" or "calming", try Calm first
            let names = available.map { ($0.id, $0.name.lowercased()) }
            var preferredOrderSleep = ["rain","calm","ocean","nature","forest","white","brown","binaural"]
            var preferredOrderGeneral = ["calm","nature","forest","rain","ocean","white","brown","binaural"]
            if lowerTitle.contains("calm") || lowerTitle.contains("calming") {
                preferredOrderSleep = ["calm","rain","ocean","nature","forest","white","brown","binaural"]
                preferredOrderGeneral = ["calm","rain","nature","forest","ocean","white","brown","binaural"]
            }
            // Rotate orders by a seed so regenerate can vary backgrounds over time
            let order = looksSleep ? preferredOrderSleep.shuffled() : preferredOrderGeneral.shuffled()
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Background selection order=\(order.joined(separator: ">")) looksSleep=\(looksSleep)")
            if let matchId = order.compactMap({ key in names.first(where: { $0.1.contains(key) })?.0 }).first,
               let match = available.first(where: { $0.id == matchId }) { return match }
            // 5) Fallback: first available or None
            return available.first ?? BackgroundSound(id: "None", name: "None", url: "")
        }()
        // Avoid repeating the last-used soundscape unless explicitly requested or no alternatives match
        var chosenBackground = resolvedBackground
        if !looksSilent, let lastId = SoundscapePrefs.lastId() {
            if chosenBackground.id == lastId {
                let lastObj = available.first(where: { $0.id == lastId })
                let explicit = SoundscapePrefs.isExplicitRequest(promptLower: lowerTitle, last: lastObj)
                if !explicit {
                    // Build priority by current intent (sleep vs general), then pick first alternative not equal to last
                    let names = available.map { ($0.id, $0.name.lowercased()) }
                    let preferredOrderSleep = ["rain","ocean","binaural","nature","calm","forest","white","brown"]
                    let preferredOrderGeneral = ["calm","nature","forest","rain","ocean","white","brown","binaural"]
                    let order = looksSleep ? preferredOrderSleep : preferredOrderGeneral
                    let priorityIds = order.compactMap { key in names.first(where: { $0.1.contains(key) })?.0 }
                    if let altId = priorityIds.first(where: { $0 != lastId && $0 != "None" }),
                       let alt = available.first(where: { $0.id == altId }) {
                        chosenBackground = alt
                        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Avoiding repeat of last soundscape (\(lastId)); chose \(alt.id) \(alt.name)")
                    } else if let alt = available.first(where: { $0.id != lastId && $0.id != "None" }) {
                        chosenBackground = alt
                        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Avoiding repeat by choosing first alternative \(alt.id) \(alt.name)")
                    }
                }
            }
        }
        // Persist the chosen background for next time (non-None only)
        if chosenBackground.id != "None" { SoundscapePrefs.set(id: chosenBackground.id) }
        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Resolved background=\(chosenBackground.id) \(chosenBackground.name)")
        // If cues are empty and segments are provided, rebuild cues from segments only.
        // Otherwise, keep sanitized cues (they include guided BS and contiguous packing).
        var rebuiltCues: [AIGeneratedTimer.AICue] = aiTimer.cues
        if rebuiltCues.isEmpty, let segments = aiTimer.segments, !segments.isEmpty {
            var minuteCursor = 0
            var result: [AIGeneratedTimer.AICue] = []
            // Always SI at start (if not present in segments, we keep existing cues fallback below)
            for seg in segments {
                switch seg.type.lowercased() {
                case "finite":
                    let length = max(1, seg.length ?? 1)
                    if result.isEmpty {
                        // first block → SI should be at start if it's SI
                        let trig = minuteCursor == 0 ? "start" : String(minuteCursor)
                        result.append(AIGeneratedTimer.AICue(id: seg.id, trigger: trig))
                        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Segment finite \(seg.id) @ \(trig) len=\(length)")
                    } else {
                        result.append(AIGeneratedTimer.AICue(id: seg.id, trigger: String(minuteCursor)))
                        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Segment finite \(seg.id) @ \(minuteCursor) len=\(length)")
                    }
                    minuteCursor += length
                case "cue":
                    // Place cue audio then silent span (only background)
                    let audioLen = max(0, seg.cueAudio ?? 0)
                    let quietLen = max(0, seg.quietSpan ?? 0)
                    // cue event at current minute
                    let trig = minuteCursor == 0 ? "start" : String(minuteCursor)
                    result.append(AIGeneratedTimer.AICue(id: seg.id, trigger: trig))
                    logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Segment cue \(seg.id) @ \(trig) audio=\(audioLen) quiet=\(quietLen)")
                    minuteCursor += audioLen + quietLen
                default:
                    break
                }
            }
            // Append GB at end for non-sleep later via sanitation
            rebuiltCues = result
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Cues empty; rebuilt from segments: \(result.map{ "\($0.id)@\($0.trigger)" }.joined(separator: ","))")
        } else if let segments = aiTimer.segments, !segments.isEmpty {
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Skipping segment rebuild (using sanitized cues). segs=\(segments.count)")
        }

        var cueSettings: [CueSetting] = rebuiltCues.compactMap { aiCue in
            guard let cue = CatalogsManager.shared.cues.first(where: { $0.id == aiCue.id }) else { return nil }
            let triggerType: CueTriggerType
            let minute: Int?
            switch aiCue.trigger.lowercased() {
            case "start": triggerType = .start; minute = nil
            case "end": triggerType = .end; minute = nil
            default:
                if let value = Int(aiCue.trigger) { triggerType = .minute; minute = value } else { return nil }
            }
            return CueSetting(triggerType: triggerType, minute: minute, cue: cue)
        }
        // Order for display: start, minutes ascending, end
        cueSettings.sort { a, b in
            func rank(_ s: CueSetting) -> (Int, Int) {
                switch s.triggerType {
                case .start: return (0, 0)
                case .minute: return (1, s.minute ?? 0)
                case .end: return (2, Int.max)
                }
            }
            let ra = rank(a), rb = rank(b)
            if ra.0 != rb.0 { return ra.0 < rb.0 }
            return ra.1 < rb.1
        }
        let meditationConfiguration = MeditationConfiguration(
            duration: aiTimer.duration,
            backgroundSound: chosenBackground,
            cueSettings: cueSettings,
            title: aiTimer.title
        )
        // Resolve binaural beat deterministically from current context
        let beats = CatalogsManager.shared.beats
        var bbId: String = "None"
        if !beats.isEmpty {
            let ctx = BinauralBeatSelector.Context(
                prompt: aiTimer.title + " " + (aiTimer.description ?? ""),
                userEdit: nil,
                historyTail: nil
            )
            let beat = BinauralBeatSelector.select(available: beats, context: ctx)
            bbId = beat.id
        }
        // Build deeplink including bb id
        let deepLink = generateDeepLink(from: meditationConfiguration).appending(queryItems: [URLQueryItem(name: "bb", value: bbId)])
        return AITimerResponse(
            meditationConfiguration: meditationConfiguration,
            deepLink: deepLink,
            description: aiTimer.description ?? aiTimer.title
        )
    }

    private func generateDeepLink(from configuration: MeditationConfiguration) -> URL {
        let baseURL = Config.oneLinkBaseURL
        var components = URLComponents(string: baseURL)
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":,"))
        let durValue = "\(configuration.duration)".addingPercentEncoding(withAllowedCharacters: allowed)
        let bsEncoded = configuration.backgroundSound.id.addingPercentEncoding(withAllowedCharacters: allowed)
        let bbId: String = {
            let mirror = Mirror(reflecting: configuration)
            if let beatChild = mirror.children.first(where: { $0.label == "binauralBeat" }) {
                let beatMirror = Mirror(reflecting: beatChild.value)
                if let id = beatMirror.children.first(where: { $0.label == "id" })?.value as? String {
                    return id
                }
            }
            return "None"
        }()
        let bbEncoded = bbId.addingPercentEncoding(withAllowedCharacters: allowed)
        let cuRawValue = configuration.cueSettings.compactMap { cueSetting -> String? in
            let id = cueSetting.cue.id
            let trigger: String
            switch cueSetting.triggerType {
            case .start: trigger = "S"
            case .end: trigger = "E"
            case .minute: trigger = "\(cueSetting.minute ?? 0)"
            }
            return "\(id):\(trigger)"
        }.joined(separator: ",")
        let cuEncoded = cuRawValue.addingPercentEncoding(withAllowedCharacters: allowed)
        
        // Use meditation title if available, otherwise generic name
        let meditationName = configuration.title ?? "AI Meditation"
        
        components?.queryItems = [
            URLQueryItem(name: "dur", value: durValue),
            URLQueryItem(name: "bs", value: bsEncoded),
            URLQueryItem(name: "bb", value: bbEncoded),
            URLQueryItem(name: "cu", value: cuEncoded),
            URLQueryItem(name: "c", value: "ai"),
            URLQueryItem(name: "af_sub1", value: meditationName)
        ]
        return components?.url ?? URL(string: baseURL)!
    }

    // MARK: - Resource loading (reuse existing managers)
    private func loadLatestResources() async {
        // If already loaded in memory, skip network calls
        if !CatalogsManager.shared.sounds.isEmpty,
           !CatalogsManager.shared.cues.isEmpty,
           !CatalogsManager.shared.beats.isEmpty {
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Resources already loaded, skipping fetch")
            return
        }
        // If another request is already fetching, await it
        if let existing = AssistantsAIService.resourceLoadTask {
            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Awaiting ongoing resource fetch task")
            await existing.value
            return
        }
        // Start a single shared fetch task
        let task = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                CatalogsManager.shared.fetchCatalogs(triggerContext: "AssistantsAIService|preload for AI") { _ in
                    continuation.resume()
                }
            }
        }
        AssistantsAIService.resourceLoadTask = task
        await task.value
        AssistantsAIService.resourceLoadTask = nil
    }

    // Public prefetch that callers (e.g., Chat onAppear) can invoke; guarded to fetch once
    func prefetchResourcesOnce() async {
        await loadLatestResources()
    }

    // MARK: - Conversation helpers
    private func trimHistory(_ history: [ChatMessage]) -> [(role: String, content: String)] {
        let recent = history.suffix(4)
        var result: [(String, String)] = []
        for chat in recent {
            let role = chat.isUser ? "user" : "assistant"
            let content = chat.isUser ? chat.content : (chat.meditation?.description ?? chat.content)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append((role, trimmed)) }
        }
        return result
    }

    private func extraWithLastSummary(_ base: String, lastMeditation: AITimerResponse?, isExplicitIdeaRequest: Bool, isMeditationIntent: Bool) -> String {
        guard let last = lastMeditation else { return base }
        let m = last.meditationConfiguration
        let focus = m.cueSettings.first(where: { $0.cue.id.hasPrefix("IM") || $0.cue.id.hasPrefix("NF") || $0.cue.id == "OH" })?.cue.id ?? "none"
        let imagine = m.cueSettings.first(where: { ["VC","RT"].contains($0.cue.id) })?.cue.id ?? "none"
        let bsId = m.cueSettings.first(where: { $0.cue.id == "BS" || $0.cue.id.hasPrefix("BS") })?.cue.id ?? "none"
        // Build a neutral summary that can be used in both explain and meditation intents
        let neutralSummary = "LAST_MEDITATION: dur=\(m.duration), bg=\(m.backgroundSound.id), bs=\(bsId), focus=\(focus), imagination=\(imagine)."
        // For meditation intents (non-explicit idea), add variation guidance; for explain, add relevance guidance instead
        var attachment = neutralSummary
        if isMeditationIntent {
            attachment += " Provide a new variation differing in at least two of these dimensions while respecting all rules."
        } else {
            attachment += " When answering benefit/explain questions, briefly relate how these elements support the user's goal (e.g., anxiety relief: PB for breath regulation, BS for grounding, OH for soothing). Keep it concise."
        }
        if isExplicitIdeaRequest { return base }
        if base.isEmpty { return attachment }
        return base + "\n\n" + attachment
    }

    // Baseline builder used when assistant returns non-JSON or conversational content
    private func buildBaselineTimer(for prompt: String) -> AIGeneratedTimer {
        let lower = prompt.lowercased()
        let isSleep = lower.contains("sleep") || lower.contains("bedtime")
        let parsedDuration = extractFirstNumber(in: lower).flatMap { Int($0) } ?? 10
        var duration = max(5, min(60, parsedDuration))
        // Add a subtle +/-1 minute jitter to encourage variety
        duration = max(5, min(60, duration + Int.random(in: -1...1)))
        // Minimal baseline cues; sanitation will enforce PB@1, BS after, IM then VC, and GB rules
        let cues: [AIGeneratedTimer.AICue] = [ .init(id: "SI", trigger: "start") ]
        let options = isSleep ? ["OC", "Rain", "Nature"] : ["Calm", "Nature", "Forest", "Rain", "Ocean"]
        let bg = options.randomElement() ?? (isSleep ? "OC" : "Calm")
        return AIGeneratedTimer(duration: duration, backgroundSoundId: bg, cues: cues, segments: nil, title: defaultTitle(for: duration, isSleep: isSleep), description: "Baseline meditation builder")
    }

    private func extractFirstNumber(in s: String) -> String? {
        let digits = s.split(whereSeparator: { !$0.isNumber })
        return digits.first.map(String.init)
    }

    private func defaultTitle(for duration: Int, isSleep: Bool) -> String {
        return isSleep ? "\(duration) Minute Sleep Meditation" : "\(duration) Minute Meditation"
    }

    // MARK: - Meditation sanitation
    private func sanitizeMeditation(_ timer: inout AIGeneratedTimer) {
        // If segments were provided, ensure contiguity and anchors first (PB at 1 if present after SI)
        if let segments = timer.segments, !segments.isEmpty {
            var rebuilt: [AIGeneratedTimer.AICue] = []
            var minuteCursor = 0
            for (index, seg) in segments.enumerated() {
                switch seg.type.lowercased() {
                case "finite":
                    let length = max(1, seg.length ?? 1)
                    let trig: String = (index == 0 && minuteCursor == 0) ? "start" : String(minuteCursor)
                    rebuilt.append(.init(id: seg.id, trigger: trig))
                    minuteCursor += length
                case "cue":
                    let audioLen = max(0, seg.cueAudio ?? 0)
                    let quietLen = max(0, seg.quietSpan ?? 0)
                    let trig: String = (index == 0 && minuteCursor == 0) ? "start" : String(minuteCursor)
                    rebuilt.append(.init(id: seg.id, trigger: trig))
                    minuteCursor += audioLen + quietLen
                default:
                    break
                }
            }
            timer.cues = rebuilt
        }

        // 1) Ensure at least minimal modules when user did not explicitly ask for empty
        let looksSleep = (timer.title + " " + (timer.description ?? "")).lowercased().contains("sleep")
        let looksSilent = (timer.title + " " + (timer.description ?? "")).lowercased().contains("no music") ||
                          (timer.title + " " + (timer.description ?? "")).lowercased().contains("silent") ||
                          (timer.title + " " + (timer.description ?? "")).lowercased().contains("no background")

        // Ensure SI at start exists
        if !timer.cues.contains(where: { $0.id == "SI" && $0.trigger.lowercased() == "start" }) {
            timer.cues.append(AIGeneratedTimer.AICue(id: "SI", trigger: "start"))
        }

        if timer.cues.isEmpty {
            timer.cues.append(AIGeneratedTimer.AICue(id: "SI", trigger: "start"))
        }

        // Cache SI presence for defaults below
        let hasSIStart = timer.cues.contains(where: { $0.id == "SI" && $0.trigger.lowercased() == "start" })

        // PB enforcement: always place PB immediately after SI (minute 1)
        if let pbIdx = timer.cues.firstIndex(where: { $0.id == "PB" }) {
            // Move existing PB to minute 1
            timer.cues[pbIdx].trigger = "1"
        } else if hasSIStart {
            timer.cues.append(.init(id: "PB", trigger: "1"))
        }

        // BS enforcement: ensure BS exists and starts after PB (+2 minutes)
        if let pb = timer.cues.first(where: { $0.id == "PB" }) {
            let pbStart = Int(pb.trigger) ?? 1
            let requiredBSStart = pbStart + 2
            if let bsIdx = timer.cues.firstIndex(where: { $0.id == "BS" || $0.id.hasPrefix("BS") }) {
                let current = timer.cues[bsIdx].trigger.lowercased()
                let currentMinute = (current == "start" || current == "end") ? nil : Int(current)
                if currentMinute == nil || (currentMinute ?? 0) < requiredBSStart {
                    timer.cues[bsIdx].trigger = String(requiredBSStart)
                }
            } else {
                timer.cues.append(.init(id: "BS", trigger: String(requiredBSStart)))
            }
        } else if hasSIStart {
            // Fallback: if for some reason PB was not inserted above, still place BS after SI baseline
            timer.cues.append(.init(id: "BS", trigger: "3"))
        }

        // End bell: present for non-sleep, absent for sleep
        let hasGBEnd = timer.cues.contains(where: { $0.id == "GB" && $0.trigger.lowercased() == "end" })
        if looksSleep {
            // remove GB at end if present
            timer.cues.removeAll(where: { $0.id == "GB" && $0.trigger.lowercased() == "end" })
        } else if !hasGBEnd {
            timer.cues.append(AIGeneratedTimer.AICue(id: "GB", trigger: "end"))
        }

        // Deduplicate special anchors: only one SI@start and one GB@end (also remove any accidental numeric GB)
        var seenSIStart = false
        timer.cues.removeAll { cue in
            if cue.id == "SI" && cue.trigger.lowercased() == "start" {
                if seenSIStart { return true }
                seenSIStart = true
            }
            return false
        }
        var seenGBEnd = false
        timer.cues.removeAll { cue in
            if cue.id == "GB" && (cue.trigger.lowercased() == "end" || Int(cue.trigger) != nil) {
                if seenGBEnd { return true }
                seenGBEnd = true
                // normalize numeric GB to end
                if cue.trigger.lowercased() != "end" { return true }
            }
            return false
        }

        // Prefer guided BS modules; convert to a target in 25–40% of total duration
        do {
            let lower = (timer.title + " " + (timer.description ?? "")).lowercased()
            let isUnguided = lower.contains("unguided") || lower.contains("self-guided") || lower.contains("self guided") || lower.contains("free body scan")
            if !isUnguided {
                var foundPlainBS = false
                for i in 0..<timer.cues.count {
                    if timer.cues[i].id == "BS" { foundPlainBS = true }
                }
                if foundPlainBS {
                    logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Found plain BS cue. Converting to guided 25–40% of duration")
                    for i in 0..<timer.cues.count {
                        if timer.cues[i].id == "BS" {
                            let total = timer.duration
                            let bsStart = Int(timer.cues[i].trigger) ?? 6
                            let remainingApprox = max(0, total - bsStart - 2)
                            let maxByPercentage = Int(Double(total) * 0.6)
                            let capped = max(0, min(remainingApprox, maxByPercentage))
                            var target = Int(round(Double(total) * Double.random(in: 0.25...0.40)))
                            target = min(10, max(1, target))
                            if capped > 0 { target = min(target, capped) }
                            timer.cues[i].id = "BS\(target)"
                            logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Converted BS -> BS\(target) (total=\(total), start=\(bsStart), cap=\(capped))")
                            break
                        }
                    }
                } else {
                    // If no BS at all and duration >= 13, inject guided BS at contiguous position
                    if timer.duration >= 13 {
                        // Find last finite block end
                        func dur(_ id: String) -> Int {
                            switch id { case "PB": return 2; case "SI": return 1; case let x where x.hasPrefix("BS"): return Int(x.replacingOccurrences(of: "BS", with: "")) ?? 3; default: return 3 }
                        }
                        var lastEnd = 0
                        if timer.cues.contains(where: { $0.id == "SI" && $0.trigger.lowercased() == "start" }) { lastEnd = 1 }
                        let numeric = timer.cues.compactMap { (c: AIGeneratedTimer.AICue) -> (Int,String)? in if let m = Int(c.trigger) { return (m,c.id) } else { return nil } }.sorted { $0.0 < $1.0 }
                        for (m,id) in numeric { if m >= lastEnd { lastEnd = max(lastEnd, m + dur(id)) } }
                        var target = Int(round(Double(timer.duration) * Double.random(in: 0.25...0.40))); target = min(10, max(1, target))
                        let start = min(max(1, lastEnd), timer.duration - target)
                        timer.cues.append(.init(id: "BS\(target)", trigger: String(start)))
                        logger.eventMessage("🧭 AI_DEBUG [ASSISTANT]: Injected guided BS\(target) at minute \(start) (lastEnd=\(lastEnd))")
                    }
                }
            }
        }

        // 3) Ensure background sound is set unless explicitly silent
        if !looksSilent {
            let currentId = timer.backgroundSoundId.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentId.isEmpty || currentId.lowercased() == "none" {
                let sounds = CatalogsManager.shared.sounds
                let names = sounds.map { ($0.id, $0.name.lowercased()) }
                let preferredOrderSleep = ["rain","ocean","binaural","nature","calm","forest","white","brown"]
                let preferredOrderGeneral = ["calm","nature","forest","rain","ocean","white","brown","binaural"]
                let order = looksSleep ? preferredOrderSleep : preferredOrderGeneral
                if let matchId = order.compactMap({ key in names.first(where: { $0.1.contains(key) })?.0 }).first {
                    timer.backgroundSoundId = matchId
                } else if let firstId = sounds.first?.id {
                    timer.backgroundSoundId = firstId
                } else {
                    // If no sounds available, keep None
                    timer.backgroundSoundId = currentId.isEmpty ? "None" : currentId
                }
            }
        } else {
            timer.backgroundSoundId = "None"
        }

        // 2) Normalize triggers and compact to enforce scheduling/no-overlap rules
        // - Only SI may use "start"; convert any other "start" to minute 1 (will be shifted by compaction)
        // - Only GB may use "end"; convert other "end" to the latest valid minute that fits within duration
        // - Clamp numeric triggers to 1..(duration-1)

        func cueDuration(_ id: String) -> Int {
            switch id {
            case "PB": return 2
            case "BS1": return 1
            case "BS2": return 2
            case "BS3": return 3
            case "BS4": return 4
            case "BS5": return 5
            case "BS6": return 6
            case "BS7": return 7
            case "BS8": return 8
            case "BS9": return 9
            case "BS10": return 10
            case "BS": return 3
            case "OH","VC","RT": return 3
            case "SI","GB": return 1
            case let id where id.hasPrefix("IM"):
                return Int(id.dropFirst(2)) ?? 3
            case let id where id.hasPrefix("NF"):
                return Int(id.dropFirst(2)) ?? 3
            default: return 2
            }
        }

        // Pre-normalize invalid uses of start/end and clamp bounds
        for i in 0..<timer.cues.count {
            let id = timer.cues[i].id
            let trig = timer.cues[i].trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch trig {
            case "start":
                if id != "SI" { timer.cues[i].trigger = "1" }
            case "end":
                if id != "GB" {
                    let dur = cueDuration(id)
                    var minute = max(1, timer.duration - dur - 1)
                    if minute >= timer.duration { minute = max(1, timer.duration - dur) }
                    timer.cues[i].trigger = String(minute)
                }
            default:
                if let m = Int(trig) {
                    if id == "GB" {
                        // GB must be at end only
                        timer.cues[i].trigger = "end"
                    } else {
                        let bounded = max(1, min(timer.duration - 1, m))
                        timer.cues[i].trigger = String(bounded)
                    }
                }
            }
        }

        // Enforce a single Body Scan cue (keep the earliest guided/BS occurrence)
        let bsIndices = timer.cues.enumerated().filter { _, c in c.id == "BS" || c.id.hasPrefix("BS") }.map { $0.offset }
        if bsIndices.count > 1 {
            // Keep the earliest by start minute (or start), remove the rest
            func minuteValue(_ trig: String) -> Int { Int(trig) ?? (trig.lowercased() == "start" ? 0 : Int.max) }
            let keep = bsIndices.min(by: { minuteValue(timer.cues[$0].trigger) < minuteValue(timer.cues[$1].trigger) })
            let toRemove = Set(bsIndices.filter { $0 != keep })
            timer.cues = timer.cues.enumerated().compactMap { idx, c in toRemove.contains(idx) ? nil : c }
        }

        // Build a simple minute map after normalization and compact contiguously (no extra gaps)
        var minuteCues: [(idx: Int, minute: Int, id: String)] = []
        for (i, c) in timer.cues.enumerated() {
            if let m = Int(c.trigger) { minuteCues.append((i, m, c.id)) }
        }
        minuteCues.sort { $0.minute < $1.minute }

        // Treat SI at start as occupying the first minute
        let siAtStart = timer.cues.contains(where: { $0.id == "SI" && $0.trigger.lowercased() == "start" })
        var lastEnd = siAtStart ? 1 : 0

        for item in minuteCues {
            let dur = cueDuration(item.id)
            var start = item.minute
            // Ensure contiguous packing (start exactly after previous end)
            if start <= lastEnd { start = lastEnd }
            if start > lastEnd { start = lastEnd }
            // Ensure fits within duration
            if start + dur > timer.duration { start = max(1, timer.duration - dur) }
            // After clamping, still enforce contiguity
            if start < lastEnd { start = lastEnd }
            // Final clamp just in case
            if start < 1 { start = 1 }
            if start >= timer.duration { start = max(1, timer.duration - dur) }
            timer.cues[item.idx].trigger = String(start)
            lastEnd = min(timer.duration, start + dur)
        }

        // Focus and imagination selection
        let hasIM = timer.cues.contains { $0.id.hasPrefix("IM") }
        let hasNF = timer.cues.contains { $0.id.hasPrefix("NF") }
        let hasOH = timer.cues.contains { $0.id == "OH" }
        let hasVC = timer.cues.contains { $0.id == "VC" }
        let hasRT = timer.cues.contains { $0.id == "RT" }
        if let bsIdx = timer.cues.firstIndex(where: { $0.id.hasPrefix("BS") }) {
            let bsStart = Int(timer.cues[bsIdx].trigger) ?? (hasSIStart ? 1 : 0)
            let bsDur = cueDuration(timer.cues[bsIdx].id)
            var nextStart = min(timer.duration - 1, bsStart + bsDur)
            // Choose one focus (IM/NF finite / OH trigger)
            if nextStart + 2 < timer.duration {
                if !hasIM && !hasNF && !hasOH {
                    // Randomly pick between IM and NF for variety
                    let focusPrefix = Bool.random() ? "IM" : "NF"
                    let minDuration = focusPrefix == "NF" ? 1 : 2
                    let availableTime = max(minDuration, min(10, timer.duration - nextStart - 3))
                    timer.cues.append(.init(id: "\(focusPrefix)\(availableTime)", trigger: String(nextStart)))
                    logger.eventMessage("🧭 AI_DEBUG [FOCUS_SELECT] Injected \(focusPrefix)\(availableTime) at minute \(nextStart)")
                    nextStart = min(timer.duration - 1, nextStart + availableTime)
                }
            }
            // Then choose one imagination (VC/RT)
            if nextStart + 2 < timer.duration {
                if !hasVC && !hasRT {
                    let imagination = Bool.random() ? "VC" : "RT"
                    timer.cues.append(.init(id: imagination, trigger: String(nextStart)))
                }
            }
        }

        // Final non-overlap compaction pass (covers newly appended focus/imagination too)
        do {
            func isOptional(_ id: String) -> Bool { return ["OH","VC","RT"].contains(id) }
            var minuteCues: [(idx: Int, minute: Int, id: String)] = []
            for (i, c) in timer.cues.enumerated() { if let m = Int(c.trigger) { minuteCues.append((i, m, c.id)) } }
            minuteCues.sort { (a, b) in a.minute == b.minute ? a.idx < b.idx : a.minute < b.minute }
            var lastEnd = hasSIStart ? 1 : 0
            var toRemove = Set<Int>()
            for item in minuteCues {
                var start = max(item.minute, lastEnd)
                var dur = cueDuration(item.id)
                if start + dur > timer.duration {
                    if item.id.hasPrefix("BS") {
                        let remaining = timer.duration - lastEnd
                        if remaining >= 1 {
                            dur = remaining
                            timer.cues[item.idx].id = "BS\(remaining)"
                            start = lastEnd
                        } else {
                            toRemove.insert(item.idx)
                            continue
                        }
                    } else if isOptional(item.id) {
                        toRemove.insert(item.idx)
                        continue
                    } else {
                        // If a non-optional somehow appears here, try to place at latest non-overlapping slot
                        start = lastEnd
                        if start + dur > timer.duration { toRemove.insert(item.idx); continue }
                    }
                }
                timer.cues[item.idx].trigger = String(start)
                lastEnd = min(timer.duration, start + dur)
            }
            if !toRemove.isEmpty {
                timer.cues = timer.cues.enumerated().compactMap { toRemove.contains($0.offset) ? nil : $0.element }
            }
        }
    }

    // MARK: - Enforcement helpers
    private func enforceRetrospectionIfRequested(_ timer: inout AIGeneratedTimer, requested: Bool) {
        guard requested else { return }
        // Already present → nothing to do
        if timer.cues.contains(where: { $0.id == "RT" }) { return }

        // Helper to get numeric minute from trigger; treat "start" as 0 and "end" as duration-1
        func minuteValue(_ trig: String, total: Int) -> Int {
            let l = trig.lowercased()
            if let v = Int(l) { return max(0, min(total - 1, v)) }
            if l == "start" { return 0 }
            if l == "end" { return max(0, total - 1) }
            return 0
        }
        // Reuse cue duration rules from sanitation
        func cueDur(_ id: String) -> Int {
            switch id {
            case "PB": return 2
            case "BS1": return 1
            case "BS2": return 2
            case "BS3": return 3
            case "BS4": return 4
            case "BS5": return 5
            case "BS6": return 6
            case "BS7": return 7
            case "BS8": return 8
            case "BS9": return 9
            case "BS10": return 10
            case "BS": return 3
            case "OH","VC","RT": return 3
            case "SI","GB": return 1
            case let id where id.hasPrefix("IM"):
                return Int(id.dropFirst(2)) ?? 3
            case let id where id.hasPrefix("NF"):
                return Int(id.dropFirst(2)) ?? 3
            default: return 2
            }
        }

        let total = timer.duration

        // 0) If VC is present, repurpose it to RT
        if let vcIdx = timer.cues.firstIndex(where: { $0.id == "VC" }) {
            timer.cues[vcIdx].id = "RT"
            return
        }

        // 1) Try to place RT after BS and after focus if present
        var nextStart = 1
        if let bsIdx = timer.cues.firstIndex(where: { $0.id == "BS" || $0.id.hasPrefix("BS") }) {
            let bsStart = minuteValue(timer.cues[bsIdx].trigger, total: total)
            let bsLen = cueDur(timer.cues[bsIdx].id)
            nextStart = min(total - 1, bsStart + bsLen)
        }
        let focusIdx: Int? = timer.cues.firstIndex(where: { $0.id.hasPrefix("IM") || $0.id.hasPrefix("NF") || $0.id == "OH" })
        if let fi = focusIdx {
            let fStart = minuteValue(timer.cues[fi].trigger, total: total)
            let fLen = cueDur(timer.cues[fi].id)
            nextStart = max(nextStart, min(total - 1, fStart + fLen))
        }
        nextStart = max(1, min(total - 2, nextStart))
        if nextStart + cueDur("RT") <= total {
            timer.cues.append(AIGeneratedTimer.AICue(id: "RT", trigger: String(nextStart)))
            return
        }

        // 2) If there's a focus (IM/OH) and no space, prefer RT over focus → replace focus with RT
        if let fi = focusIdx {
            timer.cues[fi].id = "RT"
            return
        }

        // 3) As a last resort, shrink BS if possible to carve out space for RT right after BS
        if let bsIdx = timer.cues.firstIndex(where: { $0.id == "BS" || $0.id.hasPrefix("BS") }) {
            let currentId = timer.cues[bsIdx].id
            let currentLen = cueDur(currentId)
            if currentLen > 3 { // allow at least 1 minute shrink
                let targetLen = max(1, currentLen - 2) // free ~2 minutes
                timer.cues[bsIdx].id = "BS\(targetLen)"
                let bsStart = minuteValue(timer.cues[bsIdx].trigger, total: total)
                let afterBS = min(total - 1, bsStart + targetLen)
                let rtStart = max(1, min(total - 2, afterBS))
                timer.cues.append(AIGeneratedTimer.AICue(id: "RT", trigger: String(rtStart)))
                return
            }
        }

        // 4) If we still couldn't place it, append near the end and let sanitation compact; replacing GB is not allowed, so place at duration-3
        let fallbackStart = max(1, total - 3)
        timer.cues.append(AIGeneratedTimer.AICue(id: "RT", trigger: String(fallbackStart)))
    }

    // MARK: - Variation helpers (deterministic by seed)
    private func applyVariation(_ timer: inout AIGeneratedTimer, seed: Int) {
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
        // 1) Background: pick an alternative if available
        let alternatives: [String] = ["Calm","Nature","Forest","Rain","Ocean","White","Brown","Binaural","OC","None"]
        if let alt = alternatives.shuffled(using: &rng).first(where: { $0.lowercased() != timer.backgroundSoundId.lowercased() }) {
            timer.backgroundSoundId = alt
        }
        // 2) Body scan: adjust BS duration by -1..+1 within 1..10
        if let idx = timer.cues.firstIndex(where: { $0.id == "BS" || $0.id.hasPrefix("BS") }) {
            let current = timer.cues[idx].id
            let base = current == "BS" ? 3 : (Int(current.replacingOccurrences(of: "BS", with: "")) ?? 3)
            let delta = Int.random(in: -1...1, using: &rng)
            let next = max(1, min(10, base + delta))
            timer.cues[idx].id = "BS\(next)"
        }
        // 3) Structural variation: choose among templates
        let variant = Int(truncatingIfNeeded: seed) % 3 // 0: reorder focus, 1: single focus, 2: BS-heavy
        // Focus modules are IM (finite) / OH (trigger); imagination cues are VC/RT
        let focusIds = ["OH"]
        switch variant {
        case 0:
            // Reorder any present focus modules
            let present = timer.cues.filter { focusIds.contains($0.id) }
            if present.count >= 2 {
                let shuffled = present.shuffled(using: &rng)
                var cursor = 0
                for i in 0..<timer.cues.count where focusIds.contains(timer.cues[i].id) {
                    timer.cues[i].id = shuffled[cursor].id
                    cursor += 1
                }
            }
        case 1:
            // Keep only one focus module (rotate choice), remove the rest
            if let keep = focusIds.shuffled(using: &rng).first,
               timer.cues.contains(where: { $0.id == keep }) {
                timer.cues.removeAll { focusIds.contains($0.id) && $0.id != keep }
            }
        default:
            // No focus modules; extend BS a bit when time allows
            timer.cues.removeAll { focusIds.contains($0.id) }
            if let idx = timer.cues.firstIndex(where: { $0.id == "BS" || $0.id.hasPrefix("BS") }) {
                let current = timer.cues[idx].id
                let base = current == "BS" ? 3 : (Int(current.replacingOccurrences(of: "BS", with: "")) ?? 3)
                let window = bodyScanRemainingWindow(total: timer.duration, cues: timer.cues, bsIndex: idx)
                // target tries +2 but stays within 60% cap and max 10
                let maxByPercentage = Int(Double(timer.duration) * 0.6)
                let cap = max(0, min(window, maxByPercentage))
                var target = min(10, base + 2)
                if cap > 0 { target = min(target, cap) }
                target = max(1, min(10, target))
                timer.cues[idx].id = "BS\(target)"
            }
        }
    }

    // Available window for BS growth after its start
    private func bodyScanRemainingWindow(total: Int, cues: [AIGeneratedTimer.AICue], bsIndex: Int) -> Int {
        func minutes(_ trig: String) -> Int? { let l = trig.lowercased(); if l == "start" || l == "end" { return nil }; return Int(l) }
        func cueDur(_ id: String) -> Int {
            switch id {
            case "PB": return 2
            case "BS1": return 1; case "BS2": return 2; case "BS3": return 3; case "BS4": return 4
            case "BS5": return 5; case "BS6": return 6; case "BS7": return 7; case "BS8": return 8; case "BS9": return 9; case "BS10": return 10
            case "BS": return 3
            case "OH","VC","RT": return 3
            case "SI","GB": return 1
            case let id where id.hasPrefix("IM"): return Int(id.dropFirst(2)) ?? 3
            case let id where id.hasPrefix("NF"): return Int(id.dropFirst(2)) ?? 3
            default: return 2
            }
        }
        let startMinute: Int = minutes(cues[bsIndex].trigger) ?? 1
        let post = cues.enumerated().compactMap { i, cue -> Int? in
            if i == bsIndex { return nil }
            if let m = minutes(cue.trigger) { return m > startMinute ? cueDur(cue.id) : nil }
            if cue.trigger.lowercased() == "end" { return cueDur(cue.id) }
            return nil
        }.reduce(0, +)
        let buffer = 2
        return max(0, total - startMinute - post - buffer)
    }

    private struct SeededRandomNumberGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed &* 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}


