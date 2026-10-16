import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('jamia_master.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE circles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        share_amount REAL NOT NULL,
        total_months INTEGER NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        cycle_type TEXT DEFAULT 'monthly',
        payment_method TEXT DEFAULT 'cash',
        status TEXT DEFAULT 'active'
      )
    ''');

    await db.execute('''
      CREATE TABLE members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        circle_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        shares_count REAL DEFAULT 1.0,
        FOREIGN KEY (circle_id) REFERENCES circles (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE payouts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        circle_id INTEGER NOT NULL,
        member_id INTEGER NOT NULL,
        month_index INTEGER NOT NULL,
        payout_date TEXT NOT NULL,
        is_received INTEGER DEFAULT 0,
        FOREIGN KEY (circle_id) REFERENCES circles (id) ON DELETE CASCADE,
        FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        circle_id INTEGER NOT NULL,
        member_id INTEGER NOT NULL,
        month_index INTEGER NOT NULL,
        amount_paid REAL NOT NULL,
        is_paid INTEGER DEFAULT 0,
        payment_method TEXT DEFAULT 'cash',
        payment_date TEXT,
        covered_by_admin INTEGER DEFAULT 0,
        FOREIGN KEY (circle_id) REFERENCES circles (id) ON DELETE CASCADE,
        FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
      )
    ''');
  }

  // --- تحديث بيانات الجمعية الشامل (القسط، البداية، النهاية) ---
  Future<void> updateCircleDetails({
    required int circleId,
    required String name,
    required double shareAmount,
    required String cycleType,
    required String paymentMethod,
    required String startDate,
    required String endDate,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. تحديث جدول الجمعيات
      await txn.update(
        'circles',
        {
          'name': name,
          'share_amount': shareAmount,
          'cycle_type': cycleType,
          'payment_method': paymentMethod,
          'start_date': startDate,
          'end_date': endDate,
        },
        where: 'id = ?',
        whereArgs: [circleId],
      );

      // 2. تحديث قيمة الأقساط غير المسددة بالقيمة الجديدة
      await txn.update(
        'payments',
        {'amount_paid': shareAmount},
        where: 'circle_id = ? AND is_paid = 0',
        whereArgs: [circleId],
      );
    });
  }

  // --- دوال حذف الجمعية وإدارة الأعضاء ---
  Future<void> deleteCircle(int circleId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('payments', where: 'circle_id = ?', whereArgs: [circleId]);
      await txn.delete('payouts', where: 'circle_id = ?', whereArgs: [circleId]);
      await txn.delete('members', where: 'circle_id = ?', whereArgs: [circleId]);
      await txn.delete('circles', where: 'id = ?', whereArgs: [circleId]);
    });
  }

  Future<void> updateMember(int memberId, String name, String phone) async {
    final db = await database;
    await db.update(
      'members',
      {'name': name, 'phone': phone},
      where: 'id = ?',
      whereArgs: [memberId],
    );
  }

  Future<void> deleteMember(int memberId, int circleId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('payments', where: 'member_id = ? AND circle_id = ?', whereArgs: [memberId, circleId]);
      await txn.delete('payouts', where: 'member_id = ? AND circle_id = ?', whereArgs: [memberId, circleId]);
      await txn.delete('members', where: 'id = ?', whereArgs: [memberId]);

      final countResult = await txn.rawQuery(
        'SELECT COUNT(*) as cnt FROM members WHERE circle_id = ?',
        [circleId],
      );
      final count = (countResult.first['cnt'] as int?) ?? 0;
      await txn.update(
        'circles',
        {'total_months': count},
        where: 'id = ?',
        whereArgs: [circleId],
      );
    });
  }

  Future<bool> swapPayoutTurns({
    required int payoutId1,
    required int memberId1,
    required int payoutId2,
    required int memberId2,
  }) async {
    final db = await database;
    return await db.transaction((txn) async {
      final checkPayouts = await txn.rawQuery(
        'SELECT id, is_received FROM payouts WHERE id IN (?, ?)',
        [payoutId1, payoutId2],
      );

      for (var row in checkPayouts) {
        if ((row['is_received'] as int) == 1) {
          return false;
        }
      }

      await txn.update('payouts', {'member_id': memberId2}, where: 'id = ?', whereArgs: [payoutId1]);
      await txn.update('payouts', {'member_id': memberId1}, where: 'id = ?', whereArgs: [payoutId2]);
      return true;
    });
  }
}
