import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('Asia/Baghdad'));
  } catch (_) {}

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(initSettings);

  final androidImpl = notificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();
  await androidImpl?.requestExactAlarmsPermission();

  runApp(const FingerprintReminderApp());
}

class FingerprintReminderApp extends StatelessWidget {
  const FingerprintReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'أوقات أداء البصمة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'IQ'),
      supportedLocales: const [Locale('ar', 'IQ'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6F8),
      ),
      home: const RootGateScreen(),
    );
  }
}

class ActivationHelper {
  static const String masterDevCode = 'marwan1988';
  static const String _salt = 'FP_MARWAN_2026_LOCK_SALT';

  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      final raw = '${info.id}-${info.model}-${info.hardware}';
      return sha256.convert(utf8.encode(raw)).toString().substring(0, 8).toUpperCase();
    }
    return 'DEV-LOCAL-01';
  }

  /// يولّد كود تفعيل مرتبط بمعرّف جهاز المستلم حصراً
  static String generateCodeForDevice(String targetDeviceId) {
    final cleanId = targetDeviceId.trim().toUpperCase();
    final digest = sha256.convert(utf8.encode('$_salt:$cleanId')).toString().toUpperCase();
    return 'FP-${digest.substring(0, 4)}-${digest.substring(4, 8)}';
  }

  static bool verifyUserCode(String enteredCode, String currentDeviceId) {
    final expected = generateCodeForDevice(currentDeviceId);
    return enteredCode.trim().toUpperCase() == expected;
  }
}

class RootGateScreen extends StatefulWidget {
  const RootGateScreen({super.key});

  @override
  State<RootGateScreen> createState() => _RootGateScreenState();
}

