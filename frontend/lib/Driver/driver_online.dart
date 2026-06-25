import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:autoshare/services/api_service.dart';
import 'dart:developer';

class DriverOnline extends StatefulWidget {
  final String source;
  final String destination;
  final String routeId;

  const DriverOnline({
    super.key,
    required this.source,
    required this.destination,
    required this.routeId,
  });

  @override
  DriverOnlineState createState() => DriverOnlineState();
}

class DriverOnlineState extends State<DriverOnline> {
  final MapController _mapController = MapController();

  // Driver's current location — updated from real GPS
  LatLng? driverLocation;

  // Route points to draw on map
  List<LatLng> routePoints = [];

  // WebSocket channel for sending location to server
  WebSocketChannel? _channel;

  // Timer that sends GPS every 3 seconds
  Timer? _locationTimer;

  // Active ride ID — null if no passenger
  String? activeRideId;

  // Passenger request popup
  bool showPopup = false;
  Map<String, dynamic>? pendingRequest;

  String driverId = '';

  List<LatLng> _fixedRoutePoints = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  // ── Initialize ─────────────────────────────────────────────────────────
  // 1. Load driver ID from SharedPreferences
  // 2. Get real GPS location
  // 3. Connect to WebSocket
  // 4. Start sending GPS every 3 seconds
  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    driverId = prefs.getString('userId') ?? '';

    // Get initial GPS location
    final location = await ApiService.getCurrentLocation();
    if (location != null && mounted) {
      setState(() {
        driverLocation = LatLng(
          location['latitude']!,
          location['longitude']!,
        );
      });
      _mapController.move(driverLocation!, 15);
    }

    // Connect to WebSocket
    _connectWebSocket();

    // Send GPS location every 3 seconds
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendLocation();
    });

    // Simulate incoming ride request after 10 seconds
    // This will be replaced with real WebSocket notification later
    Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => showPopup = true);
      }
    });

    String activeRouteId = widget.routeId;
    if (activeRouteId.isEmpty) {
      try {
        final routeData = await ApiService.getDriverActiveRoute(driverId);
        activeRouteId = routeData['route']?['route_id'] ?? '';
      } catch (e) {
        debugPrint('Could not fetch active route: $e');
      }
    }

    await _loadFixedRoute();
  }

  // ── Connect WebSocket ──────────────────────────────────────────────────
  // Opens WebSocket connection to backend
  // Backend marks driver as online in database
  void _connectWebSocket() {
    if (driverId.isEmpty) return;

    _channel = ApiService.connectDriverWebSocket(driverId);

    // Listen for any messages from server (e.g. ride requests)
    _channel!.stream.listen(
      (data) {
        final message = jsonDecode(data);
        if (message['type'] == 'ride_request') {
          setState(() {
            showPopup = true;
            pendingRequest = message;
          });
        }
      },
      onDone: () {
        // WebSocket closed — try to reconnect
        log('WebSocket closed, reconnecting...');
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      },
      onError: (error) {
        log('WebSocket error: $error');
      },
    );
  }

  // ── Send GPS location to server ────────────────────────────────────────
  // Called every 3 seconds by the timer
  // Sends current GPS coordinates + active ride ID if any
  Future<void> _sendLocation() async {
    if (_channel == null || driverId.isEmpty) return;

    // Get fresh GPS reading
    final location = await ApiService.getCurrentLocation();
    if (location == null) return;

    final lat = location['latitude']!;
    final lng = location['longitude']!;

    // Update marker on map
    if (mounted) {
      setState(() {
        driverLocation = LatLng(lat, lng);
      });
    }

    // Send to WebSocket server
    try {
      _channel!.sink.add(jsonEncode({
        "latitude": lat,
        "longitude": lng,
        "ride_id": activeRideId,  // null if no active ride
      }));
    } catch (e) {
      log('Error sending location: $e');
    }
  }

  Future<void> _loadFixedRoute() async {
    try {
      final coords = await ApiService.getFixedRoute();
      setState(() {
        _fixedRoutePoints = coords
            .map<LatLng>((c) => LatLng(c['lat'], c['lng']))
            .toList();
      });
    } catch (e) {
      debugPrint('Failed to load fixed route: $e');
    }
  }

  @override
  void dispose() {
    // Clean up when driver leaves the screen
    _locationTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Online'),
        backgroundColor: const Color.fromARGB(255, 254, 187, 38),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "recenterFab",
        backgroundColor: const Color.fromARGB(255, 254, 187, 38),
        onPressed: () {
          if (driverLocation != null) {
            _mapController.move(driverLocation!, 15);
          }
        },
        child: const Icon(Icons.my_location),
      ),
      body: Stack(
        children: [
          // ── Trip info header ─────────────────────────────────────────
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black38,
                        blurRadius: 6,
                        offset: Offset(2, 4))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Current Trip",
                        style: TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 24)),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("From: ${widget.source}",
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis),
                              Text("To: ${widget.destination}",
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        // Show live GPS coords
                        if (driverLocation != null)
                          Text(
                            '📍 ${driverLocation!.latitude.toStringAsFixed(4)}, '
                            '${driverLocation!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Map ─────────────────────────────────────────────────
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: driverLocation ?? LatLng(23.0393, 72.5129),
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

                    if (_fixedRoutePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _fixedRoutePoints,
                            color: const Color.fromARGB(255, 254, 187, 38),
                            strokeWidth: 5,
                          ),
                        ],
                      ),

                    // Driver location marker
                    if (driverLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: driverLocation!,
                            width: 50,
                            height: 50,
                            child: Image.asset(
                              'assets/Images/Auto.png',
                              width: 50,
                              height: 50,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),

          // ── Ride request popup ───────────────────────────────────────
          // Shows when a customer books this driver
          if (showPopup)
            Positioned(
              bottom: size.height * 0.1,
              left: size.width * 0.1,
              right: size.width * 0.1,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 254, 187, 38),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "From: ${pendingRequest?['pickup_address'] ?? 'Thaltej'}",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            "To: ${pendingRequest?['dropoff_address'] ?? 'Gota'}",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            "Fare: ₹${pendingRequest?['fare'] ?? '10'}",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                          const Text(
                            "Pickup: ~2 min away",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Accept button
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    showPopup = false;
                                    // Set active ride ID so location
                                    // gets forwarded to customer
                                    activeRideId =
                                        pendingRequest?['ride_id'];
                                  });
                                  // Update ride status in database
                                  if (pendingRequest?['ride_id'] != null) {
                                    ApiService.updateRideStatus(
                                      rideId: pendingRequest!['ride_id'],
                                      status: 'accepted',
                                    );
                                  }
                                },
                                child: const Text('Accept',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500)),
                              ),

                              // Reject button
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() => showPopup = false);
                                },
                                child: const Text('Reject',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => showPopup = false),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}