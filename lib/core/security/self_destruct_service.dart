// lib/core/security/self_destruct_service.dart
import "dart:io";
import "dart:math";
import "dart:typed_data";

import "package:cloud_firestore/cloud_firestore.dart"
    as firestore; // Import with prefix for clarity
import "package:cloud_firestore/cloud_firestore.dart"
    hide FieldValue; // Hide Sembast's FieldValue
import "package:crypto/crypto.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../presentation/chat/providers/auth_providers.dart";
import "../../presentation/decoy_screen/decoy_screen.dart";
import "../history/history_service.dart";
import "../logging/logger_provider.dart";
import "../logging/logger_service.dart";
import "secure_storage_service.dart";

final selfDestructServiceProvider = Provider<SelfDestructService>((ref) {
  return SelfDestructService(ref);
});

class SelfDestructService {
  final Ref _ref;
  final FirebaseFirestore _firestoreInstance = FirebaseFirestore.instance;
  
  // عدد دورات الكتابة فوق الملفات للتأكد من المسح الآمن
  static const int _secureWipeIterations = 3;
  
  // قائمة بأنماط الكتابة المختلفة للمسح الآمن
  static final List<List<int> Function(int)> _wipePatterns = [
    // نمط الأصفار
    (int size) => List<int>.filled(size, 0),
    // نمط الواحدات
    (int size) => List<int>.filled(size, 255),
    // نمط عشوائي
    (int size) {
      final random = Random.secure();
      return List<int>.generate(size, (_) => random.nextInt(256));
    },
  ];

  SelfDestructService(this._ref);

  /// مسح آمن لقاعدة بيانات Sembast مع التحقق من اكتمال العملية
  Future<bool> _secureWipeSembastDatabase(LoggerService logger) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbPath = "${appDocDir.path}/the_conduit_app.db";
      final dbFile = File(dbPath);

