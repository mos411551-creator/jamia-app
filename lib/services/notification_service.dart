import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    } catch (_) {}

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> scheduleCircleReminder({
    required int notificationId,
    required String circleName,
    required String receiverName,
    required DateTime dueDate,
  }) async {
    final reminderDate = dueDate.subtract(const Duration(days: 2));
    final scheduledDate = DateTime(
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
      10,
      0,
    );

    if (scheduledDate.isBefore(DateTime.now())) return;

    final tz.TZDateTime tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'jamia_channel',
      'تنبيهات الجمعيات',
      channelDescription: 'قناة إرسال تذكيرات مواعيد استحقاق الجمعيات',
      importance: Importance.max,
      priority: Priority.high,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId,
      'تذكير باقتراب موعد الجمعية ⏳',
      'باقي يومان على تحصيل قسط جمعية "$circleName" - المستحق: $receiverName',
      tzScheduledDate,
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
