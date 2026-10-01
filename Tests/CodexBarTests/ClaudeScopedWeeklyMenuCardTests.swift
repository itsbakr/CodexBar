import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ClaudeScopedWeeklyMenuCardTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `claude card shows scoped weekly rows after standard lanes regardless of optional usage`() throws {
        let snapshot = Self.snapshot(extraRateWindows: [
            Self.weeklyWindow(id: "claude-weekly-scoped-fable", title: "Fable only", usedPercent: 11),
        ])

        for showOptionalUsage in [true, false] {
            let model = try Self.makeModel(snapshot: snapshot, showOptionalUsage: showOptionalUsage)
            #expect(model.metrics.map(\.title) == ["Session", "Weekly", "Sonnet", "Fable weekly"])
        }
    }

    @Test
    func `multiple scoped weekly rows render in payload order`() throws {
        let snapshot = Self.snapshot(extraRateWindows: [
            Self.weeklyWindow(
                id: "claude-weekly-scoped-example-model",
                title: "Example Model only",
                usedPercent: 30),
            Self.weeklyWindow(id: "claude-weekly-scoped-fable", title: "Fable only", usedPercent: 11),
        ])

        let model = try Self.makeModel(snapshot: snapshot)

        #expect(model.metrics.map(\.id) == [
            "primary",
            "secondary",
            "tertiary",
            "claude-weekly-scoped-example-model",
            "claude-weekly-scoped-fable",
        ])
        #expect(model.metrics.suffix(2).map(\.title) == ["Example Model weekly", "Fable weekly"])
    }

    @Test
    func `retired daily routines window from an older synced snapshot produces no metric`() throws {
        let snapshot = Self.snapshot(extraRateWindows: [
            Self.weeklyWindow(id: "claude-weekly-scoped-fable", title: "Fable only", usedPercent: 11),
            Self.weeklyWindow(id: "claude-routines", title: "Daily Routines", usedPercent: 7),
        ])

        let model = try Self.makeModel(snapshot: snapshot)

        #expect(model.metrics.map(\.id) == ["primary", "secondary", "tertiary", "claude-weekly-scoped-fable"])
    }

    @Test
    func `usage item descriptors title the scoped row as a weekly model lane`() throws {
        let snapshot = Self.snapshot(extraRateWindows: [
            Self.weeklyWindow(id: "claude-weekly-scoped-fable", title: "Fable only", usedPercent: 11),
            Self.weeklyWindow(id: "claude-routines", title: "Daily Routines", usedPercent: 7),
        ])

        let descriptors = try Self.makeModel(snapshot: snapshot).usageItemDescriptors

        #expect(descriptors.first { $0.id == .metric("claude-weekly-scoped-fable") }?.title == "Fable weekly")
        #expect(!descriptors.contains { $0.id == .metric("claude-routines") })
    }

    private static func weeklyWindow(id: String, title: String, usedPercent: Double) -> NamedRateWindow {
        NamedRateWindow(
            id: id,
            title: title,
            window: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 10080,
                resetsAt: self.now.addingTimeInterval(8600),
                resetDescription: nil))
    }

    private static func snapshot(extraRateWindows: [NamedRateWindow]) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 2,
                windowMinutes: nil,
                resetsAt: self.now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 8,
                windowMinutes: 10080,
                resetsAt: self.now.addingTimeInterval(7200),
                resetDescription: nil),
            tertiary: RateWindow(
                usedPercent: 16,
                windowMinutes: 10080,
                resetsAt: self.now.addingTimeInterval(7800),
                resetDescription: nil),
            extraRateWindows: extraRateWindows,
            updatedAt: self.now,
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "Max"))
    }

    private static func makeModel(
        snapshot: UsageSnapshot,
        showOptionalUsage: Bool = true) throws -> UsageMenuCardView.Model
    {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        return UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "codex@example.com", plan: "plus"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: showOptionalUsage,
            hidePersonalInfo: false,
            now: Self.now))
    }
}
