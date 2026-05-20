import Flutter
import UIKit
#if canImport(WearEngine)
import WearEngine // Asegúrate de haber instalado el SDK vía CocoaPods o Framework
#endif

#if canImport(ActivityKit)
import ActivityKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Propiedades existentes
  private let timerSuiteName = "group.com.josh.healthyt"
  private let timerStateKey = "workout_timer_state"
  private let pendingActionKey = "workout_timer_pending_action"
  private let pendingActionNotificationName = "com.josh.healthyt.workout.pendingAction"
  private let liveActivityPushTokenKey = "workout_live_activity_push_token"
  private let liveActivityIdKey = "workout_live_activity_id"
#if canImport(ActivityKit)
  private var restAutoAdvanceWorkItems: [String: DispatchWorkItem] = [:]
#endif
  
  // --- NUEVAS PROPIEDADES PARA EL RELOJ ---
  private var wearableChannel: FlutterMethodChannel?
  private var workoutChannel: FlutterMethodChannel?
#if canImport(WearEngine)
  private var p2pClient: P2PClient?
#endif
  private let watchBundleName = "com.aureadesign.workout" // El que pusiste en DevEco
  // ----------------------------------------

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 1. Registramos los plugins al iniciar la app
    GeneratedPluginRegistrant.register(with: self)
    
    // Registrar canales de Flutter (Corrige error crítico de comunicación con Live Activities)
    // Se utiliza registrar(forPlugin:) para evitar el warning de deprecación (flutter-launch-rootvc)
    if let pluginRegistrar = self.registrar(forPlugin: "HealtyTChannels") {
        registerChannels(binaryMessenger: pluginRegistrar.messenger())
    }

    // 2. Inicializamos WearEngine
    setupWearEngine()
    
    // 3. Escuchar la notificación de la Isla Dinámica para saltar el descanso
    NotificationCenter.default.addObserver(self, selector: #selector(handleSkipNotification), name: NSNotification.Name("SkipRestNotification"), object: nil)
    
    // 4. Escuchar la notificación del botón Siguiente
    NotificationCenter.default.addObserver(self, selector: #selector(handleNextStepNotification), name: NSNotification.Name("NextStepNotification"), object: nil)

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        Unmanaged.passUnretained(self).toOpaque(),
        AppDelegate.pendingWorkoutActionCallback,
        pendingActionNotificationName as CFString,
        nil,
        .deliverImmediately
    )
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static let pendingWorkoutActionCallback: CFNotificationCallback = { _, observer, _, _, _ in
      guard let observer else {
          return
      }

      let appDelegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
      appDelegate.dispatchPendingWorkoutAction()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
      super.applicationDidBecomeActive(application)
      dispatchPendingWorkoutAction()
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
      if handleWorkoutAction(url: url) {
          return true
      }
      return super.application(app, open: url, options: options)
  }

  func registerChannels(binaryMessenger: FlutterBinaryMessenger) {
      registerWorkoutChannel(binaryMessenger: binaryMessenger)
      registerWearableChannel(binaryMessenger: binaryMessenger)
  }

  private func registerWorkoutChannel(binaryMessenger: FlutterBinaryMessenger) {
    workoutChannel = FlutterMethodChannel(name: "com.josh.workout/timer", binaryMessenger: binaryMessenger)
    workoutChannel?.setMethodCallHandler({ [weak self] (call, result) in
        self?.handleWorkoutTimer(call: call, result: result)
    })
  }

  private func registerWearableChannel(binaryMessenger: FlutterBinaryMessenger) {
    wearableChannel = FlutterMethodChannel(
        name: "com.aureadesign/wearable",
        binaryMessenger: binaryMessenger
    )

    wearableChannel?.setMethodCallHandler({ [weak self] (call, result) in
        if call.method == "sendToWatch" {
            self?.sendToWatch(call: call, result: result)
        } else {
            result(FlutterMethodNotImplemented)
        }
    })
  }

  // --- MÉTODOS DE INTEGRACIÓN HUAWEI ---

  private func setupWearEngine() {
#if canImport(WearEngine)
      // Inicializamos el cliente P2P
      self.p2pClient = WearEngine.shared.getLinkClient().getP2PClient()
      
      // Escuchamos mensajes que vienen del reloj (Stop, Next)
      p2pClient?.registerReceiver(forBundle: watchBundleName) { [weak self] (message) in
          guard let data = message.data else { return }
          let messageString = String(data: data, encoding: .utf8) ?? ""
          
          DispatchQueue.main.async {
              // Reenviamos el comando a Flutter
              self?.wearableChannel?.invokeMethod("onWatchAction", arguments: ["payload": messageString])
              
              // Opcional: Si el reloj manda "stop", puedes detener la Live Activity desde aquí mismo
              if messageString.contains("stop") {
                  Task { await self?.performStopLiveActivity() }
              }
          }
      }
#else
      print("WearEngine SDK no encontrado. Integración con Huawei Watch desactivada.")
#endif
  }

  private func sendToWatch(call: FlutterMethodCall, result: @escaping FlutterResult) {
      guard let args = call.arguments as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Se esperaba un JSON string", details: nil))
          return
      }
      
#if canImport(WearEngine)
      let message = Message()
      message.data = args.data(using: .utf8)
      
      // Enviamos el mensaje al Watch Fit 4
      p2pClient?.send(message, toBundle: watchBundleName) { (error) in
          DispatchQueue.main.async {
              if let error = error {
                  result(FlutterError(code: "SEND_ERR", message: error.localizedDescription, details: nil))
              } else {
                  result(true)
              }
          }
      }
#else
      result(FlutterError(code: "UNAVAILABLE", message: "WearEngine SDK no está instalado en iOS.", details: nil))
#endif
  }

  // --- MÉTODOS DE LIVE ACTIVITIES Y DEEP LINKS ---
  
  @objc private func handleSkipNotification() {
      DispatchQueue.main.async {
          // Le enviamos la instrucción "skipRest" al archivo de Flutter
          self.workoutChannel?.invokeMethod("skipRest", arguments: nil)
      }
  }

  @objc private func handleNextStepNotification() {
      DispatchQueue.main.async {
          // Instrucción inteligente de "siguiente" a Flutter
          self.workoutChannel?.invokeMethod("nextStep", arguments: nil)
      }
  }

  func handleWorkoutAction(url: URL) -> Bool {
      let action = url.host ?? url.absoluteString
      if action.contains("next") {
          handleNextStepNotification()
          return true
      }
      if action.contains("stop") {
          workoutChannel?.invokeMethod("stopWorkout", arguments: nil)
          Task { await performStopLiveActivity() }
          return true
      }
      if action.contains("skip") {
          handleSkipNotification()
          return true
      }
      if action.contains("pause") {
          workoutChannel?.invokeMethod("pauseTimer", arguments: nil)
          return true
      }
      if action.contains("resume") || action.contains("play") {
          workoutChannel?.invokeMethod("resumeTimer", arguments: nil)
          return true
      }
      return false
  }

  private func consumePendingWorkoutAction() -> String? {
      guard let defaults = UserDefaults(suiteName: timerSuiteName),
            let action = defaults.string(forKey: pendingActionKey) else {
          return nil
      }

      defaults.removeObject(forKey: pendingActionKey)
      defaults.synchronize()
      return action
  }

  private func savePendingWorkoutAction(_ action: String) {
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

  fileprivate func dispatchPendingWorkoutAction() {
      guard workoutChannel != nil else {
          return
      }

      guard let action = consumePendingWorkoutAction() else {
          return
      }

      DispatchQueue.main.async {
          self.workoutChannel?.invokeMethod(action, arguments: nil)
      }
  }

  private func handleWorkoutTimer(call: FlutterMethodCall, result: @escaping FlutterResult) {
      if #available(iOS 16.1, *) {
          switch call.method {
          case "startTimer":
              guard let args = call.arguments as? [String: Any],
                    let title = args["title"] as? String,
                    let startTime = args["startTime"] as? Int,
                    let endTime = args["endTime"] as? Int else {
                  result(FlutterError(code: "INVALID_ARGS", message: "Faltan argumentos", details: nil))
                  return
              }
              
              let attributes = WorkoutAttributes()
              let isPaused = (args["isPaused"] as? Bool) ?? false
              let state = WorkoutAttributes.ContentState(
                  title: title,
                  startTime: startTime,
                  endTime: endTime,
                  isPaused: isPaused,
                  pausedRemaining: isPaused ? (args["pausedRemaining"] as? Int) : nil,
                  currentExerciseIndex: args["currentExerciseIndex"] as? Int ?? 0,
                  currentSet: args["currentSet"] as? Int ?? 1,
                  totalSets: args["totalSets"] as? Int ?? 1,
                  totalExercises: args["totalExercises"] as? Int ?? 1,
                  restSeconds: args["restSeconds"] as? Int ?? 0,
                  isResting: args["isResting"] as? Bool ?? false
              )
              
              do {
                  if ActivityAuthorizationInfo().areActivitiesEnabled {
                      let activity: Activity<WorkoutAttributes>
                      if #available(iOS 16.2, *) {
                          let content = liveActivityContent(for: state)
                          activity = try Activity<WorkoutAttributes>.request(
                              attributes: attributes,
                              content: content,
                              pushType: nil
                          )
                      } else {
                          activity = try Activity<WorkoutAttributes>.request(
                              attributes: attributes,
                              contentState: state,
                              pushType: nil
                          )
                      }
                      saveLiveActivityIdentity(activityId: activity.id, pushToken: nil)
                      scheduleRestAutoAdvanceIfNeeded(for: activity)
                      result([
                          "ok": true,
                          "activityId": activity.id
                      ])
                  } else {
                      result(FlutterError(code: "UNAUTHORIZED", message: "Actividades no permitidas", details: nil))
                  }
              } catch {
                  result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
              }
              
          case "stopTimer":
              Task { @MainActor in
                  cancelRestAutoAdvance()
                  for activity in Activity<WorkoutAttributes>.activities {
                      if #available(iOS 16.2, *) {
                          await activity.end(nil as ActivityContent<WorkoutAttributes.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
                      } else {
                          await activity.end(using: nil as WorkoutAttributes.ContentState?, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
                      }
                  }
                  clearLiveActivityIdentity()
                  result(true)
              }
              
          case "pauseTimer":
              Task { @MainActor in
                  for activity in Activity<WorkoutAttributes>.activities {
                      cancelRestAutoAdvance(for: activity.id)
                      let currentEndTime = activity.contentState.endTime
                      let currentStartTime = activity.contentState.startTime
                      let now = Int(Date().timeIntervalSince1970)
                      let remaining = max(0, currentEndTime - now)
                      
                      let newState = WorkoutAttributes.ContentState(
                          title: activity.contentState.title,
                          startTime: currentStartTime,
                          endTime: currentEndTime,
                          isPaused: true,
                          pausedRemaining: remaining,
                          currentExerciseIndex: activity.contentState.currentExerciseIndex,
                          currentSet: activity.contentState.currentSet,
                          totalSets: activity.contentState.totalSets,
                          totalExercises: activity.contentState.totalExercises,
                          restSeconds: activity.contentState.restSeconds,
                          isResting: activity.contentState.isResting
                      )
                      if #available(iOS 16.2, *) {
                          await activity.update(liveActivityContent(for: newState))
                      } else {
                          await activity.update(using: newState)
                      }
                  }
                  result(true)
              }
              
          case "resumeTimer":
              Task { @MainActor in
                  for activity in Activity<WorkoutAttributes>.activities {
                      if activity.contentState.isPaused {
                          let remaining = activity.contentState.pausedRemaining ?? 0
                          let now = Int(Date().timeIntervalSince1970)
                          let newEndTime = now + remaining
                          
                          let newState = WorkoutAttributes.ContentState(
                              title: activity.contentState.title,
                              startTime: now,
                              endTime: newEndTime,
                              isPaused: false,
                              pausedRemaining: nil,
                              currentExerciseIndex: activity.contentState.currentExerciseIndex,
                              currentSet: activity.contentState.currentSet,
                              totalSets: activity.contentState.totalSets,
                              totalExercises: activity.contentState.totalExercises,
                              restSeconds: activity.contentState.restSeconds,
                              isResting: activity.contentState.isResting
                          )
                          if #available(iOS 16.2, *) {
                              await activity.update(liveActivityContent(for: newState))
                          } else {
                              await activity.update(using: newState)
                          }
                          scheduleRestAutoAdvanceIfNeeded(for: activity)
                      }
                  }
                  result(true)
              }

          case "updateTimer":
              guard let args = call.arguments as? [String: Any] else {
                  result(FlutterError(code: "INVALID_ARGS", message: "Faltan argumentos", details: nil))
                  return
              }

              Task { @MainActor in
                  let now = Int(Date().timeIntervalSince1970)

                  for activity in Activity<WorkoutAttributes>.activities {
                      let currentState = activity.contentState
                      let title = args["title"] as? String ?? currentState.title
                      let startTime = (args["startTime"] as? Int) ?? currentState.startTime
                      let endTime = (args["endTime"] as? Int) ?? currentState.endTime
                      let isPaused = (args["isPaused"] as? Bool) ?? currentState.isPaused
                      let currentExerciseIndex = (args["currentExerciseIndex"] as? Int) ?? currentState.currentExerciseIndex
                      let currentSet = (args["currentSet"] as? Int) ?? currentState.currentSet
                      let totalSets = (args["totalSets"] as? Int) ?? currentState.totalSets
                      let totalExercises = (args["totalExercises"] as? Int) ?? currentState.totalExercises
                      let restSeconds = (args["restSeconds"] as? Int) ?? currentState.restSeconds
                      let isResting = (args["isResting"] as? Bool) ?? currentState.isResting
                      let remaining = max(0, endTime - now)
                      let pausedRemaining = isPaused
                          ? ((args["pausedRemaining"] as? Int) ?? currentState.pausedRemaining ?? remaining)
                          : nil

                      let newState = WorkoutAttributes.ContentState(
                          title: title,
                          startTime: startTime,
                          endTime: endTime,
                          isPaused: isPaused,
                          pausedRemaining: pausedRemaining,
                          currentExerciseIndex: currentExerciseIndex,
                          currentSet: currentSet,
                          totalSets: totalSets,
                          totalExercises: totalExercises,
                          restSeconds: restSeconds,
                          isResting: isResting
                      )

                      if #available(iOS 16.2, *) {
                          await activity.update(liveActivityContent(for: newState))
                      } else {
                          await activity.update(using: newState)
                      }
                      scheduleRestAutoAdvanceIfNeeded(for: activity)
                  }

                  result(true)
              }
              
          case "getTimerState":
              Task { @MainActor in
                  guard let activity = Activity<WorkoutAttributes>.activities.first else {
                      result(["isActive": false])
                      return
                  }

                  let resolvedState = await autoAdvanceRestIfNeeded(for: activity)
                  guard let state = resolvedState else {
                      result(["isActive": false])
                      return
                  }

                  result(liveActivityStateResult(activity: activity, state: state))
              }

          case "consumePendingAction":
              result(consumePendingWorkoutAction())

          case "getLiveActivityPushToken":
              result([
                  "activityId": liveActivityIdResultValue(),
                  "pushToken": liveActivityPushTokenResultValue()
              ])
              
          default:
              result(FlutterMethodNotImplemented)
          }
      } else {
          result(FlutterError(code: "UNAVAILABLE", message: "Requiere iOS 16.1+", details: nil))
      }
  }

