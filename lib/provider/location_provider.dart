// location_provider.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'marker_provider.dart';

class LocationProvider extends ChangeNotifier {
  StreamSubscription<Position>? _positionSubscription;
  bool _navigationRunning = false;
  LatLng? _lastReportedLocation;

  // Buffering mechanism for location updates
  final List<LatLng> _locationBuffer = [];
  Timer? _bufferProcessTimer;
  final _bufferProcessInterval = const Duration(milliseconds: 500);

  bool get navigationRunning => _navigationRunning;

  void setNavigationRunning(bool value) {
    _navigationRunning = value;
    notifyListeners();
  }

  Future<LatLng?> getCurrentLocation() async {
    final locationStatus = await Permission.location.request();
    if (locationStatus.isGranted) {
      try {
        // Use the last known position first for faster response
        Position? position;
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (e) {
          // Ignore errors with last known position
        }

        // If no last known position, get current position
        if (position == null) {
          position = await Geolocator.getCurrentPosition();
        }

        return LatLng(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } catch (e) {
        print('Error getting current location: $e');
        return null;
      }
    } else {
      print('Location permission denied.');
      return null;
    }
  }

  Future<void> startLocationTracking(BuildContext context) async {
    await stopLocationTracking();

    final locationStatus = await Permission.location.request();
    if (locationStatus.isGranted) {
      // Use a larger distance filter to reduce update frequency
      final int distanceFilter = _navigationRunning ? 5 : 10;

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
          // Reduce sample rate
          timeLimit: const Duration(milliseconds: 500),
        ),
      ).listen((Position position) {
        final newLocation = LatLng(
          latitude: position.latitude,
          longitude: position.longitude,
        );

        // Add location to buffer
        _addLocationToBuffer(newLocation);
      });

      // Start buffer processing timer
      _startBufferProcessing(context);
    } else {
      print('Location permission denied for tracking.');
    }
  }

  void _addLocationToBuffer(LatLng location) {
    _locationBuffer.add(location);
  }

  void _startBufferProcessing(BuildContext context) {
    _bufferProcessTimer?.cancel();
    _bufferProcessTimer = Timer.periodic(_bufferProcessInterval, (timer) {
      if (_locationBuffer.isEmpty) return;

      // Take the latest location from buffer
      final latestLocation = _locationBuffer.last;
      _locationBuffer.clear();

      // Update markers with the latest location
      if (_lastReportedLocation != latestLocation) {
        _lastReportedLocation = latestLocation;
        final markerProvider = Provider.of<MarkerProvider>(
          context,
          listen: false,
        );
        markerProvider.updateAllMarkers(latestLocation);
      }
    });
  }

  Future<void> stopLocationTracking() async {
    _bufferProcessTimer?.cancel();
    _bufferProcessTimer = null;

    if (_positionSubscription != null) {
      await _positionSubscription!.cancel();
      _positionSubscription = null;
    }

    _locationBuffer.clear();
  }

  void dispose() {
    stopLocationTracking();
    super.dispose();
  }
}