      if (await dbFile.exists()) {
        logger.info("SelfDestructService",
            "Sembast DB found at $dbPath. Initiating secure wipe protocol.");
        
        final fileSize = await dbFile.length();
        if (fileSize == 0) {
          logger.warn("SelfDestructService", 
              "Sembast DB file exists but has zero size. Proceeding with deletion.");
          await dbFile.delete();
          return !await dbFile.exists();
        }
        
        // حساب قيمة التجزئة الأصلية للملف للتحقق لاحقاً
        final originalHash = await _calculateFileHash(dbFile);
        logger.info("SelfDestructService", 
            "Original file hash: $originalHash. Starting secure wipe process.");
        
        // تنفيذ عدة دورات من الكتابة فوق الملف بأنماط مختلفة
        for (int i = 0; i < _secureWipeIterations; i++) {
          final pattern = _wipePatterns[i % _wipePatterns.length];
          final wipeData = pattern(fileSize);
          
          final sink = dbFile.openWrite(mode: FileMode.writeOnly);
          sink.add(wipeData);
          await sink.flush();
          await sink.close();
          
          // التحقق من أن البيانات تم كتابتها بالفعل
          final newHash = await _calculateFileHash(dbFile);
          if (newHash == originalHash) {
            logger.error("SelfDestructService", 
                "Wipe iteration $i failed: File content unchanged. Attempting alternative method.");
            
            // محاولة بديلة باستخدام طريقة مختلفة للكتابة
            await dbFile.writeAsBytes(wipeData, flush: true);
            final retryHash = await _calculateFileHash(dbFile);
            
            if (retryHash == originalHash) {
              logger.error("SelfDestructService", 
                  "Alternative wipe method also failed. File system may be preventing overwrites.");
            } else {
              logger.info("SelfDestructService", 
                  "Alternative wipe method successful for iteration $i.");
            }
          } else {
            logger.info("SelfDestructService", 
                "Wipe iteration $i successful. New hash: $newHash");
          }
          
          // تأخير قصير بين العمليات لتجنب إرهاق النظام
          await Future.delayed(const Duration(milliseconds: 50));
        }
        
        // حذف الملف بعد الكتابة فوقه
        await dbFile.delete();
        
        // التحقق من أن الملف تم حذفه بالفعل
        final fileExists = await dbFile.exists();
        if (fileExists) {
          logger.error("SelfDestructService", 
              "Failed to delete Sembast DB file after secure wipe. File still exists.");
          return false;
        } else {
          logger.info("SelfDestructService", 
              "Sembast DB file successfully wiped and deleted: $dbPath");
          return true;
        }
      } else {
        logger.info("SelfDestructService",
            "Sembast DB file not found at $dbPath. No wipe needed.");
        return true;
      }
    } catch (e, s) {
      logger.error(
          "SelfDestructService", "Error during Sembast DB secure wipe", e, s);
      return false;
    }
  }

  /// حساب قيمة تجزئة SHA-256 للملف
  Future<String> _calculateFileHash(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      return "hash_calculation_failed";
    }
  }

  /// مسح SharedPreferences مع التحقق من اكتمال العملية
  Future<bool> _clearSharedPreferences(LoggerService logger) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // حفظ عدد المفاتيح قبل المسح للتحقق لاحقاً
      final keysBeforeClear = prefs.getKeys();
      final keyCountBeforeClear = keysBeforeClear.length;
      
      if (keyCountBeforeClear == 0) {
        logger.info("SelfDestructService", "SharedPreferences already empty. No clearing needed.");
        return true;
      }
      
      logger.info("SelfDestructService", 
          "Clearing SharedPreferences. Keys before clear: $keyCountBeforeClear");
      
      // مسح البيانات
      final clearResult = await prefs.clear();
      
      if (!clearResult) {
        logger.error("SelfDestructService", 
            "SharedPreferences.clear() returned false. Attempting individual key removal.");
        
        // محاولة حذف كل مفتاح على حدة إذا فشلت عملية المسح الكاملة
        bool allRemoved = true;
        for (final key in keysBeforeClear) {
          final removed = await prefs.remove(key);
          if (!removed) {
            logger.error("SelfDestructService", "Failed to remove key: $key");
            allRemoved = false;
          }
        }
        
        if (!allRemoved) {
          logger.error("SelfDestructService", 
              "Some SharedPreferences keys could not be removed.");
          return false;
        }
      }
      
      // التحقق من أن جميع المفاتيح تم حذفها
      final keysAfterClear = prefs.getKeys();
      final keyCountAfterClear = keysAfterClear.length;
      
      if (keyCountAfterClear > 0) {
        logger.error("SelfDestructService", 
            "SharedPreferences not fully cleared. Keys remaining: $keyCountAfterClear");
        return false;
      }
      
      logger.info("SelfDestructService", "SharedPreferences successfully cleared and verified.");
      return true;
    } catch (e, s) {
      logger.error(
          "SelfDestructService", "Error clearing SharedPreferences", e, s);
      return false;
    }
  }

  /// مسح مجلدات التخزين المؤقت ومجلدات الدعم مع التحقق من اكتمال العملية
  Future<bool> _clearAppCacheAndSupportDirs(LoggerService logger) async {
    bool allSuccess = true;
    
    try {
      // مسح مجلد التخزين المؤقت
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        logger.info("SelfDestructService",
            "Clearing cache directory: ${cacheDir.path}");
        
        // مسح محتويات المجلد أولاً قبل حذف المجلد نفسه
        await _secureWipeDirectory(cacheDir, logger);
        
        // حذف المجلد بشكل متكرر
        await cacheDir.delete(recursive: true);
        
        // التحقق من أن المجلد تم حذفه
        if (await cacheDir.exists()) {
          logger.error("SelfDestructService", 
              "Failed to delete cache directory after wiping: ${cacheDir.path}");
          allSuccess = false;
        } else {
          logger.info("SelfDestructService", 
              "Cache directory successfully wiped and deleted: ${cacheDir.path}");
        }
      }

      // مسح مجلد دعم التطبيق
      final appSupportDir = await getApplicationSupportDirectory();
      if (await appSupportDir.exists()) {
        logger.info("SelfDestructService",
            "Clearing application support directory: ${appSupportDir.path}");
        
        // مسح محتويات المجلد أولاً قبل حذف المجلد نفسه
        await _secureWipeDirectory(appSupportDir, logger);
        
        // حذف المجلد بشكل متكرر
        await appSupportDir.delete(recursive: true);
        
        // التحقق من أن المجلد تم حذفه
        if (await appSupportDir.exists()) {
          logger.error("SelfDestructService", 
              "Failed to delete app support directory after wiping: ${appSupportDir.path}");
          allSuccess = false;
        } else {
          logger.info("SelfDestructService", 
              "App support directory successfully wiped and deleted: ${appSupportDir.path}");
        }
      }
      
      return allSuccess;
    } catch (e, s) {
      logger.error("SelfDestructService",
          "Error clearing app cache/support directories", e, s);
      return false;
    }
  }

  /// مسح آمن لمحتويات مجلد بالكامل
  Future<void> _secureWipeDirectory(Directory directory, LoggerService logger) async {
    try {
      // الحصول على قائمة بجميع الملفات في المجلد وجميع المجلدات الفرعية
      final entities = await directory.list(recursive: true).toList();
      
      // مسح الملفات أولاً
      for (final entity in entities) {
        if (entity is File) {
          try {
            final fileSize = await entity.length();
            if (fileSize > 0) {
              // استخدام نمط عشوائي للكتابة فوق الملف
              final random = Random.secure();
              final wipeData = Uint8List(fileSize);
              for (int i = 0; i < fileSize; i++) {
                wipeData[i] = random.nextInt(256);
              }
              
              await entity.writeAsBytes(wipeData, flush: true);
            }
            await entity.delete();
          } catch (e) {
            logger.warn("SelfDestructService", 
                "Error wiping file ${entity.path}: $e. Continuing with next file.");
          }
        }
      }
      
      // حذف المجلدات الفرعية من الأعمق إلى الأعلى
      final directories = entities
          .whereType<Directory>()
          .toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length)); // ترتيب تنازلي حسب طول المسار
      
      for (final subDir in directories) {
        try {
          await subDir.delete();
        } catch (e) {
          logger.warn("SelfDestructService", 
              "Error deleting subdirectory ${subDir.path}: $e. Continuing with next directory.");
        }
      }
    } catch (e, s) {
      logger.error("SelfDestructService", 
          "Error during secure directory wipe", e, s);
    }
  }

  /// تنفيذ التدمير الذاتي مع التحقق من اكتمال العملية
  Future<bool> initiateSelfDestruct(BuildContext context,
      {String? triggeredBy, bool performLogout = true, bool silent = false}) async {
    final logger = _ref.read(appLoggerProvider);
    final secureStorageService = _ref.read(secureStorageServiceProvider);
    final currentAgentCode = await secureStorageService.readAgentCode();
    
    // إنشاء معرف فريد للعملية للتتبع في السجلات
    final operationId = DateTime.now().millisecondsSinceEpoch.toString();

    logger.error(
        "FULL SELF-DESTRUCT SEQUENCE INITIATED [ID:$operationId] by: ${triggeredBy ?? 'Unknown'}. Agent: $currentAgentCode. Perform Logout: $performLogout. Silent: $silent",
        "SELF_DESTRUCT_SERVICE");

    // التقاط BuildContext والحالة المثبتة قبل الفجوات غير المتزامنة
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    bool isContextMounted() => context.mounted;

    // إظهار إشعار بدء العملية إذا لم تكن صامتة
    if (!silent && isContextMounted()) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('بدء تسلسل التدمير الذاتي الكامل للبيانات المحلية...',
              style: GoogleFonts.cairo(color: Colors.white)),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    await Future.delayed(const Duration(milliseconds: 500));

    // قائمة لتتبع نجاح كل خطوة
    final Map<String, bool> operationResults = {};

    try {
      // 1. مسح البيانات على الخادم
      if (currentAgentCode != null && currentAgentCode.isNotEmpty) {
        logger.info("SelfDestructService [ID:$operationId]",
            "Marking server-side conversations as deleted for agent: $currentAgentCode");
        
        try {
          final conversationsSnapshot = await _firestoreInstance
              .collection('conversations')
              .where('participants', arrayContains: currentAgentCode)
              .get();

          logger.info("SelfDestructService [ID:$operationId]",
              "Found ${conversationsSnapshot.docs.length} conversations to mark as deleted for agent $currentAgentCode.");
          
          if (conversationsSnapshot.docs.isNotEmpty) {
            WriteBatch batch = _firestoreInstance.batch();
            for (final convDoc in conversationsSnapshot.docs) {
              batch.update(convDoc.reference, {
                'deletedForUsers.$currentAgentCode': true,
                'updatedAt': firestore.FieldValue.serverTimestamp()
              });
            }
            await batch.commit();
            operationResults['server_data_marking'] = true;
            logger.info("SelfDestructService [ID:$operationId]",
                "Successfully marked ${conversationsSnapshot.docs.length} conversations as deleted for agent $currentAgentCode.");
          } else {
            operationResults['server_data_marking'] = true;
            logger.info("SelfDestructService [ID:$operationId]",
                "No conversations found to mark as deleted for agent $currentAgentCode.");
          }
        } catch (e, s) {
          operationResults['server_data_marking'] = false;
          logger.error("SelfDestructService [ID:$operationId]",
              "Error marking server-side conversations as deleted", e, s);
        }
      } else {
        operationResults['server_data_marking'] = true;
        logger.warn("SelfDestructService [ID:$operationId]",
            "No agent code found. Skipping server-side data marking.");
      }

      // 2. مسح السجل المحلي
      try {
        final historyService = _ref.read(historyServiceProvider);
        await historyService.clearHistory();
        operationResults['history_clearing'] = true;
        logger.info("SelfDestructService [ID:$operationId]", "Cleared local history.");
      } catch (e, s) {
        operationResults['history_clearing'] = false;
        logger.error("SelfDestructService [ID:$operationId]", 
            "Error clearing local history", e, s);
      }

      // 3. مسح قاعدة بيانات Sembast بشكل آمن
      operationResults['sembast_wipe'] = await _secureWipeSembastDatabase(logger);

      // 4. مسح التخزين الآمن
      try {
        await secureStorageService.deleteAll();
        operationResults['secure_storage_clearing'] = true;
        logger.info("SelfDestructService [ID:$operationId]", "Cleared FlutterSecureStorage.");
      } catch (e, s) {
        operationResults['secure_storage_clearing'] = false;
        logger.error("SelfDestructService [ID:$operationId]", 
            "Error clearing FlutterSecureStorage", e, s);
      }

      // 5. مسح SharedPreferences
      operationResults['shared_prefs_clearing'] = await _clearSharedPreferences(logger);

      // 6. مسح مجلدات التخزين المؤقت ومجلدات الدعم
      operationResults['cache_dirs_clearing'] = await _clearAppCacheAndSupportDirs(logger);

      // 7. تسجيل الخروج إذا كان مطلوباً
      if (performLogout) {
        try {
          final authService = _ref.read(authServiceProvider);
          await authService.signOut();
          operationResults['logout'] = true;
          logger.info("SelfDestructService [ID:$operationId]", "User logged out successfully.");
        } catch (e, s) {
          operationResults['logout'] = false;
          logger.error("SelfDestructService [ID:$operationId]", 
              "Error during logout", e, s);
        }
      } else {
        operationResults['logout'] = true;
        logger.info("SelfDestructService [ID:$operationId]", "Logout skipped as requested.");
      }

      // التحقق من نجاح جميع العمليات
      final bool allOperationsSuccessful = !operationResults.values.contains(false);
      
      // تسجيل نتيجة العملية الكاملة
      if (allOperationsSuccessful) {
        logger.info("SelfDestructService [ID:$operationId]",
            "SELF-DESTRUCT COMPLETED SUCCESSFULLY. All operations succeeded: $operationResults");
        
        // إظهار إشعار نجاح العملية إذا لم تكن صامتة
        if (!silent && isContextMounted()) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('تم مسح جميع البيانات المحلية بنجاح.',
                  style: GoogleFonts.cairo(color: Colors.white)),
              backgroundColor: Colors.green.shade800,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        // الانتقال إلى شاشة ما بعد التدمير
        if (isContextMounted()) {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => const DecoyScreen(isPostDestruct: true)),
            (route) => false,
          );
        }
        
        return true;
      } else {
        logger.error("SelfDestructService [ID:$operationId]",
            "SELF-DESTRUCT PARTIALLY FAILED. Operation results: $operationResults");
        
        // إظهار إشعار فشل العملية إذا لم تكن صامتة
        if (!silent && isContextMounted()) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('فشل في مسح بعض البيانات المحلية. جاري محاولة التنظيف النهائي...',
                  style: GoogleFonts.cairo(color: Colors.white)),
              backgroundColor: Colors.orange.shade900,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        // محاولة تنظيف نهائية للبيانات الحساسة
        try {
          logger.info("SelfDestructService [ID:$operationId]",
              "Attempting final cleanup for critical data...");
          
          final authService = _ref.read(authServiceProvider);
          await authService.signOut();
          await _ref.read(secureStorageServiceProvider).deleteAll();
          await _clearSharedPreferences(logger);
          _ref.invalidate(currentAgentCodeProvider);
          
          if (isContextMounted()) {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => const DecoyScreen(isPostDestruct: true)),
              (route) => false,
            );
          }
        } catch (finalError, finalStackTrace) {
          logger.error("SelfDestructService [ID:$operationId]", 
              "Error during fallback cleanup", finalError, finalStackTrace);
        }
      }
      
      return false;
    } catch (e, s) {
      logger.error("SelfDestructService [ID:$operationId]",
          "CRITICAL ERROR during self-destruct sequence", e, s);
      
      // إظهار إشعار فشل العملية إذا لم تكن صامتة
      if (!silent && isContextMounted()) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء مسح البيانات. جاري محاولة التنظيف النهائي...',
                style: GoogleFonts.cairo(color: Colors.white)),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      // محاولة تنظيف نهائية للبيانات الحساسة
      try {
        logger.info("SelfDestructService [ID:$operationId]",
            "Attempting emergency cleanup after critical error...");
        
        final authService = _ref.read(authServiceProvider);
        await authService.signOut();
        await _ref.read(secureStorageServiceProvider).deleteAll();
        await _clearSharedPreferences(logger);
        _ref.invalidate(currentAgentCodeProvider);
        
        if (isContextMounted()) {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => const DecoyScreen(isPostDestruct: true)),
            (route) => false,
          );
        }
      } catch (finalError, finalStackTrace) {
        logger.error("SelfDestructService [ID:$operationId]", 
            "Error during emergency cleanup", finalError, finalStackTrace);
      }
      
      return false;
    }
  }

  /// تنفيذ التدمير الذاتي بشكل صامت دون إظهار أي إشعارات
  Future<bool> initiateSilentSelfDestruct(BuildContext context,
      {String? triggeredBy, bool performLogout = false}) async {
    return initiateSelfDestruct(
      context,
      triggeredBy: triggeredBy,
      performLogout: performLogout,
      silent: true,
    );
  }
  
  /// طريقة مختصرة للتدمير الذاتي الصامت - تستخدم من قبل DecoyScreenController
  Future<bool> silentSelfDestruct({String? triggeredBy}) async {
    final logger = _ref.read(appLoggerProvider);
    logger.info("SelfDestructService", "Silent self-destruct triggered without context by: ${triggeredBy ?? 'Unknown'}");
    
    try {
      // تنفيذ عمليات التدمير الذاتي بدون سياق واجهة المستخدم
      final secureStorageService = _ref.read(secureStorageServiceProvider);
      final currentAgentCode = await secureStorageService.readAgentCode();
      
      // 1. مسح البيانات على الخادم
      if (currentAgentCode != null && currentAgentCode.isNotEmpty) {
        try {
          final conversationsSnapshot = await _firestoreInstance
              .collection('conversations')
              .where('participants', arrayContains: currentAgentCode)
              .get();
          
          if (conversationsSnapshot.docs.isNotEmpty) {
            WriteBatch batch = _firestoreInstance.batch();
            for (final convDoc in conversationsSnapshot.docs) {
              batch.update(convDoc.reference, {
                'deletedForUsers.$currentAgentCode': true,
                'updatedAt': firestore.FieldValue.serverTimestamp()
              });
            }
            await batch.commit();
          }
        } catch (e, s) {
          logger.error("SelfDestructService", "Error marking server-side conversations as deleted", e, s);
        }
      }
      
      // 2. مسح السجل المحلي
      try {
        final historyService = _ref.read(historyServiceProvider);
        await historyService.clearHistory();
      } catch (e, s) {
        logger.error("SelfDestructService", "Error clearing local history", e, s);
      }
      
      // 3. مسح التخزين الآمن
      try {
        await secureStorageService.deleteAll();
      } catch (e, s) {
        logger.error("SelfDestructService", "Error clearing secure storage", e, s);
      }
      
      // 4. مسح SharedPreferences
      await _clearSharedPreferences(logger);
      
      // 5. مسح قاعدة بيانات Sembast
      await _secureWipeSembastDatabase(logger);
      
      // 6. مسح مجلدات التخزين المؤقت
      await _clearAppCacheAndSupportDirs(logger);
      
      logger.info("SelfDestructService", "Silent self-destruct completed");
      return true;
    } catch (e, s) {
      logger.error("SelfDestructService", "Error during silent self-destruct", e, s);
      return false;
    }
  }
}
