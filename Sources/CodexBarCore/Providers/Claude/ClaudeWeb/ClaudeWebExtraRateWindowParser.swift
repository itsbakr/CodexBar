import CoreFoundation
import Foundation

enum ClaudeWebExtraRateWindowParser {
    /// Claude's extra rows are the model-scoped weekly limits; the retired Routines/Cowork keys are ignored.
    static func parse(from json: [String: Any]) -> [NamedRateWindow] {
        ClaudeScopedWeeklyLimitMapper.extraRateWindows(from: self.scopedWeeklyLimits(from: json))
    }

    /// Entry-by-entry parse of the `limits` array, shared with the OAuth path: a field of an
    /// unexpected type reads as missing instead of discarding the entry or its siblings.
    static func scopedWeeklyLimits(from json: [String: Any]) -> [ClaudeScopedWeeklyLimitMapper.Limit] {
        guard let limits = json["limits"] as? [Any] else { return [] }
        return limits.compactMap { $0 as? [String: Any] }.map { entry in
            let scope = entry["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            return ClaudeScopedWeeklyLimitMapper.Limit(
                kind: entry["kind"] as? String,
                group: entry["group"] as? String,
                percent: Self.percentValue(from: entry["percent"]),
                resetsAt: ISO8601DateParser.parse(entry["resets_at"] as? String),
                modelID: model?["id"] as? String,
                modelName: model?["display_name"] as? String)
        }
    }

    private static func percentValue(from value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.doubleValue
    }
}
