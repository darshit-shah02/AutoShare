import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../General/app_drawer.dart';
import '../General/exit_pop_up.dart';
import 'package:autoshare/services/api_service.dart';
import 'dart:async';
import 'package:autoshare/Customer/confirm_ride_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  CustomerHomePageState createState() => CustomerHomePageState();
}

class CustomerHomePageState extends State<CustomerHomePage> {
  String userName = '';
  String userId = '';
  LatLng? _currentLocation;

  final MapController _mapController = MapController();
  final LatLng _ahmedabad = const LatLng(23.0215374, 72.5800568);

  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();

  List<Map<String, dynamic>> _pickupSuggestions = [];
  List<Map<String, dynamic>> _dropoffSuggestions = [];
  double? _pickupLat, _pickupLng;
  double? _dropoffLat, _dropoffLng;
  Timer? _debounce;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('userName') ?? 'Customer';
      userId = prefs.getString('userId') ?? '';
    });

    final location = await ApiService.getCurrentLocation();
    if (location != null) {
      setState(() {
        _currentLocation = LatLng(
          location['latitude']!,
          location['longitude']!,
        );
      });
      _mapController.move(_currentLocation!, 15);
      await _reverseGeocode(location['latitude']!, location['longitude']!);
    }
  }

  @override
  void dispose() {
    pickupController.dispose();
    dropoffController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Search with debounce ──────────────────────────────────────────────────
  void _onPickupChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (value.length >= 3) {
        final suggestions = await ApiService.searchAddress(value);
        if (mounted) setState(() => _pickupSuggestions = suggestions);
      } else {
        if (mounted) setState(() => _pickupSuggestions = []);
      }
    });
  }

  void _onDropoffChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (value.length >= 3) {
        final suggestions = await ApiService.searchAddress(value);
        if (mounted) setState(() => _dropoffSuggestions = suggestions);
      } else {
        if (mounted) setState(() => _dropoffSuggestions = []);
      }
    });
  }

  // ── Reverse Geocode ───────────────────────────────────────────────────────
  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?lat=$lat&lon=$lng&format=json',
        ),
        headers: {'User-Agent': 'AutoShare/1.0'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['display_name'] ?? '';
        if (address.isNotEmpty && mounted) {
          setState(() {
            pickupController.text = address;
            _pickupLat = lat;
            _pickupLng = lng;
          });
        }
      }
    } catch (e) {
      // Keep coordinates as fallback
      if (mounted) {
        setState(() {
          _pickupLat = lat;
          _pickupLng = lng;
        });
      }
    }
  }

  // ── Use Current Location as Pickup ────────────────────────────────────────
  Future<void> _useCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final location = await ApiService.getCurrentLocation();
      if (location == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get location. Please enable GPS.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _currentLocation = LatLng(
          location['latitude']!,
          location['longitude']!,
        );
      });

      _mapController.move(_currentLocation!, 15);
      await _reverseGeocode(location['latitude']!, location['longitude']!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location set as pickup ✅'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        handlePopResult(context, didPop, result);
      },
      child: Scaffold(
        drawer: AppDrawer(userType: 'Customer', userName: userName),
        appBar: AppBar(
          iconTheme: const IconThemeData(color: Colors.black),
          title: const Text(
            'Customer Home Page',
            style: TextStyle(color: Colors.black),
          ),
          backgroundColor: const Color.fromARGB(255, 254, 187, 38),
        ),
        backgroundColor: const Color.fromARGB(255, 254, 187, 38),
        body: SafeArea(
          child: Stack(
            children: [
              // ── Map background ───────────────────────────────────────
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation ?? _ahmedabad,
                    initialZoom: 13,
                    minZoom: 10,
                    maxZoom: 18,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.autorickshaw',
                    ),
                    // Show current location marker on map
                    if (_currentLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentLocation!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // ── Bottom sheet ─────────────────────────────────────────
              DraggableScrollableSheet(
                initialChildSize: 0.67,
                minChildSize: 0.05,
                maxChildSize: 0.67,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6)
                      ],
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Drag handle ──────────────────────────
                            Center(
                              child: Container(
                                height: 5,
                                width: 40,
                                margin: const EdgeInsets.only(
                                    top: 5, bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Center(
                              child: Text(
                                'Select Address',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Divider(
                                thickness: 1, color: Colors.grey),

                            // ── Pickup label + Use My Location ───────
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Pickup',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _isLoadingLocation
                                      ? null
                                      : _useCurrentLocation,
                                  icon: _isLoadingLocation
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color.fromARGB(
                                                255, 254, 187, 38),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.my_location,
                                          size: 14,
                                          color: Color.fromARGB(
                                              255, 254, 187, 38),
                                        ),
                                  label: const Text(
                                    'Use my location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color.fromARGB(
                                          255, 254, 187, 38),
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),

                            // ── Pickup text field ────────────────────
                            _buildTextField(
                              hint: 'Pickup Location',
                              prefixIcon: const Icon(
                                Icons.gps_fixed,
                                color: Color.fromARGB(255, 254, 187, 38),
                              ),
                              controller: pickupController,
                              onChanged: _onPickupChanged,
                            ),

                            // ── Pickup suggestions ───────────────────
                            if (_pickupSuggestions.isNotEmpty)
                              _buildSuggestionsList(
                                suggestions: _pickupSuggestions,
                                onSelect: (suggestion) {
                                  setState(() {
                                    pickupController.text =
                                        suggestion['display_name'];
                                    _pickupLat =
                                        suggestion['lat'] as double;
                                    _pickupLng =
                                        suggestion['lng'] as double;
                                    _pickupSuggestions = [];
                                  });
                                },
                              ),

                            const SizedBox(height: 12),

                            // ── Dropoff label ────────────────────────
                            const Text(
                              'Dropoff',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // ── Dropoff text field ───────────────────
                            _buildTextField(
                              hint: 'Dropoff Destination',
                              prefixIcon: const Icon(
                                Icons.location_on,
                                color: Color.fromARGB(255, 254, 187, 38),
                              ),
                              controller: dropoffController,
                              onChanged: _onDropoffChanged,
                            ),

                            // ── Dropoff suggestions ──────────────────
                            if (_dropoffSuggestions.isNotEmpty)
                              _buildSuggestionsList(
                                suggestions: _dropoffSuggestions,
                                onSelect: (suggestion) {
                                  setState(() {
                                    dropoffController.text =
                                        suggestion['display_name'];
                                    _dropoffLat =
                                        suggestion['lat'] as double;
                                    _dropoffLng =
                                        suggestion['lng'] as double;
                                    _dropoffSuggestions = [];
                                  });
                                },
                              ),

                            const SizedBox(height: 12),
                            const Divider(
                                thickness: 1, color: Colors.grey),

                            // ── Next button ──────────────────────────
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    (_pickupLat != null &&
                                            _dropoffLat != null)
                                        ? () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ConfirmRideScreen(
                                                  pickupLat: _pickupLat!,
                                                  pickupLng: _pickupLng!,
                                                  pickupAddress:
                                                      pickupController
                                                          .text,
                                                  dropoffLat: _dropoffLat!,
                                                  dropoffLng: _dropoffLng!,
                                                  dropoffAddress:
                                                      dropoffController
                                                          .text,
                                                  userId: userId,
                                                ),
                                              ),
                                            );
                                          }
                                        : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color.fromARGB(
                                      255, 254, 187, 38),
                                  foregroundColor: Colors.black,
                                  disabledBackgroundColor:
                                      Colors.grey.shade300,
                                  minimumSize:
                                      const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Next',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reusable suggestions list ─────────────────────────────────────────────
  Widget _buildSuggestionsList({
    required List<Map<String, dynamic>> suggestions,
    required Function(Map<String, dynamic>) onSelect,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Colors.grey),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return ListTile(
            dense: true,
            leading:
                const Icon(Icons.location_on, color: Colors.grey, size: 18),
            title: Text(
              suggestion['short_name'] ?? suggestion['display_name'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              suggestion['display_name'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            onTap: () => onSelect(suggestion),
          );
        },
      ),
    );
  }

  // ── Text field builder ────────────────────────────────────────────────────
  Widget _buildTextField({
    required String hint,
    required Widget prefixIcon,
    required TextEditingController controller,
    Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(50),
        child: TextField(
          controller: controller,
          onChanged: (value) {
            setState(() {});
            onChanged?.call(value);
          },
          decoration: InputDecoration(
            prefixIcon: prefixIcon,
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
              borderSide:
                  const BorderSide(color: Colors.grey, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
              borderSide: const BorderSide(
                  color: Color.fromARGB(255, 254, 187, 38), width: 2.0),
            ),
          ),
        ),
      ),
    );
  }
}