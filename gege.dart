import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'data/inventory_db.dart';
import 'services/inventory_service.dart';
import 'ui/stock_tab.dart';

void main() {
  runApp(const MyApp());
}

/* =======================
   МОДЕЛЬ АРМАТУРЫ
======================= */
class Armatura {
  final int? id;
  final String name;
  final String diameter;
  final String length;

  Armatura({
    this.id,
    required this.name,
    required this.diameter,
    required this.length,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'diameter': diameter,
    'length': length,
  };

  factory Armatura.fromMap(Map<String, dynamic> map) => Armatura(
    id: map['id'] as int?,
    name: map['name'] as String,
    diameter: map['diameter'] as String,
    length: map['length'] as String,
  );
}

/* =======================
   МОДЕЛЬ ПОЛЬЗОВАТЕЛЯ
======================= */
class AppUser {
  final int? id;
  final String email;
  final String passwordHash;

  AppUser({this.id, required this.email, required this.passwordHash});

  Map<String, dynamic> toMap() => {
    'id': id,
    'email': email,
    'password_hash': passwordHash,
  };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
    id: map['id'] as int?,
    email: map['email'] as String,
    passwordHash: map['password_hash'] as String,
  );
}

/* =======================
   DATABASE SQLITE
======================= */
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('armatura.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE armatura (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            diameter TEXT NOT NULL,
            length TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            CREATE TABLE users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              email TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  // Armatura
  Future<void> insertArmatura(Armatura armatura) async {
    final db = await database;
    await db.insert('armatura', armatura.toMap());
  }

  Future<List<Armatura>> getAllArmatura() async {
    final db = await database;
    final result = await db.query('armatura', orderBy: 'id DESC');
    return result.map((e) => Armatura.fromMap(e)).toList();
  }

  Future<void> deleteArmatura(int id) async {
    final db = await database;
    await db.delete('armatura', where: 'id = ?', whereArgs: [id]);
  }

  // Users
  Future<AppUser?> getUserByEmail(String email) async {
    final db = await database;
    final res = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return AppUser.fromMap(res.first);
  }

  Future<int> createUser(String email, String passwordHash) async {
    final db = await database;
    return db.insert('users', {
      'email': email.trim().toLowerCase(),
      'password_hash': passwordHash,
    });
  }
}

/* =======================
   AUTH SERVICE
======================= */
class AuthService {
  static const _sessionKey = 'session_user_email';

  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  static Future<String?> currentUserEmail() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_sessionKey);
  }

  static Future<void> signIn(String email) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_sessionKey, email.trim().toLowerCase());
  }

  static Future<void> signOut() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_sessionKey);
  }
}

/* =======================
   APP THEME
======================= */
ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF2B2B2B),
    brightness: Brightness.light,
  );

  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFF7F7F8),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
  );
}

/* =======================
   APP ROOT
======================= */
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeShell(userEmail: 'local'),
    );
  }
}

class Boot extends StatelessWidget {
  const Boot({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: AuthService.currentUserEmail(),
      builder: (BuildContext context, AsyncSnapshot<String?> snap) {
        final email = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (email == null) return const AuthPage();
        return HomeShell(userEmail: email);
      },
    );
  }
}

