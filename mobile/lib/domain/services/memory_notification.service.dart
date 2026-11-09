import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/memory.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/memory.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

/// Once a day (after 09:00) shows a Google-Photos-style "N years ago on <date>" notification
/// with a big picture. Called from the background worker; never throws.
Future<void> showDailyMemoryNotification(ProviderContainer ref) async {
  final log = Logger('MemoryNotification');
  try {
    final user = ref.read(currentUserProvider);
    final now = DateTime.now();
    if (user == null || !user.memoryEnabled || now.hour < 9) return;

    final dir = await getApplicationSupportDirectory();
    final flag = File('${dir.path}/last_memory_notification.txt');
    final today = DateFormat('yyyy-MM-dd').format(now);
    if (flag.existsSync() && flag.readAsStringSync() == today) return;

    final memories = await MemoryService(ref.read(driftProvider).memoryRepository).getMemoryLane(user.id);
    final usable = memories.where((m) => m.type == MemoryTypeEnum.onThisDay && m.assets.isNotEmpty).toList()
      ..sort((a, b) => a.data.year.compareTo(b.data.year));
    if (usable.isEmpty) return;

    final memory = usable.first;
    final years = now.year - memory.data.year;
    final asset = memory.assets.first;
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (years < 1 || endpoint == null) return;

    final res = await NetworkRepository.client.get(Uri.parse('$endpoint/assets/${asset.id}/thumbnail?size=preview'));
    if (res.statusCode != 200) return;
    final img = File('${dir.path}/memory_notification.jpg')..writeAsBytesSync(res.bodyBytes);

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@drawable/notification_icon')));
    await plugin.show(
      7001,
      years == 1 ? '1 year ago' : '$years years ago',
      'On ${DateFormat('d MMMM').format(now)}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'memories',
          'Memories',
          channelDescription: 'Daily "on this day" memories',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          largeIcon: FilePathAndroidBitmap(img.path),
          styleInformation: BigPictureStyleInformation(FilePathAndroidBitmap(img.path), hideExpandedLargeIcon: true),
        ),
      ),
    );
    flag.writeAsStringSync(today);
  } catch (e, s) {
    log.warning('Daily memory notification failed', e, s);
  }
}
