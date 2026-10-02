import SwiftUI
import SwimKit

/// Swim: a pool-swim workout app for the watch, laid out the way Kevin wants
/// it rather than the way Apple's Workout app allows (2026-09-30).
///
/// Watch-only, like Rowing: the workout reaches Fitness on the phone through
/// Health, and the Hub is untouched. See `SWIM.md`.
@main
struct SwimApp: App {
    @State private var session = SwimSession()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let page = RenderDemo.page {
                RenderDemo(page: page)
            } else {
                SwimScreen(session: session)
            }
            #else
            SwimScreen(session: session)
            #endif
        }
    }
}

#if DEBUG
/// Each screen with fixed numbers, for screenshots from a simulator — which
/// has no pool and no Health. Launched as `-renderDemo <page>` by the
/// `render` job of swim-watch.yml. Debug builds only.
struct RenderDemo: View {
    enum Page: String { case start, pools, swimming, resting, controls, summary }

    static var page: Page? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-renderDemo"), i + 1 < args.count else { return nil }
        return Page(rawValue: args[i + 1])
    }

    let page: Page
    @State private var pool: Pool = .yards25

    var body: some View {
        switch page {
        case .start:
            StartPage(pool: $pool) {}
        case .pools:
            NavigationStack { PoolMenu(pool: $pool) {} }
        case .swimming:
            // The numbers from Kevin's mockup; no water reading yet.
            pager(.metrics, MetricValues(pool: .yards25, meters: 0, total: 3.43,
                                         waterCelsius: nil, heartRate: 71, zone: .rest))
        case .resting:
            pager(.metrics, MetricValues(pool: .yards25, meters: 8 * 22.86, total: 1234,
                                         waterCelsius: 27.8, heartRate: 142, zone: .three))
        case .controls:
            pager(.controls, MetricValues(pool: .yards25, meters: 0, total: 0,
                                          waterCelsius: nil, heartRate: nil, zone: nil))
        case .summary:
            SummaryPage(summary: .init(pool: .yards25, meters: 40 * 22.86, duration: 1712,
                                       sets: 6, averageHeartRate: 128, waterCelsius: 27.8,
                                       activeCalories: 312,
                                       stats: SwimStats(pool: .yards25, meters: 40 * 22.86, swimSeconds: 1180,
                                                        strokeCount: 640,
                                                        lengthStrokes: Array(repeating: 2, count: 32)
                                                            + Array(repeating: 4, count: 8)))) {}
        }
    }

    private func pager(_ start: LivePage, _ values: MetricValues) -> some View {
        LivePager(page: .constant(start)) {
            ControlsPage(isPaused: false, end: {}, pause: {}, lock: {})
        } metrics: {
            MetricsPage(values: values)
        }
    }
}
#endif
