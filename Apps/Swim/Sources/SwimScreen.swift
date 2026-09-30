import SwiftUI
import SwimKit

/// The palette of Kevin's mockup (2026-09-30): a deep blue-green ground, pale
/// teal labels, white numbers, a coral heart.
enum Palette {
    static let ground = Color(red: 0.06, green: 0.13, blue: 0.16)
    static let rule = Color(red: 0.36, green: 0.52, blue: 0.56).opacity(0.7)
    static let label = Color(red: 0.66, green: 0.84, blue: 0.87)
    static let badge = Color(red: 0.20, green: 0.44, blue: 0.50)
    static let heart = Color(red: 0.93, green: 0.30, blue: 0.40)
    static let total = Color(red: 0.98, green: 0.84, blue: 0.30)

    static func zone(_ zone: HeartZone) -> Color {
        switch zone {
        case .rest: Color(red: 0.45, green: 0.78, blue: 0.76)
        case .one: .blue
        case .two: .green
        case .three: .yellow
        case .four: .orange
        case .five: .red
        }
    }
}

/// The whole app, one screen at a time: Start → swimming → saved.
struct SwimScreen: View {
    let session: SwimSession
    /// The last pool chosen is the next one offered.
    @AppStorage("pool") private var pool: Pool = .yards25

    var body: some View {
        Group {
            switch session.phase {
            case .idle:
                StartPage(pool: $pool) { Task { await session.start(in: pool) } }
            case .starting:
                ProgressView("Starting…")
            case .running:
                SwimLiveView(session: session)
            case .saving:
                ProgressView("Saving…")
            case .saved(let summary):
                SummaryPage(summary: summary) { session.dismiss() }
            case .discarded:
                message("Nothing to save", detail: "Under a minute with no lengths.")
            case .failed(let why):
                message("Couldn't record", detail: why.localizedCaseInsensitiveContains("authoriz")
                    ? "Allow Health for Swim: iPhone Settings → Health → Data Access & Devices → Swim → Turn On All."
                    : why)
            }
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { session.dismiss() }
        }
    }
}

/// Start, and the pool it will count lengths in. The pool button opens the
/// three choices; the choice is remembered.
struct StartPage: View {
    @Binding var pool: Pool
    let start: () -> Void
    @State private var choosing = false

    var body: some View {
        VStack(spacing: 10) {
            SwimBadge(size: 40)
            Button(action: start) {
                Text("Start").font(.title3.bold()).frame(maxWidth: .infinity)
            }
            .tint(Palette.badge)
            Button { choosing = true } label: {
                HStack {
                    Image(systemName: "ruler")
                    Text("Pool \(pool.title)").font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $choosing) {
            NavigationStack {
                PoolMenu(pool: $pool) { choosing = false }
            }
        }
    }
}

struct PoolMenu: View {
    @Binding var pool: Pool
    let done: () -> Void

    var body: some View {
        List(Pool.allCases) { option in
            Button {
                pool = option
                done()
            } label: {
                HStack {
                    Text(option.title).font(.title3.weight(.semibold))
                    Spacer()
                    if option == pool {
                        Image(systemName: "checkmark").foregroundStyle(Palette.label)
                    }
                }
            }
        }
        .navigationTitle("Pool Length")
    }
}

/// The swimmer icon in its teal disc, top-left in the mockup.
struct SwimBadge: View {
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: "figure.pool.swim")
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.badge, in: Circle())
    }
}

/// The live swim, laid out like Apple's Workout app: swipe right for the
/// controls, and the metrics are the page it opens on. End is one swipe away
/// on purpose, as in Rowing — never under a wet wrist.
private struct SwimLiveView: View {
    let session: SwimSession
    @State private var page = LivePage.metrics

    var body: some View {
        LivePager(page: $page) {
            ControlsPage(
                isPaused: session.isPaused,
                end: { Task { await session.finish() } },
                pause: session.togglePause,
                lock: session.lockScreen
            )
        } metrics: {
            LiveMetrics(session: session)
        }
    }
}

enum LivePage: Hashable { case controls, metrics }

/// The two live pages, side by side. In a NavigationStack so the metrics
/// page can put its badge in the clock's row, where the mockup has it.
struct LivePager<Controls: View, Metrics: View>: View {
    @Binding var page: LivePage
    @ViewBuilder let controls: Controls
    @ViewBuilder let metrics: Metrics

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                controls.tag(LivePage.controls)
                metrics.tag(LivePage.metrics)
            }
            .tabViewStyle(.page)
        }
    }
}

