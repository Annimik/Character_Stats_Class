import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class InventoryDb {
  static final InventoryDb instance = InventoryDb._();
  InventoryDb._();

  static const _dbName = 'inventory.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        // Важно для ссылочной целостности
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seed(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    // 1) Склад(ы). Для MVP будет один склад id=1
    await db.execute('''
      CREATE TABLE warehouses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      );
    ''');

    // 2) Пользователи (локально). Для предприятия позже лучше серверная авторизация.
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'worker'
      );
    ''');

    // 3) Товары/позиции (что это за арматура)
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,               -- A300
        name TEXT NOT NULL,                      -- "Арматура A300"
        diameter_mm INTEGER NOT NULL CHECK(diameter_mm > 0),
        length_mm INTEGER NOT NULL CHECK(length_mm > 0),
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT
      );
    ''');

    // 4) Остатки (сколько сейчас на складе). 1 строка на (product, warehouse)
    await db.execute('''
      CREATE TABLE stock_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        warehouse_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0 CHECK(quantity >= 0),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(product_id, warehouse_id),
        FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY(warehouse_id) REFERENCES warehouses(id) ON DELETE CASCADE
      );
    ''');

    // 5) Движения (журнал операций). Это база для синхронизации “потом”.
    await db.execute('''
      CREATE TABLE movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK(type IN ('in','out','adjust')),
        product_id INTEGER NOT NULL,
        warehouse_id INTEGER NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0),
        user_id INTEGER NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY(warehouse_id) REFERENCES warehouses(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('CREATE INDEX idx_products_code ON products(code);');
    await db.execute('CREATE INDEX idx_movements_product ON movements(product_id);');
    await db.execute('CREATE INDEX idx_stock_product ON stock_items(product_id);');
  }

  Future<void> _seed(Database db) async {
    // Один склад по умолчанию
    await db.insert('warehouses', {'name': 'Main'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
