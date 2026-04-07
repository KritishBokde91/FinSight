import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/sms_label.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sms_labels.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE labels (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  smsHash TEXT NOT NULL,
  senderId TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  originalText TEXT NOT NULL,
  normalizedText TEXT NOT NULL,
  suggestedLabel TEXT NOT NULL DEFAULT "PENDING",
  aiLabel TEXT,
  aiModel TEXT,
  userLabel TEXT,
  isCorrected BOOLEAN NOT NULL DEFAULT 0,
  UNIQUE(smsHash)
)
''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns for v2
      try { await db.execute('ALTER TABLE labels ADD COLUMN aiLabel TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE labels ADD COLUMN aiModel TEXT'); } catch (_) {}
    }
  }

  Future<int> insertLabel(SmsLabel label) async {
    final db = await instance.database;
    return await db.insert(
      'labels',
      label.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Labels where user hasn't reviewed yet — for the swipe UI
  Future<List<SmsLabel>> getUnreviewedLabels({int limit = 50}) async {
    final db = await instance.database;
    final maps = await db.query(
      'labels',
      where: 'userLabel IS NULL OR userLabel = ""',
      limit: limit,
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => SmsLabel.fromMap(m)).toList();
  }

  /// Labels where AI hasn't run yet
  Future<List<SmsLabel>> getPendingAiLabels({int limit = 10}) async {
    final db = await instance.database;
    final maps = await db.query(
      'labels',
      where: 'aiLabel IS NULL',
      limit: limit,
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => SmsLabel.fromMap(m)).toList();
  }

  Future<int> updateAiLabel(int id, String aiLabel, String aiModel) async {
    final db = await instance.database;
    return db.update(
      'labels',
      {'aiLabel': aiLabel, 'aiModel': aiModel, 'suggestedLabel': aiLabel},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateLabelUserFeedback(int id, String userLabel, bool isCorrected) async {
    final db = await instance.database;
    return db.update(
      'labels',
      {'userLabel': userLabel, 'isCorrected': isCorrected ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<SmsLabel>> getAllLabels() async {
    final db = await instance.database;
    final maps = await db.query('labels', orderBy: 'timestamp DESC');
    return maps.map((m) => SmsLabel.fromMap(m)).toList();
  }

  Future<Map<String, int>> getStats() async {
    final db = await instance.database;
    final total = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM labels')) ?? 0;
    final reviewed = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM labels WHERE userLabel != "" AND userLabel IS NOT NULL')) ?? 0;
    final aiLabeled = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM labels WHERE aiLabel IS NOT NULL')) ?? 0;
    final pendingAi = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM labels WHERE aiLabel IS NULL')) ?? 0;
    return {
      'total': total,
      'reviewed': reviewed,
      'pending_review': total - reviewed,
      'ai_labeled': aiLabeled,
      'pending_ai': pendingAi,
    };
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
