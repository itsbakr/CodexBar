import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct ClaudeExtraWindowQuotaWarningTests {
    private func makeSettings(suiteName: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    @MainActor
    final class SessionQuotaNotifierSpy: SessionQuotaNotifying {
        private(set) var quotaWarningPosts: [(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled: Bool,
            onScreenAlertEnabled: Bool)] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled: Bool,
            onScreenAlertEnabled: Bool)
        {
            self.quotaWarningPosts.append((
                event: event,
                provider: provider,
                soundEnabled: soundEnabled,
                onScreenAlertEnabled: onScreenAlertEnabled))
        }
    }

    @Test
    func `claude sibling scoped weekly windows fire independent weekly warnings`() {
        let settings = self.makeSettings(suiteName: "ClaudeExtraWindowQuotaWarningTests-independent")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50, 20]
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)
        settings.showOptionalCreditsAndExtraUsage = false

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)

        store.handleQuotaWarningTransitions(
            provider: .claude,
            snapshot: self.claudeExtraWindowSnapshot(fableUsed: 40, otherModelUsed: 40))
        store.handleQuotaWarningTransitions(
            provider: .claude,
            snapshot: self.claudeExtraWindowSnapshot(fableUsed: 55, otherModelUsed: 55))

        #expect(notifier.quotaWarningPosts.count == 2)
        let fable = notifier.quotaWarningPosts.first { $0.event.windowID == "claude-weekly-scoped-fable" }
        let otherModel = notifier.quotaWarningPosts.first { $0.event.windowID == Self.otherModelWindowID }
        #expect(fable?.event.window == .weekly)
        #expect(fable?.event.threshold == 50)
        #expect(fable?.event.windowDisplayLabel == "Fable only")
        #expect(otherModel?.event.threshold == 50)
        #expect(otherModel?.event.windowDisplayLabel == "Example Model only")

        // Each window keeps independent fired-threshold state instead of clobbering the shared weekly key.
        let fableKey = UsageStore.QuotaWarningStateKey(
            provider: .claude,
            window: .weekly,
            accountDiscriminator: nil,
            windowID: "claude-weekly-scoped-fable")
        let otherModelKey = UsageStore.QuotaWarningStateKey(
            provider: .claude,
            window: .weekly,
            accountDiscriminator: nil,
            windowID: Self.otherModelWindowID)
        #expect(store.quotaWarningState[fableKey]?.firedThresholds.contains(50) == true)
        #expect(store.quotaWarningState[otherModelKey]?.firedThresholds.contains(50) == true)
    }

    @Test
    func `retired routines window does not post a quota warning`() {
        let settings = self.makeSettings(suiteName: "ClaudeExtraWindowQuotaWarningTests-retired-routines")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)

        /// Older synced snapshots can still carry the retired Daily Routines row.
        func snapshot(used: Double) -> UsageSnapshot {
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                extraRateWindows: [
                    NamedRateWindow(
                        id: "claude-routines",
                        title: "Daily Routines",
                        window: RateWindow(
                            usedPercent: used,
                            windowMinutes: 7 * 24 * 60,
                            resetsAt: nil,
                            resetDescription: nil)),
                ],
                updatedAt: Date())
        }
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: snapshot(used: 40))
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: snapshot(used: 55))

        #expect(notifier.quotaWarningPosts.isEmpty)
        #expect(!store.quotaWarningState.keys.contains { $0.windowID == "claude-routines" })
    }

    @Test
    func `antigravity summary extra windows do not trigger the claude extra-window lane`() {
        let settings = self.makeSettings(suiteName: "ClaudeExtraWindowQuotaWarningTests-antigravity-guard")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50, 20]
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)

        func snapshot(used: Double) -> UsageSnapshot {
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                extraRateWindows: [
                    NamedRateWindow(
                        id: "antigravity-quota-summary-model-weekly",
                        title: "Weekly",
                        window: RateWindow(
                            usedPercent: used,
                            windowMinutes: 7 * 24 * 60,
                            resetsAt: nil,
                            resetDescription: nil)),
                ],
                updatedAt: Date())
        }
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: snapshot(used: 40))
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: snapshot(used: 55))

        #expect(notifier.quotaWarningPosts.isEmpty)
    }

    @Test
    func `claude scoped weekly window refires after recovering above threshold`() {
        let settings = self.makeSettings(suiteName: "ClaudeExtraWindowQuotaWarningTests-refire")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)

        // 60% remaining -> 45% (fires 50) -> 60% (clears 50) -> 45% (refires 50).
        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 40, otherModelUsed: nil))
        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 55, otherModelUsed: nil))
        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 40, otherModelUsed: nil))
        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 55, otherModelUsed: nil))

        #expect(notifier.quotaWarningPosts.count == 2)
        #expect(notifier.quotaWarningPosts.allSatisfy { $0.event.windowID == "claude-weekly-scoped-fable" })
    }

    @Test
    func `claude extra-window fired state is pruned when a window disappears but others remain`() {
        let settings = self.makeSettings(suiteName: "ClaudeExtraWindowQuotaWarningTests-prune")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)

        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 40, otherModelUsed: 40))
        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 55, otherModelUsed: 55))
        let fableKey = UsageStore.QuotaWarningStateKey(
            provider: .claude,
            window: .weekly,
            accountDiscriminator: nil,
            windowID: "claude-weekly-scoped-fable")
        let otherModelKey = UsageStore.QuotaWarningStateKey(
            provider: .claude,
            window: .weekly,
            accountDiscriminator: nil,
            windowID: Self.otherModelWindowID)
        #expect(store.quotaWarningState[fableKey] != nil)
        #expect(store.quotaWarningState[otherModelKey] != nil)

        // Fable ends while the sibling scoped window is still present: this refresh carries authoritative
        // extras, so Fable's stale state is dropped and the sibling's state is kept.
        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: nil, otherModelUsed: 55))
        #expect(store.quotaWarningState[fableKey] == nil)
        #expect(store.quotaWarningState[otherModelKey] != nil)
    }

    @Test
    func `claude extra-window reconciliation preserves sibling account state`() {
        let settings = self.makeSettings(suiteName: "ClaudeExtraWindowQuotaWarningTests-account-prune")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)

        store.handleQuotaWarningTransitions(
            provider: .claude,
            snapshot: self.claudeExtraWindowSnapshot(fableUsed: 40, otherModelUsed: nil),
            accountDiscriminator: "account-a")
        store.handleQuotaWarningTransitions(
            provider: .claude,
            snapshot: self.claudeExtraWindowSnapshot(fableUsed: 55, otherModelUsed: nil),
            accountDiscriminator: "account-a")
        let accountAFableKey = UsageStore.QuotaWarningStateKey(
            provider: .claude,
            window: .weekly,
            accountDiscriminator: "account-a",
            windowID: "claude-weekly-scoped-fable")
        #expect(store.quotaWarningState[accountAFableKey] != nil)

        store.handleQuotaWarningTransitions(
            provider: .claude,
            snapshot: self.claudeExtraWindowSnapshot(fableUsed: nil, otherModelUsed: 40),
            accountDiscriminator: "account-b")
        #expect(store.quotaWarningState[accountAFableKey] != nil)

        store.handleQuotaWarningTransitions(
            provider: .claude,
            snapshot: self.claudeExtraWindowSnapshot(fableUsed: 55, otherModelUsed: nil),
            accountDiscriminator: "account-a")

        #expect(notifier.quotaWarningPosts.count == 1)
        #expect(notifier.quotaWarningPosts.first?.event.windowID == "claude-weekly-scoped-fable")
        #expect(notifier.quotaWarningPosts.first?.event.threshold == 50)
    }

    @Test
    func `disabling weekly warnings clears all account-scoped claude extra-window state`() {
        let settings = self.makeSettings(suiteName: "ClaudeExtraWindowQuotaWarningTests-disable")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)

        let accountIDs = ["account-a", "account-b"]
        for accountID in accountIDs {
            store.handleQuotaWarningTransitions(
                provider: .claude,
                snapshot: self.claudeExtraWindowSnapshot(fableUsed: 40, otherModelUsed: 40),
                accountDiscriminator: accountID)
        }
        let seededKeys = accountIDs.flatMap { accountID in
            [
                UsageStore.QuotaWarningStateKey(
                    provider: .claude,
                    window: .weekly,
                    accountDiscriminator: accountID,
                    windowID: "claude-weekly-scoped-fable"),
                UsageStore.QuotaWarningStateKey(
                    provider: .claude,
                    window: .weekly,
                    accountDiscriminator: accountID,
                    windowID: Self.otherModelWindowID),
            ]
        }
        #expect(seededKeys.allSatisfy { store.quotaWarningState[$0] != nil })

        settings.setQuotaWarningWindowEnabled(.weekly, enabled: false)
        store.handleQuotaWarningTransitions(
            provider: .claude,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, extraRateWindows: nil, updatedAt: Date()),
            accountDiscriminator: accountIDs[0])
        #expect(seededKeys.allSatisfy { store.quotaWarningState[$0] == nil })
    }

    @Test
    func `claude extra-window state survives a transient extras miss without re-posting`() {
        let settings = self.makeSettings(suiteName: "ClaudeExtraWindowQuotaWarningTests-transient-miss")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)

        // Fable crosses 50% and warns once.
        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 40, otherModelUsed: nil))
        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 55, otherModelUsed: nil))
        #expect(notifier.quotaWarningPosts.count == 1)
        let fableKey = UsageStore.QuotaWarningStateKey(
            provider: .claude,
            window: .weekly,
            accountDiscriminator: nil,
            windowID: "claude-weekly-scoped-fable")

        // A failed web-extras fetch delivers nil extras while the main snapshot is intact. The fired
        // state must persist so the warning is not re-posted when extras recover.
        store.handleQuotaWarningTransitions(
            provider: .claude,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, extraRateWindows: nil, updatedAt: Date()))
        #expect(store.quotaWarningState[fableKey] != nil)

        store.handleQuotaWarningTransitions(
            provider: .claude, snapshot: self.claudeExtraWindowSnapshot(fableUsed: 55, otherModelUsed: nil))
        #expect(notifier.quotaWarningPosts.count == 1)
    }

    private static let otherModelWindowID = "claude-weekly-scoped-example-model"

    private func claudeExtraWindowSnapshot(fableUsed: Double?, otherModelUsed: Double?) -> UsageSnapshot {
        var windows: [NamedRateWindow] = []
        if let fableUsed {
            windows.append(NamedRateWindow(
                id: "claude-weekly-scoped-fable",
                title: "Fable only",
                window: RateWindow(
                    usedPercent: fableUsed, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil)))
        }
        if let otherModelUsed {
            windows.append(NamedRateWindow(
                id: Self.otherModelWindowID,
                title: "Example Model only",
                window: RateWindow(
                    usedPercent: otherModelUsed, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil)))
        }
        return UsageSnapshot(primary: nil, secondary: nil, extraRateWindows: windows, updatedAt: Date())
    }
}
