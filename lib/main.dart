import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:another_telephony/telephony.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:url_launcher/url_launcher.dart';

const int warningAlarmId = 1001;
const int finalAlarmId = 1002;
const seed = Color(0xFF6C8CFF);

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> addLog(String msg) async {
  final prefs = await SharedPreferences.getInstance();
  final log = prefs.getStringList('eventLog') ?? [];
  final ts = DateTime.now();
  final timeStr =
      '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
  log.add('$timeStr — $msg');
  if (log.length > 20) log.removeAt(0);
  await prefs.setStringList('eventLog', log);
}

Future<void> initNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notifications.initialize(initSettings);
}

Future<void> showWarningNotification() async {
  const androidDetails = AndroidNotificationDetails(
    'raahat_warning',
    'Safety Warning',
    channelDescription: 'Warns before sending an emergency alert',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
  );
  const details = NotificationDetails(android: androidDetails);
  await notifications.show(
    0,
    '⚠️ Are you safe?',
    'Raahat kholo aur "I\'m safe" dabao, warna alert automatically chala jayega.',
    details,
  );
}

@pragma('vm:entry-point')
Future<void> warningAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  await addLog('Warning alarm FIRED');
  await initNotifications();
  await showWarningNotification();
}

@pragma('vm:entry-point')
Future<void> finalAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  await addLog('Final alarm FIRED');
  final prefs = await SharedPreferences.getInstance();
  final contactsJson = prefs.getStringList('contacts') ?? [];
  final userName = prefs.getString('userName') ?? 'I';

  String locText = 'location unavailable';
  try {
    final pos =
        await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    locText = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    await prefs.setString('lastLat', pos.latitude.toString());
    await prefs.setString('lastLng', pos.longitude.toString());
  } catch (e) {
    final lat = prefs.getString('lastLat');
    final lng = prefs.getString('lastLng');
    if (lat != null && lng != null) {
      locText = 'https://maps.google.com/?q=$lat,$lng';
    }
  }

  final message =
      '🚨 SOS Alert from $userName\nI need help right now.\nLocation: $locText';

  final telephony = Telephony.instance;
  for (final c in contactsJson) {
    final map = jsonDecode(c);
    final phone = map['phone'];
    try {
      await telephony.sendSms(to: phone, message: message);
      await addLog('SMS sent to $phone');
    } catch (e) {
      await addLog('SMS FAILED to $phone: $e');
    }
  }

  await prefs.setBool('alertSent', true);
  await prefs.remove('timerEndTime');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  await initNotifications();
  runApp(const RaahatApp());
}

