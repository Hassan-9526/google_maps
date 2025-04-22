// marker_provider.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:mapbox_flutter_map/provider/model_classes.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

class MarkerProvider extends ChangeNotifier {
  GoogleNavigationViewController? _navigationViewController;
  Map<String, MarkerData> _markersMap = <String, MarkerData>{};

  // Marker icons
  ImageDescriptor? _carIcon;
  ImageDescriptor? _taxiIcon;
  ImageDescriptor? _truckIcon;

  // Throttling variables
  DateTime _lastUpdateTime = DateTime.now();
  final _updateThrottleDuration = const Duration(milliseconds: 300);
  LatLng? _pendingUpdateLocation;
  Timer? _throttleTimer;

  // Distance threshold for updates (meters)
  final double _updateDistanceThreshold = 5.0;
  LatLng? _lastUpdatedLocation;

  // Getters
  Map<String, MarkerData> get markersMap => _markersMap;
  GoogleNavigationViewController? get navigationViewController =>
      _navigationViewController;

  // Set navigation view controller
  void setNavigationViewController(GoogleNavigationViewController controller) {
    _navigationViewController = controller;
    notifyListeners();
  }

  // Load marker icons efficiently
  Future<void> loadMarkerIcons(TickerProvider vsync) async {
    try {
      // Load all icons in parallel
      final futures = await Future.wait([
        _createIconFromAsset('assets/images/car.png'),
        _createIconFromAsset('assets/images/car2.png'),
        _createIconFromAsset('assets/images/car.png'),
      ]);

      _carIcon = futures[0];
      _taxiIcon = futures[1];
      _truckIcon = futures[2];

      notifyListeners();
    } catch (e) {
      print('Error loading marker icons: $e');
    }
  }

  Future<ImageDescriptor?> _createIconFromAsset(String assetPath) async {
    try {
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List imageBytes = byteData.buffer.asUint8List();

      // Use compute for image processing to avoid blocking main thread
      final Uint8List resizedBytes = await _resizeImageInBackground(imageBytes);
      final ByteData resizedByteData = resizedBytes.buffer.asByteData();

      return await registerBitmapImage(
        bitmap: resizedByteData,
        imagePixelRatio: 2.0,
      );
    } catch (e) {
      print('Error creating icon: $e');
      return null;
    }
  }

  // Process image in background
  Future<Uint8List> _resizeImageInBackground(Uint8List imageBytes) async {
    final ReceivePort receivePort = ReceivePort();

    await Isolate.spawn(
      _isolateResizeImage,
      _ImageResizeData(imageBytes, receivePort.sendPort),
    );

    final Uint8List result = await receivePort.first;
    return result;
  }

  // Static method to be called in isolate
  static void _isolateResizeImage(_ImageResizeData data) {
    final img.Image? originalImage = img.decodeImage(data.imageBytes);
    if (originalImage == null) {
      data.sendPort.send(data.imageBytes);
      return;
    }

    final img.Image resized = img.copyResize(
      originalImage,
      width: 90,
      height: 90,
    );

    final Uint8List resizedBytes = Uint8List.fromList(img.encodePng(resized));
    data.sendPort.send(resizedBytes);
  }

  // Add all markers
  Future<void> addAllMarkers(
    LatLng currentLocation,
    TickerProvider vsync,
  ) async {
    if (_navigationViewController == null) return;

    _lastUpdatedLocation = currentLocation;

    // Add main vehicle marker
    await _addMarker(
      'main',
      currentLocation,
      _carIcon,
      'Your Vehicle',
      'Your current location',
      vsync,
    );

    // Add taxi marker slightly offset
    final taxiLocation = LatLng(
      latitude: currentLocation.latitude + 0.0005,
      longitude: currentLocation.longitude - 0.0003,
    );
    await _addMarker(
      'taxi',
      taxiLocation,
      _taxiIcon,
      'Taxi',
      'Nearby taxi',
      vsync,
    );

    // Add truck marker with different offset
    final truckLocation = LatLng(
      latitude: currentLocation.latitude - 0.0007,
      longitude: currentLocation.longitude + 0.0006,
    );
    await _addMarker(
      'truck',
      truckLocation,
      _truckIcon,
      'Truck',
      'Delivery truck',
      vsync,
    );

    notifyListeners();
  }

