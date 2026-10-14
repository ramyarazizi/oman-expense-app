// ============================================================================
// سامانه جامع مدیریت تنخواه و هزینه‌های عمان (نسخه چندپلتفرمی و ابری)
// قابل اجرا روی ۳ پلتفرم: اندروید (.apk)، ویندوز (.exe - ویندوز 8/10/11) و آیفون (iOS)
// دارای ۲ سطح دسترسی مجزا:
//   ۱. نسخه مادر (مدیر - شما): ثبت، ویرایش، حذف و ارسال به اینترنت (محافظت‌شده با رمز مادر)
//   ۲. نسخه مشاهده‌گر و واحد مالی (فقط رویت): بدون امکان دخل و تصرف در اعداد + گزارش‌گیری
//      در هر بازه تاریخی دلخواه (۷ روزه، ۱۰ روزه، ۱۵ روزه، از تاریخ تا تاریخ) و خروجی مالی
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const OmanEnterpriseExpenseApp());
}

class OmanEnterpriseExpenseApp extends StatelessWidget {
  const OmanEnterpriseExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سامانه تنخواه و هزینه‌های عمان (نسخه مادر و واحد مالی)',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F766E),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const EnterpriseHomePage(),
    );
  }
}

enum TxMode { expense, deposit }
enum ExpenseSource { petty, pocket, personal }

class CustomFilterDef {
  final String id;
  final String name;
  final List<String> options;

