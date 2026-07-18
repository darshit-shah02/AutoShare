import 'dart:async';
import 'package:autoshare/Customer/autoricksaw_booking.dart';
import 'package:autoshare/Customer/autoricksaw_list.dart';
import 'package:autoshare/services/api_service.dart';
import 'package:flutter/material.dart';

class WaitingForDriverScreen extends StatefulWidget {
  final String rideId;
  final String fare;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final String pickupAddress;
  final String dropoffAddress;
  final Map<String, dynamic> pickupNearestPoint;
  final Map<String, dynamic> dropoffNearestPoint;

  const WaitingForDriverScreen({
    super.key,
    required this.rideId,
    required this.fare,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupNearestPoint,
    required this.dropoffNearestPoint,
  });

  @override
  WaitingForDriverScreenState createState() => WaitingForDriverScreenState();
}

class WaitingForDriverScreenState extends State<WaitingForDriverScreen> {
  Timer? _pollTimer;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    // Poll ride status every 3 seconds
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkRideStatus(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Poll ride status ───────────────────────────────────────────────────
  // Checks every 3 seconds if driver accepted
  // When accepted → navigate to booking screen with driver details
  Future<void> _checkRideStatus() async {
    try {
      final result = await ApiService.getRideStatus(widget.rideId);
      final status = result['status'];

      if (status == 'accepted' && result['driver'] != null) {
        // Driver accepted! Stop polling
        _pollTimer?.cancel();

        if (!mounted) return;

        // Navigate to booking screen with driver details
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AutoricksawBooking(
              cost: widget.fare,
              driverName: result['driver']['name'],
              driverPhoneNo: result['driver']['phone'],
              vehicalNo: result['driver']['vehicle_number'],
              fare: widget.fare,
              rideId: widget.rideId,
              driverId: result['driver']['id'],
              pickupNearestPoint: widget.pickupNearestPoint,
              dropoffNearestPoint: widget.dropoffNearestPoint,
            ),
          ),
        );
      } else if (status == 'cancelled') {
        _pollTimer?.cancel();
        if (!mounted) return;
        _goBackToAutoList();
      }
    } catch (e) {
      debugPrint('Status poll error: $e');
    }
  }

  // ── Cancel ride ────────────────────────────────────────────────────────
  Future<void> _cancelRide() async {
    setState(() => _isCancelling = true);
    try {
      await ApiService.updateRideStatus(
        rideId: widget.rideId,
        status: 'cancelled',
      );
      _pollTimer?.cancel();
      if (!mounted) return;
      _goBackToAutoList();
    } catch (e) {
      setState(() => _isCancelling = false);
    }
  }

  void _goBackToAutoList() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AutoricksawList(
          pickupLat: widget.pickupLat,
          pickupLng: widget.pickupLng,
          dropoffLat: widget.dropoffLat,
          dropoffLng: widget.dropoffLng,
          pickupAddress: widget.pickupAddress,
          dropoffAddress: widget.dropoffAddress,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // ── Animation ──────────────────────────────────────────
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 254, 248, 195),
                    borderRadius: BorderRadius.circular(75),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.electric_rickshaw,
                      size: 80,
                      color: Color.fromARGB(255, 254, 187, 38),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Loading indicator ──────────────────────────────────
                const CircularProgressIndicator(
                  color: Color.fromARGB(255, 254, 187, 38),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 24),

                const Text(
                  'Looking for your driver...',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please wait while the driver\naccepts your request',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Ride details card ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.circle,
                              color: Colors.green, size: 12),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.pickupAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.red, size: 12),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.dropoffAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.currency_rupee,
                              size: 16, color: Colors.grey),
                          Text(
                            widget.fare,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── Cancel button ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isCancelling ? null : _cancelRide,
                    child: _isCancelling
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.red,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Cancel Request',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}