import 'dart:convert';
import 'package:autoshare/Customer/autoricksaw_list.dart';
import 'package:autoshare/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class ConfirmRideScreen extends StatefulWidget {
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddress;
  final String userId;

  const ConfirmRideScreen({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.dropoffAddress,
    required this.userId,
  });

  @override
  ConfirmRideScreenState createState() => ConfirmRideScreenState();
}

class ConfirmRideScreenState extends State<ConfirmRideScreen> {
  final MapController _mapController = MapController();

  // Fixed route points from database
  List<LatLng> _fixedRoutePoints = [];

  // Walking paths
  List<LatLng> _walkingToPickupRoute = [];   // user → nearest pickup point
  List<LatLng> _walkingFromDropoff = [];      // nearest dropoff point → destination

  // Nearest points on fixed route
  LatLng? _nearestPickupPoint;   // where user boards auto
  LatLng? _nearestDropoffPoint;  // where user exits auto

  // Distances
  double _walkToRouteMeters = 0;    // x — walking to fixed route
  double _rideOnRouteMeters = 0;    // y — ride on fixed route
  double _walkFromRouteMeters = 0;  // z — walking from fixed route

  // Fare based on y
  double _fare = 0;

  // Whether user is within 300m of fixed route
  bool _canBook = false;
  bool _isLoading = true;
  String _statusMessage = 'Calculating your route...';

  @override
  void initState() {
    super.initState();
    _loadRouteDetails();
  }

