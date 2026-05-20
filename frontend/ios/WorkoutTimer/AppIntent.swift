//
//  AppIntent.swift
//  WorkoutTimer
//
//  Created by Josh on 02/05/26.
//

import WidgetKit
import AppIntents
import ActivityKit
import Foundation

private let timerSuiteName = "group.com.josh.healthyt"
private let timerStateKey = "workout_timer_state"
private let pendingActionKey = "workout_timer_pending_action"
private let pendingActionNotificationName = "com.josh.healthyt.workout.pendingAction"

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}

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
                pausedRemaining: remaining,
                currentExerciseIndex: currentState.currentExerciseIndex,
                currentSet: currentState.currentSet,
                totalSets: currentState.totalSets,
                totalExercises: currentState.totalExercises,
                restSeconds: currentState.restSeconds,
                isResting: currentState.isResting
            )

            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            } else {
                await activity.update(using: updatedState)
            }

            saveTimerState(updatedState, isActive: true)
            savePendingAction("pauseTimer")
        }

        return .result()
    }
}

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
                pausedRemaining: nil,
                currentExerciseIndex: currentState.currentExerciseIndex,
                currentSet: currentState.currentSet,
                totalSets: currentState.totalSets,
                totalExercises: currentState.totalExercises,
                restSeconds: currentState.restSeconds,
                isResting: currentState.isResting
            )

            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            } else {
                await activity.update(using: updatedState)
            }

            saveTimerState(updatedState, isActive: true)
            savePendingAction("resumeTimer")
        }

        return .result()
    }
}

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

struct NextStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Continuar"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard #available(iOS 16.1, *) else {
            return .result()
        }

        let now = Int(Date().timeIntervalSince1970)

        for activity in Activity<WorkoutAttributes>.activities {
            let currentState = activity.contentState
            let updatedState: WorkoutAttributes.ContentState

            if currentState.isResting {
                guard let nextStep = advancedWorkoutStep(from: currentState) else {
                    savePendingAction("nextStep")
                    await end(activity)
                    clearTimerState()
                    continue
                }

                updatedState = WorkoutAttributes.ContentState(
                    title: activeTitle(from: currentState.title, fallback: nextStep.title),
                    startTime: now,
                    endTime: now,
                    isPaused: false,
                    pausedRemaining: nil,
                    currentExerciseIndex: nextStep.exerciseIndex,
                    currentSet: nextStep.set,
                    totalSets: currentState.totalSets,
                    totalExercises: currentState.totalExercises,
                    restSeconds: currentState.restSeconds,
                    isResting: false
                )
            } else if currentState.restSeconds > 0 {
                updatedState = WorkoutAttributes.ContentState(
                    title: restTitle(from: currentState.title),
                    startTime: now,
                    endTime: now + currentState.restSeconds,
                    isPaused: false,
                    pausedRemaining: nil,
                    currentExerciseIndex: currentState.currentExerciseIndex,
                    currentSet: currentState.currentSet,
                    totalSets: currentState.totalSets,
                    totalExercises: currentState.totalExercises,
                    restSeconds: currentState.restSeconds,
                    isResting: true
                )
            } else {
                guard let nextStep = advancedWorkoutStep(from: currentState) else {
                    savePendingAction("nextStep")
                    await end(activity)
                    clearTimerState()
                    continue
                }

                updatedState = WorkoutAttributes.ContentState(
                    title: activeTitle(from: currentState.title, fallback: nextStep.title),
                    startTime: now,
                    endTime: now,
                    isPaused: false,
                    pausedRemaining: nil,
                    currentExerciseIndex: nextStep.exerciseIndex,
                    currentSet: nextStep.set,
                    totalSets: currentState.totalSets,
                    totalExercises: currentState.totalExercises,
                    restSeconds: currentState.restSeconds,
                    isResting: false
                )
            }

            await update(activity, with: updatedState)

            saveTimerState(updatedState, isActive: true)
        }

        savePendingAction("nextStep")
        return .result()
    }
}

private func restTitle(from title: String) -> String {
    "Descanso\n\(nextLine(from: title) ?? "Sig: siguiente serie")"
}

private func activeTitle(from title: String, fallback: String) -> String {
    let nextLine = nextLine(from: title) ?? fallback
    let activeStep = nextLine
        .replacingOccurrences(of: "Sig:", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return "En sesión: \(activeStep.isEmpty ? fallback : activeStep)\nSig: siguiente serie"
}

private func nextLine(from title: String) -> String? {
    let parts = title.components(separatedBy: "\n")
    guard parts.count > 1 else {
        return nil
    }
    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
}

private func advancedWorkoutStep(
    from state: WorkoutAttributes.ContentState
) -> (exerciseIndex: Int, set: Int, title: String)? {
    if state.currentSet < state.totalSets {
        let nextSet = state.currentSet + 1
        return (state.currentExerciseIndex, nextSet, "Serie \(nextSet)/\(state.totalSets)")
    }

    let nextExerciseIndex = state.currentExerciseIndex + 1
    guard nextExerciseIndex < state.totalExercises else {
        return nil
    }

    return (nextExerciseIndex, 1, "Ejercicio \(nextExerciseIndex + 1)/\(state.totalExercises)")
}

private func update(
    _ activity: Activity<WorkoutAttributes>,
    with state: WorkoutAttributes.ContentState
) async {
    if #available(iOS 16.2, *) {
        await activity.update(ActivityContent(state: state, staleDate: nil))
    } else {
        await activity.update(using: state)
    }
}

private func end(_ activity: Activity<WorkoutAttributes>) async {
    if #available(iOS 16.2, *) {
        await activity.end(nil as ActivityContent<WorkoutAttributes.ContentState>?, dismissalPolicy: .immediate)
    } else {
        await activity.end(using: nil as WorkoutAttributes.ContentState?, dismissalPolicy: .immediate)
    }
}

private func saveTimerState(
    _ state: WorkoutAttributes.ContentState,
    isActive: Bool
) {
    guard let defaults = UserDefaults(suiteName: timerSuiteName) else {
        return
    }

    var payload: [String: Any] = [
        "title": state.title,
        "startTime": state.startTime,
        "endTime": state.endTime,
        "isPaused": state.isPaused,
        "isActive": isActive,
        "currentExerciseIndex": state.currentExerciseIndex,
        "currentSet": state.currentSet,
        "totalSets": state.totalSets,
        "totalExercises": state.totalExercises,
        "restSeconds": state.restSeconds,
        "isResting": state.isResting,
    ]

    if let pausedRemaining = state.pausedRemaining {
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