/* =======================
   AUTH UI (LOGIN/REGISTER)
======================= */
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool isLogin = true;
  bool loading = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });

    final email = emailCtrl.text.trim().toLowerCase();
    final pass = passCtrl.text;

    if (!email.contains('@') || pass.length < 4) {
      setState(() {
        loading = false;
        error = 'Проверь email и пароль (минимум 4 символа).';
      });
      return;
    }

    try {
      final db = DatabaseHelper.instance;
      final existing = await db.getUserByEmail(email);
      final hash = AuthService.hashPassword(pass);

      if (isLogin) {
        if (existing == null || existing.passwordHash != hash) {
          setState(() {
            loading = false;
            error = 'Неверный email или пароль.';
          });
          return;
        }
      } else {
        if (existing != null) {
          setState(() {
            loading = false;
            error = 'Пользователь уже существует. Войди.';
          });
          return;
        }
        await db.createUser(email, hash);
      }

      await AuthService.signIn(email);
      if (!mounted) return;

      Navigator.of(context as BuildContext).pushReplacement(
        MaterialPageRoute(builder: (BuildContext _) => HomeShell(userEmail: email)),
      );
    } catch (_) {
      setState(() {
        error = 'Ошибка. Попробуй ещё раз.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Вход' : 'Регистрация')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Склад арматуры',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                ),
                const SizedBox(height: 14),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : submit,
                    child: Text(
                      loading ? '...' : (isLogin ? 'Войти' : 'Создать аккаунт'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: loading
                      ? null
                      : () => setState(() {
                    isLogin = !isLogin;
                    error = null;
                  }),
                  child: Text(
                    isLogin ? 'Нет аккаунта? Регистрация' : 'Уже есть аккаунт? Войти',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* =======================
   HOME WITH TABS
======================= */
class HomeShell extends StatefulWidget {
  final String userEmail;
  const HomeShell({super.key, required this.userEmail});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  late final InventoryService inventory;

  @override
  void initState(){
    super.initState();
    inventory = InventoryService(InventoryDb.instance);
    inventory.seedDemoDataIfEmpty();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      AddArmaturaTab(
        onAdded: () => setState(() {}),
        inventory: inventory,
        userEmail: widget.userEmail,
      ),
      StockTab(inventory: inventory),
      ScannerTab(
        onScanned: () => setState(() {}),
        inventory: inventory,
        userEmail: widget.userEmail,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(index == 0
            ? 'Добавить'
            : index == 1
            ? 'Склад'
            : 'Сканер'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<int>(
              icon: const Icon(Icons.more_horiz),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              itemBuilder: (BuildContext _) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    widget.userEmail,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 1,
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 18),
                      SizedBox(width: 10),
                      Text('Выйти'),
                    ],
                  ),
                ),
              ],
              onSelected: (v) async {
                if (v == 1) {
                  await AuthService.signOut();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (BuildContext _) => const AuthPage()),
                        (route) => false,
                  );
                }
              },
            ),
          )
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: pages[index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            label: 'Добавить',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Склад',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Сканер',
          ),
        ],
      ),
    );
  }
}

/* =======================
   TAB: ADD MANUALLY
======================= */
class AddArmaturaTab extends StatefulWidget {
  final VoidCallback onAdded;
  final InventoryService inventory;
  final String userEmail;

  const AddArmaturaTab({
    super.key,
    required this.onAdded,
    required this.inventory,
    required this.userEmail,
  });

  @override
  State<AddArmaturaTab> createState() => _AddArmaturaTabState();
}

class _AddArmaturaTabState extends State<AddArmaturaTab> {
  final codeCtrl = TextEditingController();      // A300
  final nameCtrl = TextEditingController();      // Арматура A300
  final diameterCtrl = TextEditingController();  // мм
  final lengthCtrl = TextEditingController();    // мм
  final amountCtrl = TextEditingController(text: '1'); // шт

  bool loading = false;
  String? error;

  int _parseInt(String s, {required String field}) {
    final v = int.tryParse(s.trim());
    if (v == null) throw FormatException('Поле "$field" должно быть целым числом.');
    return v;
  }

  Future<void> addOrStockIn() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final code = codeCtrl.text.trim().toUpperCase();
      final name = nameCtrl.text.trim();

      if (code.isEmpty || name.isEmpty) {
        throw FormatException('Заполни CODE и Название.');
      }

      final diameterMm = _parseInt(diameterCtrl.text, field: 'Диаметр (мм)');
      final lengthMm = _parseInt(lengthCtrl.text, field: 'Длина (мм)');
      final amount = _parseInt(amountCtrl.text, field: 'Количество (шт)');

      if (diameterMm <= 0 || lengthMm <= 0 || amount <= 0) {
        throw FormatException('Диаметр, длина и количество должны быть > 0.');
      }

