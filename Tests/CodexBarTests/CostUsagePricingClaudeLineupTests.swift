import Foundation
import Testing
@testable import CodexBarCore

struct CostUsagePricingClaudeLineupTests {
    /// 1000 input, 10000 cache reads, 2000 5m writes, 1000 1h writes (2x input), and 500 output tokens.
    @Test(arguments: [
        ("claude-fable-5-1", 0.0825),
        ("claude-mythos-5-1", 0.0825),
        ("claude-mythos-5", 0.09),
        ("claude-opus-5", 0.045),
        ("claude-opus-5-5", 0.034),
        ("anthropic.claude-opus-5-5", 0.034),
        ("us.anthropic.claude-opus-5-5", 0.034),
        ("claude-sonnet-5", 0.018),
        ("claude-sonnet-5-5", 0.018),
        ("global.anthropic.claude-sonnet-5-5", 0.018),
    ])
    func `bundled current lineup rows price every token bucket`(model: String, expected: Double) throws {
        let cost = try #require(CostUsagePricing.claudeCostUSD(
            model: model,
            inputTokens: 1000,
            cacheReadInputTokens: 10000,
            cacheCreationInputTokens: 3000,
            cacheCreationInputTokens1h: 1000,
            outputTokens: 500,
            modelsDevCatalog: ModelsDevCatalog(providers: [:])))
        #expect(abs(cost - expected) < 1e-12)
    }

    @Test(arguments: [("claude-opus-5-5", 3.6), ("claude-sonnet-5-5", 1.8)])
    func `current lineup bills the full context window at standard rates`(model: String, expected: Double) throws {
        let cost = try #require(CostUsagePricing.claudeCostUSD(
            model: model,
            inputTokens: 900_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0,
            modelsDevCatalog: ModelsDevCatalog(providers: [:])))
        #expect(abs(cost - expected) < 1e-12)
    }
}
