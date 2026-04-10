//
//  FractionalCueID.swift
//  Dojo
//
//  Shared parsing for expanded fractional clip IDs (collapse to _FRAC modules, playback gain rules).
//

import Foundation

enum FractionalCueID {

    /// Prefix used when collapsing atomic clips into one `_FRAC` row (e.g. `NF` from `NF_C001`).
    /// Perfect Breath uses `PBV_` / `PBS_` clip IDs → prefix `PB`.
    static func fractionalCollapsePrefix(of cueId: String) -> String? {
        if cueId.hasPrefix("PBV_") || cueId.hasPrefix("PBS_") { return "PB" }
        guard let range = cueId.range(of: #"_C\d+$"#, options: .regularExpression) else { return nil }
        let prefix = String(cueId[cueId.startIndex..<range.lowerBound])
        return prefix.isEmpty ? nil : prefix
    }

    /// Atomic expanded IM/NF clips (`IM_C###`, `NF_C###`) — same loudness pipeline as body scan; no legacy monolithic boost.
    static func isAtomicMantraOrNostrilClip(_ moduleId: String) -> Bool {
        guard let range = moduleId.range(of: #"_C\d+$"#, options: .regularExpression) else { return false }
        let prefix = String(moduleId[moduleId.startIndex..<range.lowerBound])
        return prefix == "IM" || prefix == "NF"
    }
}
