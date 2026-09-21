import 'package:flutter/material.dart';

void main() {
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
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raahat — Safety Companion')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🛡️', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            const Text('App pipeline is working!',
                style: TextStyle(fontSize: 18)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(40),
              ),
              child: const Text('SOS', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}