  Future<void> _loadRouteDetails() async {
    try {
      // Step 1 — Load fixed route from backend
      final coords = await ApiService.getFixedRoute();
      setState(() {
        _fixedRoutePoints = coords
            .map<LatLng>((c) => LatLng(c['lat'], c['lng']))
            .toList();
      });
      print('Fixed route coords count: ${coords.length}');

      // Step 2 — Get nearest points on fixed route
      final token = await ApiService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      // Get nearest pickup point on fixed route
      final pickupNearestRes = await http.get(
        Uri.parse(
          '${ApiService.baseUrl}/rides/nearest-on-route'
          '?lat=${widget.pickupLat}&lng=${widget.pickupLng}'
        ),
        headers: headers,
      );
      // ignore: avoid_print
      print('Pickup nearest status: ${pickupNearestRes.statusCode}');
      print('Pickup nearest body: ${pickupNearestRes.body}');

      // Get nearest dropoff point on fixed route
      final dropoffNearestRes = await http.get(
        Uri.parse(
          '${ApiService.baseUrl}/rides/nearest-on-route'
          '?lat=${widget.dropoffLat}&lng=${widget.dropoffLng}'
        ),
        headers: headers,
      );
      // ignore: avoid_print
      print('Dropoff nearest status: ${dropoffNearestRes.statusCode}');
      print('Dropoff nearest body: ${dropoffNearestRes.body}');

      if (pickupNearestRes.statusCode == 200 &&
          dropoffNearestRes.statusCode == 200) {
        final pickupNearest = jsonDecode(pickupNearestRes.body);
        final dropoffNearest = jsonDecode(dropoffNearestRes.body);

        setState(() {
          _nearestPickupPoint = LatLng(
            pickupNearest['latitude'],
            pickupNearest['longitude'],
          );
          _nearestDropoffPoint = LatLng(
            dropoffNearest['latitude'],
            dropoffNearest['longitude'],
          );
        });

        // Step 3 — Calculate all 3 distances
        const distCalc = Distance();

        // x — walk from user to nearest pickup point on route
        _walkToRouteMeters = distCalc(
          LatLng(widget.pickupLat, widget.pickupLng),
          _nearestPickupPoint!,
        );

        // y — ride distance along fixed route
        _rideOnRouteMeters = distCalc(
          _nearestPickupPoint!,
          _nearestDropoffPoint!,
        );

        // z — walk from dropoff route point to destination
        _walkFromRouteMeters = distCalc(
          _nearestDropoffPoint!,
          LatLng(widget.dropoffLat, widget.dropoffLng),
        );

        // Step 4 — Calculate fare based on y (ride distance)
        _fare = _calculateFare(_rideOnRouteMeters);

        // Step 5 — Check if user is within 300m of fixed route
        _canBook = _walkToRouteMeters <= 300;

        setState(() {
          _statusMessage = _canBook
              ? 'You can book this ride!'
              : 'You are ${(_walkToRouteMeters / 1000).toStringAsFixed(2)} km '
                'from the nearest auto route point. Must be within 300m.';
        });

        // Step 6 — Get walking paths from OSRM
        await _fetchWalkingPaths();

        // Step 7 — Fit map to show everything
        _fitMap();
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading route details. Please try again.';
        _isLoading = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Shared Auto Fare Slabs ────────────────────────────────────────────
  double _calculateFare(double meters) {
    final km = meters / 1000;
    if (km <= 1) return 10;
    if (km <= 3) return 20;
    if (km <= 5) return 30;
    if (km <= 7) return 40;
    if (km <= 10) return 50;
    return 50 + (((km - 10) / 2).ceil()) * 10;
  }

  // ── Fetch Walking Paths ───────────────────────────────────────────────
  Future<void> _fetchWalkingPaths() async {
    if (_nearestPickupPoint == null || _nearestDropoffPoint == null) return;

    try {
      // Walking path 1: user → nearest pickup point on route
      final path1 = await _getWalkingPath(
        fromLat: widget.pickupLat,
        fromLng: widget.pickupLng,
        toLat: _nearestPickupPoint!.latitude,
        toLng: _nearestPickupPoint!.longitude,
      );
      setState(() => _walkingToPickupRoute = path1);

      // Walking path 2: nearest dropoff point → destination
      final path2 = await _getWalkingPath(
        fromLat: _nearestDropoffPoint!.latitude,
        fromLng: _nearestDropoffPoint!.longitude,
        toLat: widget.dropoffLat,
        toLng: widget.dropoffLng,
      );
      setState(() => _walkingFromDropoff = path2);
    } catch (e) {
      debugPrint('Walking path error: $e');
    }
  }

  Future<List<LatLng>> _getWalkingPath({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    final token = await ApiService.getToken();
    final response = await http.get(
      Uri.parse(
        '${ApiService.baseUrl}/rides/walking-path'
        '?from_lat=$fromLat&from_lng=$fromLng'
        '&to_lat=$toLat&to_lng=$toLng'
      ),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List coords = data['path'];
      return coords.map<LatLng>((c) => LatLng(c['lat'], c['lng'])).toList();
    }
    return [];
  }

  // ── Fit Map to Show Everything ────────────────────────────────────────
  void _fitMap() {
    final allPoints = [
      LatLng(widget.pickupLat, widget.pickupLng),
      LatLng(widget.dropoffLat, widget.dropoffLng),
      if (_nearestPickupPoint != null) _nearestPickupPoint!,
      if (_nearestDropoffPoint != null) _nearestDropoffPoint!,
      ..._fixedRoutePoints,
    ];

    if (allPoints.isEmpty) return;

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat, minLng),
            LatLng(maxLat, maxLng),
          ),
          padding: const EdgeInsets.all(60),
        ),
      );
    });
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Confirm Ride',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color.fromARGB(255, 254, 187, 38),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          // ── Full screen map ──────────────────────────────────────────
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(widget.pickupLat, widget.pickupLng),
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.autorickshaw',
                ),

                // Fixed auto route — yellow solid line
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

                // Walking path to pickup point — blue dotted
                if (_walkingToPickupRoute.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _walkingToPickupRoute,
                        color: Colors.blue,
                        strokeWidth: 3,
                      ),
                    ],
                  ),

                // Walking path from dropoff — blue dotted
                if (_walkingFromDropoff.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _walkingFromDropoff,
                        color: Colors.blue,
                        strokeWidth: 3,
                      ),
                    ],
                  ),

                // Markers
                MarkerLayer(
                  markers: [
                    // User's pickup location
                    Marker(
                      point: LatLng(widget.pickupLat, widget.pickupLng),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),

                    // Nearest point on route for pickup — where auto picks up
                    if (_nearestPickupPoint != null)
                      Marker(
                        point: _nearestPickupPoint!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.directions_walk,
                          color: Colors.green,
                          size: 40,
                        ),
                      ),

                    // Nearest point on route for dropoff — where auto drops
                    if (_nearestDropoffPoint != null)
                      Marker(
                        point: _nearestDropoffPoint!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.directions_walk,
                          color: Colors.orange,
                          size: 40,
                        ),
                      ),

                    // User's dropoff destination
                    Marker(
                      point: LatLng(widget.dropoffLat, widget.dropoffLng),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Loading indicator ────────────────────────────────────────
          if (_isLoading)
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color.fromARGB(255, 254, 187, 38),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Calculating your route...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Map legend ───────────────────────────────────────────────
          Positioned(
            top: 16,
            left: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Row(children: [
                      Icon(Icons.person_pin_circle,
                          color: Colors.blue, size: 16),
                      SizedBox(width: 4),
                      Text('You', style: TextStyle(fontSize: 11)),
                    ]),
                    Row(children: [
                      Icon(Icons.directions_walk,
                          color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('Board here', style: TextStyle(fontSize: 11)),
                    ]),
                    Row(children: [
                      Icon(Icons.directions_walk,
                          color: Colors.orange, size: 16),
                      SizedBox(width: 4),
                      Text('Exit here', style: TextStyle(fontSize: 11)),
                    ]),
                    Row(children: [
                      Icon(Icons.location_on,
                          color: Colors.red, size: 16),
                      SizedBox(width: 4),
                      Text('Destination', style: TextStyle(fontSize: 11)),
                    ]),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom details card ──────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Distance breakdown ─────────────────────────────
                  // x — walking to route
                  _distanceRow(
                    icon: Icons.directions_walk,
                    color: Colors.blue,
                    label: 'Walk to auto route',
                    distance: _formatDistance(_walkToRouteMeters),
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 8),

                  // y — ride on fixed route
                  _distanceRow(
                    icon: Icons.electric_rickshaw,
                    color: const Color.fromARGB(255, 254, 187, 38),
                    label: 'Ride on fixed route',
                    distance: _formatDistance(_rideOnRouteMeters),
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 8),

                  // z — walking from route
                  _distanceRow(
                    icon: Icons.directions_walk,
                    color: Colors.orange,
                    label: 'Walk to destination',
                    distance: _formatDistance(_walkFromRouteMeters),
                    isLoading: _isLoading,
                  ),

                  const Divider(height: 24),

                  // Fare
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Estimated Fare',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isLoading
                            ? 'Calculating...'
                            : '₹${_fare.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 254, 187, 38),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 300m warning if too far
                  if (!_isLoading && !_canBook)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (!_isLoading && _canBook)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'You are ${_formatDistance(_walkToRouteMeters)} '
                            'from the auto route ✅',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Book button — only enabled within 300m
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canBook
                            ? const Color.fromARGB(255, 254, 187, 38)
                            : Colors.grey.shade300,
                        foregroundColor:
                            _canBook ? Colors.black : Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: (_canBook && !_isLoading)
                          ? () {
                              Navigator.push(
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
                          : null,
                      child: Text(
                        _isLoading
                            ? 'Loading...'
                            : _canBook
                                ? 'Find Available Autos'
                                : 'Too far from auto route',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Distance row widget ──────────────────────────────────────────────
  Widget _distanceRow({
    required IconData icon,
    required Color color,
    required String label,
    required String distance,
    required bool isLoading,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
        Text(
          isLoading ? '...' : distance,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}