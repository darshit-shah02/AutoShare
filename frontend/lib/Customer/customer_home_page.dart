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

  // final DraggableScrollableController _sheetController = DraggableScrollableController();

  List<Map<String, dynamic>> _pickupSuggestions = [];
  List<Map<String, dynamic>> _dropoffSuggestions = [];
  double? _pickupLat, _pickupLng;
  double? _dropoffLat, _dropoffLng;
  Timer? _debounce;  // prevents API call on every single keystroke

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

    // Get real GPS location
    final location = await ApiService.getCurrentLocation();
    if (location != null) {
      setState(() {
        _currentLocation = LatLng(
          location['latitude']!,
          location['longitude']!,
        );
      });
      // Move map to user's real location
      _mapController.move(_currentLocation!, 15);
      await _reverseGeocode(location['latitude']!, location['longitude']!);
    }
  }

  // double _sheetExtent = 0.67;

  @override
  void dispose() {
    pickupController.dispose();
    dropoffController.dispose();
    // _sheetController.dispose();
    super.dispose();
  }

  // ── Search with debounce ──────────────────────────────────────────────────
  // Waits 500ms after user stops typing before calling API
  // Prevents too many API calls while user is still typing
  void _onPickupChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (value.length >= 3) {
        final suggestions = await ApiService.searchAddress(value);
        setState(() => _pickupSuggestions = suggestions);
      } else {
        setState(() => _pickupSuggestions = []);
      }
    });
  }

  void _onDropoffChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (value.length >= 3) {
        final suggestions = await ApiService.searchAddress(value);
        setState(() => _dropoffSuggestions = suggestions);
      } else {
        setState(() => _dropoffSuggestions = []);
      }
    });
  }

  // ── Reverse Geocode ───────────────────────────────────────────────────────
  // Converts GPS coordinates to a human readable address
  // Called when app gets user's location on startup
  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?lat=$lat&lon=$lng&format=json'
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
      _pickupLat = 23.0393;
      _pickupLng = 72.5129;
    }
  }

  // String _calculateDistance() {
  //   if (_pickupLat == null || _dropoffLat == null) return '';
    
  //   const Distance distance = Distance();
  //   final meters = distance(
  //     LatLng(_pickupLat!, _pickupLng!),
  //     LatLng(_dropoffLat!, _dropoffLng!),
  //   );
    
  //   if (meters < 1000) {
  //     return '${meters.toStringAsFixed(0)} m';
  //   } else {
  //     return '${(meters / 1000).toStringAsFixed(1)} km';
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    // final screenHeight = MediaQuery.of(context).size.height;

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
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _ahmedabad,
                    initialZoom: 13,
                    minZoom: 10,
                    maxZoom: 18,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.autorickshaw',
                    ),
                    // Show markers only when coordinates are selected
                    // MarkerLayer(
                    //   markers: [
                    //     // User's current GPS location
                    //     if (_currentLocation != null)
                    //       Marker(
                    //         point: _currentLocation!,
                    //         width: 40,
                    //         height: 40,
                    //         child: const Icon(
                    //           Icons.person_pin_circle,
                    //           color: Colors.blue,
                    //           size: 40,
                    //         ),
                    //       ),
                    //     // Pickup location marker
                    //     if (_pickupLat != null && _pickupLng != null)
                    //       Marker(
                    //         point: LatLng(_pickupLat!, _pickupLng!),
                    //         width: 40,
                    //         height: 40,
                    //         child: const Icon(
                    //           Icons.location_on,
                    //           color: Colors.green,
                    //           size: 40,
                    //         ),
                    //       ),
                    //     // Dropoff location marker
                    //     if (_dropoffLat != null && _dropoffLng != null)
                    //       Marker(
                    //         point: LatLng(_dropoffLat!, _dropoffLng!),
                    //         width: 40,
                    //         height: 40,
                    //         child: const Icon(
                    //           Icons.location_on,
                    //           color: Colors.red,
                    //           size: 40,
                    //         ),
                    //       ),
                    //   ],
                    // ),
                  ],
                ),
              ),
              // AnimatedPositioned(
              //   duration: const Duration(milliseconds: 100),
              //   curve: Curves.easeOut,
              //   bottom: screenHeight * _sheetExtent + 10,
              //   right: 20,
              //   child: FloatingActionButton(
              //     heroTag: 'customer_home_fab',
              //     backgroundColor: Colors.white,
              //     elevation: 4,
              //     onPressed: () {
              //       if (_pickupLat != null && _pickupLng != null) {
              //         // Move to pickup location
              //         _mapController.move(LatLng(_pickupLat!, _pickupLng!), 14);
              //       } else if (_currentLocation != null) {
              //         // Move to current location
              //         _mapController.move(_currentLocation!, 14);
              //       } else {
              //         _mapController.move(_ahmedabad, 14);
              //       }
              //     },
              //     child: const Icon(Icons.my_location, color: Colors.black87),
              //   ),
              // ),
              DraggableScrollableSheet(
                // controller: _sheetController,
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
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              height: 5,
                              width: 40,
                              margin:
                                  const EdgeInsets.only(top: 5, bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Select Address',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Divider(thickness: 1, color: Colors.grey),
                            _buildTextField(
                              hint: 'Pickup Location',
                              prefixIcon: const Icon(
                                Icons.gps_fixed,
                                color: Color.fromARGB(255, 254, 187, 38),
                              ),
                              controller: pickupController,
                              onChanged: _onPickupChanged,
                            ),
                            if (_pickupSuggestions.isNotEmpty)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black26, blurRadius: 4)
                                  ],
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _pickupSuggestions.length,
                                  itemBuilder: (context, index) {
                                    final suggestion = _pickupSuggestions[index];
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.location_on, color: Colors.grey),
                                      title: Text(
                                        suggestion['short_name'] ?? suggestion['display_name'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                      subtitle: Text(
                                        suggestion['display_name'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      onTap: () {
                                        final lat = suggestion['lat'] as double;
                                        final lng = suggestion['lng'] as double;
                                        setState(() {
                                          pickupController.text = suggestion['display_name'];
                                          _pickupLat = lat;
                                          _pickupLng = lng;
                                          _pickupSuggestions = [];  // hide suggestions
                                        });

                                        // Move map to selected location
                                        // WidgetsBinding.instance.addPostFrameCallback((_) {
                                        //   _mapController.move(LatLng(lat, lng), 15);
                                        //   _sheetController.animateTo(
                                        //     0.15,
                                        //     duration: const Duration(milliseconds: 300),
                                        //     curve: Curves.easeOut,
                                        //   );
                                        // });
                                      },
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 8),
                            _buildTextField(
                              hint: 'Dropoff Destination',
                              prefixIcon: const Icon(
                                Icons.location_on,
                                color: Color.fromARGB(255, 254, 187, 38),
                              ),
                              controller: dropoffController,
                              onChanged: _onDropoffChanged,
                            ),
                            if (_dropoffSuggestions.isNotEmpty)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black26, blurRadius: 4)
                                  ],
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _dropoffSuggestions.length,
                                  itemBuilder: (context, index) {
                                    final suggestion = _dropoffSuggestions[index];
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.location_on, color: Colors.grey),
                                      title: Text(
                                        suggestion['short_name'] ?? suggestion['display_name'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                      subtitle: Text(
                                        suggestion['display_name'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      onTap: () {
                                        final lat = suggestion['lat'] as double;
                                        final lng = suggestion['lng'] as double;
                                        setState(() {
                                          dropoffController.text = suggestion['display_name'];
                                          _dropoffLat = lat;
                                          _dropoffLng = lng;
                                          _dropoffSuggestions = [];
                                        });
                                        // WidgetsBinding.instance.addPostFrameCallback((_) {
                                        //   _mapController.move(LatLng(lat, lng), 13);
                                        //   _sheetController.animateTo(
                                        //     0.15,
                                        //     duration: const Duration(milliseconds: 300),
                                        //     curve: Curves.easeOut,
                                        //   );
                                        // });
                                      },
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 8),
                            // if (_pickupLat != null && _dropoffLat != null)
                            //   Padding(
                            //     padding: const EdgeInsets.symmetric(vertical: 8),
                            //     child: Row(
                            //       mainAxisAlignment: MainAxisAlignment.center,
                            //       children: [
                            //         const Icon(Icons.straighten, size: 16, color: Colors.grey),
                            //         const SizedBox(width: 4),
                            //         Text(
                            //           'Distance: ${_calculateDistance()}',
                            //           style: const TextStyle(
                            //             fontSize: 14,
                            //             fontWeight: FontWeight.w500,
                            //             color: Colors.grey,
                            //           ),
                            //         ),
                            //       ],
                            //     ),
                            //   ),
                            const Divider(thickness: 1, color: Colors.grey),
                            ElevatedButton(
                              // Only enable if both locations selected with real coordinates
                              onPressed: (_pickupLat != null && _dropoffLat != null)
                                  ? () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ConfirmRideScreen(
                                            pickupLat: _pickupLat!,
                                            pickupLng: _pickupLng!,
                                            pickupAddress: pickupController.text,
                                            dropoffLat: _dropoffLat!,
                                            dropoffLng: _dropoffLng!,
                                            dropoffAddress: dropoffController.text,
                                            userId: userId,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,  // disabled until real location selected
                              child: const Text('Next'),
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
              borderSide: const BorderSide(color: Colors.grey, width: 1.5),
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
