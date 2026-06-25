import 'package:autoshare/Driver/driver_online.dart';
import 'package:autoshare/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RouteSelectionScreen extends StatefulWidget {
  const RouteSelectionScreen({super.key});

  @override
  RouteSelectionScreenState createState() => RouteSelectionScreenState();
}

class RouteSelectionScreenState extends State<RouteSelectionScreen> {
  List<Map<String, dynamic>> _routes = [];
  bool _isLoading = true;
  String? _selectedRouteId;
  String _driverId = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _driverId = prefs.getString('userId') ?? '';
    await _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    try {
      final routes = await ApiService.getPredefinedRoutes();
      setState(() {
        _routes = routes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmRoute() async {
    if (_selectedRouteId == null) return;

    try {
      await ApiService.selectDriverRoute(
        driverId: _driverId,
        routeId: _selectedRouteId!,
      );

      final selectedRoute = _routes.firstWhere(
        (r) => r['id'] == _selectedRouteId,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverOnline(
            source: selectedRoute['start_address'] ?? '',
            destination: selectedRoute['end_address'] ?? '',
            routeId: _selectedRouteId!,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to select route: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Select Your Route',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color.fromARGB(255, 254, 187, 38),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color.fromARGB(255, 254, 187, 38),
              ),
            )
          : Column(
              children: [
                // ── Header ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey.shade50,
                  child: const Text(
                    'Select the route you will drive today',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ),

                // ── Route List ───────────────────────────────────────
                Expanded(
                  child: _routes.isEmpty
                      ? const Center(
                          child: Text(
                            'No routes available.\nContact admin to add routes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _routes.length,
                          itemBuilder: (context, index) {
                            final route = _routes[index];
                            final isSelected =
                                _selectedRouteId == route['id'];

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedRouteId = route['id'];
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color.fromARGB(
                                          255, 254, 248, 195)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color.fromARGB(
                                            255, 254, 187, 38)
                                        : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      // Route icon
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color.fromARGB(
                                                  255, 254, 187, 38)
                                              : Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        child: Icon(
                                          Icons.electric_rickshaw,
                                          color: isSelected
                                              ? Colors.black
                                              : Colors.grey,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // Route details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              route['name'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.circle,
                                                  color: Colors.green,
                                                  size: 10,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    route['start_address'] ??
                                                        '',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.location_on,
                                                  color: Colors.red,
                                                  size: 10,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    route['end_address'] ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),

                                            // Distance and duration
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.straighten,
                                                  size: 12,
                                                  color: Colors.grey.shade500,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${((route['total_distance_meters'] ?? 0) / 1000).toStringAsFixed(1)} km',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Icon(
                                                  Icons.access_time,
                                                  size: 12,
                                                  color: Colors.grey.shade500,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '~${route['estimated_duration_minutes'] ?? 0} min',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Selection indicator
                                      if (isSelected)
                                        const Icon(
                                          Icons.check_circle,
                                          color: Color.fromARGB(
                                              255, 254, 187, 38),
                                          size: 24,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // ── Confirm Button ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedRouteId != null
                            ? const Color.fromARGB(255, 254, 187, 38)
                            : Colors.grey.shade300,
                        foregroundColor: _selectedRouteId != null
                            ? Colors.black
                            : Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed:
                          _selectedRouteId != null ? _confirmRoute : null,
                      child: const Text(
                        'Start Driving on This Route',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}