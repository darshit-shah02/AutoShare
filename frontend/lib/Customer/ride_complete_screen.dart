import 'package:autoshare/Customer/customer_home_page.dart';
import 'package:autoshare/Payment/payment_success.dart';
import 'package:autoshare/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class RideCompleteScreen extends StatefulWidget {
  final String rideId;
  final String fare;
  final String driverName;
  final String vehicalNo;

  const RideCompleteScreen({
    super.key,
    required this.rideId,
    required this.fare,
    required this.driverName,
    required this.vehicalNo,
  });

  @override
  RideCompleteScreenState createState() => RideCompleteScreenState();
}

class RideCompleteScreenState extends State<RideCompleteScreen> {
  late Razorpay _razorpay;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _isLoading = true);
    try {
      await ApiService.verifyPayment(
        rideId: widget.rideId,
        orderId: response.orderId ?? '',
        paymentId: response.paymentId ?? '',
        signature: response.signature ?? '',
      );
      if (!mounted) return;
      _goToRating();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _payOnline() async {
    setState(() => _isLoading = true);
    try {
      final orderData = await ApiService.createPaymentOrder(
        rideId: widget.rideId,
        amount: double.parse(widget.fare),
      );
      setState(() => _isLoading = false);

      var options = {
        'key': orderData['key_id'],
        'amount': orderData['amount'],
        'currency': orderData['currency'],
        'order_id': orderData['order_id'],
        'name': 'AutoShare',
        'description': 'Auto Rickshaw Fare',
        'theme': {'color': '#FEBB26'},
      };
      _razorpay.open(options);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _payCash() async {
    // Show dialog telling customer to pay driver cash
    // Driver will confirm receipt on their screen
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay Driver Cash'),
        content: Text(
          'Please pay ₹${widget.fare} in cash to the driver.\n\n'
          'Waiting for driver to confirm receipt...',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    // Poll for cash confirmation from driver
    _pollForCashConfirmation();
  }

  void _pollForCashConfirmation() async {
    for (int i = 0; i < 60; i++) {  // poll for 3 minutes max
      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      try {
        final status = await ApiService.getRideStatus(widget.rideId);

        print('Payment status: ${status['payment_status']}');  // ← debug

        // ✅ Check payment_status field specifically
        if (status['payment_status'] == 'paid') {
          if (!mounted) return;
          Navigator.pop(context);  // close "waiting" dialog
          _goToRating();
          return;
        }
      } catch (e) {
        debugPrint('Poll error: $e');
        // continue polling
      }
    }

    // Timeout after 3 minutes
    if (mounted) {
      Navigator.pop(context);  // close dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmation timed out. Please check with driver.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _goToRating() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => Paymentsuccess(
          driverName: widget.driverName,
          vehicalNo: widget.vehicalNo,
          rideId: widget.rideId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Completion icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 254, 248, 195),
                  borderRadius: BorderRadius.circular(60),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle,
                    size: 70,
                    color: Color.fromARGB(255, 254, 187, 38),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'You have arrived!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Thank you for riding with ${widget.driverName}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Fare card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 254, 248, 195),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color.fromARGB(255, 254, 187, 38),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Total Fare: ',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
              const SizedBox(height: 32),

              const Text(
                'Choose payment method',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),

              const Spacer(),

              // Pay Online button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 254, 187, 38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _payOnline,
                  icon: const Icon(Icons.payment, color: Colors.black),
                  label: const Text(
                    'Pay Online (UPI / Card)',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Pay Cash button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color.fromARGB(255, 254, 187, 38),
                      width: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _payCash,
                  icon: const Icon(
                    Icons.money,
                    color: Color.fromARGB(255, 254, 187, 38),
                  ),
                  label: const Text(
                    'Pay Cash to Driver',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}