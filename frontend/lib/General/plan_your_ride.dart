import 'package:autoshare/Driver/driver_online.dart';
import 'package:autoshare/General/maps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:autoshare/Customer/autoricksaw_list.dart';

class PlanYourRide extends StatefulWidget {
  final String pickupLocation;
  final String dropoffLocation;
  final String userType;
  final String buttonText;
  final String distance;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;

  const PlanYourRide({
    super.key,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.userType,
    required this.buttonText,
    required this.distance,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  });

  @override
  PlanYourRideState createState() => PlanYourRideState();
}

class PlanYourRideState extends State<PlanYourRide> {
  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _dropoffFocusNode = FocusNode();
  double _pickupElevation = 0.1;
  double _dropoffElevation = 0.1;

  late TextEditingController pickupController;
  late TextEditingController dropoffController;

  final TransformationController _transformationController =
      TransformationController();

  final MapController _mapController = MapController();
  final LatLng _ahmedabad = const LatLng(23.0215374, 72.5800568);
  double _sheetExtent = 0.40;

  @override
  @override
  void initState() {
    super.initState();
    pickupController = TextEditingController(text: widget.pickupLocation);
    dropoffController = TextEditingController(text: widget.dropoffLocation);

    pickupController.addListener(() => setState(() {}));
    dropoffController.addListener(() => setState(() {}));

    final matrix = Matrix4.identity();
    matrix.scaleByDouble(2.0, 2.0, 1.0, 1);
    _transformationController.value = matrix;

    _pickupFocusNode.addListener(() {
      setState(() {
        _pickupElevation = _pickupFocusNode.hasFocus ? 8 : 0.1;
      });
    });

    _dropoffFocusNode.addListener(() {
      setState(() {
        _dropoffElevation = _dropoffFocusNode.hasFocus ? 8 : 0.1;
      });
    });
  }

  @override
  void dispose() {
    _pickupFocusNode.dispose();
    _dropoffFocusNode.dispose();
    pickupController.dispose();
    dropoffController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: AhmedabadMap(mapController: _mapController),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            bottom: screenHeight * _sheetExtent + 20,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: () {
                _mapController.move(_ahmedabad, 14);
              },
              child: const Icon(Icons.my_location, color: Colors.black87),
            ),
          ),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              setState(() {
                _sheetExtent = notification.extent;
              });
              return true;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.40,
              minChildSize: 0.05,
              maxChildSize: 0.40,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6)
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Center(
                            child: Container(
                              height: 5,
                              width: 40,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children:  [
                              Text(
                                '',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${widget.distance}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          Material(
                              elevation: _pickupElevation,
                              borderRadius: BorderRadius.circular(50),
                              child: TextField(
                                focusNode: _pickupFocusNode,
                                controller: pickupController,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.gps_fixed,
                                    color: Color.fromARGB(255, 254, 187, 38),
                                  ),
                                  hintText: 'Pickup Location',
                                  filled: true,
                                  fillColor: Colors.white,
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: const BorderSide(
                                        color: Colors.grey, width: 1.5),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: const BorderSide(
                                        color:
                                            Color.fromARGB(255, 254, 187, 38),
                                        width: 2.0),
                                  ),
                                ),
                              )),
                          const SizedBox(height: 12),
                          Material(
                            elevation: _dropoffElevation,
                            borderRadius: BorderRadius.circular(50),
                            child: TextField(
                              focusNode: _dropoffFocusNode,
                              controller: dropoffController,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(
                                  Icons.location_on,
                                  color: Color.fromARGB(255, 254, 187, 38),
                                ),
                                hintText: 'Dropoff Location',
                                filled: true,
                                fillColor: Colors.white,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(50),
                                  borderSide: const BorderSide(
                                      color: Colors.grey, width: 1.5),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(50),
                                  borderSide: const BorderSide(
                                      color: Color.fromARGB(255, 254, 187, 38),
                                      width: 2.0),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: (pickupController.text.isNotEmpty &&
                                    dropoffController.text.isNotEmpty)
                                ? () {
                                    // Only driver uses this screen now
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DriverOnline(
                                          source: pickupController.text,
                                          destination: dropoffController.text,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color.fromARGB(255, 254, 187, 38),
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: Colors.grey.shade300,
                              disabledForegroundColor: Colors.grey.shade600,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              minimumSize: const Size.fromHeight(50),
                            ),
                            child: Text(
                              widget.buttonText,
                              style: TextStyle(fontSize: 16),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