/// Reads the session each tick and hands plain values to the page, so a
/// render can hand it its own.
private struct LiveMetrics: View {
    let session: SwimSession
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        // Hundredths need a fast tick; a dimmed wrist gets one a second.
        TimelineView(.periodic(from: .now, by: dimmed ? 1 : 0.05)) { context in
            MetricsPage(values: .init(session: session, at: context.date), hundredths: !dimmed)
        }
    }
}

/// Everything the metrics page draws.
struct MetricValues {
    var pool: Pool
    var meters: Double
    var total: TimeInterval
    var status: Status
    var heartRate: Double?
    var zone: HeartZone?
    var isPaused = false

    enum Status {
        case swimming(TimeInterval)
        case resting(TimeInterval)
    }

    init(pool: Pool, meters: Double, total: TimeInterval, status: Status,
         heartRate: Double?, zone: HeartZone?, isPaused: Bool = false) {
        self.pool = pool
        self.meters = meters
        self.total = total
        self.status = status
        self.heartRate = heartRate
        self.zone = zone
        self.isPaused = isPaused
    }

    @MainActor
    init(session: SwimSession, at now: Date) {
        let status: Status = switch session.tracker.status(at: now) {
        case .swimming(let since): .swimming(now.timeIntervalSince(since))
        case .resting(let since, _): .resting(now.timeIntervalSince(since))
        }
        self.init(
            pool: session.pool,
            meters: session.meters,
            total: session.elapsed(at: now),
            status: status,
            heartRate: session.heartRate,
            zone: zip(session.heartRate, session.maxHeartRate).map { HeartZone(bpm: $0, maxHeartRate: $1) },
            isPaused: session.isPaused
        )
    }
}

/// Swift has no zip for optionals; this is the one place that wants it.
private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

/// Kevin's layout, from his mockup (2026-09-30): total distance across the
/// top, set time and heart rate side by side beneath, thin rules between.
/// Total workout time sits by the swimmer badge, in yellow so it is never
/// read as the clock across from it.
///
/// While resting, the left cell becomes the rest clock — Apple's app does the
/// same, and a frozen set time would look like a stuck watch.
struct MetricsPage: View {
    let values: MetricValues
    let hundredths: Bool

    var body: some View {
        VStack(spacing: 0) {
            rule
            VStack(spacing: -2) {
                Text("Total Distance")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.label)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(values.pool.displayDistance(meters: values.meters))")
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(values.pool.unitLabel)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .padding(.vertical, 4)
            rule

            HStack(spacing: 0) {
                setCell
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Palette.rule).frame(width: 1).padding(.vertical, 4)
                heartCell
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
            rule
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .background(Palette.ground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 6) {
                    SwimBadge(size: 30)
                    Text(values.isPaused ? "Paused" : SwimClock.total(values.total))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.total)
                }
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(Palette.rule).frame(height: 1)
    }

    private var setCell: some View {
        let (label, seconds): (String, TimeInterval) = switch values.status {
        case .swimming(let s): ("Total Set Time", s)
        case .resting(let s): ("Rest", s)
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.label)
            Text(SwimClock.set(seconds, hundredths: hundredths))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heartCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.heart)
                Text(values.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.label)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 10)
            }
            if let zone = values.zone {
                HStack(spacing: 4) {
                    Text("ZONE: \(zone.label)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.label)
                    Circle().fill(Palette.zone(zone)).frame(width: 7, height: 7)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Swiped to from the metrics: End, Pause and Water Lock, as in Apple's app.
struct ControlsPage: View {
    let isPaused: Bool
    let end: () -> Void
    let pause: () -> Void
    let lock: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                control("Lock", "drop.fill", .cyan, lock)
                control("End", "xmark", .red, end)
            }
            GridRow {
                control(isPaused ? "Resume" : "Pause",
                        isPaused ? "arrow.clockwise" : "pause.fill", .yellow, pause)
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    private func control(_ title: String, _ icon: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 58, height: 58)
                    .background(tint.opacity(0.25), in: Circle())
                    .foregroundStyle(tint)
                Text(title).font(.footnote.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
    }
}

/// What was just saved.
struct SummaryPage: View {
    let summary: SwimSession.Summary
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Label("Saved to Health", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(summary.pool.displayDistance(meters: summary.meters))")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text(summary.pool.unitLabel).font(.title3.weight(.semibold))
                }
                row("Time", SwimClock.total(summary.duration))
                row("Sets", "\(summary.sets)")
                row("Avg Heart Rate", summary.averageHeartRate.map { "\(Int($0.rounded())) BPM" } ?? "--")
                Button("Done", action: done).padding(.top, 4)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.body)
    }
}
