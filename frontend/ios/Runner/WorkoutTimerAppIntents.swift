import ActivityKit
import AppIntents
import Foundation
import WidgetKit
import SwiftUI
import ActivityKit

// NOTA: Si este archivo está en el target principal (Runner), tener @main aquí 
// causará conflicto con AppDelegate. Los Widgets de Live Activities deben estar 
// en su propio target en Xcode (Widget Extension) donde sí llevarían el @main.
// Comentamos @main para que compile sin problemas tu app principal.
struct WorkoutTimerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            // ----------------------------------------------------
            // 1. VISTA DE LA PANTALLA DE BLOQUEO (LOCK SCREEN)
            // ----------------------------------------------------
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.isPaused ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        Text(context.state.isPaused ? "Pausado" : "En sesión")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Text(context.state.title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    if #available(iOS 17.0, *) {
                        // Botón Pausar / Reanudar
                        if context.state.isPaused {
                            Button(intent: ResumeWorkoutIntent()) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 42, height: 42)
                            }
                            .tint(.green)
                            .buttonBorderShape(.circle)
                        } else {
                            Button(intent: PauseWorkoutIntent()) {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 42, height: 42)
                            }
                            .tint(.orange)
                            .buttonBorderShape(.circle)
                        }
                        
                        // NUEVO: Botón de Siguiente
                        Button(intent: NextStepIntent()) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 42, height: 42)
                        }
                        .tint(.green)
                        .buttonBorderShape(.circle)
                        
                        // Botón Detener
                        Button(intent: StopWorkoutIntent()) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 42, height: 42)
                        }
                        .tint(.red)
                        .buttonBorderShape(.circle)
                    } else {
                        Text(context.state.isPaused ? "Pausado" : "Activo")
                            .font(.title3)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // ----------------------------------------------------
                // 2. VISTA EXPANDIDA DE LA ISLA DINÁMICA
                // ----------------------------------------------------
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundColor(context.state.isPaused ? .orange : .green)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isPaused ? "Pausado" : "Activo")
                        .font(.caption)
                        .bold()
                        .foregroundColor(context.state.isPaused ? .orange : .green)
                        .padding(.top, 8)
                        .padding(.trailing, 4)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    // Usar VStack para controlar mejor el espaciado y evitar el notch
                    VStack(alignment: .center, spacing: 5) {
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 8)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 22) {
                        if #available(iOS 17.0, *) {
                            // Botón Pausar / Reanudar
                            if context.state.isPaused {
                                Button(intent: ResumeWorkoutIntent()) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 17, weight: .bold))
                                        .frame(width: 42, height: 42)
                                }
                                .tint(.green)
                                .buttonBorderShape(.circle)
                            } else {
                                Button(intent: PauseWorkoutIntent()) {
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 17, weight: .bold))
                                        .frame(width: 42, height: 42)
                                }
                                .tint(.orange)
                                .buttonBorderShape(.circle)
                            }
                            
                            // NUEVO: Botón de Siguiente
                            Button(intent: NextStepIntent()) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .frame(width: 42, height: 42)
                            }
                            .tint(.green)
                            .buttonBorderShape(.circle)

                            Button(intent: StopWorkoutIntent()) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .frame(width: 42, height: 42)
                            }
                            .tint(.red)
                            .buttonBorderShape(.circle)
                        } else {
                            // Fallback para iOS 16: Link interactivo que llama a la app para avanzar
                            Link(destination: URL(string: "workout://next")!) {
                                HStack {
                                    Image(systemName: "forward.fill")
                                    Text("Siguiente")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            }
                        }
                    } // Fin HStack
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                // Vista compacta: Izquierda (ícono)
                Image(systemName: "timer")
                    .foregroundColor(context.state.isPaused ? .orange : .green)
            } compactTrailing: {
                // Vista compacta: Derecha (estado)
                Text(context.state.isPaused ? "Pausa" : "Activo")
                    .font(.caption2)
                    .bold()
                    .foregroundColor(context.state.isPaused ? .orange : .green)
            } minimal: {
                // Vista mínima (cuando hay múltiples Live Activities)
                Image(systemName: "timer")
                    .foregroundColor(.green)
            }
        }
    }
}

