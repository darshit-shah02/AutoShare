import 'package:autoshare/services/api_service.dart';
import 'package:flutter/material.dart';

class DriverCashConfirmScreen extends StatefulWidget {
  final String rideId;
  final String fare;
  final String customerName;
  final String source;
  final String destination;
  final String routeId;

  const DriverCashConfirmScreen({
    super.key,
    required this.rideId,
    required this.fare,
    required this.customerName,
    required this.source,
    required this.destination,
    required this.routeId,
  });

  @override
  DriverCashConfirmScreenState createState() => DriverCashConfirmScreenState();
}

class DriverCashConfirmScreenState extends State<DriverCashConfirmScreen> {
  bool _isConfirming = false;

  Future<void> _confirmCashReceived() async {
    setState(() => _isConfirming = true);
    try {
      await ApiService.confirmCashReceived(widget.rideId);
      if (!mounted) return;
      // Return to the SAME driver online screen we came from (pop, not
      // pushReplacement). This screen is always pushed on top of an
      // existing DriverOnline instance, so pushReplacement was throwing
      // that instance away and rebuilding a fresh one — wiping out the
      // markers/tracking for any OTHER passenger still on board.
      Navigator.pop(context);
    } catch (e) {
      setState(() => _isConfirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Payment'),
        backgroundColor: const Color.fromARGB(255, 254, 187, 38),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.money,
                size: 80,
                color: Color.fromARGB(255, 254, 187, 38),
              ),
              const SizedBox(height: 24),

              Text(
                '${widget.customerName} will pay cash',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 254, 248, 195),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Collect: ',
                        style: TextStyle(fontSize: 18)),
                    Text(
                      '₹${widget.fare}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 254, 187, 38),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isConfirming ? null : _confirmCashReceived,
                  child: _isConfirming
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Cash Received ✓',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
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
  }
}