import 'dart:async';
import 'dart:html' as html;

class WebRestNotificationService {
  Timer? _restTimer;
  html.Notification? _activeNotification;
  StreamSubscription<html.Event>? _visibilitySubscription;
  DateTime? _restEndTime;
  String _restFinishedBody = 'Es hora de continuar con tu rutina. A darle!';

  Future<void> requestPermission() async {
    if (!html.Notification.supported) return;
    if (html.Notification.permission == 'default') {
      await html.Notification.requestPermission();
    }
  }

  Future<void> scheduleRestFinishedNotification(
    int seconds, {
    String? body,
  }) async {
    cancelRestNotification();
    if (seconds <= 0 || !html.Notification.supported) return;

    await requestPermission();
    if (html.Notification.permission != 'granted') return;

    _restFinishedBody = body ?? 'Es hora de continuar con tu rutina. A darle!';
    _restEndTime = DateTime.now().add(Duration(seconds: seconds));
    _visibilitySubscription = html.document.onVisibilityChange.listen((_) {
      _showNotificationIfRestFinished();
    });
    _restTimer = Timer(
      Duration(seconds: seconds),
      _showNotificationIfRestFinished,
    );
  }

  void cancelRestNotification() {
    _restTimer?.cancel();
    _restTimer = null;
    _visibilitySubscription?.cancel();
    _visibilitySubscription = null;
    _restEndTime = null;
    _activeNotification?.close();
    _activeNotification = null;
  }

  void _showNotificationIfRestFinished() {
    final restEndTime = _restEndTime;
    if (restEndTime == null || DateTime.now().isBefore(restEndTime)) return;

    _restTimer?.cancel();
    _restTimer = null;
    _visibilitySubscription?.cancel();
    _visibilitySubscription = null;
    _restEndTime = null;
    _activeNotification = html.Notification(
      'Descanso terminado',
      body: _restFinishedBody,
      icon: '/icons/Icon-192.png',
      tag: 'healthy-t-rest-finished',
    );
  }
}
