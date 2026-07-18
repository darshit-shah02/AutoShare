import 'dart:convert';
import 'dart:developer';
import 'package:autoshare/Payment/payment.dart';
import 'package:autoshare/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../General/cancel_ride.dart';
import '../General/exit_pop_up.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';

class AutoricksawBooking extends StatefulWidget {
  final String cost;
  final String driverName;
  final String driverPhoneNo;
  final String vehicalNo;
  final String fare;
  final String rideId;
  final String driverId;
  final Map<String, dynamic> pickupNearestPoint;
  final Map<String, dynamic> dropoffNearestPoint;

  const AutoricksawBooking({
    required this.cost,
    required this.driverPhoneNo,
    required this.driverName,
    required this.vehicalNo,
    required this.fare,
    required this.rideId,
    required this.driverId,
    required this.pickupNearestPoint,
    required this.dropoffNearestPoint,
    super.key,
  });

  @override
  AutoricksawBookingState createState() => AutoricksawBookingState();
}

class AutoricksawBookingState extends State<AutoricksawBooking> {
  final MapController _mapController = MapController();

  // User's real GPS location
  LatLng? userLocation;

  // Nearest points on fixed route
  LatLng? pickupRoutePoint;
  LatLng? dropoffRoutePoint;

  // Walking path coordinates
  List<LatLng> walkingPathToPickup = [];   // user → pickup route point
  List<LatLng> walkingPathFromDropoff = []; // dropoff route point → destination

  // Auto route between pickup and dropoff on fixed route
  List<LatLng> autoRoutePath = [];

  // Driver location marker
  LatLng driverLocation = LatLng(23.038596, 72.512236);

  double _sheetExtent = 0.37;
  bool isLoadingPath = true;

  WebSocketChannel? _customerChannel;
  Timer? _locationPollTimer;
  Timer? _customerLocationTimer;

  @override
  void initState() {
    super.initState();
    _initializeBooking();
  }

  // ── Initialize booking screen ──────────────────────────────────────────
  // 1. Get user's real GPS location
  // 2. Parse nearest route points from booking response
  // 3. Fetch walking paths from OSRM
  Future<void> _initializeBooking() async {
    // Get real GPS location
    final location = await ApiService.getCurrentLocation();
    if (location != null) {
      setState(() {
        userLocation = LatLng(
          location['latitude']!,
          location['longitude']!,
        );
      });
    }

    // Parse nearest route points from booking response
    if (widget.pickupNearestPoint.isNotEmpty) {
      setState(() {
        pickupRoutePoint = LatLng(
          widget.pickupNearestPoint['latitude'],
          widget.pickupNearestPoint['longitude'],
        );
        dropoffRoutePoint = LatLng(
          widget.dropoffNearestPoint['latitude'],
          widget.dropoffNearestPoint['longitude'],
        );
      });
    }

    // Fetch walking paths if we have all points
    if (userLocation != null && pickupRoutePoint != null) {
      await _fetchWalkingPaths();
    }

    setState(() => isLoadingPath = false);

    _connectToDriverLocation();
    _startSendingCustomerLocation();
  }

