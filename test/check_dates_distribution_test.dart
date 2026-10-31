import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('check dates distribution in user db', () async {
    sqfliteFfiInit();
    final dbFile = File('C:/Users/Rajiv Kumar/Documents/opscore_pro.db');
    if (!dbFile.existsSync()) {
      print('DB does not exist');
      return;
    }
    final db = await databaseFactoryFfi.openDatabase(dbFile.path);

    // Group by drawDate/saleDate
    final dates = await db.rawQuery('''
      SELECT substr(drawDate, 1, 10) as dDate, substr(saleDate, 1, 10) as sDate, drawName, count(*) as cnt 
      FROM ticket_sales 
      GROUP BY dDate, drawName 
      ORDER BY cnt DESC 
      LIMIT 20
    ''');
    print('Dates distribution in DB:');
    for (final d in dates) {
      print('drawDate: ${d['dDate']}, saleDate: ${d['sDate']}, drawName: ${d['drawName']}, count: ${d['cnt']}');
    }
    await db.close();
  });
}

