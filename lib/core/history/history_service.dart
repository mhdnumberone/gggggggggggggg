// lib/core/history/history_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart'
    as path_lib; // استخدام alias لتجنب المشاكل المستقبلية
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';

import '../logging/logger_provider.dart';
import '../logging/logger_service.dart';
import 'history_item.dart';

final historyServiceProvider = Provider<HistoryService>((ref) {
  final logger = ref.watch(appLoggerProvider);
  return HistoryService(logger);
});

class HistoryService {
  static const String _dbName = 'conduit_history_v3.db';
  static const String _storeName = 'operations_history_v3';
  static const int _maxHistoryItems = 100; // تم الإبقاء على الاسم الصحيح هنا

  Database? _db;
  final _store = intMapStoreFactory.store(_storeName);
  final LoggerService _logger;

  HistoryService(this._logger);

  Future<Database> get _database async {
    if (_db == null) {
      _logger.info("_database_getter", "Database is null, initializing...");
      await _initDb();
    }
    // لا حاجة للتحقق من hasBeenOpened هنا، Sembast يتعامل مع ذلك عند الفتح
    if (_db == null) {
      _logger.error(
          "_database_getter", "Database is STILL NULL after _initDb call!");
      throw Exception("Sembast database could not be initialized or opened.");
    }
    return _db!;
  }

  Future<void> _initDb() async {
    const tag = "_initDb";
    if (_db != null) {
      // إذا لم يكن null، افترض أنه تم التعامل معه
      _logger.info(tag,
          "Database instance may already exist or Sembast will handle re-opening.");
      // إذا كنت تريد أن تكون أكثر أمانًا، يمكنك محاولة الإغلاق أولاً إذا لم يكن مفتوحًا
      // ولكن هذا قد يكون معقدًا. Sembast عادةً ما يكون جيدًا في هذا.
      // إذا كنت تواجه مشاكل "Database already opened"، يمكنك إضافة منطق هنا.
      // For now, let's assume if _db is not null, it's either open or Sembast can open it.
      // If it was closed manually AND not set to null, that's a different state to handle.
      // The simplest is: if _db is null, open. Otherwise, assume Sembast handles it.
      // To be very safe against "already opened" if init is called multiple times without closing:
      // if (_db != null) {
      //   try { await _db!.close(); } catch(_){} // ignore errors if already closed
      //   _db = null;
      // }
      return; // تم تعديل هذا الشرط ليكون أبسط
    }

    DatabaseFactory dbFactory;
    String dbPath;

    if (kIsWeb) {
      dbFactory = databaseFactoryWeb;
      dbPath = _dbName;
      _logger.info(tag, "Using Sembast Web DB: $dbPath");
    } else {
      dbFactory = databaseFactoryIo;
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        dbPath = path_lib.join(appDocDir.path, _dbName); // استخدام alias
        _logger.info(tag, "Using Sembast IO DB at: $dbPath");
      } catch (e, stackTrace) {
        _logger.error(tag, "Error getting application documents directory", e,
            stackTrace);
        rethrow;
      }
    }
    try {
      _db = await dbFactory.openDatabase(dbPath);
      _logger.info(tag, "Sembast DB Initialized successfully.");
    } catch (e, stackTrace) {
      _logger.error(
          tag, "Failed to open Sembast DB at path: $dbPath", e, stackTrace);
      _db = null;
      rethrow;
    }
  }

  // ... (loadHistory, addHistoryItem, deleteItem, clearHistory) كما كانت في الرد السابق ...
  // (مع التأكد من استخدام _maxHistoryItems بشكل صحيح في addHistoryItem)

  Future<void> addHistoryItem(HistoryItem newItem) async {
    const tag = "addHistoryItem";
    _logger.info(tag,
        "Adding new history item: ${newItem.operationDescription}, ID: ${newItem.id}");
    try {
      final db = await _database;
      await _store.add(db, newItem.toJson());
      _logger.debug(tag, "Item added successfully. ID: ${newItem.id}");

      final count = await _store.count(db);
      if (count > _maxHistoryItems) {
        // <<<< استخدام الثابت الصحيح
        _logger.info(tag,
            "History size ($count) exceeds max ($_maxHistoryItems). Trimming...");
        final finder = Finder(
            sortOrders: [SortOrder('timestamp', true)],
            limit: count - _maxHistoryItems); // <<<< استخدام الثابت الصحيح
        final recordsToDelete = await _store.findKeys(db, finder: finder);
        if (recordsToDelete.isNotEmpty) {
          await _store.records(recordsToDelete).delete(db);
          _logger.info(
              tag, "Trimmed ${recordsToDelete.length} old history items.");
        }
      }
    } catch (e, stackTrace) {
      _logger.error(
          tag, "Error adding history item. ID: ${newItem.id}", e, stackTrace);
    }
  }

  Future<List<HistoryItem>> loadHistory() async {
    const tag = "loadHistory";
    _logger.info(tag, "Loading history from Sembast.");
    try {
      final db = await _database;
      final finder = Finder(sortOrders: [SortOrder('timestamp', false)]);
      final records = await _store.find(db, finder: finder);
      _logger.debug(tag, "Found ${records.length} history records.");
      return records
          .map((snapshot) {
            try {
              return HistoryItem.fromJson(snapshot.value);
            } catch (e, stackTrace) {
              _logger.error(
                  tag,
                  "Error parsing HistoryItem from JSON: ${snapshot.value}",
                  e,
                  stackTrace);
              return null;
            }
          })
          .whereType<HistoryItem>()
          .toList();
    } catch (e, stackTrace) {
      _logger.error(tag, "Error loading history collection", e, stackTrace);
      return [];
    }
  }

  Future<void> deleteItem(String id) async {
    const tag = "deleteItem";
    _logger.info(tag, "Deleting history item with id: $id");
    try {
      final db = await _database;
      final finder = Finder(filter: Filter.equals('id', id));
      final deletedCount = await _store.delete(db, finder: finder);
      _logger.info(tag, "Deleted $deletedCount item(s) with id: $id.");
    } catch (e, stackTrace) {
      _logger.error(
          tag, "Error deleting history item with id: $id", e, stackTrace);
    }
  }

  Future<void> clearHistory() async {
    const tag = "clearHistory";
    _logger.info(tag, "Clearing all history items.");
    try {
      final db = await _database;
      final deletedCount = await _store.delete(db);
      _logger.info(tag, "Cleared $deletedCount history items.");
    } catch (e, stackTrace) {
      _logger.error(tag, "Error clearing history", e, stackTrace);
    }
  }

  Future<void> closeDb() async {
    const tag = "closeDb";
    if (_db != null) {
      try {
        // Sembast's close is idempotent, safe to call even if already closed or being closed.
        await _db!.close();
        _logger.info(tag, "Sembast DB Close requested/completed.");
      } catch (e, stackTrace) {
        _logger.error(tag, "Error closing Sembast DB", e, stackTrace);
      } finally {
        _db = null;
      }
    } else {
      _logger.info(
          tag, "Sembast DB was already null, no action taken to close.");
    }
  }
}
