import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabaseHelper {
  static const String _dbName = "LocationCache.db";
  static const int _dbVersion = 1;
  static const String tableLocations = 'locations';
  LocalDatabaseHelper._();
  static final LocalDatabaseHelper instance = LocalDatabaseHelper._();
  static Database? _db;

  Future<Database> get database async {
    return _db ??= await _initDatabase();
  }

  Future<Database> _initDatabase() async {
    final dbPath = join(await getDatabasesPath(), _dbName);
    return openDatabase(dbPath, version: _dbVersion, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableLocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        custom_user_id TEXT NOT NULL,
        user_id TEXT,
        location_lat REAL NOT NULL,
        location_lng REAL NOT NULL,
        last_updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertLocation(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert(tableLocations, row);
  }

  Future<List<Map<String, dynamic>>> getAllLocations() async {
    final db = await database;
    return db.query(tableLocations);
  }

  Future<int> clearAllLocations() async {
    final db = await database;
    return db.delete(tableLocations);
  }
}