#if canImport(ActivityKit)
  @available(iOS 16.1, *)
  private func scheduleRestAutoAdvanceIfNeeded(for activity: Activity<WorkoutAttributes>) {
      cancelRestAutoAdvance(for: activity.id)

      let state = activity.contentState
      guard state.isResting, !state.isPaused else {
          return
      }

      let now = Int(Date().timeIntervalSince1970)
      let delay = max(0, state.endTime - now)
      let workItem = DispatchWorkItem { [weak self] in
          guard let self else {
              return
          }

          Task { @MainActor in
              await self.autoAdvanceRestIfNeeded(for: activity)
          }
      }

      restAutoAdvanceWorkItems[activity.id] = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: workItem)
  }

  @available(iOS 16.1, *)
  private func cancelRestAutoAdvance(for activityId: String? = nil) {
      if let activityId {
          restAutoAdvanceWorkItems.removeValue(forKey: activityId)?.cancel()
          return
      }

      for workItem in restAutoAdvanceWorkItems.values {
          workItem.cancel()
      }
      restAutoAdvanceWorkItems.removeAll()
  }

  @available(iOS 16.1, *)
  @MainActor
  @discardableResult
  private func autoAdvanceRestIfNeeded(
      for activity: Activity<WorkoutAttributes>
  ) async -> WorkoutAttributes.ContentState? {
      restAutoAdvanceWorkItems.removeValue(forKey: activity.id)?.cancel()

      let state = activity.contentState
      guard state.isResting, !state.isPaused else {
          return state
      }

      let now = Int(Date().timeIntervalSince1970)
      guard state.endTime <= now else {
          scheduleRestAutoAdvanceIfNeeded(for: activity)
          return state
      }

      guard let nextState = activeStateAfterRest(from: state, now: now) else {
          savePendingWorkoutAction("skipRest")
          await endLiveActivity(activity)
          if readLiveActivityId() == activity.id {
              clearLiveActivityIdentity()
          }
          return nil
      }

      await updateLiveActivity(activity, with: nextState)
      savePendingWorkoutAction("restFinished")
      return nextState
  }

  @available(iOS 16.1, *)
  private func activeStateAfterRest(
      from state: WorkoutAttributes.ContentState,
      now: Int
  ) -> WorkoutAttributes.ContentState? {
      guard let nextStep = advancedWorkoutStep(from: state) else {
          return nil
      }

      let parsedSet = setProgress(from: nextLine(from: state.title) ?? state.title)
      let totalSets = parsedSet?.totalSets ?? state.totalSets

      return WorkoutAttributes.ContentState(
          title: activeTitle(from: state.title, fallback: nextStep.title),
          startTime: now,
          endTime: now,
          isPaused: false,
          pausedRemaining: nil,
          currentExerciseIndex: nextStep.exerciseIndex,
          currentSet: parsedSet?.set ?? nextStep.set,
          totalSets: totalSets,
          totalExercises: state.totalExercises,
          restSeconds: state.restSeconds,
          isResting: false
      )
  }

  @available(iOS 16.1, *)
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

  private func setProgress(from title: String) -> (set: Int, totalSets: Int)? {
      guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*/\s*(\d+)"#) else {
          return nil
      }

      let range = NSRange(title.startIndex..<title.endIndex, in: title)
      guard let match = regex.firstMatch(in: title, range: range),
            match.numberOfRanges >= 3,
            let setRange = Range(match.range(at: 1), in: title),
            let totalRange = Range(match.range(at: 2), in: title),
            let set = Int(String(title[setRange])),
            let totalSets = Int(String(title[totalRange])) else {
          return nil
      }

      return (set, totalSets)
  }

  @available(iOS 16.1, *)
  private func updateLiveActivity(
      _ activity: Activity<WorkoutAttributes>,
      with state: WorkoutAttributes.ContentState
  ) async {
      if #available(iOS 16.2, *) {
          await activity.update(liveActivityContent(for: state))
      } else {
          await activity.update(using: state)
      }
  }

  @available(iOS 16.1, *)
  private func endLiveActivity(_ activity: Activity<WorkoutAttributes>) async {
      if #available(iOS 16.2, *) {
          await activity.end(nil as ActivityContent<WorkoutAttributes.ContentState>?, dismissalPolicy: .immediate)
      } else {
          await activity.end(using: nil as WorkoutAttributes.ContentState?, dismissalPolicy: .immediate)
      }
  }

  @available(iOS 16.2, *)
  private func liveActivityContent(
      for state: WorkoutAttributes.ContentState
  ) -> ActivityContent<WorkoutAttributes.ContentState> {
      ActivityContent(state: state, staleDate: staleDate(for: state))
  }

  private func staleDate(for state: WorkoutAttributes.ContentState) -> Date? {
      guard state.isResting, !state.isPaused else {
          return nil
      }

      let now = Int(Date().timeIntervalSince1970)
      guard state.endTime > now else {
          return nil
      }

      return Date(timeIntervalSince1970: TimeInterval(state.endTime))
  }

  @available(iOS 16.1, *)
  private func liveActivityStateResult(
      activity: Activity<WorkoutAttributes>,
      state: WorkoutAttributes.ContentState
  ) -> [String: Any] {
      [
          "isActive": true,
          "isPaused": state.isPaused,
          "endTime": state.endTime,
          "pausedRemaining": state.pausedRemaining ?? 0,
          "currentExerciseIndex": state.currentExerciseIndex,
          "currentSet": state.currentSet,
          "totalSets": state.totalSets,
          "totalExercises": state.totalExercises,
          "restSeconds": state.restSeconds,
          "isResting": state.isResting,
          "activityId": activity.id,
          "pushToken": liveActivityPushTokenResultValue()
      ]
  }
