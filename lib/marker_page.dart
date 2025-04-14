import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:image/image.dart' as img;


class MarkerPage extends StatefulWidget {
  const MarkerPage({super.key});

  @override
  State<MarkerPage> createState() => _MarkerPageState();
}

class _MarkerPageState extends State<MarkerPage> {
  late GoogleNavigationViewController _navigationViewController;
  bool _navigationRunning = false;

  List<Marker> _markers = <Marker>[];
  ImageDescriptor? _customIcon;
  Marker? _selectedMarker;

  // Called when the navigation view is created
  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    _navigationViewController = controller;
  }

  // Add marker at camera center (or predefined location)
  Future<void> _addCustomMarker() async {
    final ByteData byteData = await rootBundle.load('assets/images/marker.png');
    final Uint8List imageBytes = byteData.buffer.asUint8List();

    final img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) return;

    final img.Image resized = img.copyResize(originalImage, width: 60, height: 60);
    final Uint8List resizedBytes = Uint8List.fromList(img.encodePng(resized));

    // Convert to ByteData
    final ByteData resizedByteData = resizedBytes.buffer.asByteData();

    // Register marker icon
    _customIcon = await registerBitmapImage(
      bitmap: resizedByteData,
      imagePixelRatio: 2.0,
    );

    // Add marker
    final MarkerOptions options = MarkerOptions(
      position: LatLng(latitude: 37.791957, longitude: -122.412529),
      icon: _customIcon!,
      infoWindow: const InfoWindow(
        title: 'Custom Marker',
        snippet: 'This is a custom marker',
      ),
    );

    final List<Marker?> addedMarkers = await _navigationViewController.addMarkers([options]);
    if (addedMarkers.isNotEmpty && addedMarkers.first != null) {
      setState(() {
        _markers.add(addedMarkers.first!);
      });
    }
  }

  Future<void> _startNavigation() async {
    // You can add start navigation logic here
    setState(() {
      _navigationRunning = true;
    });
  }

  Future<void> _stopNavigation() async {
    // Stop navigation logic
    setState(() {
      _navigationRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navigation Marker Page')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GoogleMapsNavigationView(
                onViewCreated: _onViewCreated,
                initialNavigationUIEnabledPreference:
                NavigationUIEnabledPreference.disabled,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _addCustomMarker,
                  child: const Text('Add Marker'),
                ),
                ElevatedButton(
                  onPressed: _navigationRunning ? _stopNavigation : _startNavigation,
                  child: Text(_navigationRunning ? 'Stop Navigation' : 'Start Navigation'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
