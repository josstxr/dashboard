class WebRestNotificationService {
  Future<void> requestPermission() async {}

  Future<void> scheduleRestFinishedNotification(
    int seconds, {
    String? body,
  }) async {}

  void cancelRestNotification() {}
}
