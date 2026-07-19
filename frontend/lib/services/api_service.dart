import 'dart:convert';
import 'package:autoshare/config.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  // Change this to your FastAPI URL
  // For emulator use: http://10.0.2.2:8000
  // For real device use: http://YOUR_PC_IP:8000
  static String get baseUrl => AppConfig.apiBaseUrl;

  // Secure storage for JWT token
  // Unlike SharedPreferences, this encrypts data on the device
  static const _storage = FlutterSecureStorage();

  // ── Token helpers ──────────────────────────────────────────────────────────

  // Save token after login/register
  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'access_token', value: token);
  }

  // Get token for authenticated requests
  static Future<String?> getToken() async {
    return await _storage.read(key: 'access_token');
  }

  // Delete token on logout
  static Future<void> deleteToken() async {
    await _storage.delete(key: 'access_token');
  }

  // ── Auth headers ───────────────────────────────────────────────────────────
  // Attaches JWT token to every request that needs authentication
  static Future<Map<String, String>> authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Register Customer ──────────────────────────────────────────────────────
  // Sends customer details to /auth/register/customer
  // Returns the response map with token, role, user_id, name
  static Future<Map<String, dynamic>> registerCustomer({
    required String name,
    required String email,
    required String phone,
    required String password,
    String gender = 'Other',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register/customer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'gender': gender,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      // Save token securely on device
      await saveToken(data['access_token']);
      return data;
    } else {
      // Throw the error message from FastAPI
      throw Exception(data['detail'] ?? 'Registration failed');
    }
  }

  // ── Register Driver ────────────────────────────────────────────────────────
  // Same as customer but also sends vehicle_number and license_number
  static Future<Map<String, dynamic>> registerDriver({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String vehicleNumber,
    required String licenseNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register/driver'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'vehicle_number': vehicleNumber,
        'license_number': licenseNumber,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      await saveToken(data['access_token']);
      return data;
    } else {
      throw Exception(data['detail'] ?? 'Registration failed');
    }
  }

  // ── Login ──────────────────────────────────────────────────────────────────
  // Sends email, password, role to /auth/login
  // Returns token + user info on success
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String role,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'role': role,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      await saveToken(data['access_token']);
      return data;
    } else {
      throw Exception(data['detail'] ?? 'Login failed');
    }
  }

  // ── Get Driver Stats ─────────────────────────────────────────────────────
  // Fetches driver's rating, total trips and earnings from the backend
  // Called when driver home page loads
  static Future<Map<String, dynamic>> getDriverStats(String driverId) async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/drivers/stats/$driverId'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load driver stats');
    }
  }

  // ── Get Nearby Autos ──────────────────────────────────────────────────────
  // Called when customer enters pickup and dropoff location
  // Returns list of nearby online drivers with fare estimate
  static Future<List<Map<String, dynamic>>> getNearbyAutos({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse(
        '$baseUrl/rides/nearby-autos'
        '?pickup_lat=$pickupLat&pickup_lng=$pickupLng'
        '&dropoff_lat=$dropoffLat&dropoff_lng=$dropoffLng'
      ),
      headers: headers,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to get nearby autos');
    }
  }

  // ── Book a Ride ───────────────────────────────────────────────────────────
  // Called when customer confirms booking with a specific driver
  // Returns ride_id, fare, nearest route points for walking path
  static Future<Map<String, dynamic>> bookRide({
    required String userId,
    required String driverId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? pickupAddress,
    String? dropoffAddress,
  }) async {
    final headers = await authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rides/book'),
      headers: headers,
      body: jsonEncode({
        'user_id': userId,
        'driver_id': driverId,
        'pickup_latitude': pickupLat,
        'pickup_longitude': pickupLng,
        'dropoff_latitude': dropoffLat,
        'dropoff_longitude': dropoffLng,
        'pickup_address': pickupAddress,
        'dropoff_address': dropoffAddress,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Booking failed');
    }
  }
  
  // ── Get Current GPS Location ──────────────────────────────────────────────
  // Requests location permission from user
  // Then gets their current GPS coordinates
  // Returns null if permission denied or location unavailable
  static Future<Map<String, double>?> getCurrentLocation() async {
    // Check if location services are enabled on device
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    // Request permission if not already granted
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!kIsWeb) {  // ← ADD THIS CHECK
        await Geolocator.openAppSettings();
      }
      return null;
    }

    // Get current position with high accuracy
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );

    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
    };
  }

  // ── WebSocket URL ─────────────────────────────────────────────────────────
  // Note: WebSocket uses ws:// not http://
  // For emulator: ws://10.0.2.2:8000
  // For real device: ws://YOUR_PC_IP:8000
  static String get wsUrl => AppConfig.wsBaseUrl;
  // Change to your IP if testing on real device:
  // static const String wsUrl = 'ws://192.168.29.196:8000';

  // ── Connect driver to WebSocket ───────────────────────────────────────────
  // Driver app calls this when they go online
  // Returns a WebSocketChannel that driver uses to send GPS updates
  static WebSocketChannel connectDriverWebSocket(String driverId) {
    final channel = WebSocketChannel.connect(
      Uri.parse('$wsUrl/drivers/ws/driver/$driverId'),
    );
    return channel;
  }

  // ── Connect customer to WebSocket ─────────────────────────────────────────
  // Customer app calls this after booking is confirmed
  // Returns a WebSocketChannel that receives live driver location
  static WebSocketChannel connectCustomerWebSocket(String rideId) {
    final channel = WebSocketChannel.connect(
      Uri.parse('$wsUrl/drivers/ws/customer/$rideId'),
    );
    return channel;
  }

  // ── Get Pending Ride Request ──────────────────────────────────────────────
  // Driver polls this every 3 seconds as backup to WebSocket
  // Ensures driver gets ride requests even if WebSocket disconnects
  static Future<Map<String, dynamic>?> getPendingRequest(
      String driverId) async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/rides/pending-request/$driverId'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['request'];
    }
    return null;
  }

  // ── Update Ride Status ────────────────────────────────────────────────────
  // Called by driver when they accept, start or complete a ride
  // Updates the status in database
  static Future<void> updateRideStatus({
    required String rideId,
    required String status,
  }) async {
    final headers = await authHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/rides/$rideId/status'),
      headers: headers,
      body: jsonEncode({'status': status}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to update ride status: ${response.statusCode}');
    }
  }

  // ── Complete Ride ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> completeRide(String rideId) async {
    final headers = await authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rides/$rideId/complete'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to complete ride');
  }

  // ── Driver Confirms Cash Received ─────────────────────────────────────────
  static Future<void> confirmCashReceived(String rideId) async {
    final headers = await authHeaders();
    await http.post(
      Uri.parse('$baseUrl/rides/$rideId/cash-received'),
      headers: headers,
    );
  }

  // ── Get Pending Request (updated) ─────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPendingRequests(
      String driverId) async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/rides/pending-request/$driverId'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final requests = data['requests'] as List? ?? [];
      return requests.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // ── Create Razorpay Order ─────────────────────────────────────────────────
  // Called when customer taps Pay
  // Returns order_id and key_id needed to open Razorpay payment sheet
  static Future<Map<String, dynamic>> createPaymentOrder({
    required String rideId,
    required double amount,
  }) async {
    final headers = await authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/payments/create-order'),
      headers: headers,
      body: jsonEncode({
        'ride_id': rideId,
        'amount': amount,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to create order');
    }
  }

  // ── Verify Payment ────────────────────────────────────────────────────────
  // Called after Razorpay payment succeeds
  // Sends payment IDs to backend for verification
  static Future<void> verifyPayment({
    required String rideId,
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final headers = await authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/payments/verify'),
      headers: headers,
      body: jsonEncode({
        'ride_id': rideId,
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Payment verification failed');
    }
  }

  // ── Cash Payment ──────────────────────────────────────────────────────────
  // Called when customer selects cash payment
  // No Razorpay involved — just records payment in database
  static Future<void> recordCashPayment({
    required String rideId,
  }) async {
    final headers = await authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/payments/cash'),
      headers: headers,
      body: jsonEncode({'ride_id': rideId}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to record cash payment: ${response.statusCode}');
    }
  }

  // ── Submit Rating ─────────────────────────────────────────────────────────
  // Called after ride completes
  // Saves customer's rating for the driver
  // Also updates driver's average rating in database
  static Future<void> submitRating({
    required String rideId,
    required int rating,
  }) async {
    final headers = await authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rides/$rideId/rating'),
      headers: headers,
      body: jsonEncode({'rating': rating}),
    );
  }

  // ── Search Address (Nominatim) ────────────────────────────────────────────
  // Uses OpenStreetMap's Nominatim API to search addresses
  // Returns list of matching addresses with coordinates
  // Called on every keystroke in pickup/dropoff field
  static Future<List<Map<String, dynamic>>> searchAddress(String query) async {
    if (query.length < 3) return [];

    final response = await http.get(
      Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&limit=7'
        '&countrycodes=in'
        '&addressdetails=1'
        '&accept-language=en'
      ),
      headers: {
        'User-Agent': 'AutoShare/1.0',  // Nominatim requires this
      },
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map<Map<String, dynamic>>((item) {
        // Build a cleaner display name
        String displayName = item['display_name'];

        return {
          'display_name': displayName,
          'short_name': _buildShortName(item),  // ← shorter cleaner name
          'lat': double.parse(item['lat']),
          'lng': double.parse(item['lon']),
        };
      }).toList();
    }
    return [];
  }
  // Build a shorter readable name for the suggestion
  static String _buildShortName(Map item) {
    final address = item['address'] ?? {};
    final parts = <String>[];

    // Add the most specific parts first
    if (address['road'] != null) parts.add(address['road']);
    if (address['suburb'] != null) parts.add(address['suburb']);
    if (address['city'] != null) parts.add(address['city']);
    else if (address['town'] != null) parts.add(address['town']);

    return parts.isNotEmpty ? parts.join(', ') : item['display_name'];
  }

  // ── Get Fixed Route ───────────────────────────────────────────────────────
  // Fetches the fixed auto route stored in database
  // Returns list of coordinates forming the route polyline
  static Future<List<Map<String, dynamic>>> getFixedRoute() async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/rides/fixed-route'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      var coords = data['coordinates'];

      // Handle nested list from Supabase RPC
      if (coords is List && coords.isNotEmpty && coords[0] is List) {
        coords = coords[0];
      }

      return List<Map<String, dynamic>>.from(coords);
    }
    return [];
  }

  // ── Get Predefined Routes ─────────────────────────────────────────────────
  // Fetches list of all predefined routes from database
  // Shown to driver when they tap "Go Online"
  static Future<List<Map<String, dynamic>>> getPredefinedRoutes() async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/rides/predefined-routes'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // ── Select Driver Route ───────────────────────────────────────────────────
  // Called when driver confirms which route they'll drive
  // Saves to driver_routes table in database
  static Future<void> selectDriverRoute({
    required String driverId,
    required String routeId,
  }) async {
    final headers = await authHeaders();
    await http.post(
      Uri.parse('$baseUrl/rides/select-route'),
      headers: headers,
      body: jsonEncode({
        'driver_id': driverId,
        'route_id': routeId,
      }),
    );
  }

  static Future<Map<String, dynamic>> getDriverActiveRoute(String driverId) async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/rides/driver-active-route/$driverId'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return {'route': null};
  }

  // ── Get Ride Status ───────────────────────────────────────────────────────
  // Customer polls this every 3 seconds while waiting for driver
  // Returns status + driver details when accepted
  static Future<Map<String, dynamic>> getRideStatus(String rideId) async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/rides/$rideId/status'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
      // Now returns: {ride_id, status, fare, payment_status, payment_method, driver}
    }
    throw Exception('Failed to get ride status');
  }

  // ── Update Customer Location ──────────────────────────────────────────────
  // Customer sends live location to backend after ride is accepted
  // Driver can see customer location on their map
  static Future<void> updateCustomerLocation({
    required String rideId,
    required double lat,
    required double lng,
  }) async {
    final headers = await authHeaders();
    await http.post(
      Uri.parse('$baseUrl/rides/$rideId/customer-location'),
      headers: headers,
      body: jsonEncode({'latitude': lat, 'longitude': lng}),
    );
  }

  // ── Get Customer Location ─────────────────────────────────────────────────
  // Driver polls this to see customer's live location
  static Future<Map<String, dynamic>?> getCustomerLocation(String rideId) async {
    final headers = await authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/rides/$rideId/customer-location'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }
}