  CustomFilterDef({
    required this.id,
    required this.name,
    required this.options,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'options': options,
      };

  factory CustomFilterDef.fromJson(Map<String, dynamic> j) => CustomFilterDef(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        options: (j['options'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      );
}

class TransactionRecord {
  final String id;
  final TxMode mode;
  final ExpenseSource source;
  final double amountOMR;
  final DateTime date;
  final String topic;
  final String category;
  final String title;
  final String note;
  final Map<String, String> customValues;

  TransactionRecord({
    required this.id,
    required this.mode,
    required this.source,
    required this.amountOMR,
    required this.date,
    required this.topic,
    required this.category,
    required this.title,
    this.note = '',
    this.customValues = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode.name,
        'source': source.name,
        'amountOMR': amountOMR,
        'date': date.toIso8601String(),
        'topic': topic,
        'category': category,
        'title': title,
        'note': note,
        'customValues': customValues,
      };

  factory TransactionRecord.fromJson(Map<String, dynamic> j) {
    return TransactionRecord(
      id: j['id']?.toString() ?? '',
      mode: j['mode'] == 'deposit' ? TxMode.deposit : TxMode.expense,
      source: ExpenseSource.values.firstWhere(
        (e) => e.name == j['source'],
        orElse: () => ExpenseSource.petty,
      ),
      amountOMR: (j['amountOMR'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
      topic: j['topic']?.toString() ?? '',
      category: j['category']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      note: j['note']?.toString() ?? '',
      customValues: (j['customValues'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

class EnterpriseHomePage extends StatefulWidget {
  const EnterpriseHomePage({super.key});

  @override
  State<EnterpriseHomePage> createState() => _EnterpriseHomePageState();
}

class _EnterpriseHomePageState extends State<EnterpriseHomePage> {
  int _selectedIndex = 0;

  // ==========================================================================
  // مدیریت نقش دستگاه (نسخه مادر با دسترسی کامل در برابر نسخه مشاهده‌گر/واحد مالی)
  // ==========================================================================
  bool _isMasterAdmin = false; // به صورت پیش‌فرض در حالت امن «فقط مشاهده» باز می‌شود تا نسخه‌های دیگر نتوانند دستکاری کنند
  String _masterPin = '1234'; // رمز نسخه مادر (قابل تغییر توسط شما)

  // تنظیمات همگام‌سازی ابری (Cloud Sync URL)
  String _cloudSyncUrl = '';
  bool _isSyncing = false;
  String _lastSyncStatus = 'آماده اتصال ابری';

  // تنظیمات ارز دوم
  String _secCurrency = 'تومان';
  double _exchangeRate = 165000;

  // سرفصل‌های هزینه کرد
  List<String> _categories = [
    'خورد و خوراک و اقلام مصرفی',
    'آب و برق و قبوض (برق، آب، اینترنت)',
    'اجاره مسکن و اقامت',
    'ایاب و ذهاب و تاکسی',
    'اجاره خودرو و بنزین',
    'امور اداری، ویزا و ثبت شرکت',
    'ارسال نمونه و لجستیک',
    'تجهیزات و ملزومات کاری',
    'سایر هزینه‌ها',
  ];

  // موضوعات (پروژه‌ها / مراکز هزینه)
  List<String> _topics = [
    'تنخواه جاری شرکت در عمان',
    'امور راه‌اندازی و ثبت شرکت/برند',
    'سفر کاری مسقط',
    'مخارج شخصی روزمره',
  ];

  // فیلترهای سفارشی داینامیک
  List<CustomFilterDef> _customFilters = [
    CustomFilterDef(
      id: 'cf_payment',
      name: 'روش پرداخت',
      options: ['نقدی (Cash OMR)', 'کارت بانک مسقط', 'حواله / موبایل بانک'],
    ),
    CustomFilterDef(
      id: 'cf_receipt',
      name: 'وضعیت فاکتور',
      options: ['دارای فاکتور رسمی', 'رسید عادی', 'بدون رسید'],
    ),
  ];

  List<TransactionRecord> _transactions = [];

  // کنترلرهای فرم ثبت/ویرایش (مخصوص نسخه مادر)
  String? _editingTxId;
  TxMode _formMode = TxMode.expense;
  ExpenseSource _formSource = ExpenseSource.petty;
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  late String _selectedTopic;
  late String _selectedCategory;
  final Map<String, String> _selectedCustomValues = {};

  // کنترلرهای فیلتر گزارش‌گیری پیشرفته (بدون محدودیت زمانی)
  DateTime? _repFromDate;
  DateTime? _repToDate;
  final TextEditingController _fromDateTextCtrl = TextEditingController();
  final TextEditingController _toDateTextCtrl = TextEditingController();
  String _repSourceFilter = 'all_records';
  String _repTopicFilter = 'all';
  String _repCategoryFilter = 'all';
  String _repSearchQuery = '';
  final Map<String, String> _repCustomFilterValues = {};

  @override
  void initState() {
    super.initState();
    _selectedTopic = _topics.first;
    _selectedCategory = _categories.first;
    _syncCustomDefaults();
    _loadLocalData();
  }

  File _getLocalDbFile() {
    final dir = Directory.systemTemp;
    return File('${dir.path}/oman_enterprise_expenses_db.json');
  }

  Future<void> _loadLocalData() async {
    try {
      final f = _getLocalDbFile();
      if (await f.exists()) {
        final content = await f.readAsString();
        _applyJsonState(jsonDecode(content), fromCloud: false);
      }
    } catch (_) {}
  }

  Future<void> _saveLocalData() async {
    try {
      final f = _getLocalDbFile();
      await f.writeAsString(jsonEncode(_exportFullStateJson()));
    } catch (_) {}
  }

  Map<String, dynamic> _exportFullStateJson() {
    return {
      'updatedAt': DateTime.now().toIso8601String(),
      'secCurrency': _secCurrency,
      'exchangeRate': _exchangeRate,
      'masterPin': _masterPin,
      'cloudSyncUrl': _cloudSyncUrl,
      'categories': _categories,
      'topics': _topics,
      'customFilters': _customFilters.map((e) => e.toJson()).toList(),
      'transactions': _transactions.map((e) => e.toJson()).toList(),
    };
  }

  void _applyJsonState(Map<String, dynamic> data, {required bool fromCloud}) {
    setState(() {
      if (data['secCurrency'] != null) _secCurrency = data['secCurrency'].toString();
      if (data['exchangeRate'] != null) {
        _exchangeRate = (data['exchangeRate'] as num).toDouble();
      }
      if (!fromCloud && data['masterPin'] != null) {
        _masterPin = data['masterPin'].toString();
      }
      if (!fromCloud && data['cloudSyncUrl'] != null) {
        _cloudSyncUrl = data['cloudSyncUrl'].toString();
      }
      if (data['categories'] is List) {
        final list = (data['categories'] as List).map((e) => e.toString()).toList();
        if (list.isNotEmpty) _categories = list;
      }
      if (data['topics'] is List) {
        final list = (data['topics'] as List).map((e) => e.toString()).toList();
        if (list.isNotEmpty) _topics = list;
      }
      if (data['customFilters'] is List) {
        _customFilters = (data['customFilters'] as List)
            .map((e) => CustomFilterDef.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (data['transactions'] is List) {
        _transactions = (data['transactions'] as List)
            .map((e) => TransactionRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (!_topics.contains(_selectedTopic)) _selectedTopic = _topics.first;
      if (!_categories.contains(_selectedCategory)) _selectedCategory = _categories.first;
      _syncCustomDefaults();
    });
  }

  // ==========================================================================
  // موتور همگام‌سازی ابری اینترنتی (Cloud Sync بین ۳ دستگاه)
  // ==========================================================================
  Future<void> _pushToCloud() async {
    if (!_isMasterAdmin) {
      _showMsg('فقط نسخه مادر (مدیر) اجازه ارسال و تغییر اطلاعات در فضای ابری را دارد.');
      return;
    }
    if (_cloudSyncUrl.trim().isEmpty) {
      _showMsg('لطفاً ابتدا در بخش تنظیمات ابری، آدرس پایگاه داده اینترنتی (Cloud URL) را وارد کنید.');
      return;
    }
    setState(() {
      _isSyncing = true;
      _lastSyncStatus = 'در حال ارسال به فضای ابری...';
    });

    try {
      final uri = Uri.parse(_cloudSyncUrl.trim());
      final client = HttpClient();
      final req = await client.putUrl(uri);
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      final payload = jsonEncode(_exportFullStateJson());
      req.add(utf8.encode(payload));
      final resp = await req.close();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() => _lastSyncStatus = '✅ همگام‌سازی ابری موفق (${_fmtTime(DateTime.now())})');
        _showMsg('✅ اطلاعات با موفقیت در اینترنت به‌روزرسانی شد و برای ۲ نسخه دیگر قابل رویت است.');
      } else {
        setState(() => _lastSyncStatus = 'خطا در ارسال (${resp.statusCode})');
      }
      client.close();
    } catch (e) {
      setState(() => _lastSyncStatus = 'خطا در اتصال به اینترنت');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _pullFromCloud() async {
    if (_cloudSyncUrl.trim().isEmpty) {
      _showMsg('لطفاً ابتدا آدرس همگام‌سازی ابری (Cloud URL) را در تنظیمات وارد کنید.');
      return;
    }
    setState(() {
      _isSyncing = true;
      _lastSyncStatus = 'در حال دریافت آخرین اطلاعات...';
    });

    try {
      final uri = Uri.parse(_cloudSyncUrl.trim());
      final client = HttpClient();
      final req = await client.getUrl(uri);
      req.headers.set('Accept', 'application/json');
      final resp = await req.close();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = await resp.transform(utf8.decoder).join();
        if (body.isNotEmpty && body != 'null') {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            _applyJsonState(decoded, fromCloud: true);
            await _saveLocalData();
            setState(() => _lastSyncStatus = '✅ دریافت موفق (${_fmtTime(DateTime.now())})');
            _showMsg('✅ آخرین اطلاعات ثبت‌شده توسط نسخه مادر دریافت شد.');
          }
        }
      } else {
        setState(() => _lastSyncStatus = 'خطا در دریافت (${resp.statusCode})');
      }
      client.close();
    } catch (e) {
      setState(() => _lastSyncStatus = 'خطا در اتصال به اینترنت');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  void _syncCustomDefaults() {
    for (final cf in _customFilters) {
      if (!_selectedCustomValues.containsKey(cf.id) && cf.options.isNotEmpty) {
        _selectedCustomValues[cf.id] = cf.options.first;
      }
      if (!_repCustomFilterValues.containsKey(cf.id)) {
        _repCustomFilterValues[cf.id] = 'all';
      }
    }
  }

  String _fmtOMR(double val) => val.toStringAsFixed(3);

  String _fmtSec(double omr) {
    final total = (omr * _exchangeRate).round();
    final str = total.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
    return '$str $_secCurrency';
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  double get _totalPettyIn => _transactions
      .where((t) => t.mode == TxMode.deposit)
      .fold(0.0, (s, t) => s + t.amountOMR);

  double get _totalPettyOut => _transactions
      .where((t) => t.mode == TxMode.expense && t.source == ExpenseSource.petty)
      .fold(0.0, (s, t) => s + t.amountOMR);

  double get _totalPocketOut => _transactions
      .where((t) => t.mode == TxMode.expense && t.source == ExpenseSource.pocket)
      .fold(0.0, (s, t) => s + t.amountOMR);

  double get _totalPersonalOut => _transactions
      .where((t) => t.mode == TxMode.expense && t.source == ExpenseSource.personal)
      .fold(0.0, (s, t) => s + t.amountOMR);

  double get _pettyBalance => _totalPettyIn - _totalPettyOut;

  // ==========================================================================
  // تغییر حالت بین «نسخه مادر (مدیر)» و «نسخه مشاهده‌گر / واحد مالی (فقط رویت)»
  // ==========================================================================
  void _showRoleSwitchDialog() {
    final pinCtrl = TextEditingController();
    final cloudCtrl = TextEditingController(text: _cloudSyncUrl);
    final newPinCtrl = TextEditingController(text: _masterPin);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isMasterAdmin
            ? '👑 تنظیمات نسخه مادر و همگام‌سازی ابری'
            : '🔒 ورود به نسخه مادر / تنظیم اتصال ابری'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isMasterAdmin ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _isMasterAdmin
                      ? 'وضعیت فعلی دستگاه: 👑 نسخه مادر (دسترسی کامل به ثبت، ویرایش و ارسال به اینترنت)'
                      : 'وضعیت فعلی دستگاه: 👁️ نسخه مشاهده‌گر و واحد مالی (فقط رویت و گزارش‌گیری — بدون امکان تغییر اعداد)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cloudCtrl,
                decoration: const InputDecoration(
                  labelText: 'آدرس اینترنتی پایگاه داده ابری (Cloud Sync URL)',
                  hintText: 'https://your-db.firebaseio.com/oman.json',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (!_isMasterAdmin) ...[
                const Text(
                  'اگر این دستگاه متعلق به شما (نسخه مادر) است، رمز مادر را وارد کنید تا قفل ثبت اطلاعات باز شود (رمز پیش‌فرض: 1234):',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'رمز نسخه مادر (Master PIN)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: newPinCtrl,
                  decoration: const InputDecoration(
                    labelText: 'تغییر رمز نسخه مادر',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_isMasterAdmin)
            TextButton(
              onPressed: () {
                setState(() {
                  _isMasterAdmin = false;
                  _cloudSyncUrl = cloudCtrl.text.trim();
                  if (newPinCtrl.text.trim().isNotEmpty) {
                    _masterPin = newPinCtrl.text.trim();
                  }
                  _selectedIndex = 0;
                });
                _saveLocalData();
                Navigator.pop(ctx);
                _showMsg('دستگاه به حالت «مشاهده‌گر (فقط رویت)» قفل شد.');
              },
              child: const Text('قفل کردن روی حالت مشاهده‌گر'),
            ),
          TextButton(
            onPressed: () {
              setState(() => _cloudSyncUrl = cloudCtrl.text.trim());
              _saveLocalData();
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره آدرس ابری و بستن'),
          ),
          if (!_isMasterAdmin)
            FilledButton(
              onPressed: () {
                setState(() => _cloudSyncUrl = cloudCtrl.text.trim());
                if (pinCtrl.text.trim() == _masterPin) {
                  setState(() => _isMasterAdmin = true);
                  _saveLocalData();
                  Navigator.pop(ctx);
                  _showMsg('👑 نسخه مادر فعال شد! اکنون می‌توانید اعداد و هزینه‌ها را ثبت و ویرایش کنید.');
                } else {
                  _saveLocalData();
                  Navigator.pop(ctx);
                  _showMsg('آدرس ابری ذخیره شد (حالت مشاهده‌گر بدون تغییر باقی ماند).');
                }
              },
              child: const Text('تایید و فعال‌سازی نسخه مادر'),
            ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ثبت و ویرایش تراکنش (فقط در نسخه مادر)
  // ==========================================================================
  void _saveTransaction() {
    if (!_isMasterAdmin) {
      _showMsg('این نسخه فقط برای مشاهده و گزارش‌گیری است و امکان ثبت یا تغییر اعداد را ندارد.');
      return;
    }
    final amt = double.tryParse(_amountCtrl.text.trim());
    final title = _titleCtrl.text.trim();
    if (amt == null || amt <= 0 || title.isEmpty) {
      _showMsg('لطفاً مبلغ معتبر (OMR) و شرح تراکنش را وارد کنید.');
      return;
    }

    final rec = TransactionRecord(
      id: _editingTxId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      mode: _formMode,
      source: _formSource,
      amountOMR: double.parse(amt.toStringAsFixed(3)),
      date: _selectedDate,
      topic: _selectedTopic,
      category: _formMode == TxMode.deposit ? 'دریافت تنخواه از شرکت' : _selectedCategory,
      title: title,
      note: _noteCtrl.text.trim(),
      customValues: Map<String, String>.from(_selectedCustomValues),
    );

    setState(() {
      if (_editingTxId != null) {
        final idx = _transactions.indexWhere((t) => t.id == _editingTxId);
        if (idx != -1) _transactions[idx] = rec;
        _editingTxId = null;
      } else {
        _transactions.insert(0, rec);
      }
      _amountCtrl.clear();
      _titleCtrl.clear();
      _noteCtrl.clear();
      _selectedIndex = 0;
    });

    _saveLocalData();
    if (_cloudSyncUrl.trim().isNotEmpty) {
      _pushToCloud();
    } else {
      _showMsg('✅ اطلاعات در نسخه مادر ذخیره شد.');
    }
  }

  void _startEditTransaction(TransactionRecord t) {
    if (!_isMasterAdmin) return;
    setState(() {
      _editingTxId = t.id;
      _formMode = t.mode;
      _formSource = t.source;
      _amountCtrl.text = t.amountOMR.toStringAsFixed(3);
      _selectedDate = t.date;
      if (_topics.contains(t.topic)) _selectedTopic = t.topic;
      if (t.mode == TxMode.expense && _categories.contains(t.category)) {
        _selectedCategory = t.category;
      }
      _titleCtrl.text = t.title;
      _noteCtrl.text = t.note;
      t.customValues.forEach((k, v) => _selectedCustomValues[k] = v);
      _selectedIndex = 1; // رفتن به تب ثبت/ویرایش
    });
  }

  void _deleteTransaction(String id) {
    if (!_isMasterAdmin) return;
    setState(() {
      _transactions.removeWhere((t) => t.id == id);
    });
    _saveLocalData();
    if (_cloudSyncUrl.trim().isNotEmpty) _pushToCloud();
    _showMsg('تراکنش حذف شد.');
  }

  // ==========================================================================
  // فیلتر بازه زمانی بدون محدودیت (۷ روزه، ۱۰ روزه، ۱۵ روزه، ۳۰ روزه و دلخواه)
  // ==========================================================================
  void _setQuickDaysRange(int? days) {
    setState(() {
      if (days == null) {
        _repFromDate = null;
        _repToDate = null;
        _fromDateTextCtrl.clear();
        _toDateTextCtrl.clear();
      } else {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final start = today.subtract(Duration(days: days - 1));
        _repFromDate = start;
        _repToDate = today;
        _fromDateTextCtrl.text = _fmtDate(start);
        _toDateTextCtrl.text = _fmtDate(today);
      }
    });
  }

  void _applyTypedDates() {
    setState(() {
      final f = DateTime.tryParse(_fromDateTextCtrl.text.trim());
      final t = DateTime.tryParse(_toDateTextCtrl.text.trim());
      _repFromDate = f;
      _repToDate = t;
    });
  }

  List<TransactionRecord> _getFilteredReportList() {
    final list = _transactions.where((t) {
      if (_repFromDate != null) {
        final dStart = DateTime(_repFromDate!.year, _repFromDate!.month, _repFromDate!.day);
        if (t.date.isBefore(dStart)) return false;
      }
      if (_repToDate != null) {
        final dEnd = DateTime(_repToDate!.year, _repToDate!.month, _repToDate!.day, 23, 59, 59);
        if (t.date.isAfter(dEnd)) return false;
      }

      if (_repSourceFilter == 'all_expenses' && t.mode != TxMode.expense) return false;
      if (_repSourceFilter == 'company_all' &&
          !(t.mode == TxMode.expense &&
              (t.source == ExpenseSource.petty || t.source == ExpenseSource.pocket))) {
        return false;
      }
      if (_repSourceFilter == 'petty' &&
          !(t.mode == TxMode.expense && t.source == ExpenseSource.petty)) {
        return false;
      }
      if (_repSourceFilter == 'pocket' &&
          !(t.mode == TxMode.expense && t.source == ExpenseSource.pocket)) {
        return false;
      }
      if (_repSourceFilter == 'personal' &&
          !(t.mode == TxMode.expense && t.source == ExpenseSource.personal)) {
        return false;
      }
      if (_repSourceFilter == 'deposits' && t.mode != TxMode.deposit) return false;

      if (_repTopicFilter != 'all' && t.topic != _repTopicFilter) return false;
      if (_repCategoryFilter != 'all' && t.category != _repCategoryFilter) return false;

      if (_repSearchQuery.isNotEmpty) {
        final q = _repSearchQuery.toLowerCase();
        final hay = '${t.title} ${t.note} ${t.topic} ${t.category}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }

      for (final cf in _customFilters) {
        final selectedOpt = _repCustomFilterValues[cf.id] ?? 'all';
        if (selectedOpt != 'all') {
          if ((t.customValues[cf.id] ?? '') != selectedOpt) return false;
        }
      }

      return true;
    }).toList();

    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // ==========================================================================
  // خروجی‌های تخصصی واحد مالی (CSV استاندارد حسابداری + کپی مستقیم Excel TSV)
  // ==========================================================================
  String _buildAccountingCSV({required String separator}) {
    final list = _getFilteredReportList();
    final cfNames = _customFilters.map((e) => e.name).toList();
    final headers = [
      'ردیف',
      'تاریخ',
      'کد سند',
      'نوع حساب',
      'مرکز هزینه (موضوع)',
      'سرفصل حسابداری',
      'شرح آرتیکل',
      'بدهکار - هزینه (OMR)',
      'بستانکار - دریافت تنخواه (OMR)',
      'معادل ($_secCurrency)',
      ...cfNames,
      'یادداشت / شماره رسید',
    ];

    final rows = <String>[headers.join(separator)];
    for (int i = 0; i < list.length; i++) {
      final t = list[i];
      final typeLabel = t.mode == TxMode.deposit
          ? 'دریافت تنخواه'
          : (t.source == ExpenseSource.petty
              ? 'هزینه از تنخواه شرکت'
              : (t.source == ExpenseSource.pocket ? 'پرداخت از جیب (بستانکار)' : 'هزینه شخصی'));
      final debit = t.mode == TxMode.expense ? _fmtOMR(t.amountOMR) : '0.000';
      final credit = t.mode == TxMode.deposit ? _fmtOMR(t.amountOMR) : '0.000';
      final secVal = (t.amountOMR * _exchangeRate).round().toString();
      final cfVals = _customFilters.map((cf) => (t.customValues[cf.id] ?? '').replaceAll(separator, ' ')).toList();

      rows.add([
        (i + 1).toString(),
        _fmtDate(t.date),
        t.id,
        typeLabel,
        t.topic.replaceAll(separator, ' '),
        t.category.replaceAll(separator, ' '),
        t.title.replaceAll(separator, ' '),
        debit,
        credit,
        secVal,
        ...cfVals,
        t.note.replaceAll(separator, ' '),
      ].join(separator));
    }
    return rows.join('\n');
  }

  void _copyExcelTSVForFinance() {
    final list = _getFilteredReportList();
    if (list.isEmpty) {
      _showMsg('هیچ رکوردی در بازه انتخابی برای خروجی واحد مالی وجود ندارد.');
      return;
    }
    final tsv = _buildAccountingCSV(separator: '\t');
    Clipboard.setData(ClipboardData(text: tsv));
    _showMsg('✅ جدول استاندارد حسابداری کپی شد! واحد مالی می‌تواند مستقیماً در Excel یا نرم‌افزار مالی Paste (Ctrl+V) کند.');
  }

  Future<void> _saveCSVFileForFinance() async {
    final list = _getFilteredReportList();
    if (list.isEmpty) {
      _showMsg('هیچ رکوردی در بازه انتخابی وجود ندارد.');
      return;
    }
    try {
      final csv = '\uFEFF${_buildAccountingCSV(separator: ',')}';
      final dir = Directory.current;
      final fileName = 'Oman_Finance_Report_${_fmtDate(DateTime.now())}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv, encoding: utf8);
      _showMsg('✅ فایل اکسل واحد مالی با نام $fileName در پوشه برنامه ذخیره شد.');
    } catch (e) {
      // در صورتی که روی موبایل دسترسی پوشه جاری محدود باشد، در کلیپ‌بورد کپی می‌شود
      final csv = _buildAccountingCSV(separator: ',');
      Clipboard.setData(ClipboardData(text: csv));
      _showMsg('✅ محتوای فایل CSV حسابداری در حافظه کپی شد.');
    }
  }

  void _copyFormattedSummaryReport() {
    final list = _getFilteredReportList();
    if (list.isEmpty) {
      _showMsg('موردی در این بازه زمانی یافت نشد.');
      return;
    }

    final Map<String, double> byCat = {};
    double sumExp = 0;
    double sumDep = 0;
    for (final t in list) {
      if (t.mode == TxMode.deposit) {
        sumDep += t.amountOMR;
      } else {
        sumExp += t.amountOMR;
        byCat[t.category] = (byCat[t.category] ?? 0) + t.amountOMR;
      }
    }

    final fromStr = _repFromDate != null ? _fmtDate(_repFromDate!) : 'ابتدای دوره';
    final toStr = _repToDate != null ? _fmtDate(_repToDate!) : 'امروز';

    final sb = StringBuffer();
    sb.writeln('📊 گزارش رسمی صورت‌وضعیت تنخواه و هزینه‌های عمان');
    sb.writeln('📅 بازه گزارش: از $fromStr تا $toStr');
    sb.writeln('──────────────────────');
    sb.writeln('💰 جمع تنخواه دریافتی در این بازه: ${_fmtOMR(sumDep)} OMR');
    sb.writeln('💸 جمع هزینه‌های انجام‌شده در این بازه: ${_fmtOMR(sumExp)} OMR (${_fmtSec(sumExp)})');
    sb.writeln('📌 مانده کل تنخواه فعلی: ${_fmtOMR(_pettyBalance)} OMR');
    sb.writeln('──────────────────────');
    sb.writeln('📂 تفکیک بر اساس سرفصل‌های هزینه کرد:');
    byCat.forEach((cat, amt) {
      sb.writeln('• $cat: ${_fmtOMR(amt)} OMR');
    });
    sb.writeln('──────────────────────');
    sb.writeln('📋 ریز هزینه‌ها به تفکیک تاریخ:');
    for (final t in list) {
      final sign = t.mode == TxMode.deposit ? '+' : '-';
      sb.writeln('▫️ [${_fmtDate(t.date)}] ${t.title} | ${t.category} | ${t.topic} : $sign${_fmtOMR(t.amountOMR)} OMR');
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));
    _showMsg('✅ گزارش کامل صورت‌وضعیت کپی شد.');
  }

  @override
  Widget build(BuildContext context) {
    // اگر نسخه مشاهده‌گر (واحد مالی / ویندوز) باشد، فقط ۲ تب «پیشخوان» و «گزارش‌گیری مالی» نمایش داده می‌شود
    // اگر نسخه مادر (شما) باشد، هر ۴ تب (شامل ثبت تراکنش و مدیریت سرفصل/فیلترها) فعال است!
    final tabs = <Widget>[
      _buildDashboardTab(),
      if (_isMasterAdmin) _buildAddTransactionTab(),
      _buildReportsTab(),
      if (_isMasterAdmin) _buildCustomizeTab(),
    ];

    final navDestinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'پیشخوان و تنخواه'),
      if (_isMasterAdmin)
        const NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'ثبت / ویرایش (مادر)'),
      const NavigationDestination(icon: Icon(Icons.assessment_outlined), label: 'گزارش‌گیری و مالی'),
      if (_isMasterAdmin)
        const NavigationDestination(icon: Icon(Icons.tune_outlined), label: 'سرفصل و فیلترها'),
    ];

    if (_selectedIndex >= tabs.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _isMasterAdmin ? const Color(0xFF0F766E) : const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isMasterAdmin
                  ? '👑 سامانه تنخواه عمان (نسخه مادر - دسترسی کامل)'
                  : '👁️ سامانه تنخواه عمان (نسخه مشاهده‌گر و واحد مالی)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              _lastSyncStatus,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'دریافت آخرین اطلاعات از اینترنت',
            onPressed: _isSyncing ? null : _pullFromCloud,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          if (_isMasterAdmin)
            IconButton(
              tooltip: 'ارسال اطلاعات نسخه مادر به اینترنت',
              onPressed: _isSyncing ? null : _pushToCloud,
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: _showRoleSwitchDialog,
            icon: Icon(_isMasterAdmin ? Icons.lock_open : Icons.lock_outline, size: 18),
            label: Text(_isMasterAdmin ? 'نسخه مادر' : 'فقط رویت'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildHeaderStat('کل تنخواه دریافتی', '${_fmtOMR(_totalPettyIn)} OMR'),
                _buildHeaderStat('خرج‌شده از تنخواه', '${_fmtOMR(_totalPettyOut)} OMR'),
                _buildHeaderStat(
                  _pettyBalance >= 0 ? 'مانده تنخواه' : 'طلب از شرکت',
                  '${_fmtOMR(_pettyBalance.abs())} OMR',
                ),
              ],
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: tabs[_selectedIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: navDestinations,
      ),
    );
  }

  Widget _buildHeaderStat(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  // ==========================================================================
  // تب ۱: پیشخوان و خلاصه وضعیت
  // ==========================================================================
  Widget _buildDashboardTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (!_isMasterAdmin)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF0284C7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF0369A1)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'این دستگاه در حالت «مشاهده‌گر و گزارش‌گیری (بدون امکان دخل و تصرف)» قرار دارد. برای دریافت آخرین اعداد واردشده توسط نسخه مادر، دکمه ابر (🔄) بالای صفحه را بزنید.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF0C4A6E)),
                  ),
                ),
                TextButton(
                  onPressed: _showRoleSwitchDialog,
                  child: const Text('ورود رمز مادر'),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'هزینه از تنخواه شرکت',
                '${_fmtOMR(_totalPettyOut)} OMR',
                _fmtSec(_totalPettyOut),
                const Color(0xFF0369A1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                'پرداخت از جیب برای کار',
                '${_fmtOMR(_totalPocketOut)} OMR',
                'طلب از شرکت: ${_fmtSec(_totalPocketOut)}',
                const Color(0xFFB45309),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'هزینه‌های شخصی',
                '${_fmtOMR(_totalPersonalOut)} OMR',
                _fmtSec(_totalPersonalOut),
                const Color(0xFF6D28D9),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                'خالص تراز با شرکت',
                '${_fmtOMR((_totalPettyIn - (_totalPettyOut + _totalPocketOut)).abs())} OMR',
                (_totalPettyIn - (_totalPettyOut + _totalPocketOut)) >= 0
                    ? 'مانده تنخواه نزد شما'
                    : 'بستانکار از شرکت',
                const Color(0xFF15803D),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'آخرین تراکنش‌های ثبت‌شده',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _selectedIndex = _isMasterAdmin ? 2 : 1);
                      },
                      icon: const Icon(Icons.filter_alt_outlined, size: 18),
                      label: const Text('گزارش‌گیری پیشرفته و بازه تاریخی'),
                    ),
                  ],
                ),
                const Divider(),
                if (_transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Text('هنوز اطلاعاتی ثبت نشده است.'),
                    ),
                  )
                else
                  ..._transactions.take(15).map((t) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '📅 ${_fmtDate(t.date)}  |  🏷️ ${t.topic}  |  📂 ${t.category}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${t.mode == TxMode.deposit ? '+' : ''}${_fmtOMR(t.amountOMR)} OMR',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: t.mode == TxMode.deposit
                                        ? Colors.green[700]
                                        : Colors.black87,
                                  ),
                                ),
                                Text(
                                  _fmtSec(t.amountOMR),
                                  style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                                ),
                              ],
                            ),
                            if (_isMasterAdmin) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _startEditTransaction(t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                onPressed: () => _deleteTransaction(t.id),
                              ),
                            ],
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, String sub, Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(right: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      ),
    );
  }

  // ==========================================================================
  // تب ۲: ثبت و ویرایش تراکنش (فقط برای نسخه مادر فعال است)
  // ==========================================================================
  Widget _buildAddTransactionTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _editingTxId == null ? '➕ ثبت تراکنش جدید (نسخه مادر)' : '✏️ ویرایش تراکنش',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    if (_editingTxId != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _editingTxId = null;
                          _amountCtrl.clear();
                          _titleCtrl.clear();
                          _noteCtrl.clear();
                        }),
                        child: const Text('انصراف از ویرایش'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<TxMode>(
                  segments: const [
                    ButtonSegment(value: TxMode.expense, label: Text('💸 ثبت هزینه کرد')),
                    ButtonSegment(value: TxMode.deposit, label: Text('💰 دریافت تنخواه از شرکت')),
                  ],
                  selected: {_formMode},
                  onSelectionChanged: (s) => setState(() => _formMode = s.first),
                ),
                const SizedBox(height: 12),
                if (_formMode == TxMode.expense) ...[
                  const Text('محل پرداخت هزینه:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SegmentedButton<ExpenseSource>(
                    segments: const [
                      ButtonSegment(value: ExpenseSource.petty, label: Text('از تنخواه شرکت')),
                      ButtonSegment(value: ExpenseSource.pocket, label: Text('از جیب برای کار')),
                      ButtonSegment(value: ExpenseSource.personal, label: Text('هزینه شخصی')),
                    ],
                    selected: {_formSource},
                    onSelectionChanged: (s) => setState(() => _formSource = s.first),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'مبلغ به ریال عمان (OMR - سه رقم اعشار)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) setState(() => _selectedDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_fmtDate(_selectedDate)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedTopic,
                  items: _topics.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _selectedTopic = v!),
                  decoration: const InputDecoration(
                    labelText: 'موضوع (پروژه / مرکز هزینه)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (_formMode == TxMode.expense) ...[
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => _selectedCategory = v!),
                    decoration: const InputDecoration(
                      labelText: 'سرفصل هزینه کرد (خورد و خوراک، آب و برق، اجاره و...)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'شرح دقیق تراکنش',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ..._customFilters.map((cf) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        value: _selectedCustomValues[cf.id],
                        items: cf.options
                            .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedCustomValues[cf.id] = v!),
                        decoration: InputDecoration(
                          labelText: cf.name,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    )),
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'یادداشت / شماره فاکتور یا طرف حساب (اختیاری)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _saveTransaction,
                  icon: const Icon(Icons.cloud_done_outlined),
                  label: Text(_editingTxId == null
                      ? 'ذخیره در نسخه مادر و همگام‌سازی ابری'
                      : 'ثبت تغییرات و به‌روزرسانی ابری'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // تب ۳: گزارش‌گیری پیشرفته بدون محدودیت تاریخی + خروجی مخصوص واحد مالی
  // ==========================================================================
  Widget _buildReportsTab() {
    final filtered = _getFilteredReportList();
    final Map<String, double> byCat = {};
    final Map<String, double> byTopic = {};
    double sumExpense = 0;
    double sumDeposit = 0;

    for (final t in filtered) {
      if (t.mode == TxMode.deposit) {
        sumDeposit += t.amountOMR;
      } else {
        sumExpense += t.amountOMR;
        byCat[t.category] = (byCat[t.category] ?? 0) + t.amountOMR;
        byTopic[t.topic] = (byTopic[t.topic] ?? 0) + t.amountOMR;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '📅 ۱. انتخاب بازه تاریخی بدون محدودیت (۷ روزه، ۱۰ روزه، ۱۵ روزه یا تاریخ شروع تا پایان)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(label: const Text('کل دوره'), onPressed: () => _setQuickDaysRange(null)),
                    ActionChip(label: const Text('امروز'), onPressed: () => _setQuickDaysRange(1)),
                    ActionChip(label: const Text('۷ روزه (یک هفته)'), onPressed: () => _setQuickDaysRange(7)),
                    ActionChip(label: const Text('۱۰ روزه'), onPressed: () => _setQuickDaysRange(10)),
                    ActionChip(label: const Text('۱۵ روزه'), onPressed: () => _setQuickDaysRange(15)),
                    ActionChip(label: const Text('۳۰ روزه (یک ماه)'), onPressed: () => _setQuickDaysRange(30)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _fromDateTextCtrl,
                        decoration: InputDecoration(
                          labelText: 'از تاریخ شروع (YYYY-MM-DD)',
                          hintText: 'مثلاً 2026-10-01',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_month),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _repFromDate ?? DateTime.now(),
                                firstDate: DateTime(2015),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setState(() {
                                  _repFromDate = picked;
                                  _fromDateTextCtrl.text = _fmtDate(picked);
                                });
                              }
                            },
                          ),
                        ),
                        onChanged: (_) => _applyTypedDates(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _toDateTextCtrl,
                        decoration: InputDecoration(
                          labelText: 'تا تاریخ پایان (YYYY-MM-DD)',
                          hintText: 'مثلاً 2026-10-15',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_month),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _repToDate ?? DateTime.now(),
                                firstDate: DateTime(2015),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setState(() {
                                  _repToDate = picked;
                                  _toDateTextCtrl.text = _fmtDate(picked);
                                });
                              }
                            },
                          ),
                        ),
                        onChanged: (_) => _applyTypedDates(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '🔍 ۲. فیلتر بر اساس حساب، موضوع، سرفصل هزینه و فیلترهای سفارشی',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _repSourceFilter,
                  items: const [
                    DropdownMenuItem(value: 'all_records', child: Text('همه تراکنش‌ها (دریافت تنخواه + هزینه‌ها)')),
                    DropdownMenuItem(value: 'all_expenses', child: Text('همه هزینه‌ها (تنخواه + از جیب + شخصی)')),
                    DropdownMenuItem(value: 'company_all', child: Text('فقط هزینه‌های مربوط به شرکت (تنخواه + از جیب)')),
                    DropdownMenuItem(value: 'petty', child: Text('فقط هزینه از محل تنخواه شرکت')),
                    DropdownMenuItem(value: 'pocket', child: Text('فقط پرداخت از جیب برای شرکت (طلب)')),
                    DropdownMenuItem(value: 'personal', child: Text('فقط هزینه‌های شخصی')),
                    DropdownMenuItem(value: 'deposits', child: Text('فقط واریزی‌های تنخواه دریافتی از شرکت')),
                  ],
                  onChanged: (v) => setState(() => _repSourceFilter = v!),
                  decoration: const InputDecoration(labelText: 'نوع حساب / منبع', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _repTopicFilter,
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('همه موضوعات')),
                          ..._topics.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                        ],
                        onChanged: (v) => setState(() => _repTopicFilter = v!),
                        decoration: const InputDecoration(labelText: 'موضوع', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _repCategoryFilter,
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('همه سرفصل‌ها')),
                          ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                        ],
                        onChanged: (v) => setState(() => _repCategoryFilter = v!),
                        decoration: const InputDecoration(labelText: 'سرفصل هزینه کرد', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._customFilters.map((cf) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButtonFormField<String>(
                        value: _repCustomFilterValues[cf.id] ?? 'all',
                        items: [
                          DropdownMenuItem(value: 'all', child: Text('همه (${cf.name})')),
                          ...cf.options.map((o) => DropdownMenuItem(value: o, child: Text(o))),
                        ],
                        onChanged: (v) => setState(() => _repCustomFilterValues[cf.id] = v!),
                        decoration: InputDecoration(
                          labelText: 'فیلتر ${cf.name}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    )),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'جستجوی کلمه کلیدی در شرح یا شماره فاکتور',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _repSearchQuery = v.trim()),
                ),
                const SizedBox(height: 14),
                const Text(
                  '🏦 ۳. خروجی‌های رسمی ویژه واحد مالی و نرم‌افزارهای حسابداری',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _copyExcelTSVForFinance,
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('کپی مستقیم جدول برای Excel و نرم‌افزار مالی (Ctrl+V)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saveCSVFileForFinance,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('ذخیره فایل CSV استاندارد حسابداری'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _copyFormattedSummaryReport,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('کپی صورت‌وضعیت متنی (واتساپ/ایمیل)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📊 خلاصه گزارش بازه انتخابی (${filtered.length} ردیف)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text('• جمع هزینه‌های فیلترشده: ${_fmtOMR(sumExpense)} OMR (${_fmtSec(sumExpense)})'),
                Text('• جمع تنخواه دریافتی در این بازه: ${_fmtOMR(sumDeposit)} OMR'),
                const Divider(height: 20),
                const Text('تفکیک بر اساس سرفصل هزینه کرد:', style: TextStyle(fontWeight: FontWeight.bold)),
                if (byCat.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('هزینه‌ای در این بازه ثبت نشده است.'),
                  )
                else
                  ...byCat.entries.map((e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Text('${_fmtOMR(e.value)} OMR  (${_fmtSec(e.value)})'),
                      )),
                const Divider(height: 20),
                const Text('تفکیک بر اساس موضوع (مرکز هزینه):', style: TextStyle(fontWeight: FontWeight.bold)),
                ...byTopic.entries.map((e) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Text('${_fmtOMR(e.value)} OMR'),
                    )),
                const Divider(height: 20),
                const Text('ریز اسناد و تراکنش‌های بازه انتخابی:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...filtered.map((t) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '[${_fmtDate(t.date)}]  ${t.title}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'موضوع: ${t.topic} | سرفصل: ${t.category}',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                                if (t.note.isNotEmpty)
                                  Text('یادداشت: ${t.note}', style: const TextStyle(fontSize: 11.5)),
                              ],
                            ),
                          ),
                          Text(
                            '${t.mode == TxMode.deposit ? '+' : ''}${_fmtOMR(t.amountOMR)} OMR',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: t.mode == TxMode.deposit ? Colors.green[700] : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // تب ۴: مدیریت سرفصل‌ها، موضوعات و فیلترهای سفارشی (مخصوص نسخه مادر)
  // ==========================================================================
  Widget _buildCustomizeTab() {
    final newCatCtrl = TextEditingController();
    final newTopicCtrl = TextEditingController();
    final newFilterNameCtrl = TextEditingController();
    final newFilterOptsCtrl = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🎛️ افزودن فیلتر سفارشی جدید', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: newFilterNameCtrl,
                  decoration: const InputDecoration(labelText: 'عنوان فیلتر (مثلاً: شهر، کد پروژه، نام راننده)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newFilterOptsCtrl,
                  decoration: const InputDecoration(labelText: 'گزینه‌ها با ویرگول (مثلاً: مسقط، صحار، صلاله)'),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () {
                    final name = newFilterNameCtrl.text.trim();
                    final opts = newFilterOptsCtrl.text
                        .split(RegExp(r'[,،]+'))
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                    if (name.isNotEmpty && opts.isNotEmpty) {
                      setState(() {
                        _customFilters.add(CustomFilterDef(
                          id: 'cf_${DateTime.now().millisecondsSinceEpoch}',
                          name: name,
                          options: opts,
                        ));
                        _syncCustomDefaults();
                      });
                      _saveLocalData();
                      if (_cloudSyncUrl.trim().isNotEmpty) _pushToCloud();
                    }
                  },
                  child: const Text('+ افزودن فیلتر و همگام‌سازی ابری'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('📂 افزودن سرفصل هزینه جدید', style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(controller: newCatCtrl, decoration: const InputDecoration(labelText: 'نام سرفصل جدید')),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final v = newCatCtrl.text.trim();
                    if (v.isNotEmpty && !_categories.contains(v)) {
                      setState(() => _categories.add(v));
                      _saveLocalData();
                      if (_cloudSyncUrl.trim().isNotEmpty) _pushToCloud();
                    }
                  },
                  child: const Text('+ افزودن سرفصل'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🏷️ افزودن موضوع / مرکز هزینه جدید', style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(controller: newTopicCtrl, decoration: const InputDecoration(labelText: 'نام موضوع جدید')),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final v = newTopicCtrl.text.trim();
                    if (v.isNotEmpty && !_topics.contains(v)) {
                      setState(() => _topics.add(v));
                      _saveLocalData();
                      if (_cloudSyncUrl.trim().isNotEmpty) _pushToCloud();
                    }
                  },
                  child: const Text('+ افزودن موضوع'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
