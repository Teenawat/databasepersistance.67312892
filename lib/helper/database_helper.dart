import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _databaseName = "MyNotes.db";
  static const _databaseVersion = 1;

  // ทำให้คลาสนี้เป็น Singleton
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  // มี reference ไปยังฐานข้อมูลเพียงหนึ่งเดียว
  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    // หาก _database เป็น null จะทำการ initialize ให้
    _database = await _initDatabase();
    return _database!;
  }

  // เมธอดสำหรับเปิดฐานข้อมูล (หรือสร้างขึ้นใหม่ถ้ายังไม่มี)
  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    debugPrint('Database path: $path'); // แสดง path ของฐานข้อมูลใน console
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate, // จะถูกเรียกเมื่อฐานข้อมูลถูกสร้างขึ้นครั้งแรก
    );
  }

  // เมธอดสำหรับสร้างตาราง (จะเพิ่มโค้ดในภายหลัง)
  Future<void> _onCreate(Database db, int version) async {
    debugPrint('onCreate ถูกเรียก: กำลังจะสร้างตาราง notes...');
    await db.execute('''
        CREATE TABLE notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          content TEXT NOT NULL
        )
        ''');
    debugPrint('ตาราง notes ถูกสร้างแล้ว');
  }
}
