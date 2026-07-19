import 'dart:async';
import 'dart:convert';
import 'package:autoshare/Driver/driver_cash_confirm_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
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

  LatLng? driverLocation;
  List<LatLng> _fixedRoutePoints = [];
  WebSocketChannel? _channel;
  Timer? _locationTimer;
  Timer? _requestPollTimer;     // polls for ride requests as backup
  Timer? _customerLocationTimer;

  // Set of all currently active (accepted, not-yet-completed) ride ids.
  // A driver can carry up to 3 passengers at once, so this must support
  // more than one concurrent ride — a single nullable String cannot.
  final Set<String> activeRideIds = {};
  bool showPopup = false;
  Map<String, dynamic>? pendingRequest;
  Map<String, LatLng> customerLocations = {};
  String driverId = '';

  // Track which ride requests we've already shown
  // Prevents showing same popup repeatedly
  final Set<String> _shownRequestIds = {};
  final List<String> _acceptedRideIds = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    driverId = prefs.getString('userId') ?? '';

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

    await _loadFixedRoute();
    _connectWebSocket();

    // Send GPS every 3 seconds
    _locationTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _sendLocation(),
    );

    // Poll for ride requests every 3 seconds (backup to WebSocket)
    _requestPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollForRideRequests(),
    );
  }

  // ── WebSocket connection ───────────────────────────────────────────────
  void _connectWebSocket() {
    if (driverId.isEmpty) return;

    _channel = ApiService.connectDriverWebSocket(driverId);

    _channel!.stream.listen(
      (data) {
        final message = jsonDecode(data);
        if (message['type'] == 'ride_request') {
          _showRideRequest(message);
        } else if (message['type'] == 'ride_completed') {
          // One passenger's ride completed
          _handleRideCompleted(message);
        }
      },
      onDone: () {
        log('WebSocket closed, reconnecting...');
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      },
      onError: (error) {
        log('WebSocket error: $error');
      },
    );
  }

  // ── Poll for ride requests (backup to WebSocket) ───────────────────────
  // This ensures driver gets requests even if WebSocket disconnects
  // Checks database directly every 3 seconds
  Future<void> _pollForRideRequests() async {
    if (driverId.isEmpty || showPopup) return;
    // Auto can carry up to 3 passengers — keep polling for more requests
    // as long as there's room, instead of stopping after the first ride.
    if (activeRideIds.length >= 3) return;

    try {
      final request = await ApiService.getPendingRequest(driverId);
      if (request != null) {
        _showRideRequest(request);
      }
    } catch (e) {
      // Silent fail — will retry in 3 seconds
    }
  }

  // ── Show ride request popup ────────────────────────────────────────────
  // Called by both WebSocket and polling
  // Uses _shownRequestIds to prevent duplicate popups
  void _showRideRequest(Map<String, dynamic> request) {
    final rideId = request['ride_id'];
    if (rideId == null || _shownRequestIds.contains(rideId)) return;

    _shownRequestIds.add(rideId);
    if (mounted) {
      setState(() {
        showPopup = true;
        pendingRequest = request;
      });
    }
  }

  // ── Send GPS location ──────────────────────────────────────────────────
  Future<void> _sendLocation() async {
    if (driverId.isEmpty) return;

    final location = await ApiService.getCurrentLocation();
    if (location == null) return;

    final lat = location['latitude']!;
    final lng = location['longitude']!;

    if (mounted) {
      setState(() {
        driverLocation = LatLng(lat, lng);
      });
    }

    // Send via WebSocket if connected
    try {
      _channel?.sink.add(jsonEncode({
        "latitude": lat,
        "longitude": lng,
        "ride_id": activeRideIds.isNotEmpty ? activeRideIds.first : null,
      }));
    } catch (e) {
      // WebSocket failed — also update via HTTP as backup
      try {
        final headers = await ApiService.authHeaders();
        await http.post(
          Uri.parse('${ApiService.baseUrl}/drivers/location'),
          headers: headers,
          body: jsonEncode({
            'driver_id': driverId,
            'latitude': lat,
            'longitude': lng,
          }),
        );
      } catch (_) {}
    }
  }

  // ── Load fixed route ───────────────────────────────────────────────────
  Future<void> _loadFixedRoute() async {
    try {
      final token = await ApiService.getToken();
      final url =
          '${ApiService.baseUrl}/rides/fixed-route?route_id=${widget.routeId}';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawCoords = data['coordinates'];

        final List coordsList = (rawCoords is List &&
                rawCoords.isNotEmpty &&
                rawCoords[0] is List)
            ? rawCoords[0] as List
            : rawCoords as List;

        if (mounted) {
          setState(() {
            _fixedRoutePoints = coordsList
                .map<LatLng>(
                    (c) => LatLng(c['lat'] as double, c['lng'] as double))
                .toList();
          });

          if (_fixedRoutePoints.isNotEmpty) {
            _mapController.move(_fixedRoutePoints.first, 13);
          }
        }
      }
    } catch (e) {
      log('Route load error: $e');
    }
  }

  // ── Accept ride ────────────────────────────────────────────────────────
  void _acceptRide() {
    if (pendingRequest == null) return;

    final rideId = pendingRequest!['ride_id'];
    setState(() {
      showPopup = false;
      activeRideIds.add(rideId);
      _acceptedRideIds.add(rideId);
    });

    ApiService.updateRideStatus(
      rideId: rideId,
      status: 'accepted',
    );

    // Make sure the shared tracking timer is running. It will pick up
    // every ride currently in activeRideIds, so we don't restart it (and
    // stop tracking other passengers) each time a new ride is accepted.
    _startCustomerLocationTracking();
  }

  // ── Track customer location for ALL active rides ───────────────────────
  // One shared timer loops over every ride currently in activeRideIds, so
  // accepting a 2nd/3rd passenger no longer stops updating the 1st one's
  // marker (previously this canceled/restarted per-ride, which meant only
  // the most recently accepted ride was ever tracked).
  void _startCustomerLocationTracking() {
    if (_customerLocationTimer != null) return; // already running

    _customerLocationTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) async {
        final rideIds = activeRideIds.toList(); // snapshot
        for (final rideId in rideIds) {
          try {
            final location = await ApiService.getCustomerLocation(rideId);
            if (location != null && mounted) {
              setState(() {
                customerLocations[rideId] = LatLng(
                  location['latitude'],
                  location['longitude'],
                );
              });
            }
          } catch (e) {
            debugPrint('Customer location error ($rideId): $e');
          }
        }
      },
    );
  }

  // Remove one completed ride's marker/tracking without touching any
  // other still-active ride.
  void _removeCompletedRide(String rideId) {
    if (!mounted) return;
    setState(() {
      activeRideIds.remove(rideId);
      customerLocations.remove(rideId);
    });
  }

  void _handleRideCompleted(Map<String, dynamic> message) {
    final rideId = message['ride_id'];
    final fare = message['fare'].toString();

    // This passenger has reached their stop — stop tracking/showing their
    // marker right away. Other active passengers are untouched.
    _removeCompletedRide(rideId);

    // Show cash confirmation if payment is cash
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Passenger Arrived'),
        content: Text('A passenger has reached their stop.\nFare: ₹$fare'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Navigate to cash confirm screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverCashConfirmScreen(
                    rideId: rideId,
                    fare: fare,
                    customerName: 'Passenger',
                    source: widget.source,
                    destination: widget.destination,
                    routeId: widget.routeId,
                  ),
                ),
              );
            },
            child: const Text('Collect Cash',
                style: TextStyle(color: Colors.black)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Online Paid',
                style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _requestPollTimer?.cancel();
    _customerLocationTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────
  Widget _statItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: const Color.fromARGB(255, 254, 187, 38), size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _formatDistance(dynamic meters) {
    if (meters == null) return '0 m';
    final m = double.tryParse(meters.toString()) ?? 0;
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
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
          Column(
            children: [
              // ── Trip info header ─────────────────────────────────────
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
                        if (driverLocation != null)
                          Text(
                            '📍 ${driverLocation!.latitude.toStringAsFixed(4)}, '
                            '${driverLocation!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                    // Show active ride indicator
                    if (activeRideIds.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.green, size: 10),
                            SizedBox(width: 4),
                            Text('Ride Active',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // ── Map ─────────────────────────────────────────────────
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        driverLocation ?? const LatLng(23.0393, 72.5129),
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

                    // Fixed route polyline
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

                    // Markers
                    MarkerLayer(
                      markers: [
                        // Driver location
                        if (driverLocation != null)
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

                        // Customer location (after accepting)
                        ...customerLocations.entries.map((entry) => Marker(
                          point: entry.value,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                        )),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Ride request popup ───────────────────────────────────────
          if (showPopup && pendingRequest != null)
            Positioned(
              bottom: size.height * 0.05,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color.fromARGB(255, 254, 187, 38),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.electric_rickshaw,
                              color: Colors.black),
                          const SizedBox(width: 8),
                          const Text(
                            'New Ride Request!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => showPopup = false),
                            child:
                                const Icon(Icons.close, color: Colors.black),
                          ),
                        ],
                      ),
                    ),

                    // Details
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Pickup
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.circle,
                                  color: Colors.green, size: 12),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Pickup',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                    Text(
                                      pendingRequest!['pickup_address'] ?? '',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Dropoff
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.location_on,
                                  color: Colors.red, size: 12),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Dropoff',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                    Text(
                                      pendingRequest!['dropoff_address'] ?? '',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const Divider(height: 20),

                          // Stats
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _statItem(
                                icon: Icons.straighten,
                                label: 'Ride Distance',
                                value: _formatDistance(
                                    pendingRequest!['distance_meters']),
                              ),
                              _statItem(
                                icon: Icons.currency_rupee,
                                label: 'Fare',
                                // ✅ Safe conversion — no toStringAsFixed on dynamic
                                value:
                                    '₹${(pendingRequest!['fare'] ?? 0).toString()}',
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  onPressed: _acceptRide,
                                  child: const Text('Accept',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side:
                                        const BorderSide(color: Colors.red),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  onPressed: () =>
                                      setState(() => showPopup = false),
                                  child: const Text('Reject',
                                      style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
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