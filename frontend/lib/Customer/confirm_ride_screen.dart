import 'dart:convert';
import 'package:autoshare/Customer/autoricksaw_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class ConfirmRideScreen extends StatefulWidget {
  // Pickup details
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;

  // Dropoff details
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddress;

  // User details
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

  // Route points between pickup and dropoff
  List<LatLng> _routePoints = [];

  // Calculated distance and estimated fare
  String _distance = '';
  double _estimatedFare = 0;

  bool _isLoadingRoute = true;

  @override
  void initState() {
    super.initState();
    _loadRouteAndDetails();
  }

  // ── Load route between pickup and dropoff ──────────────────────────────
  // Uses OSRM to get the actual road route
  // Also calculates distance and estimated fare
  Future<void> _loadRouteAndDetails() async {
    try {
      // Calculate straight line distance using latlong2
      const Distance distanceCalc = Distance();
      final meters = distanceCalc(
        LatLng(widget.pickupLat, widget.pickupLng),
        LatLng(widget.dropoffLat, widget.dropoffLng),
      );

      // Estimate fare — base ₹10 + ₹2 per 100 meters
      final fare = _calculateFare(meters);

      setState(() {
        _distance = meters < 1000
            ? '${meters.toStringAsFixed(0)} m'
            : '${(meters / 1000).toStringAsFixed(1)} km';
        _estimatedFare = double.parse(fare.toStringAsFixed(0));
      });

      // Get road route from OSRM
      await _fetchRoute();

      // Fit map to show both markers
      _fitMapToBounds();

    } catch (e) {
      setState(() => _isLoadingRoute = false);
    }
  }

  // ── Fetch road route from OSRM ─────────────────────────────────────────
  // OSRM gives us the actual road path between two points
  // Much better than a straight line
  Future<void> _fetchRoute() async {
    try {
      final url =
          'http://router.project-osrm.org/route/v1/driving/'
          '${widget.pickupLng},${widget.pickupLat};'
          '${widget.dropoffLng},${widget.dropoffLat}'
          '?overview=full&geometries=geojson';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'AutoShare/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;

        setState(() {
          _routePoints = coords
              .map<LatLng>((c) => LatLng(c[1] as double, c[0] as double))
              .toList();
          _isLoadingRoute = false;
        });

        // Update distance with actual road distance from OSRM
        final roadDistance = data['routes'][0]['distance'] as double;
        final roadFare = _calculateFare(roadDistance);
        setState(() {
          _distance = roadDistance < 1000
              ? '${roadDistance.toStringAsFixed(0)} m'
              : '${(roadDistance / 1000).toStringAsFixed(1)} km';
          _estimatedFare = double.parse(roadFare.toStringAsFixed(0));
        });
      }
    } catch (e) {
      setState(() => _isLoadingRoute = false);
    }
  }

  // ── Fit map to show both pickup and dropoff ────────────────────────────
  // Calculates the bounds that contain both markers
  // Then moves map to show them both with some padding
  void _fitMapToBounds() {
    final bounds = LatLngBounds(
      LatLng(
        widget.pickupLat < widget.dropoffLat
            ? widget.pickupLat
            : widget.dropoffLat,
        widget.pickupLng < widget.dropoffLng
            ? widget.pickupLng
            : widget.dropoffLng,
      ),
      LatLng(
        widget.pickupLat > widget.dropoffLat
            ? widget.pickupLat
            : widget.dropoffLat,
        widget.pickupLng > widget.dropoffLng
            ? widget.pickupLng
            : widget.dropoffLng,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
        ),
      );
    });
  }

  // ── Shared Auto Fare Calculator ───────────────────────────────────────────
  // Fixed price slabs for shared auto rickshaw
  // Much cheaper than regular auto since route is fixed
  double _calculateFare(double meters) {
    final km = meters / 1000;

    if (km <= 1) return 10;
    if (km <= 3) return 20;
    if (km <= 5) return 30;
    if (km <= 7) return 40;
    if (km <= 10) return 50;
    // Beyond 10km — add ₹10 per extra 2km
    return 50 + ((km - 10) / 2).ceil() * 10;
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
                initialCenter: LatLng(
                  (widget.pickupLat + widget.dropoffLat) / 2,
                  (widget.pickupLng + widget.dropoffLng) / 2,
                ),
                initialZoom: 13,
                minZoom: 10,
                maxZoom: 18,
              ),
              children: [
                // OSM tiles
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.autorickshaw',
                ),

                // Route line between pickup and dropoff
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        color: const Color.fromARGB(255, 254, 187, 38),
                        strokeWidth: 5,
                      ),
                    ],
                  ),

                // Markers
                MarkerLayer(
                  markers: [
                    // Pickup marker — green
                    Marker(
                      point: LatLng(widget.pickupLat, widget.pickupLng),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                    // Dropoff marker — red
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
          if (_isLoadingRoute)
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
                        Text('Loading route...'),
                      ],
                    ),
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
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
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

                  // Pickup row
                  Row(
                    children: [
                      const Icon(Icons.circle,
                          color: Colors.green, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.pickupAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Dotted line between pickup and dropoff
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Column(
                      children: List.generate(
                        3,
                        (i) => Container(
                          width: 2,
                          height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Dropoff row
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.red, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.dropoffAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Distance and fare row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Distance
                      Row(
                        children: [
                          const Icon(Icons.straighten,
                              size: 18, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            _distance.isEmpty ? 'Calculating...' : _distance,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      // Estimated fare
                      Row(
                        children: [
                          const Icon(Icons.currency_rupee,
                              size: 18, color: Colors.grey),
                          Text(
                            _estimatedFare == 0
                                ? 'Calculating...'
                                : '₹${_estimatedFare.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(Shared Auto)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Check for Autos button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color.fromARGB(255, 254, 187, 38),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
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
                      },
                      child: const Text(
                        'Check for Autos',
                        style: TextStyle(
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
}