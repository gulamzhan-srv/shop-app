// База данных магазина (SQLite, хранится в памяти телефона).
//
// В КАЖДОЙ таблице есть служебные поля для синхронизации через Google Диск:
//   id          — уникальный код записи (UUID), одинаковый на всех телефонах
//   updated_at  — время последнего изменения (миллисекунды)
//   device_id   — код телефона, который изменил запись
//   deleted     — 1 = запись удалена (не стираем, чтобы удаление тоже синхронизировалось)

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'shop.db';
  static const _dbVersion = 7;

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      // Проверку внешних ключей НЕ включаем: при синхронизации записи с другого
      // телефона могут прийти в любом порядке (строка продажи раньше самой продажи).
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final sql in _schema) {
          batch.execute(sql);
        }
        for (final list in _migrations.values) {
          for (final sql in list) {
            batch.execute(sql);
          }
        }
        await batch.commit(noResult: true);
      },
      // Обновление базы у тех, кто уже ставил прошлую версию приложения.
      onUpgrade: (db, oldV, newV) async {
        for (var v = oldV + 1; v <= newV; v++) {
          for (final sql in _migrations[v] ?? <String>[]) {
            await db.execute(sql);
          }
        }
      },
    );
  }

  /// Изменения базы по версиям (номер версии → команды).
  static const Map<int, List<String>> _migrations = {
    2: [
      // Шаг 4: касса — оплаты долгов и возвраты привязаны к смене.
      'ALTER TABLE debt_payments ADD COLUMN shift_id TEXT',
      'ALTER TABLE returns ADD COLUMN shift_id TEXT',
      // Сколько денег вернули клиенту и как (наличные / Kaspi / уменьшить долг).
      'ALTER TABLE returns ADD COLUMN refund REAL NOT NULL DEFAULT 0',
      "ALTER TABLE returns ADD COLUMN refund_payment TEXT",
      'CREATE INDEX idx_sales_shift ON sales(shift_id)',
      'CREATE INDEX idx_sales_customer ON sales(customer_id)',
    ],
    3: [
      // Возврат товара в партию (при возврате «на склад»).
      '''CREATE TABLE return_batches (
        id TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        return_line_id TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        qty REAL NOT NULL
      )''',
      // Остаток партии СЧИТАЕТСЯ, а не хранится: пришло − продано + вернули на склад.
      // Так два телефона, продающие одновременно, не затрут остатки друг друга.
      '''CREATE VIEW batch_left AS
        SELECT b.id, b.product_id, b.received_at, b.updated_at, b.cost_price, b.qty_in,
          b.qty_in
          - COALESCE((SELECT SUM(x.qty) FROM sale_line_batches x
                      WHERE x.batch_id = b.id AND x.deleted = 0), 0)
          + COALESCE((SELECT SUM(r.qty) FROM return_batches r
                      WHERE r.batch_id = b.id AND r.deleted = 0), 0) AS qty_left
        FROM batches b WHERE b.deleted = 0''',
      'CREATE INDEX idx_slb_batch ON sale_line_batches(batch_id)',
      'CREATE INDEX idx_rb_batch ON return_batches(batch_id)',
      // Синхронизация: какие файлы с Google Диска уже применены, какие фото выгружены.
      'CREATE TABLE sync_applied (file_name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)',
      'CREATE TABLE sync_photos (file_name TEXT PRIMARY KEY, uploaded_at INTEGER NOT NULL)',
      'CREATE INDEX idx_debtpay_sale ON debt_payments(sale_id)',
      'CREATE INDEX idx_returns_sale ON returns(sale_id)',
    ],
    4: [
      // Роль «Администратор» и PIN из 6 цифр: пересоздаём таблицу сотрудников без
      // старого ограничения ролей; pin_len — длина PIN (у старых 4, у новых 6).
      '''CREATE TABLE employees_v4 (
        id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        pin_salt TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        pin_len INTEGER NOT NULL DEFAULT 4
      )''',
      '''INSERT INTO employees_v4 (id, updated_at, device_id, deleted, name, role, pin_hash, pin_salt, active)
        SELECT id, updated_at, device_id, deleted, name, role, pin_hash, pin_salt, active FROM employees''',
      'DROP TABLE employees',
      'ALTER TABLE employees_v4 RENAME TO employees',
      // Смешанная оплата: сколько наличными и сколько Kaspi в каждой продаже.
      '''CREATE TABLE sales_v4 (
        id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        sale_date INTEGER NOT NULL,
        shift_id TEXT,
        cashier_id TEXT NOT NULL,
        payment TEXT NOT NULL,
        customer_id TEXT,
        due_date INTEGER,
        comment TEXT,
        total REAL NOT NULL DEFAULT 0,
        cost_total REAL NOT NULL DEFAULT 0,
        paid_cash REAL NOT NULL DEFAULT 0,
        paid_kaspi REAL NOT NULL DEFAULT 0
      )''',
      '''INSERT INTO sales_v4 (id, updated_at, device_id, deleted, sale_date, shift_id, cashier_id,
          payment, customer_id, due_date, comment, total, cost_total, paid_cash, paid_kaspi)
        SELECT id, updated_at, device_id, deleted, sale_date, shift_id, cashier_id,
          payment, customer_id, due_date, comment, total, cost_total,
          CASE WHEN payment = 'cash' THEN total ELSE 0 END,
          CASE WHEN payment = 'kaspi' THEN total ELSE 0 END
        FROM sales''',
      'DROP TABLE sales',
      'ALTER TABLE sales_v4 RENAME TO sales',
      'CREATE INDEX idx_sales_date ON sales(sale_date)',
      'CREATE INDEX idx_sales_shift ON sales(shift_id)',
      'CREATE INDEX idx_sales_customer ON sales(customer_id)',
      // Настройки магазина (код восстановления PIN, время синхронизации телефонов).
      '''CREATE TABLE settings (
        id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        value TEXT
      )''',
      // Журнал входов (для администратора, хранится 2 месяца).
      '''CREATE TABLE access_log (
        id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        at INTEGER NOT NULL,
        employee_id TEXT,
        employee_name TEXT,
        role TEXT,
        event TEXT NOT NULL,
        ip TEXT,
        device_name TEXT
      )''',
      'CREATE INDEX idx_access_at ON access_log(at)',
    ],
    5: [
      // Долги перед поставщиками: сколько оплачено при поступлении и до какого числа оплатить остаток.
      // paid = NULL у старых документов — значит оплачено полностью.
      'ALTER TABLE receipts ADD COLUMN paid REAL',
      'ALTER TABLE receipts ADD COLUMN due_date INTEGER',
      // Оплаты поставщикам (гасят долг, начиная с самых старых поступлений).
      '''CREATE TABLE supplier_payments (
        id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        supplier_id TEXT NOT NULL,
        paid_at INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        comment TEXT
      )''',
      'CREATE INDEX idx_suppay_supplier ON supplier_payments(supplier_id)',
      'CREATE INDEX idx_receipts_supplier ON receipts(supplier_id)',
    ],
    6: [
      // Начальные остатки: opening = 1 — начальный долг покупателя (sales), начальный долг
      // поставщику или начальный остаток склада (receipts). В выручку и поступления не входят.
      'ALTER TABLE sales ADD COLUMN opening INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE receipts ADD COLUMN opening INTEGER NOT NULL DEFAULT 0',
    ],
    7: [
      // Группы (папки) товаров, минимальный остаток и отключение товара.
      '''CREATE TABLE categories (
        id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, device_id TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        sort INTEGER NOT NULL DEFAULT 0
      )''',
      'ALTER TABLE products ADD COLUMN category_id TEXT',
      'ALTER TABLE products ADD COLUMN min_stock REAL NOT NULL DEFAULT 0',
      'ALTER TABLE products ADD COLUMN active INTEGER NOT NULL DEFAULT 1',
    ],
  };

  /// Таблицы с данными, которые синхронизируются между телефонами.
  static const syncTables = [
    'employees', 'products', 'product_photos', 'suppliers', 'receipts', 'receipt_lines',
    'batches', 'shifts', 'customers', 'sales', 'sale_lines', 'sale_line_batches',
    'debt_payments', 'cash_ops', 'returns', 'return_lines', 'return_batches',
    'settings', 'access_log', 'supplier_payments', 'categories',
  ];

  /// Общие служебные поля (вставляются в каждую таблицу).
  static const _sync = '''
    id TEXT PRIMARY KEY,
    updated_at INTEGER NOT NULL,
    device_id TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0''';

  static const List<String> _schema = [
    // ---------- Сотрудники (хозяин / кассир) ----------
    '''CREATE TABLE employees (
      $_sync,
      name TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('owner','cashier')),
      pin_hash TEXT NOT NULL,
      pin_salt TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1
    )''',

    // ---------- Товары (номенклатура) ----------
    '''CREATE TABLE products (
      $_sync,
      name TEXT NOT NULL,
      barcode TEXT,
      unit TEXT NOT NULL DEFAULT 'шт',
      sale_price REAL NOT NULL DEFAULT 0,
      comment TEXT
    )''',
    'CREATE INDEX idx_products_barcode ON products(barcode)',
    'CREATE INDEX idx_products_name ON products(name)',

    // Фото товара: несколько штук, каждое сжато до 200 КБ, сам файл
    // лежит отдельно (в папке приложения и на Google Диске), здесь — только имя.
    '''CREATE TABLE product_photos (
      $_sync,
      product_id TEXT NOT NULL REFERENCES products(id),
      file_name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )''',

    // ---------- Поставщики ----------
    '''CREATE TABLE suppliers (
      $_sync,
      name TEXT NOT NULL,
      phone TEXT,
      address TEXT
    )''',

    // ---------- Поступление товара ----------
    '''CREATE TABLE receipts (
      $_sync,
      doc_date INTEGER NOT NULL,
      supplier_id TEXT REFERENCES suppliers(id),
      comment TEXT,
      author_id TEXT NOT NULL REFERENCES employees(id),
      device_name TEXT,
      total REAL NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE receipt_lines (
      $_sync,
      receipt_id TEXT NOT NULL REFERENCES receipts(id),
      product_id TEXT NOT NULL REFERENCES products(id),
      qty REAL NOT NULL,
      price REAL NOT NULL,
      sum REAL NOT NULL
    )''',

    // Партии для ФИФО: каждая строка поступления = партия со своей ценой.
    // qty_left уменьшается при продаже (сначала самая старая партия).
    '''CREATE TABLE batches (
      $_sync,
      product_id TEXT NOT NULL REFERENCES products(id),
      receipt_line_id TEXT REFERENCES receipt_lines(id),
      received_at INTEGER NOT NULL,
      cost_price REAL NOT NULL,
      qty_in REAL NOT NULL,
      qty_left REAL NOT NULL
    )''',
    'CREATE INDEX idx_batches_fifo ON batches(product_id, received_at)',

    // ---------- Кассовые смены ----------
    '''CREATE TABLE shifts (
      $_sync,
      opened_by TEXT NOT NULL REFERENCES employees(id),
      opened_at INTEGER NOT NULL,
      cash_start REAL NOT NULL DEFAULT 0,
      closed_by TEXT REFERENCES employees(id),
      closed_at INTEGER,
      cash_end REAL
    )''',

    // ---------- Покупатели (для продажи в долг) ----------
    '''CREATE TABLE customers (
      $_sync,
      name TEXT NOT NULL,
      phone TEXT
    )''',

    // ---------- Продажи ----------
    '''CREATE TABLE sales (
      $_sync,
      sale_date INTEGER NOT NULL,
      shift_id TEXT REFERENCES shifts(id),
      cashier_id TEXT NOT NULL REFERENCES employees(id),
      payment TEXT NOT NULL CHECK (payment IN ('cash','kaspi','debt')),
      customer_id TEXT REFERENCES customers(id),
      due_date INTEGER,
      comment TEXT,
      total REAL NOT NULL DEFAULT 0,
      cost_total REAL NOT NULL DEFAULT 0
    )''',
    'CREATE INDEX idx_sales_date ON sales(sale_date)',
    '''CREATE TABLE sale_lines (
      $_sync,
      sale_id TEXT NOT NULL REFERENCES sales(id),
      product_id TEXT NOT NULL REFERENCES products(id),
      qty REAL NOT NULL,
      price REAL NOT NULL,
      sum REAL NOT NULL,
      cost REAL NOT NULL DEFAULT 0
    )''',
    // Из каких партий списан товар (нужно для точной прибыли и возврата).
    '''CREATE TABLE sale_line_batches (
      $_sync,
      sale_line_id TEXT NOT NULL REFERENCES sale_lines(id),
      batch_id TEXT NOT NULL REFERENCES batches(id),
      qty REAL NOT NULL,
      cost_price REAL NOT NULL
    )''',

    // ---------- Долги: оплаты по продажам в долг ----------
    '''CREATE TABLE debt_payments (
      $_sync,
      sale_id TEXT NOT NULL REFERENCES sales(id),
      paid_at INTEGER NOT NULL,
      amount REAL NOT NULL,
      payment TEXT NOT NULL CHECK (payment IN ('cash','kaspi')),
      employee_id TEXT NOT NULL REFERENCES employees(id)
    )''',

    // ---------- Приход / расход денег из кассы ----------
    '''CREATE TABLE cash_ops (
      $_sync,
      op_date INTEGER NOT NULL,
      shift_id TEXT REFERENCES shifts(id),
      kind TEXT NOT NULL CHECK (kind IN ('in','out')),
      amount REAL NOT NULL,
      counterparty TEXT,
      comment TEXT,
      author_id TEXT NOT NULL REFERENCES employees(id)
    )''',

    // ---------- Возвраты ----------
    // Кассир создаёт (status = 'pending'), хозяин подтверждает.
    // return_type: 'to_stock' — новый товар, возвращается на склад;
    //              'defect'   — брак/испорчен, на склад для продажи не идёт.
    '''CREATE TABLE returns (
      $_sync,
      sale_id TEXT NOT NULL REFERENCES sales(id),
      created_by TEXT NOT NULL REFERENCES employees(id),
      created_at INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
      return_type TEXT CHECK (return_type IN ('to_stock','defect')),
      approved_by TEXT REFERENCES employees(id),
      approved_at INTEGER,
      comment TEXT,
      total REAL NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE return_lines (
      $_sync,
      return_id TEXT NOT NULL REFERENCES returns(id),
      sale_line_id TEXT NOT NULL REFERENCES sale_lines(id),
      qty REAL NOT NULL,
      sum REAL NOT NULL
    )''',

    // ---------- Журнал изменений для синхронизации ----------
    // Каждое изменение записывается сюда; потом отправляется на Google Диск.
    '''CREATE TABLE sync_outbox (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      row_id TEXT NOT NULL,
      changed_at INTEGER NOT NULL,
      sent INTEGER NOT NULL DEFAULT 0
    )''',
  ];
}