class _RootGateScreenState extends State<RootGateScreen> {
  bool _loading = true;
  bool _isLoggedIn = false;
  bool _isDeveloper = false;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final id = await ActivationHelper.getDeviceId();
    final logged = prefs.getBool('is_logged_in') ?? false;
    final dev = prefs.getBool('is_developer') ?? false;
    setState(() {
      _deviceId = id;
      _isLoggedIn = logged;
      _isDeveloper = dev;
      _loading = false;
    });
  }

  Future<void> _onLoginSuccess(bool asDeveloper) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    await prefs.setBool('is_developer', asDeveloper);
    setState(() {
      _isLoggedIn = true;
      _isDeveloper = asDeveloper;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    await prefs.setBool('is_developer', false);
    setState(() {
      _isLoggedIn = false;
      _isDeveloper = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isLoggedIn) {
      return LoginScreen(
        deviceId: _deviceId,
        onAuthenticated: _onLoginSuccess,
      );
    }
    return HomeScheduleScreen(
      isDeveloper: _isDeveloper,
      deviceId: _deviceId,
      onLogout: _logout,
    );
  }
}

class LoginScreen extends StatefulWidget {
  final String deviceId;
  final Future<void> Function(bool asDeveloper) onAuthenticated;

  const LoginScreen({
    super.key,
    required this.deviceId,
    required this.onAuthenticated,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _codeController = TextEditingController();
  String? _errorMsg;

  void _submit() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMsg = 'يرجى إدخال كود التفعيل');
      return;
    }
    if (code == ActivationHelper.masterDevCode) {
      widget.onAuthenticated(true);
      return;
    }
    if (ActivationHelper.verifyUserCode(code, widget.deviceId)) {
      widget.onAuthenticated(false);
      return;
    }
    setState(() {
      _errorMsg = 'الكود غير صحيح أو غير مخصص لهذا الجهاز';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F766E).withOpacity(0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    size: 58,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'أوقات أداء البصمة',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'معرّف هذا الجهاز: ${widget.deviceId}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'أدخل كود الدخول / التفعيل',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMsg!,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _submit,
                    child: const Text(
                      'دخول',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.deviceId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ معرّف الجهاز لإرساله للمطور')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('نسخ معرّف الجهاز'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FingerprintSlot {
  final String id;
  final String title;
  final String timeWindow;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final String? extraNote;

  const FingerprintSlot({
    required this.id,
    required this.title,
    required this.timeWindow,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.extraNote,
  });
}

class HomeScheduleScreen extends StatefulWidget {
  final bool isDeveloper;
  final String deviceId;
  final VoidCallback onLogout;

  const HomeScheduleScreen({
    super.key,
    required this.isDeveloper,
    required this.deviceId,
    required this.onLogout,
  });

  @override
  State<HomeScheduleScreen> createState() => _HomeScheduleScreenState();
}

class _HomeScheduleScreenState extends State<HomeScheduleScreen> {
  DateTime _cycleStartDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  Set<String> _completedSlots = {};

  static const List<FingerprintSlot> day1Slots = [
    FingerprintSlot(
      id: 'd1_1',
      title: 'البصمة الأولى (الحضور)',
      timeWindow: 'قبل الساعة 10:00 صباحاً',
      startHour: 8,
      startMinute: 0,
      endHour: 10,
      endMinute: 0,
    ),
    FingerprintSlot(
      id: 'd1_2',
      title: 'البصمة الثانية (المسائية)',
      timeWindow: 'من 04:00 م إلى 07:00 م',
      startHour: 16,
      startMinute: 0,
      endHour: 19,
      endMinute: 0,
    ),
    FingerprintSlot(
      id: 'd1_3',
      title: 'البصمة الثالثة (الليلية)',
      timeWindow: 'من 09:00 م إلى 12:00 ص',
      startHour: 21,
      startMinute: 0,
      endHour: 23,
      endMinute: 59,
    ),
  ];

  static const List<FingerprintSlot> day2Slots = [
    FingerprintSlot(
      id: 'd2_1',
      title: 'البصمة الأولى (الصباحية)',
      timeWindow: 'من 06:00 ص إلى 09:00 ص',
      startHour: 6,
      startMinute: 0,
      endHour: 9,
      endMinute: 0,
      extraNote: 'تنبيه الانصراف: بعد الساعة 09:30 صباحاً',
    ),
    FingerprintSlot(
      id: 'd2_2',
      title: 'البصمة الثانية (المسائية)',
      timeWindow: 'من 04:00 م إلى 07:00 م',
      startHour: 16,
      startMinute: 0,
      endHour: 19,
      endMinute: 0,
    ),
    FingerprintSlot(
      id: 'd2_3',
      title: 'البصمة الثالثة (الليلية)',
      timeWindow: 'من 09:00 م إلى 12:00 ص',
      startHour: 21,
      startMinute: 0,
      endHour: 23,
      endMinute: 59,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final startIso = prefs.getString('cycle_start_date');
    final savedDone = prefs.getStringList('completed_slots') ?? [];
    setState(() {
      if (startIso != null) {
        final parsed = DateTime.parse(startIso);
        _cycleStartDate = DateTime(parsed.year, parsed.month, parsed.day);
      }
      _completedSlots = savedDone.toSet();
    });
    await _scheduleUpcomingNotifications();
  }

  Future<void> _pickCycleStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _cycleStartDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      helpText: 'اختر تاريخ أول يوم دوام',
    );
    if (picked != null) {
      final clean = DateTime(picked.year, picked.month, picked.day);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cycle_start_date', clean.toIso8601String());
      setState(() {
        _cycleStartDate = clean;
        _selectedDate = clean;
      });
      await _scheduleUpcomingNotifications();
    }
  }

  int _cycleDayIndex(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(_cycleStartDate).inDays;
    final mod = diff % 6;
    return mod < 0 ? mod + 6 : mod; // 0: عمل1, 1: عمل2, 2..5: راحة
  }

  Future<void> _toggleSlot(DateTime date, String slotId) async {
    final key = '${date.year}-${date.month}-${date.day}_$slotId';
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_completedSlots.contains(key)) {
        _completedSlots.remove(key);
      } else {
        _completedSlots.add(key);
      }
    });
    await prefs.setStringList('completed_slots', _completedSlots.toList());
  }

  Future<void> _scheduleUpcomingNotifications() async {
    await notificationsPlugin.cancelAll();
    final now = DateTime.now();
    int notifId = 100;

    for (int i = 0; i < 18; i++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final idx = _cycleDayIndex(day);
      if (idx == 0 || idx == 1) {
        final slots = idx == 0 ? day1Slots : day2Slots;
        for (final slot in slots) {
          final alertTime = DateTime(
            day.year,
            day.month,
            day.day,
            slot.startHour,
            slot.startMinute,
          );
          if (alertTime.isAfter(now)) {
            await notificationsPlugin.zonedSchedule(
              notifId++,
              'تذكير: ${slot.title}',
              'موعد البصمة الآن (${slot.timeWindow})',
              tz.TZDateTime.from(alertTime, tz.local),
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'fingerprint_alerts',
                  'تنبيهات البصمة',
                  importance: Importance.max,
                  priority: Priority.high,
                ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          }
        }
        if (idx == 1) {
          final leaveAlert = DateTime(day.year, day.month, day.day, 9, 30);
          if (leaveAlert.isAfter(now)) {
            await notificationsPlugin.zonedSchedule(
              notifId++,
              'وقت الانصراف - اليوم الثاني',
              'الساعة 09:30 صباحاً — يمكنك الانصراف الآن',
              tz.TZDateTime.from(leaveAlert, tz.local),
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'fingerprint_alerts',
                  'تنبيهات البصمة',
                  importance: Importance.max,
                  priority: Priority.high,
                ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          }
        }
      }
    }
  }

  void _showKeygenDialog() {
    final targetController = TextEditingController();
    String generated = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('🔑 توليد كود تفعيل لمستخدم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'أدخل معرّف الجهاز الذي يظهر في شاشة الدخول عند المستلم لتوليد كود خاص بجهازه فقط:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: targetController,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'مثال: A1B2C3D4',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  if (targetController.text.trim().isNotEmpty) {
                    setDialogState(() {
                      generated = ActivationHelper.generateCodeForDevice(targetController.text);
                    });
                  }
                },
                child: const Text('توليد الكود'),
              ),
              if (generated.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  generated,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: generated));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم نسخ الكود: $generated')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ الكود وإغلاق'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _arabicWeekday(int weekday) {
    const names = [
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    return names[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final idx = _cycleDayIndex(_selectedDate);
    final isWork = idx == 0 || idx == 1;
    final slots = idx == 0 ? day1Slots : (idx == 1 ? day2Slots : <FingerprintSlot>[]);
    final hijri = HijriCalendar.fromDate(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('أوقات أداء البصمة'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          if (widget.isDeveloper)
            IconButton(
              tooltip: 'توليد كود لمستخدم',
              icon: const Icon(Icons.vpn_key),
              onPressed: _showKeygenDialog,
            ),
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() {
                          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                        }),
                      ),
                      Column(
                        children: [
                          Text(
                            _arabicWeekday(_selectedDate.weekday),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day} م  |  ${hijri.hDay}/${hijri.hMonth}/${hijri.hYear} هـ',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 1));
                        }),
                      ),
                    ],
                  ),
                  const Divider(),
                  OutlinedButton.icon(
                    onPressed: _pickCycleStartDate,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      'بداية الدوام: ${_cycleStartDate.year}/${_cycleStartDate.month}/${_cycleStartDate.day}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isWork ? const Color(0xFF0F766E) : Colors.blueGrey.shade700,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  isWork ? Icons.fingerprint : Icons.weekend,
                  color: Colors.white,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    idx == 0
                        ? 'اليوم الأول للعمل (3 بصمات)'
                        : idx == 1
                            ? 'اليوم الثاني للعمل (3 بصمات + انصراف 09:30 ص)'
                            : 'يوم راحة (${idx - 1} من 4)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!isWork)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'لا توجد بصمات مطلوبة في هذا اليوم — استمتع بإجازتك',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            )
          else
            ...slots.map((slot) {
              final key = '${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}_${slot.id}';
              final done = _completedSlots.contains(key);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: Icon(
                    done ? Icons.check_circle : Icons.access_time_filled,
                    color: done ? Colors.green : const Color(0xFF0F766E),
                    size: 32,
                  ),
                  title: Text(
                    slot.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(slot.timeWindow),
                      if (slot.extraNote != null)
                        Text(
                          slot.extraNote!,
                          style: const TextStyle(
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: done ? Colors.grey.shade300 : const Color(0xFF0F766E),
                      foregroundColor: done ? Colors.black87 : Colors.white,
                    ),
                    onPressed: () => _toggleSlot(_selectedDate, slot.id),
                    child: Text(done ? 'تمت' : 'بصمت'),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