  // Add a single marker
  Future<void> _addMarker(
    String id,
    LatLng position,
    ImageDescriptor? icon,
    String title,
    String snippet,
    TickerProvider vsync,
  ) async {
    if (icon == null || _navigationViewController == null) return;

    final MarkerOptions options = MarkerOptions(
      position: position,
      icon: icon,
      infoWindow: InfoWindow(title: title, snippet: snippet),
    );

    final List<Marker?> addedMarkers = await _navigationViewController!
        .addMarkers([options]);
    if (addedMarkers.isNotEmpty && addedMarkers.first != null) {
      // Create a marker data object with animation controller
      final markerData = MarkerData(
        marker: addedMarkers.first!,
        animationController: AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 1000),
        ),
        lastPosition: position,
      );

      _markersMap[id] = markerData;
    }
  }

  // Check if update is needed based on distance
  bool _shouldUpdateMarkers(LatLng newLocation) {
    if (_lastUpdatedLocation == null) return true;

    // Calculate distance between last updated location and new location
    final double distance = _calculateDistance(
      _lastUpdatedLocation!.latitude,
      _lastUpdatedLocation!.longitude,
      newLocation.latitude,
      newLocation.longitude,
    );

    return distance >= _updateDistanceThreshold;
  }

  // Haversine formula for distance calculation
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * (pi / 180);
  }

  // Throttled update for all markers
  void updateAllMarkers(LatLng baseLocation) {
    // Skip update if the distance threshold isn't met
    if (!_shouldUpdateMarkers(baseLocation)) {
      return;
    }

    // Store the pending update location
    _pendingUpdateLocation = baseLocation;

    // If we're within the throttle window, schedule an update
    final now = DateTime.now();
    if (now.difference(_lastUpdateTime) < _updateThrottleDuration) {
      // Schedule update if not already scheduled
      if (_throttleTimer == null || !_throttleTimer!.isActive) {
        _throttleTimer = Timer(
          _updateThrottleDuration,
          _processThrottledUpdate,
        );
      }
      return;
    }

    // Otherwise update immediately
    _processThrottledUpdate();
  }

  void _processThrottledUpdate() {
    if (_pendingUpdateLocation == null) return;

    final baseLocation = _pendingUpdateLocation!;
    _lastUpdateTime = DateTime.now();
    _lastUpdatedLocation = baseLocation;
    _pendingUpdateLocation = null;

    // Update main vehicle
    if (_markersMap.containsKey('main')) {
      _updateMarkerPosition('main', baseLocation);
    }

    // Update other vehicles with slight position variations
    if (_markersMap.containsKey('taxi')) {
      final taxiLocation = LatLng(
        latitude: baseLocation.latitude + 0.0005,
        longitude: baseLocation.longitude - 0.0003,
      );
      _updateMarkerPosition('taxi', taxiLocation);
    }

    if (_markersMap.containsKey('truck')) {
      final truckLocation = LatLng(
        latitude: baseLocation.latitude - 0.0007,
        longitude: baseLocation.longitude + 0.0006,
      );
      _updateMarkerPosition('truck', truckLocation);
    }
  }

  // Update marker position without animation for efficiency
  void _updateMarkerPosition(String markerId, LatLng newLocation) {
    if (_navigationViewController == null || !_markersMap.containsKey(markerId))
      return;

    final markerData = _markersMap[markerId]!;
    final Marker marker = markerData.marker;

    // Skip if the position hasn't changed significantly
    if (_isSamePosition(markerData.lastPosition, newLocation)) {
      return;
    }

    // Use a simplified update without animation for better performance
    final MarkerOptions updatedMarkerOptions = MarkerOptions(
      position: newLocation,
      icon: marker.options.icon,
      infoWindow: marker.options.infoWindow,
    );

    // Update the marker in our map
    final updatedMarker = marker.copyWith(options: updatedMarkerOptions);
    _markersMap[markerId] = markerData.copyWith(
      marker: updatedMarker,
      lastPosition: newLocation,
    );

    // Update marker position
    _navigationViewController!.updateMarkers([updatedMarker]);
  }

  // Check if positions are effectively the same (to avoid unnecessary updates)
  bool _isSamePosition(LatLng? pos1, LatLng? pos2) {
    if (pos1 == null || pos2 == null) return false;

    // Consider positions the same if they are within a tiny threshold
    const double threshold =
        0.0000001; // Very small threshold for floating point comparison
    return (pos1.latitude - pos2.latitude).abs() < threshold &&
        (pos1.longitude - pos2.longitude).abs() < threshold;
  }

  // Clean up resources
  void dispose() {
    _throttleTimer?.cancel();
    for (final markerData in _markersMap.values) {
      markerData.animationController.dispose();
    }
    _markersMap.clear();
    super.dispose();
  }
}

class _ImageResizeData {
  final Uint8List imageBytes;
  final SendPort sendPort;

  _ImageResizeData(this.imageBytes, this.sendPort);
}
