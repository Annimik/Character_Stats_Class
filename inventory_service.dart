import 'package:sqflite/sqflite.dart';
import '../data/inventory_db.dart';

class ProductRow {
  final int id;
  final String code;
  final String name;
  final int diameterMm;
  final int lengthMm;

  ProductRow({
    required this.id,
    required this.code,
    required this.name,
    required this.diameterMm,
    required this.lengthMm,
  });

  factory ProductRow.fromMap(Map<String, dynamic> m) => ProductRow(
    id: m['id'] as int,
    code: m['code'] as String,
    name: m['name'] as String,
    diameterMm: m['diameter_mm'] as int,
    lengthMm: m['length_mm'] as int,
  );
}

class StockLine {
  final ProductRow product;
  final int quantity;

  StockLine({required this.product, required this.quantity});
}

/// Ошибка, если пытаемся списать больше, чем есть.
class InsufficientStock implements Exception {
  final int available;
  final int requested;
  InsufficientStock({required this.available, required this.requested});

  @override
  String toString() => 'InsufficientStock(available=$available, requested=$requested)';
}

class InventoryService {
  final InventoryDb _db;

  InventoryService(this._db);

  Future<Database> get _database => _db.db;

  // --------- PRODUCTS ---------

  /// Создать или обновить товар по code.
  /// Возвращает productId.
  Future<int> upsertProduct({
    required String code,
    required String name,
    required int diameterMm,
    required int lengthMm,
  }) async {
    final db = await _database;
    final normCode = code.trim().toUpperCase();

    final existing = await db.query(
      'products',
      where: 'code = ?',
      whereArgs: [normCode],
      limit: 1,
    );

    if (existing.isEmpty) {
      return db.insert('products', {
        'code': normCode,
        'name': name.trim(),
        'diameter_mm': diameterMm,
        'length_mm': lengthMm,
      });
    } else {
      final id = existing.first['id'] as int;
      await db.update(
        'products',
        {
          'name': name.trim(),
          'diameter_mm': diameterMm,
          'length_mm': lengthMm,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
  }

  Future<ProductRow?> getProductByCode(String code) async {
    final db = await _database;
    final res = await db.query(
      'products',
      where: 'code = ?',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return ProductRow.fromMap(res.first);
  }

  // --------- STOCK (CORE RULES) ---------

  /// Приход: quantity += amount, запись в movements.
  Future<void> stockIn({
    required int productId,
    required int amount,
    required int userId,
    int warehouseId = 1,
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');

    final db = await _database;
    await db.transaction((txn) async {
      await _ensureStockRow(txn, productId: productId, warehouseId: warehouseId);

      await txn.rawUpdate('''
        UPDATE stock_items
        SET quantity = quantity + ?, updated_at = datetime('now')
        WHERE product_id = ? AND warehouse_id = ?;
      ''', [amount, productId, warehouseId]);

      await txn.insert('movements', {
        'type': 'in',
        'product_id': productId,
        'warehouse_id': warehouseId,
        'amount': amount,
        'user_id': userId,
        'note': note,
      });
    });
  }

  /// Расход: проверяем, что хватит, затем quantity -= amount, запись в movements.
  Future<void> stockOut({
    required int productId,
    required int amount,
    required int userId,
    int warehouseId = 1,
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');

    final db = await _database;
    await db.transaction((txn) async {
      await _ensureStockRow(txn, productId: productId, warehouseId: warehouseId);

      final res = await txn.query(
        'stock_items',
        columns: ['quantity'],
        where: 'product_id = ? AND warehouse_id = ?',
        whereArgs: [productId, warehouseId],
        limit: 1,
      );

      final current = (res.first['quantity'] as int?) ?? 0;
      if (current - amount < 0) {
        throw InsufficientStock(available: current, requested: amount);
      }

      await txn.rawUpdate('''
        UPDATE stock_items
        SET quantity = quantity - ?, updated_at = datetime('now')
        WHERE product_id = ? AND warehouse_id = ?;
      ''', [amount, productId, warehouseId]);

      await txn.insert('movements', {
        'type': 'out',
        'product_id': productId,
        'warehouse_id': warehouseId,
        'amount': amount,
        'user_id': userId,
        'note': note,
      });
    });
  }

  /// Обзор склада: список товаров + остаток (LEFT JOIN).
  Future<List<StockLine>> listStock({int warehouseId = 1}) async {
    final db = await _database;

    final rows = await db.rawQuery('''
      SELECT
        p.id, p.code, p.name, p.diameter_mm, p.length_mm,
        COALESCE(s.quantity, 0) AS quantity
      FROM products p
      LEFT JOIN stock_items s
        ON s.product_id = p.id AND s.warehouse_id = ?
      ORDER BY p.code ASC;
    ''', [warehouseId]);

    return rows.map((m) {
      final product = ProductRow(
        id: m['id'] as int,
        code: m['code'] as String,
        name: m['name'] as String,
        diameterMm: m['diameter_mm'] as int,
        lengthMm: m['length_mm'] as int,
      );
      final qty = (m['quantity'] as int?) ?? 0;
      return StockLine(product: product, quantity: qty);
    }).toList();
  }

  Future<void> seedDemoDataIfEmpty({int warehouseId = 1}) async {
    final db = await _database;

    // Есть ли уже товары?
    final countRes = await db.rawQuery('SELECT COUNT(*) AS c FROM products;');
    final count = (countRes.first['c'] as int?) ?? 0;
    if (count > 0) return; // уже seeded

    // Нужно, чтобы был хотя бы один user для movements.
    // Если users пусто — создадим локального "admin".
    final userCountRes = await db.rawQuery('SELECT COUNT(*) AS c FROM users;');
    final userCount = (userCountRes.first['c'] as int?) ?? 0;

    int userId;
    if (userCount == 0) {
      userId = await db.insert('users', {
        'email': 'admin@local',
        'password_hash': 'demo', // для сида не важно
        'role': 'admin',
      });
    } else {
      final u = await db.rawQuery('SELECT id FROM users ORDER BY id ASC LIMIT 1;');
      userId = u.first['id'] as int;
    }

    // Создаём 2 позиции
    final a300Id = await upsertProduct(
      code: 'A300',
      name: 'Арматура A300',
      diameterMm: 12,
      lengthMm: 2000,
    );

    final b500Id = await upsertProduct(
      code: 'B500',
      name: 'Арматура B500',
      diameterMm: 10,
      lengthMm: 12000,
    );

    // Делаем приход, чтобы на складе было не 0
    await stockIn(productId: a300Id, amount: 20, userId: userId, warehouseId: warehouseId, note: 'seed');
    await stockIn(productId: b500Id, amount: 7, userId: userId, warehouseId: warehouseId, note: 'seed');
  }

  Future<int> ensureUserByEmail(String email, {String role = 'worker'}) async {
    final db = await _database;
    final norm = email.trim().toLowerCase();

    final res = await db.query(
      'users',
      columns: ['id'],
      where: 'email = ?',
      whereArgs: [norm],
      limit: 1,
    );

    if (res.isNotEmpty) return res.first['id'] as int;

    // Для MVP пароль не нужен (у тебя локальная auth отдельно).
    // Пишем placeholder.
    return db.insert('users', {
      'email': norm,
      'password_hash': 'local',
      'role': role,
    });
  }

  Future<int?> getProductIdByCode(String code) async {
    final db = await _database;
    final res = await db.query(
      'products',
      columns: ['id'],
      where: 'code = ?',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return res.first['id'] as int;
  }

  // --------- helpers ---------

  Future<void> _ensureStockRow(
      Transaction txn, {
        required int productId,
        required int warehouseId,
      }) async {
    // гарантируем наличие строки в stock_items (чтобы UPDATE сработал всегда)
    await txn.insert(
      'stock_items',
      {
        'product_id': productId,
        'warehouse_id': warehouseId,
        'quantity': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