class RaahatApp extends StatelessWidget {
  const RaahatApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raahat',
      theme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0E1116),
        cardTheme: CardThemeData(
          color: const Color(0xFF171B23),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: const HomeScreen(),
      routes: {'/contacts': (context) => const ContactsScreen()},
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int selectedMinutes = 5;
  int warningMinutesBefore = 2;
  bool timerActive = false;
  DateTime? endTime;
  List<Map<String, String>> contacts = [];
  List<String> eventLog = [];
  bool showLog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _setupEverything();
    await _loadState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkIfShouldShowSafeDialog();
      _loadState();
    }
  }

  // Sab permissions + battery/background setup ek hi flow mein, app khulte hi
  Future<void> _setupEverything() async {
    await Permission.sms.request();
    await Permission.notification.request();
    await Permission.scheduleExactAlarm.request();
    final loc = await Permission.location.request();
    if (loc.isGranted) {
      await Permission.locationAlways.request();
    }
    await Permission.ignoreBatteryOptimizations.request();

    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('bgSetupDone') ?? false;
    if (!done) {
      try {
        await DisableBatteryOptimization.showDisableAutoStartOptimizationSettings(
          title: 'Background alerts on rakho',
          description:
              'Yahan "Allow" ya toggle ON karo, taaki timer khatam hone par alert screen lock hone par bhi chale.',
        );
      } catch (_) {}
      try {
        await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
      } catch (_) {}
      await prefs.setBool('bgSetupDone', true);
    }
  }

  Future<void> _callPolice() async {
    final uri = Uri.parse('tel:112');
    try {
      await launchUrl(uri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Dialer nahi khul saka: $e')));
      }
    }
  }

  Future<void> _shareMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final url = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Location error: $e')));
      }
    }
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getStringList('contacts') ?? [];
    final endTimeStr = prefs.getString('timerEndTime');
    final log = prefs.getStringList('eventLog') ?? [];
    setState(() {
      contacts =
          contactsJson.map((c) => Map<String, String>.from(jsonDecode(c))).toList();
      eventLog = log.reversed.toList();
      if (endTimeStr != null) {
        endTime = DateTime.parse(endTimeStr);
        timerActive = endTime!.isAfter(DateTime.now());
      } else {
        timerActive = false;
      }
    });
    _checkIfShouldShowSafeDialog();
  }

  Future<void> _checkIfShouldShowSafeDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final endTimeStr = prefs.getString('timerEndTime');
    if (endTimeStr == null) return;
    final end = DateTime.parse(endTimeStr);
    final warnAt = end.subtract(Duration(minutes: warningMinutesBefore));
    final now = DateTime.now();
    if (now.isAfter(warnAt) && now.isBefore(end) && mounted) {
      _showSafeDialog(end);
    }
  }

  void _showSafeDialog(DateTime end) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('⚠️ Are you safe?'),
        content: Text(
            'Timer khatam hone wala hai (${end.hour}:${end.minute.toString().padLeft(2, '0')}). Safe ho to "I\'m safe" dabao, warna alert chala jayega.'),
        actions: [
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _stopTimer();
            },
            child: const Text("I'm safe"),
          ),
        ],
      ),
    );
  }

  Future<void> _startTimer() async {
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pehle Contacts add karo')));
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final end = now.add(Duration(minutes: selectedMinutes));
      final warnAt = end.subtract(Duration(minutes: warningMinutesBefore));

      await prefs.setStringList('eventLog', []);
      await addLog('Timer started');
      await prefs.setString('timerEndTime', end.toIso8601String());
      await prefs.setBool('alertSent', false);

      try {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        await prefs.setString('lastLat', pos.latitude.toString());
        await prefs.setString('lastLng', pos.longitude.toString());
      } catch (_) {}

      final ok1 = await AndroidAlarmManager.oneShotAt(
        warnAt,
        warningAlarmId,
        warningAlarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: false,
      );
      final ok2 = await AndroidAlarmManager.oneShotAt(
        end,
        finalAlarmId,
        finalAlarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: false,
      );
      await addLog('Alarms scheduled: warn_ok=$ok1, final_ok=$ok2');

      if (!ok1 || !ok2) {
        throw Exception('Alarm schedule failed');
      }

      setState(() {
        timerActive = true;
        endTime = end;
      });
      _loadState();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), duration: const Duration(seconds: 6)),
        );
      }
    }
  }

  Future<void> _stopTimer() async {
    await AndroidAlarmManager.cancel(warningAlarmId);
    await AndroidAlarmManager.cancel(finalAlarmId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('timerEndTime');
    setState(() {
      timerActive = false;
      endTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadState,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: seed.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: const Text('🛡️', style: TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Raahat',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w700)),
                          Text('Your safety companion',
                              style: TextStyle(fontSize: 12, color: Colors.white54)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Navigator.pushNamed(context, '/contacts');
                        _loadState();
                      },
                      icon: const Icon(Icons.people_alt_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Status card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (timerActive ? Colors.orange : seed)
                                .withOpacity(0.15),
                          ),
                          alignment: Alignment.center,
                          child: Text(timerActive ? '🟠' : '🛡️',
                              style: const TextStyle(fontSize: 40)),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          timerActive ? 'Monitoring active' : 'All safe',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        if (timerActive && endTime != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Khatam hoga: ${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}:${endTime!.second.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ),
                        const SizedBox(height: 20),
                        if (!timerActive) ...[
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButton<int>(
                              value: selectedMinutes,
                              underline: const SizedBox(),
                              dropdownColor: const Color(0xFF1E2430),
                              items: [1, 5, 10, 15, 20, 30, 45, 60]
                                  .map((m) => DropdownMenuItem(
                                      value: m, child: Text('$m min')))
                                  .toList(),
                              onChanged: (v) => setState(() => selectedMinutes = v!),
                            ),
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: 150,
                            height: 150,
                            child: ElevatedButton(
                              onPressed: _startTimer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                shape: const CircleBorder(),
                                elevation: 6,
                              ),
                              child: const Text('Start\nTimer',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ] else
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _stopTimer,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text("I'm safe — Stop timer"),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick actions
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.local_police_rounded,
                        label: 'Call 112',
                        color: Colors.redAccent,
                        onTap: _callPolice,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.location_on_rounded,
                        label: 'My Location',
                        color: seed,
                        onTap: _shareMyLocation,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.contacts_outlined, color: Colors.white60),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text('${contacts.length} contact(s) saved',
                                style: const TextStyle(fontSize: 14))),
                        TextButton(
                          onPressed: () async {
                            await Navigator.pushNamed(context, '/contacts');
                            _loadState();
                          },
                          child: const Text('Manage'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() => showLog = !showLog),
                          child: Row(
                            children: [
                              const Icon(Icons.receipt_long_outlined,
                                  color: Colors.white60),
                     
