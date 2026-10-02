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
            // Filled, with white type: a tinted plain button read as disabled
            // in the first render.
            Button(action: start) {
                Text("Start").font(.title3.bold()).foregroundStyle(.white).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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

    var body: some View {
        // Once a second: the only clock left on the page is the total, in whole
        // seconds. (The set timer's hundredths needed 20 a second until the
        // water temperature took its cell, 2026-09-30.)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            MetricsPage(values: .init(session: session, at: context.date))
        }
    }
}

/// Everything the metrics page draws.
struct MetricValues {
    var pool: Pool
    var meters: Double
    var total: TimeInterval
    /// Celsius, as Health holds it; nil until the watch has a reading.
    var waterCelsius: Double?
    var heartRate: Double?
    var zone: HeartZone?
    var isPaused = false

    init(pool: Pool, meters: Double, total: TimeInterval, waterCelsius: Double?,
         heartRate: Double?, zone: HeartZone?, isPaused: Bool = false) {
        self.pool = pool
        self.meters = meters
        self.total = total
        self.waterCelsius = waterCelsius
        self.heartRate = heartRate
        self.zone = zone
        self.isPaused = isPaused
    }

    @MainActor
    init(session: SwimSession, at now: Date) {
        self.init(
            pool: session.pool,
            meters: session.meters,
            total: session.elapsed(at: now),
            waterCelsius: session.waterCelsius,
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
/// top, two cells side by side beneath, thin rules between. Total workout time
/// sits by the swimmer badge, in yellow so it is never read as the clock
/// across from it.
///
/// ! THE LEFT CELL IS THE WATER'S TEMPERATURE, not the set timer the mockup
/// had (Kevin, later the same day: "instead of the total set time box can we
/// change that to the water temperature"). So no set or rest clock is on
/// screen any more; sets are still counted, and the summary still says how
/// many.
struct MetricsPage: View {
    let values: MetricValues

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
                waterCell
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

    /// "--" until the watch has a reading, and all swim long on a watch
    /// without the sensor: an honest blank, not a guessed number.
    private var waterCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Water Temp")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.label)
            Text(values.waterCelsius.map {
                WaterTemperature.text(celsius: $0, fahrenheit: UnitTemperature(forLocale: .current) == .fahrenheit)
            } ?? "--")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
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
            // Pause beside End, Lock below (Kevin, 2026-09-30).
            GridRow {
                control(isPaused ? "Resume" : "Pause",
                        isPaused ? "arrow.clockwise" : "pause.fill", .yellow, pause)
                control("End", "xmark", .red, end)
            }
            GridRow {
                control("Lock", "drop.fill", .cyan, lock)
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
                // Pace and SWOLF are measured while swimming, rests left out
                // (Kevin, 2026-10-02: "yes add all those to the summary").
                if let pace = summary.stats.pacePer100 {
                    row("Pace", "\(SwimClock.pace(pace)) /100 \(summary.pool.unitLabel)")
                }
                row("Sets", "\(summary.sets)")
                row("Avg Heart Rate", summary.averageHeartRate.map { "\(Int($0.rounded())) BPM" } ?? "--")
                if let swolf = summary.stats.swolf {
                    row("SWOLF", "\(swolf)")
                }
                if let calories = summary.activeCalories {
                    row("Active Calories", "\(Int(calories.rounded())) CAL")
                }
                ForEach(summary.stats.strokes) { share in
                    row(share.stroke.title, "\(share.distance) \(summary.pool.unitLabel)")
                }
                if let water = summary.waterCelsius {
                    row("Water", WaterTemperature.text(celsius: water, fahrenheit: UnitTemperature(forLocale: .current) == .fahrenheit))
                }
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
