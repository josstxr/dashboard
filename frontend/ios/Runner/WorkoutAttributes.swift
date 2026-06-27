import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var startTime: Int
        var endTime: Int
        var isPaused: Bool
        var pausedRemaining: Int?
        var currentExerciseIndex: Int = 0
        var currentSet: Int = 1
        var totalSets: Int = 1
        var totalExercises: Int = 1
        var restSeconds: Int = 0
        var isResting: Bool = false
    }
}