  void _startSendingCustomerLocation() {
    _customerLocationTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) async {
        final location = await ApiService.getCurrentLocation();
        if (location != null) {
          await ApiService.updateCustomerLocation(
            rideId: widget.rideId,
            lat: location['latitude']!,
            lng: location['longitude']!,
          );
        }
      },
    );
  }

  // ── Fetch walking paths from OSRM via our backend ─────────────────────
  Future<void> _fetchWalkingPaths() async {
    try {
      // Path 1: User location → nearest pickup point on route
      final pickupPath = await _getWalkingPath(
        from: userLocation!,
        to: pickupRoutePoint!,
      );
      setState(() => walkingPathToPickup = pickupPath);

      // Center map on user location
      _mapController.move(userLocation!, 15);
    } catch (e) {
      log('Walking path error: $e');
    }
  }

  // ── Call walking path API ──────────────────────────────────────────────
  Future<List<LatLng>> _getWalkingPath({
    required LatLng from,
    required LatLng to,
  }) async {
    final token = await ApiService.getToken();
    final response = await http.get(
      Uri.parse(
        '${ApiService.baseUrl}/rides/walking-path'
        '?from_lat=${from.latitude}&from_lng=${from.longitude}'
        '&to_lat=${to.latitude}&to_lng=${to.longitude}'
      ),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List coords = data['path'];
      return coords
          .map<LatLng>((c) => LatLng(c['lat'], c['lng']))
          .toList();
    }
    return [];
  }

  void _connectToDriverLocation() {
    if (widget.rideId.isEmpty) return;

    // Poll driver location every 3 seconds
    // Simple and reliable — calls our backend which reads from PostGIS
    _locationPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _fetchDriverLocation(),
    );
  }

  Future<void> _fetchDriverLocation() async {
    try {
      final token = await ApiService.getToken();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/drivers/location/${widget.driverId}'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          driverLocation = LatLng(
            data['latitude'],
            data['longitude'],
          );
        });
      }
    } catch (e) {
      // Silently fail — will retry in 3 seconds
    }
  }

  // Clean up timer in dispose
  @override
  void dispose() {
    _customerLocationTimer?.cancel();
    _locationPollTimer?.cancel();
    _customerChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetInitialSize = 0.37;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        handlePopResult(
          context, didPop, result,
          title: 'Cancel Ride?',
          message: 'Do you really want to cancel the ride?',
          confirmText: 'Yes',
          cancelText: 'No',
          onConfirm: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CancelRide()));
          },
        );
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.black),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ],
        ),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        endDrawer: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 200,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: Colors.white,
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(-2, 2)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: TextButton(
                        onPressed: () {
                          handlePopResult(context, false, null,
                            title: 'Cancel Ride?',
                            message: 'Do you really want to cancel the ride?',
                            confirmText: 'Yes',
                            cancelText: 'No',
                            onConfirm: () {
                              Navigator.push(context,
                                  MaterialPageRoute(
                                      builder: (_) => const CancelRide()));
                            },
                          );
                        },
                        child: const Text('Cancel Ride',
                            style: TextStyle(
                                color: Colors.black, fontSize: 16),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            // ── Map ────────────────────────────────────────────────────
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: userLocation ?? LatLng(23.0393, 72.5129),
                  initialZoom: 15,
                  minZoom: 12,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.autorickshaw',
                  ),

                  // Walking path — user to pickup route point (blue dashed)
                  if (walkingPathToPickup.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: walkingPathToPickup,
                          color: Colors.blue,
                          strokeWidth: 4,
                        ),
                       ],
                    ),

                  // Markers
                  MarkerLayer(
                    markers: [
                      // User's current location
                      if (userLocation != null)
                        Marker(
                          point: userLocation!,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.person_pin_circle,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),

                      // Nearest pickup point on fixed route
                      if (pickupRoutePoint != null)
                        Marker(
                          point: pickupRoutePoint!,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.directions_walk,
                            color: Colors.green,
                            size: 40,
                          ),
                        ),

                      // Driver location
                      Marker(
                        point: driverLocation,
                        width: 40,
                        height: 40,
                        child: Image.asset(
                          'assets/Images/Auto.png',
                          height: 40,
                          width: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Bottom sheet ───────────────────────────────────────────
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                setState(() => _sheetExtent = notification.extent);
                return true;
              },
              child: DraggableScrollableSheet(
                initialChildSize: sheetInitialSize,
                minChildSize: 0.045,
                maxChildSize: 0.37,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Color.fromARGB(255, 254, 187, 38),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      children: [
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            height: 5,
                            width: 40,
                            margin: const EdgeInsets.only(top: 8, bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const Divider(thickness: 1, color: Colors.white),
                        const SizedBox(height: 5),

                        // Ride info
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Arrive in: 10min',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16)),
                            Text('Fare: ₹${widget.fare}',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16)),

                            // Walking distance to pickup point
                            if (pickupRoutePoint != null)
                              const Text(
                                '🚶 Walk to nearest route point shown on map',
                                style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 13),
                              ),
                          ],
                        ),
                        const Divider(thickness: 1, color: Colors.white),
                        const SizedBox(height: 12),

                        // Driver info
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 100,
                              width: 100,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.grey,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: const Icon(Icons.person,
                                    size: 50, color: Colors.white),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(widget.driverName,
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16)),
                                  const SizedBox(height: 10),
                                  Text(widget.driverPhoneNo,
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16)),
                                  const SizedBox(height: 10),
                                  Text(widget.vehicalNo,
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Pay button
                        Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 100,
                            height: MediaQuery.of(context).size.height * 0.05,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => Payment(
                                      fare: widget.fare,
                                      driverName: widget.driverName,
                                      vehicalNo: widget.vehicalNo,
                                      rideId: widget.rideId,   // ← pass ride ID
                                    ),
                                  ),
                                );
                              },
                              child: const Text("Pay",
                                  style: TextStyle(
                                      color: Colors.black, fontSize: 18)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Recenter button ────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              bottom: screenHeight * _sheetExtent + 20,
              right: 20,
              child: FloatingActionButton(
                backgroundColor: const Color.fromARGB(255, 254, 187, 38),
                onPressed: () {
                  if (userLocation != null) {
                    _mapController.move(userLocation!, 15);
                  }
                },
                child: const Icon(Icons.my_location, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}