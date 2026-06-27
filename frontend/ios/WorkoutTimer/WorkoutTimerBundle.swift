import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

@main
struct WorkoutTimerBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

struct WorkoutLiveActivity: Widget {
    private let activeColor = Color(red: 0.36, green: 0.84, blue: 0.38)
    private let restColor = Color(red: 0.95, green: 0.68, blue: 0.26)
    private let pauseColor = Color.white
    private let stopColor = Color(red: 1.0, green: 0.28, blue: 0.28)

    var body: some WidgetConfiguration {

        ActivityConfiguration(for: WorkoutAttributes.self) { context in

            LockScreenWorkoutView(context: context)

        } dynamicIsland: { context in

            DynamicIsland {

                // MARK: LEADING

                DynamicIslandExpandedRegion(.leading) {

                    TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                        Image(systemName: sessionIcon(for: context.state, now: timeline.date))
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(statusColor(for: context.state, now: timeline.date))
                            .frame(width: 36, height: 44)
                    }
                }

                // MARK: CENTER

                DynamicIslandExpandedRegion(.center) {

                    TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                        let titles = parsedTitles(from: context.state.title)

                        VStack(alignment: .leading, spacing: 3) {

                            Text(sessionStatus(for: context.state, now: timeline.date).uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(statusColor(for: context.state, now: timeline.date))
                                .tracking(1.1)

                            Text(primaryExpandedTitle(from: titles, state: context.state, now: timeline.date))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)

                            Text(secondaryExpandedTitle(from: titles))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.56))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                    }
                }

                // MARK: TRAILING

