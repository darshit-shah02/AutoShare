import 'dart:async';
import 'package:autoshare/config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoshare/Login&Signup/login_page.dart';
import 'package:autoshare/Customer/customer_home_page.dart';
import 'package:autoshare/Driver/driver_home_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase — needed for Realtime
  await Supabase.initialize(
    url: 'AppConfig.supabaseUrl',
    anonKey: 'AppConfig.supabaseAnonKey',  // ← use ANON key here, not service role
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoShare',
      theme: ThemeData(
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    try {
    await http.get(Uri.parse(AppConfig.apiBaseUrl));
  } catch (_) {}
  
    await Future.delayed(const Duration(seconds: 1));

    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    String? userType = prefs.getString('userType')?.toLowerCase();

    if (!mounted) return;

    if (isLoggedIn) {
      if (userType == "customer") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CustomerHomePage()),
        );
      } else if (userType == "driver") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => DriverHomePage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginPage()),
        );
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Color.fromARGB(255, 254, 187, 38),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/Images/Auto.png',
                width: 100,
                height: 100,
              ),
              SizedBox(height: 20),
              Text(
                "Welcome",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 40),
              CircularProgressIndicator(
                color: Colors.black,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
