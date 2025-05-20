// lib/core/logging/logger_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'logger_service.dart';

// LoggerService provider that takes a class name (tag)
// هذا الـ provider سيعيد دالة تأخذ اسم الكلاس وترجع logger
// بدلًا من ذلك، يمكننا جعل كل كلاس يطلب logger خاص به
// الطريقة الأبسط هي logger عام.
final loggerServiceProvider =
    Provider.family<LoggerService, String>((ref, className) {
  return LoggerService(className);
});

// مثال لكيفية استخدامه في كلاس آخر:
// final logger = ref.watch(loggerServiceProvider('MyClassName'));
// logger.info("SomeTag", "My message");

// أو logger عام بسيط إذا لم ترد تمرير اسم الكلاس في كل مرة
final appLoggerProvider = Provider<LoggerService>((ref) {
  return LoggerService("AppGlobal"); // اسم عام
});
