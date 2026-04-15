//
//  FractionalCueID.swift
//  Dojo
//
//  Shared parsing for expanded fractional clip IDs (collapse to _FRAC modules, playback gain rules).
//

import Foundation

enum FractionalCueID {

    /// Internal group key: consecutive cues with the same key merge into one Timer editor row.
    private static let bodyScanTierGroupKey = "__BS_TIER__"

    /// Prefix used when collapsing atomic clips into one `_FRAC` row (e.g. `NF` from `NF_C001`).
    /// Perfect Breath uses `PBV_` / `PBS_` clip IDs → prefix `PB`.
    static func fractionalCollapsePrefix(of cueId: String) -> String? {
        if cueId.hasPrefix("PBV_") || cueId.hasPrefix("PBS_") { return "PB" }
        guard let range = cueId.range(of: #"_C\d+$"#, options: .regularExpression) else { return nil }
        let prefix = String(cueId[cueId.startIndex..<range.lowerBound])
        return prefix.isEmpty ? nil : prefix
    }

    /// Expanded server / composer clips (`INT_GRT_*`, `BS_MAC_*`, `PBV_*`, `IM_C###`, …) → merge key for Timer Customize.
    static func editorCollapseGroupKey(of cueId: String) -> String? {
        if cueId == "INT_FRAC" { return nil }
        if cueId.hasPrefix("INT_") { return "INT_FRAC" }
        if cueId.hasPrefix("PBV_") || cueId.hasPrefix("PBS_") { return "PB_FRAC" }
        if let range = cueId.range(of: #"_C\d+$"#, options: .regularExpression) {
            let prefix = String(cueId[cueId.startIndex..<range.lowerBound])
            if prefix == "IM" || prefix == "NF" { return "\(prefix)_FRAC" }
            if prefix == "MVK" { return "MV_KM_FRAC" }
            if prefix == "MVG" { return "MV_GR_FRAC" }
            if prefix == "EVK" { return "EV_KM_FRAC" }
            if prefix == "EVG" { return "EV_GR_FRAC" }
        }
        if isBodyScanTierAtomicId(cueId) { return bodyScanTierGroupKey }
        return nil
    }

    /// Maps a collapse group key + clip ids in that run to the catalog `moduleId` (e.g. `BS_FRAC_UP`).
    static func editorCollapsedModuleId(groupKey: String, clipIds: [String]) -> String {
        if groupKey != bodyScanTierGroupKey { return groupKey }
        return bodyScanModuleIdFromTierClipIds(clipIds)
    }

    /// Tier body-scan atoms from `bodyScanTierPlan` (`BS_SYS_*`, `BS_MAC_*`, …), not monolithic `BS1`…`BS10`.
    static func isBodyScanTierAtomicId(_ cueId: String) -> Bool {
        guard cueId.hasPrefix("BS_") else { return false }
        if cueId.hasPrefix("BS_FRAC") { return false }
        if cueId.range(of: #"^BS([1-9]|10)$"#, options: .regularExpression) != nil { return false }
        return true
    }

    private static func bodyScanModuleIdFromTierClipIds(_ ids: [String]) -> String {
        let blob = ids.joined(separator: " ").uppercased()
        if blob.contains("ENTRY_BOTTOM") { return "BS_FRAC_UP" }
        if blob.contains("ENTRY_TOP") { return "BS_FRAC_DOWN" }
        let upHints = ["_BOTTOM", "FEET", "TOE", "ANKLE", "SHIN", "THIGH", "LEG"]
        let downHints = ["_TOP", "HEAD", "CROWN", "FACE", "NECK", "SCALP", "FOREHEAD"]
        let upScore = upHints.filter { blob.contains($0) }.count
        let downScore = downHints.filter { blob.contains($0) }.count
        if upScore > downScore { return "BS_FRAC_UP" }
        if downScore > upScore { return "BS_FRAC_DOWN" }
        return "BS_FRAC_DOWN"
    }

    /// Atomic expanded IM/NF/Morning Viz clips (`IM_C###`, `NF_C###`, `MVK_C###`, `MVG_C###`) — same loudness pipeline as body scan; no legacy monolithic boost.
    static func isAtomicMantraOrNostrilClip(_ moduleId: String) -> Bool {
        guard let range = moduleId.range(of: #"_C\d+$"#, options: .regularExpression) else { return false }
        let prefix = String(moduleId[moduleId.startIndex..<range.lowerBound])
        return prefix == "IM" || prefix == "NF" || prefix == "MVK" || prefix == "MVG"
    }
}