      final userId = await widget.inventory.ensureUserByEmail(widget.userEmail);

      final productId = await widget.inventory.upsertProduct(
        code: code,
        name: name,
        diameterMm: diameterMm,
        lengthMm: lengthMm,
      );

      await widget.inventory.stockIn(
        productId: productId,
        amount: amount,
        userId: userId,
        note: 'manual',
      );

      codeCtrl.clear();
      nameCtrl.clear();
      diameterCtrl.clear();
      lengthCtrl.clear();
      amountCtrl.text = '1';

      widget.onAdded();

      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('Добавлено (приход выполнен)')),
      );
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Новая позиция / Приход',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'CODE (например A300)'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Название'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: diameterCtrl,
                        decoration: const InputDecoration(labelText: 'Диаметр (мм)'),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: lengthCtrl,
                        decoration: const InputDecoration(labelText: 'Длина (мм)'),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Количество (шт)'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : addOrStockIn,
                    icon: const Icon(Icons.add),
                    label: Text(loading ? '...' : 'Сохранить и сделать приход'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const _HintCard(
          icon: Icons.info_outline,
          text: 'Вводи размеры в мм. Количество — в штуках. CODE должен быть уникальным.',
        ),
      ],
    );
  }
}

/* =======================
   TAB: LIST
======================= */
class ArmaturaListTab extends StatefulWidget {
  const ArmaturaListTab({super.key});

  @override
  State<ArmaturaListTab> createState() => _ArmaturaListTabState();
}

class _ArmaturaListTabState extends State<ArmaturaListTab> {
  List<Armatura> list = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    list = await DatabaseHelper.instance.getAllArmatura();
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Пока пусто.\nДобавь позицию вручную или через сканер.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: list.length,
        itemBuilder: (BuildContext context, int i) {
          final item = list[i];
          return Card(
            child: ListTile(
              title: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Ø ${item.diameter} • ${item.length} м'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (item.id == null) return;
                  await DatabaseHelper.instance.deleteArmatura(item.id!);
                  await load();
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/* =======================
   TAB: SCANNER
======================= */
class ScannerTab extends StatelessWidget {
  final VoidCallback onScanned;
  final InventoryService inventory;
  final String userEmail;

  const ScannerTab({
    super.key,
    required this.onScanned,
    required this.inventory,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const _HintCard(
            icon: Icons.qr_code_2,
            text: 'Формат QR: Название, Диаметр, Длина',
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Material(
                color: Colors.black,
                child: MobileScanner(
                  // ✅ ЯВНО типизируем capture, чтобы не было "Context"/type inference проблем
                  onDetect: (BarcodeCapture capture) async {
                    onDetect: (BarcodeCapture capture) async {
                      final String? code = capture.barcodes.first.rawValue;
                      if (code == null) return;

                      final parts = code.split(';');
                      if (parts.length != 3) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Неверный формат QR. Нужно 3 поля.')),
                        );
                        return;
                      }

                      final rawName = parts[0].trim();
                      final diameterMm = int.tryParse(parts[1].trim());
                      final lengthMm = int.tryParse(parts[2].trim());

                      if (rawName.isEmpty || diameterMm == null || lengthMm == null) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('QR: имя/диаметр/длина должны быть корректными.')),
                        );
                        return;
                      }

                      // userId для movements
                      final userId = await inventory.ensureUserByEmail(userEmail);

                      // безопасный вариант: code = name (потом улучшим формат)
                      final productId = await inventory.upsertProduct(
                        code: rawName.toUpperCase(),
                        name: rawName,
                        diameterMm: diameterMm,
                        lengthMm: lengthMm,
                      );

                      await inventory.stockIn(
                        productId: productId,
                        amount: 1,
                        userId: userId,
                        note: 'qr',
                      );

                      onScanned();

                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Добавлено из QR (приход +1)')),
                      );
                    };
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* =======================
   SMALL UI WIDGETS
======================= */
class _HintCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HintCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(height: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
