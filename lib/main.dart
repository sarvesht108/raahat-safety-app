import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:another_telephony/telephony.dart';

const int warningAlarmId = 1001;
const int finalAlarmId = 1002;

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

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
  await initNotifications();
  await showWarningNotification();
}

@pragma('vm:entry-point')
Future<void> finalAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    } catch (_) {}
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
        colorSchemeSeed: const Color(0xFF7C9CFF),
        brightness: Brightness.dark,
        useMaterial3: true,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
    _requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkIfShouldShowSafeDialog();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.sms,
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
      Permission.scheduleExactAlarm,
    ].request();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getStringList('contacts') ?? [];
    final endTimeStr = prefs.getString('timerEndTime');
    setState(() {
      contacts =
          contactsJson.map((c) => Map<String, String>.from(jsonDecode(c))).toList();
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
        title: const Text('⚠️ Are you safe?'),
        content: Text(
            'Timer khatam hone wala hai (${end.hour}:${end.minute.toString().padLeft(2, '0')}). Safe ho to "I\'m safe" dabao, warna alert chala jayega.'),
        actions: [
          TextButton(
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
        rescheduleOnReboot: true,
      );
      final ok2 = await AndroidAlarmManager.oneShotAt(
        end,
        finalAlarmId,
        finalAlarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );

      if (!ok1 || !ok2) {
        throw Exception('Alarm schedule failed (ok1=$ok1, ok2=$ok2)');
      }

      setState(() {
        timerActive = true;
        endTime = end;
      });
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
      appBar: AppBar(
        title: const Text('Raahat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () async {
              await Navigator.pushNamed(context, '/contacts');
              _loadState();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(timerActive ? '🟠' : '🛡️', style: const TextStyle(fontSize: 50)),
              const SizedBox(height: 10),
              if (timerActive && endTime != null)
                Text(
                    'Khatam hoga: ${endTime!.hour}:${endTime!.minute.toString().padLeft(2, '0')}'),
              const SizedBox(height: 20),
              if (!timerActive) ...[
                const Text('Timer set karo (minutes):'),
                DropdownButton<int>(
                  value: selectedMinutes,
                  items: [5, 10, 15, 20, 30, 45, 60]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                      .toList(),
                  onChanged: (v) => setState(() => selectedMinutes = v!),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _startTimer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.all(30),
                    shape: const CircleBorder(),
                  ),
                  child: const Text('Start\nTimer', textAlign: TextAlign.center),
                ),
              ] else
                ElevatedButton(
                  onPressed: _stopTimer,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text("I'm safe — Stop timer"),
                ),
              const SizedBox(height: 30),
              Text('${contacts.length} contact(s) saved'),
            ],
          ),
        ),
      ),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, String>> contacts = [];
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('contacts') ?? [];
    setState(() {
      contacts = list.map((c) => Map<String, String>.from(jsonDecode(c))).toList();
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = contacts.map((c) => jsonEncode(c)).toList();
    await prefs.setStringList('contacts', list);
  }

  void _addContact() {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) return;
    setState(() => contacts.add({'name': name, 'phone': phone}));
    _save();
    nameController.clear();
    phoneController.clear();
  }

  void _removeContact(int index) {
    setState(() => contacts.removeAt(index));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted Contacts')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Phone (with country code)'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _addContact, child: const Text('+ Add contact')),
            const Divider(height: 30),
            Expanded(
              child: ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(contacts[i]['name'] ?? ''),
                  subtitle: Text(contacts[i]['phone'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeContact(i),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
