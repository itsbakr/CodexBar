import Foundation

enum ClaudeWebExtraRateWindowParser {
    /// Claude's extra rows are the model-scoped weekly limits; retired Daily Routines/Cowork keys are ignored.
    static func parse(from json: [String: Any]) -> [NamedRateWindow] {
        guard let limits = json["limits"] as? [[String: Any]] else { return [] }
        let mappedLimits = limits.map { entry in
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
        return ClaudeScopedWeeklyLimitMapper.extraRateWindows(from: mappedLimits)
    }

    private static func percentValue(from value: Any?) -> Double? {
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }
        return nil
    }
}