                DynamicIslandExpandedRegion(.trailing) {

                    TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                        timerText(for: context.state, now: timeline.date)
                            .font(.system(
                                size: isRestState(context.state, now: timeline.date) ? 22 : 18,
                                weight: .black,
                                design: .rounded
                            ))
                            .monospacedDigit()
                            .foregroundStyle(statusColor(for: context.state, now: timeline.date))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .frame(
                                width: isRestState(context.state, now: timeline.date) ? 82 : 100,
                                alignment: .trailing
                            )
                    }
                }

                // MARK: BOTTOM

                DynamicIslandExpandedRegion(.bottom) {

                    VStack(spacing: 6) {

                        // PROGRESS BAR

                        TimelineView(.animation) { timeline in
                            if isRestState(context.state, now: timeline.date) {
                                restScrubber(
                                    for: context.state,
                                    now: timeline.date,
                                    height: 4,
                                    thumbSize: 10,
                                    trackOpacity: 0.09
                                )
                                .frame(height: 10)
                            } else {
                                Color.clear.frame(height: 0)
                            }
                        }
                        .padding(.horizontal, 6)

                        // BUTTONS

                        HStack(spacing: 26) {

                            islandButton(
                                icon: "stop.fill",
                                foreground: stopColor,
                                intent: StopWorkoutIntent()
                            )

                            if context.state.isPaused {

                                islandButton(
                                    icon: "play.fill",
                                    foreground: activeColor,
                                    intent: ResumeWorkoutIntent(),
                                    isPrimary: true
                                )

                            } else {

                                islandButton(
                                    icon: "pause.fill",
                                    foreground: pauseColor,
                                    intent: PauseWorkoutIntent(),
                                    isPrimary: true
                                )
                            }

                            islandButton(
                                icon: "forward.fill",
                                foreground: activeColor,
                                intent: NextStepIntent()
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 0)
                    .padding(.bottom, 0)
                    .padding(.horizontal, 10)
                }

            } compactLeading: {

                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    Image(systemName: compactSessionIcon(for: context.state, now: timeline.date))
                        .resizable()
                        .scaledToFit()
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(statusColor(for: context.state, now: timeline.date))
                        .frame(
                            width: isRestState(context.state, now: timeline.date) ? 13 : 18,
                            height: isRestState(context.state, now: timeline.date) ? 13 : 16
                        )
                        .frame(width: 28, height: 22)
                }

            } compactTrailing: {

                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    timerText(for: context.state, now: timeline.date)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(statusColor(for: context.state, now: timeline.date))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                        .frame(width: 78, height: 28, alignment: .center)
                }

            } minimal: {

                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    Image(systemName: compactSessionIcon(for: context.state, now: timeline.date))
                        .resizable()
                        .scaledToFit()
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(statusColor(for: context.state, now: timeline.date))
                        .frame(width: 13, height: 13)
                        .frame(width: 20, height: 20)
                }
            }
            .keylineTint(.clear)
            .contentMargins(.horizontal, 1, for: .compactLeading)
            .contentMargins(.horizontal, 1, for: .compactTrailing)
        }
    }

    // MARK: BUTTON

    @ViewBuilder
    private func islandButton<I: AppIntent>(
        icon: String,
        foreground: Color = .white,
        intent: I,
        isPrimary: Bool = false
    ) -> some View {

        let size: CGFloat = isPrimary ? 50 : 46

        Button(intent: intent) {

            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(
                    .system(
                        size: isPrimary ? 25 : 22,
                        weight: .black
                    )
                )
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: HELPERS

    private func statusColor(for state: WorkoutAttributes.ContentState, now: Date = Date()) -> Color {
        isRestState(state, now: now) ? restColor : activeColor
    }

    private func sessionIcon(for state: WorkoutAttributes.ContentState, now: Date = Date()) -> String {
        isRestState(state, now: now) ? "figure.flexibility" : "figure.strengthtraining.traditional"
    }

    private func compactSessionIcon(for state: WorkoutAttributes.ContentState, now: Date = Date()) -> String {
        isRestState(state, now: now) ? "figure.flexibility" : "figure.strengthtraining.traditional"
    }

    private func sessionStatus(for state: WorkoutAttributes.ContentState, now: Date = Date()) -> String {
        if isRestState(state, now: now) {
            return "En descanso"
        }

        return state.isPaused ? "Pausado" : "En sesión"
    }

    private func isRestState(_ state: WorkoutAttributes.ContentState, now: Date = Date()) -> Bool {
        let looksLikeRest = state.isResting || state.title.lowercased().hasPrefix("descanso")
        if state.isPaused {
            return looksLikeRest
        }
        return looksLikeRest && Int(now.timeIntervalSince1970) < state.endTime
    }

    @ViewBuilder
    private func timerText(for state: WorkoutAttributes.ContentState, now: Date = Date()) -> some View {

        if state.isPaused {

            Text(formattedDuration(state.pausedRemaining ?? 0))

        } else if !isRestState(state, now: now) {

            Text("En sesión")

        } else {

            Text(
                timerInterval:
                    Date(timeIntervalSince1970: TimeInterval(state.startTime))
                ...
                    Date(timeIntervalSince1970: TimeInterval(state.endTime)),
                countsDown: true
            )
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func progressWidth(
        for state: WorkoutAttributes.ContentState,
        totalWidth: CGFloat,
        now: Date = Date()
    ) -> CGFloat {

        guard isRestState(state, now: now) else {
            return 0
        }

        let total = max(1.0, Double(state.restSeconds > 0 ? state.restSeconds : state.endTime - state.startTime))
        let remaining: Double

        if state.isPaused {
            remaining = Double(
                state.pausedRemaining ??
                    max(0, state.endTime - Int(now.timeIntervalSince1970))
            )
        } else {
            remaining = max(0, Double(state.endTime) - now.timeIntervalSince1970)
        }

        let elapsed = min(total, max(0, total - remaining))
        let pct = min(1.0, elapsed / total)

        return totalWidth * CGFloat(pct)
    }

    private func restScrubber(
        for state: WorkoutAttributes.ContentState,
        now: Date = Date(),
        height: CGFloat,
        thumbSize: CGFloat,
        trackOpacity: Double
    ) -> some View {
        GeometryReader { geo in
            let fillWidth = progressWidth(
                for: state,
                totalWidth: geo.size.width,
                now: now
            )
            let maxThumbX = max(0, geo.size.width - thumbSize)
            let thumbX = min(max(0, fillWidth - (thumbSize / 2)), maxThumbX)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(trackOpacity))
                    .frame(height: height)

                Capsule()
                    .fill(statusColor(for: state, now: now))
                    .frame(width: fillWidth, height: height)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                    .offset(x: thumbX)
            }
            .frame(height: max(height, thumbSize), alignment: .center)
        }
    }

    private func parsedTitles(
        from fullTitle: String
    ) -> (main: String, secondary: String) {

        let components = fullTitle.components(separatedBy: "\n")

        return (
            components.first ?? "",
            components.count > 1 ? components[1] : ""
        )
    }

    private func primaryExpandedTitle(
        from titles: (main: String, secondary: String),
        state: WorkoutAttributes.ContentState,
        now: Date = Date()
    ) -> String {
        if !isRestState(state, now: now), state.isResting, !titles.secondary.isEmpty {
            return titles.secondary
                .replacingOccurrences(of: "Sig:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return titles.main
            .replacingOccurrences(of: "En sesión:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func secondaryExpandedTitle(
        from titles: (main: String, secondary: String)
    ) -> String {

        titles.secondary.isEmpty
        ? "Rutina activa"
        : titles.secondary
    }
}

// MARK: LOCK SCREEN

struct LockScreenWorkoutView: View {

    let context: ActivityViewContext<WorkoutAttributes>
    private let activeColor = Color(red: 0.36, green: 0.84, blue: 0.38)
    private let restColor = Color(red: 0.95, green: 0.68, blue: 0.26)
    private let pauseColor = Color.white
    private let stopColor = Color(red: 1.0, green: 0.28, blue: 0.28)

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            let titles = parsedTitles(from: context.state.title)

            VStack(alignment: .leading, spacing: 14) {

                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: sessionIcon(now: now))
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(statusColor(now: now))
                        .frame(width: 42, height: 48)

                    VStack(alignment: .leading, spacing: 6) {

                        Text(statusLabel(now: now).uppercased())
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(statusColor(now: now))
                        .tracking(1.4)

                        Text(primaryTitle(from: titles, now: now))
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        Text(secondaryTitle(from: titles))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer()

                    timerText(now: now)
                        .font(.system(
                            size: isRestState(now: now) ? 28 : 30,
                            weight: .black,
                            design: .rounded
                        ))
                        .monospacedDigit()
                        .foregroundStyle(statusColor(now: now))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .frame(
                            width: isRestState(now: now) ? 86 : 132,
                            alignment: .trailing
                        )
                }

                if isRestState(now: now) {
                    restScrubber(
                        for: context.state,
                        now: now,
                        height: 5,
                        thumbSize: 15,
                        trackOpacity: 0.10
                    )
                    .frame(height: 15)
                }

                HStack(spacing: 16) {

                    lockActionButton(
                        icon: "stop.fill",
                        accessibilityLabel: "Detener",
                        color: stopColor,
                        intent: StopWorkoutIntent()
                    )

                    if context.state.isPaused {
                        lockActionButton(
                            icon: "play.fill",
                            accessibilityLabel: "Reanudar",
                            color: activeColor,
                            intent: ResumeWorkoutIntent(),
                            isPrimary: true
                        )
                    } else {
                        lockActionButton(
                            icon: "pause.fill",
                            accessibilityLabel: "Pausar",
                            color: pauseColor,
                            intent: PauseWorkoutIntent(),
                            isPrimary: true
                        )
                    }

                    lockActionButton(
                        icon: "forward.fill",
                        accessibilityLabel: "Siguiente",
                        color: activeColor,
                        intent: NextStepIntent()
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.black.opacity(0.94))
            )
            .activityBackgroundTint(.black)
        }
    }

    private func statusColor(now: Date = Date()) -> Color {
        isRestState(now: now) ? restColor : activeColor
    }

    private func sessionIcon(now: Date = Date()) -> String {
        isRestState(now: now) ? "figure.flexibility" : "figure.strengthtraining.traditional"
    }

    private func statusLabel(now: Date = Date()) -> String {
        if isRestState(now: now) {
            return "Descanso activo"
        }

        return context.state.isPaused ? "Pausado" : "En sesión"
    }

    private func isRestState(now: Date = Date()) -> Bool {
        let looksLikeRest = context.state.isResting ||
            context.state.title.lowercased().hasPrefix("descanso")
        if context.state.isPaused {
            return looksLikeRest
        }
        return looksLikeRest && Int(now.timeIntervalSince1970) < context.state.endTime
    }

    @ViewBuilder
    private func timerText(now: Date = Date()) -> some View {
        if context.state.isPaused {
            Text(formattedDuration(context.state.pausedRemaining ?? 0))
        } else if !isRestState(now: now) {
            Text("En sesión")
        } else {
            Text(
                timerInterval:
                    Date(timeIntervalSince1970: TimeInterval(context.state.startTime))
                ...
                    Date(timeIntervalSince1970: TimeInterval(context.state.endTime)),
                countsDown: true
            )
        }
    }

    private func lockActionButton<I: AppIntent>(
        icon: String,
        accessibilityLabel: String,
        color: Color,
        intent: I,
        isPrimary: Bool = false
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: isPrimary ? 22 : 20, weight: .black))
            .foregroundStyle(color)
            .frame(width: isPrimary ? 58 : 54, height: isPrimary ? 50 : 46)
            .background(
                Capsule()
                    .fill(color.opacity(isPrimary ? 0.18 : 0.12))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(isPrimary ? 0.34 : 0.22), lineWidth: 1)
            )
            .contentShape(Capsule())
            .accessibilityLabel(Text(accessibilityLabel))
        }
        .buttonStyle(.plain)
    }

    private func progressWidth(
        for state: WorkoutAttributes.ContentState,
        totalWidth: CGFloat,
        now: Date = Date()
    ) -> CGFloat {

        guard isRestState(now: now) else {
            return 0
        }

        let total = max(1.0, Double(state.restSeconds > 0 ? state.restSeconds : state.endTime - state.startTime))
        let remaining: Double

        if state.isPaused {
            remaining = Double(
                state.pausedRemaining ??
                    max(0, state.endTime - Int(now.timeIntervalSince1970))
            )
        } else {
            remaining = max(0, Double(state.endTime) - now.timeIntervalSince1970)
        }

        let elapsed = min(total, max(0, total - remaining))
        let pct = min(1.0, elapsed / total)

        return totalWidth * CGFloat(pct)
    }

    private func restScrubber(
        for state: WorkoutAttributes.ContentState,
        now: Date = Date(),
        height: CGFloat,
        thumbSize: CGFloat,
        trackOpacity: Double
    ) -> some View {
        GeometryReader { geo in
            let fillWidth = progressWidth(
                for: state,
                totalWidth: geo.size.width,
                now: now
            )
            let maxThumbX = max(0, geo.size.width - thumbSize)
            let thumbX = min(max(0, fillWidth - (thumbSize / 2)), maxThumbX)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(trackOpacity))
                    .frame(height: height)

                Capsule()
                    .fill(statusColor(now: now))
                    .frame(width: fillWidth, height: height)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
                    .offset(x: thumbX)
            }
            .frame(height: max(height, thumbSize), alignment: .center)
        }
    }

    private func parsedTitles(from fullTitle: String) -> (main: String, secondary: String) {
        let components = fullTitle.components(separatedBy: "\n")
        return (components.first ?? "", components.count > 1 ? components[1] : "")
    }

    private func primaryTitle(from titles: (main: String, secondary: String), now: Date = Date()) -> String {
        if !isRestState(now: now), context.state.isResting, !titles.secondary.isEmpty {
            return titles.secondary
                .replacingOccurrences(of: "Sig:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return titles.main
            .replacingOccurrences(of: "En sesión:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func secondaryTitle(from titles: (main: String, secondary: String)) -> String {
        titles.secondary.isEmpty ? "Rutina activa" : titles.secondary
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
