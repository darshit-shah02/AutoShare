import 'package:autoshare/Customer/conformation_pop_up.dart';
import 'package:autoshare/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoricksawList extends StatefulWidget {
  // These are passed from PlanYourRide screen
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final String pickupAddress;
  final String dropoffAddress;

  const AutoricksawList({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.pickupAddress,
    required this.dropoffAddress,
  });

  @override
  AutoricksawListState createState() => AutoricksawListState();
}

class AutoricksawListState extends State<AutoricksawList> {
  // List of nearby autos from API
  List<Map<String, dynamic>> autos = [];
  bool isLoading = true;
  String? errorMessage;
  String userId = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ── Load user ID and fetch nearby autos ───────────────────────────────
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('userId') ?? '';
    await _fetchNearbyAutos();
  }

  // ── Fetch nearby autos from API ───────────────────────────────────────
  // Shows loading spinner while fetching
  // Shows error message if fetch fails
  // Shows "no autos found" if list is empty
  Future<void> _fetchNearbyAutos() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final result = await ApiService.getNearbyAutos(
        pickupLat: widget.pickupLat,
        pickupLng: widget.pickupLng,
        dropoffLat: widget.dropoffLat,
        dropoffLng: widget.dropoffLng,
      );

      setState(() {
        autos = result;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString().replaceAll('Exception: ', '');
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Back'),
        backgroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Available Autos for Ride",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  // Shows real count from API
                  Text(
                    isLoading
                        ? "Searching for autos..."
                        : "${autos.length} auto${autos.length == 1 ? '' : 's'} found",
                    style: const TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            ),

            Expanded(
              child: isLoading
                  // ── Loading state ──────────────────────────────────
                  ? const Center(child: CircularProgressIndicator(
                      color: Color.fromARGB(255, 254, 187, 38),
                    ))
                  : errorMessage != null
                      // ── Error state ────────────────────────────────
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(errorMessage!,
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchNearbyAutos,
                                child: const Text('Retry'),
                              )
                            ],
                          ),
                        )
                      : autos.isEmpty
                          // ── Empty state ────────────────────────────
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.electric_rickshaw,
                                      size: 80, color: Colors.grey),
                                  SizedBox(height: 12),
                                  Text(
                                    "No autos available nearby",
                                    style: TextStyle(
                                        fontSize: 18, color: Colors.grey),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "Try again in a few minutes",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          // ── Auto list ──────────────────────────────
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              itemCount: autos.length,
                              itemBuilder: (context, index) {
                                final auto = autos[index];
                                return _buildAutoCard(auto);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Auto card widget ───────────────────────────────────────────────────
  // Shows real driver details from API
  Widget _buildAutoCard(Map<String, dynamic> auto) {
    final canBook = auto['can_book'] as bool? ?? false;
    final maleCount = auto['male_count'] as int? ?? 0;
    final femaleCount = auto['female_count'] as int? ?? 0;
    final distanceMeters = auto['distance_meters'] as double? ?? 0;
    final seatsLeft = auto['seats_left'] as int? ?? 3;

    return Card(
      elevation: 6,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: canBook ? Colors.black : Colors.grey.shade300, width: 1.5),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Real driver name
                      Text(auto['name'] ?? '',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("Vehicle: ${auto['vehicle_number'] ?? ''}"),
                      Text("⭐ ${auto['rating']?.toStringAsFixed(1) ?? '5.0'}"),
                      // Distance from auto to customer pickup
                      Row(
                        children: [
                          const Icon(Icons.directions_car,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            distanceMeters < 1000
                                ? "${distanceMeters.toStringAsFixed(0)} m away"
                                : "${(distanceMeters / 1000).toStringAsFixed(1)} km away",
                            style: TextStyle(
                              color: canBook ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),

                      Text("Fare: ₹${auto['fare']?.toStringAsFixed(0) ?? '0'}"),

                      // Gender passenger count
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${maleCount}M  ${femaleCount}F',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: seatsLeft > 0 ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: seatsLeft > 0 ? Colors.green : Colors.red,
                          ),
                        ),
                        child: Text(
                          seatsLeft > 0 ? '$seatsLeft seat${seatsLeft == 1 ? '' : 's'} left' : 'Full',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: seatsLeft > 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ),

                      // 500m warning
                      if (!canBook)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 13, color: Colors.orange),
                              const SizedBox(width: 4),
                              Text(
                                'Auto must be within 500m to book',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.orange.shade700),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    'assets/Images/urban_tuk_tuk.png',
                    width: 80,
                    height: 80,
                    color: canBook ? null : Colors.grey,
                    colorBlendMode: canBook ? null : BlendMode.saturation,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canBook ? () {
                  handleConfirmResult(
                    context,
                    false,
                    null,
                    cost: auto['distance_meters']?.toString() ?? '0',
                    driverPhoneNo: auto['phone'] ?? '',
                    driverName: auto['name'] ?? '',
                    vehicalNo: auto['vehicle_number'] ?? '',
                    fare: auto['fare']?.toString() ?? '0',
                    driverId: auto['driver_id'] ?? '',
                    userId: userId,
                    pickupLat: widget.pickupLat,
                    pickupLng: widget.pickupLng,
                    dropoffLat: widget.dropoffLat,
                    dropoffLng: widget.dropoffLng,
                    pickupAddress: widget.pickupAddress,
                    dropoffAddress: widget.dropoffAddress,
                  );
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canBook ? const Color.fromARGB(255, 254, 187, 38) : Colors.grey.shade300,
                  side: BorderSide(color: canBook ? Colors.black : Colors.transparent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  canBook ? "Select this Auto" : "Auto too far",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color:canBook ? Colors.black : Colors.grey,),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}