private let timerSuiteName = "group.com.josh.healthyt"
private let timerStateKey = "workout_timer_state"
private let pendingActionKey = "workout_timer_pending_action"
private let pendingActionNotificationName = "com.josh.healthyt.workout.pendingAction"

@available(iOS 16.1, *)
struct PauseWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Workout"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard #available(iOS 16.1, *) else {
            return .result()
        }

        let now = Int(Date().timeIntervalSince1970)

        for activity in Activity<WorkoutAttributes>.activities {
            let currentState = activity.contentState
            guard !currentState.isPaused else {
                continue
            }

            let remaining = max(0, currentState.endTime - now)
            let updatedState = WorkoutAttributes.ContentState(
                title: currentState.title,
                startTime: currentState.startTime,
                endTime: currentState.endTime,
                isPaused: true,
                pausedRemaining: remaining
            )

            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            } else {
                await activity.update(using: updatedState)
            }

            saveTimerState(
                title: currentState.title,
                startTime: currentState.startTime,
                endTime: currentState.endTime,
                isPaused: true,
                pausedRemaining: remaining,
                isActive: true
            )
        }

        return .result()
    }
}

@available(iOS 16.1, *)
struct ResumeWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume Workout"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard #available(iOS 16.1, *) else {
            return .result()
        }

        let now = Int(Date().timeIntervalSince1970)

        for activity in Activity<WorkoutAttributes>.activities {
            let currentState = activity.contentState
            guard currentState.isPaused else {
                continue
            }

            let remaining = currentState.pausedRemaining ?? 0
            let newEndTime = now + remaining
            let updatedState = WorkoutAttributes.ContentState(
                title: currentState.title,
                startTime: now,
                endTime: newEndTime,
                isPaused: false,
                pausedRemaining: nil
            )

            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            } else {
                await activity.update(using: updatedState)
            }

            saveTimerState(
                title: currentState.title,
                startTime: now,
                endTime: newEndTime,
                isPaused: false,
                pausedRemaining: nil,
                isActive: true
            )
        }

        return .result()
    }
}

@available(iOS 16.1, *)
struct NextStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Siguiente"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard #available(iOS 16.1, *) else {
            return .result()
        }
        savePendingAction("nextStep")
        return .result()
    }
}

@available(iOS 16.1, *)
struct StopWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Detener Rutina"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard #available(iOS 16.1, *) else {
            return .result()
        }

        savePendingAction("stopWorkout")
        clearTimerState()

        for activity in Activity<WorkoutAttributes>.activities {
            if #available(iOS 16.2, *) {
                await activity.end(nil as ActivityContent<WorkoutAttributes.ContentState>?, dismissalPolicy: .immediate)
            } else {
                await activity.end(using: nil as WorkoutAttributes.ContentState?, dismissalPolicy: .immediate)
            }
        }

        return .result()
    }
}

private func saveTimerState(
    title: String,
    startTime: Int,
    endTime: Int,
    isPaused: Bool,
    pausedRemaining: Int?,
    isActive: Bool
) {
    guard let defaults = UserDefaults(suiteName: timerSuiteName) else {
        return
    }

    var payload: [String: Any] = [
        "title": title,
        "startTime": startTime,
        "endTime": endTime,
        "isPaused": isPaused,
        "isActive": isActive,
    ]

    if let pausedRemaining {
        payload["pausedRemaining"] = pausedRemaining
    }

    defaults.set(payload, forKey: timerStateKey)
    defaults.synchronize()
}

private func clearTimerState() {
    guard let defaults = UserDefaults(suiteName: timerSuiteName) else {
        return
    }
    defaults.removeObject(forKey: timerStateKey)
    defaults.synchronize()
}

private func savePendingAction(_ action: String) {
    guard let defaults = UserDefaults(suiteName: timerSuiteName) else {
        return
    }

    defaults.set(action, forKey: pendingActionKey)
    defaults.synchronize()

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(pendingActionNotificationName as CFString),
        nil,
        nil,
        true
    )
}
