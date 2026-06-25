import 'package:autoshare/General/app_drawer.dart';
import 'package:autoshare/General/plan_your_ride.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoshare/services/api_service.dart';
import 'package:autoshare/Driver/route_selection_screen.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  DriverHomePageState createState() => DriverHomePageState();
}

class DriverHomePageState extends State<DriverHomePage> {
  // These will be loaded from SharedPreferences and API
  String driverName = '';
  String driverId = '';
  double rating = 0.0;
  int totalTrips = 0;
  double totalEarnings = 0.0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    // Load data when screen opens
    _loadDriverData();
  }

  // ── Load driver data ─────────────────────────────────────────────────────
  // First loads name from SharedPreferences (instant)
  // Then fetches latest stats from API (rating, trips, earnings)
  Future<void> _loadDriverData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load basic info saved during login/register
    setState(() {
      driverName = prefs.getString('userName') ?? 'Driver';
      driverId = prefs.getString('userId') ?? '';
    });

    // Fetch latest stats from API
    try {
      final stats = await ApiService.getDriverStats(driverId);
      setState(() {
        rating = (stats['rating'] ?? 5.0).toDouble();
        totalTrips = stats['total_trips'] ?? 0;
        totalEarnings = (stats['total_earnings'] ?? 0.0).toDouble();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(userType: 'Driver', userName: driverName),
      appBar: AppBar(
        backgroundColor: Color.fromARGB(255, 254, 187, 38),
        title: const Text('Driver Home Page'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Driver greeting ──────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.person,
                                size: 100, color: Colors.blueAccent),
                            const SizedBox(width: 20.0),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Hello,',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500)),
                                // Shows real driver name from API
                                Text(driverName,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                            const Spacer(),
                            // ── Go Online button ─────────────────────
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(100, 80),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                backgroundColor: Colors.green,
                                elevation: 5,
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RouteSelectionScreen(),
                                  ),
                                );
                              },
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Text('Go,',
                                      style: TextStyle(
                                          fontSize: 20, color: Colors.white)),
                                  Text('Online',
                                      style: TextStyle(
                                          fontSize: 20, color: Colors.white)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.grey),

                      // ── Today's Earnings ─────────────────────────────
                      // Shows real earnings from database
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset('assets/Images/Auto.png',
                                height: 50, width: 50),
                            const SizedBox(width: 20),
                            Text(
                              'Total Earnings: ₹${totalEarnings.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.grey),

                      // ── Total Trips ──────────────────────────────────
                      Container(
                        alignment: Alignment.center,
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          'Trips Completed: $totalTrips',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const Divider(color: Colors.grey),

                      // ── Rating ───────────────────────────────────────
                      Container(
                        alignment: Alignment.center,
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          'Your Rating: $rating ⭐',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const Divider(color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}