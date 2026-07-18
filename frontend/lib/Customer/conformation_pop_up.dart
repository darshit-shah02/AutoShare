import 'package:autoshare/Customer/autoricksaw_booking.dart';
import 'package:autoshare/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:autoshare/Customer/waiting_for_driver_screen.dart';

Future<void> handleConfirmResult(
  BuildContext context,
  bool didPop,
  Object? result, {
  required String cost,
  required String driverPhoneNo,
  required String driverName,
  required String vehicalNo,
  required String fare,
  required String driverId,        
  required String userId,          
  required double pickupLat,       
  required double pickupLng,       
  required double dropoffLat,      
  required double dropoffLng,      
  required String pickupAddress,   
  required String dropoffAddress,  
}) async {
  if (!didPop) {
    final navigator = Navigator.of(context);
    final shouldBook = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Book Ride?'),
        content: const Text('Do you really want to book this ride?'),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.black)),
          ),
          TextButton(
            onPressed: () => navigator.pop(true),
            child: const Text('Book',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (shouldBook == true) {
      // Show loading while booking
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // Call real booking API
        final rideData = await ApiService.bookRide(
          userId: userId,
          driverId: driverId,
          pickupLat: pickupLat,
          pickupLng: pickupLng,
          dropoffLat: dropoffLat,
          dropoffLng: dropoffLng,
          pickupAddress: pickupAddress,
          dropoffAddress: dropoffAddress,
        );

        if (!context.mounted) return;
        Navigator.pop(context); // close loading

        // Navigate to booking screen with real ride data
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WaitingForDriverScreen(
              rideId: rideData['ride_id'],
              fare: fare,
              pickupLat: pickupLat,
              pickupLng: pickupLng,
              dropoffLat: dropoffLat,
              dropoffLng: dropoffLng,
              pickupAddress: pickupAddress,
              dropoffAddress: dropoffAddress,
              pickupNearestPoint: rideData['pickup_nearest_point'] ?? {},
              dropoffNearestPoint: rideData['dropoff_nearest_point'] ?? {},
            ),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        Navigator.pop(context); // close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}