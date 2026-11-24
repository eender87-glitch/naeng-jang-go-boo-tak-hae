import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/food_item.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const AndroidNotificationDetails _androidDetails = AndroidNotificationDetails(
    'fridge_expiry_d3_channel',
    '식자재 소비기한 D-3 알림',
    channelDescription: '채소 및 식자재 폐기 3일 전(냉동 7일 전) 소비 알림 채널',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
  );

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return true;
    final granted = await androidImpl.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> showImmediateTest(List<FoodItem> items) async {
    await init();
    final urgent = items.where((it) => it.reminderEnabled && calcDDay(it.expiryDate) <= it.reminderOffset).toList();
    final body = urgent.isNotEmpty
        ? '${urgent.take(3).map((e) => '${e.name}(${formatDDayLabel(calcDDay(e.expiryDate))})').join(', ')} 섭취 기한이 임박했어요!'
        : 'D-3 네이티브 알람이 정상 연결되었습니다! 앱을 꺼두어도 정해진 날에 알려드릴게요.';

    await _plugin.show(
      999001,
      '🥬 냉장고를 부탁해 D-3 소비기한 알림',
      body,
      _details,
    );
  }

  Future<void> schedule10SecondBackgroundTest() async {
    await init();
    final target = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));
    await _zonedScheduleSafe(
      id: 999002,
      title: '🔔 냉장고를 부탁해 백그라운드 알람 테스트',
      body: '앱을 꺼두어도 정상적으로 도착하는 네이티브 D-3 알람 테스트입니다!',
      scheduledDate: target,
    );
  }

  Future<void> scheduleForItem(FoodItem item, int notifyHour, int notifyMinute) async {
    await init();
    await _plugin.cancel(item.notificationId);
    if (!item.reminderEnabled) return;

    final expDate = parseDateStr(item.expiryDate);
    final alertDay = expDate.subtract(Duration(days: item.reminderOffset));
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      alertDay.year,
      alertDay.month,
      alertDay.day,
      notifyHour,
      notifyMinute,
    );

    final now = tz.TZDateTime.now(tz.local);
    // 만약 D-3 알림 시각이 이미 지났으나 아직 만료 전이라면, 오늘 희망 시각 또는 내일(만료일 이내)로 예약
    if (!scheduled.isAfter(now)) {
      final expEvening = tz.TZDateTime(
        tz.local,
        expDate.year,
        expDate.month,
        expDate.day,
        notifyHour,
        notifyMinute,
      );
      if (expEvening.isAfter(now)) {
        final todayTarget = tz.TZDateTime(tz.local, now.year, now.month, now.day, notifyHour, notifyMinute);
        scheduled = todayTarget.isAfter(now)
            ? todayTarget
            : tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, notifyHour, notifyMinute);
        if (scheduled.isAfter(expEvening)) {
          scheduled = expEvening;
        }
      } else {
        return; // 이미 만료된 항목은 과거 알람 예약 생략
      }
    }

    final remaining = parseDateStr(item.expiryDate).difference(DateTime(scheduled.year, scheduled.month, scheduled.day)).inDays;
    final dayDesc = remaining <= 0 ? '오늘 만료' : '$remaining일 남음';

    await _zonedScheduleSafe(
      id: item.notificationId,
      title: '${item.emoji} ${item.name} 섭취 기한 임박 ($dayDesc)',
      body: '만료 예정일 ${item.expiryDate}입니다. 버리기 전에 오늘 저녁 메뉴로 활용해 보세요!',
      scheduledDate: scheduled,
    );
  }

  Future<void> rescheduleAll(List<FoodItem> items, int notifyHour, int notifyMinute) async {
    await init();
    await _plugin.cancelAll();
    for (final item in items) {
      if (item.reminderEnabled) {
        await scheduleForItem(item, notifyHour, notifyMinute);
      }
    }
  }

  Future<void> cancelForItem(FoodItem item) async {
    await init();
    await _plugin.cancel(item.notificationId);
  }

  Future<void> _zonedScheduleSafe({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {
      // Android 13+ 정확 알람 권한이 미허용된 경우에도 안전하게 백그라운드 알람 예약
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