#endif
  
  func performStopLiveActivity() async {
#if canImport(ActivityKit)
      if #available(iOS 16.1, *) {
          await MainActor.run {
              cancelRestAutoAdvance()
          }
          for activity in Activity<WorkoutAttributes>.activities {
              if #available(iOS 16.2, *) {
                  await activity.end(nil as ActivityContent<WorkoutAttributes.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
              } else {
                  await activity.end(using: nil as WorkoutAttributes.ContentState?, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
              }
          }
          clearLiveActivityIdentity()
      }
#endif
  }

  private func observePushTokenUpdates(for activity: Activity<WorkoutAttributes>) {
      Task {
          for await tokenData in activity.pushTokenUpdates {
              let token = tokenData.map { String(format: "%02x", $0) }.joined()
              saveLiveActivityIdentity(activityId: activity.id, pushToken: token)
          }
      }
  }

  private func saveLiveActivityIdentity(activityId: String, pushToken: String?) {
      guard let defaults = UserDefaults(suiteName: timerSuiteName) else {
          return
      }
      defaults.set(activityId, forKey: liveActivityIdKey)
      if let pushToken {
          defaults.set(pushToken, forKey: liveActivityPushTokenKey)
      }
  }

  private func clearLiveActivityIdentity() {
      guard let defaults = UserDefaults(suiteName: timerSuiteName) else {
          return
      }
      defaults.removeObject(forKey: liveActivityIdKey)
      defaults.removeObject(forKey: liveActivityPushTokenKey)
  }

  private func readLiveActivityId() -> String? {
      UserDefaults(suiteName: timerSuiteName)?.string(forKey: liveActivityIdKey)
  }

  private func readLiveActivityPushToken() -> String? {
      UserDefaults(suiteName: timerSuiteName)?.string(forKey: liveActivityPushTokenKey)
  }

  private func liveActivityIdResultValue() -> Any {
      readLiveActivityId() ?? NSNull()
  }

  private func liveActivityPushTokenResultValue() -> Any {
      readLiveActivityPushToken() ?? NSNull()
  }
}
