import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';

class MultipleMarkerMovingPage extends StatefulWidget {
  const MultipleMarkerMovingPage({super.key});

  @override
  State<MultipleMarkerMovingPage> createState() =>
      _MultipleMarkerMovingPageState();
}

class _MultipleMarkerMovingPageState extends State<MultipleMarkerMovingPage>
    with TickerProviderStateMixin {
  bool _navigationRunning = false;
  GoogleNavigationViewController? _navigationViewController;
  StreamSubscription<NavInfoEvent>? _navInfoSubscription;
  StreamSubscription<Position>? _positionSubscription;
  NavInfo? _navInfo;
  Timer? _customMarkerTimer;
  List<LatLng> _routePolyline = [];
  int _currentIndex = 0;

  // Track multiple markers
  Map<String, MarkerData> _markersMap = <String, MarkerData>{};
  ImageDescriptor? _carIcon;
  ImageDescriptor? _taxiIcon;
  ImageDescriptor? _truckIcon;

  bool _showBottomSheet = false;

  @override
  void initState() {
    super.initState();
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    // Load multiple icons
    _carIcon = await _createIconFromAsset('assets/images/car.png');
    _taxiIcon = await _createIconFromAsset('assets/images/car2.png');
    _truckIcon = await _createIconFromAsset('assets/images/car.png');
  }

  Future<ImageDescriptor?> _createIconFromAsset(String assetPath) async {
    try {
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List imageBytes = byteData.buffer.asUint8List();

      final img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) return null;

      final img.Image resized = img.copyResize(
        originalImage,
        width: 90,
        height: 90,
      );
      final Uint8List resizedBytes = Uint8List.fromList(img.encodePng(resized));
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

  Future<LatLng?> _getCurrentLocation() async {
    final locationStatus = await Permission.location.request();
    if (locationStatus.isGranted) {
      try {
        final Position position = await Geolocator.getCurrentPosition();
        return LatLng(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } catch (e) {
        _showMessage('Error getting current location: $e');
        return null;
      }
    } else {
      _showMessage('Location permission denied.');
      return null;
    }
  }

  Future<void> _startLocationTracking() async {
    await _stopLocationTracking();

    final locationStatus = await Permission.location.request();
    if (locationStatus.isGranted) {
      final int distanceFilter = _navigationRunning ? 5 : 10;

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
        ),
      ).listen((Position position) {
        final newLocation = LatLng(
          latitude: position.latitude,
          longitude: position.longitude,
        );

        // Update all markers with new variations of position
        _updateAllMarkers(newLocation);
      });
    } else {
      _showMessage('Location permission denied for tracking.');
    }
  }

  void _updateAllMarkers(LatLng baseLocation) {
    // Update main vehicle
    if (_markersMap.containsKey('main')) {
      _updateMovingMarker('main', baseLocation);
    }

    // Update other vehicles with slight position variations
    if (_markersMap.containsKey('taxi')) {
      final taxiLocation = LatLng(
        latitude: baseLocation.latitude + 0.0005,
        longitude: baseLocation.longitude - 0.0003,
      );
      _updateMovingMarker('taxi', taxiLocation);
    }

    if (_markersMap.containsKey('truck')) {
      final truckLocation = LatLng(
        latitude: baseLocation.latitude - 0.0007,
        longitude: baseLocation.longitude + 0.0006,
      );
      _updateMovingMarker('truck', truckLocation);
    }
  }

  Future<void> _stopLocationTracking() async {
    if (_positionSubscription != null) {
      await _positionSubscription!.cancel();
      _positionSubscription = null;
    }
  }

  Future<void> _addAllMarkers() async {
    final currentLocation = await _getCurrentLocation();
    if (currentLocation == null || _navigationViewController == null) return;

    // Add main vehicle marker
    await _addMarker(
      'main',
      currentLocation,
      _carIcon,
      'Your Vehicle',
      'Your current location',
    );

    // Add taxi marker slightly offset
    final taxiLocation = LatLng(
      latitude: currentLocation.latitude + 0.0005,
      longitude: currentLocation.longitude - 0.0003,
    );
    await _addMarker('taxi', taxiLocation, _taxiIcon, 'Taxi', 'Nearby taxi');

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
    );

    // Start tracking all markers
    _startLocationTracking();
  }

  Future<void> _addMarker(
    String id,
    LatLng position,
    ImageDescriptor? icon,
    String title,
    String snippet,
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
          vsync: this,
          duration: const Duration(milliseconds: 1500),
        ),
      );

      setState(() {
        _markersMap[id] = markerData;
      });
    }
  }

  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    _navigationViewController = controller;
    await controller.setMyLocationEnabled(false);

    await _addAllMarkers();
    setState(() {});
  }

  Future<void> _startNavigation() async {
    _showMessage('Starting navigation.');

    final locationStatus = await Permission.location.request();
    if (!locationStatus.isGranted) {
      _showMessage('Location permission denied.');
      return;
    }

    if (!await GoogleMapsNavigator.areTermsAccepted()) {
      await GoogleMapsNavigator.showTermsAndConditionsDialog(
        'Navigation Sample',
        'My Company',
      );
    }

    await GoogleMapsNavigator.initializeNavigationSession();
    await _setupListeners();

    final currentLocation = await _getCurrentLocation();
    if (currentLocation != null) {
      await GoogleMapsNavigator.simulator.setUserLocation(currentLocation);

      // Update all markers with current location
      _updateAllMarkers(currentLocation);

      setState(() {
        _navigationRunning = true;
      });

      await _startLocationTracking();
    } else {
      _showMessage('Could not get current location.');
      return;
    }

    final Destinations msg = Destinations(
      waypoints: <NavigationWaypoint>[
        NavigationWaypoint.withLatLngTarget(
          title: 'Samnabad',
          target: const LatLng(latitude: 31.5336, longitude: 74.2988),
        ),
      ],
      displayOptions: NavigationDisplayOptions(
        showDestinationMarkers: true,
        showTrafficLights: true,
      ),
    );

    final NavigationRouteStatus status =
        await GoogleMapsNavigator.setDestinations(msg);
    if (status == NavigationRouteStatus.statusOk) {
      await GoogleMapsNavigator.startGuidance();
      _hideMessage();
    } else {
      _showMessage('Starting navigation failed.');
      setState(() {
        _navigationRunning = false;
      });
    }
  }

  Future<void> _setupListeners() async {
    _clearListeners();
    _navInfoSubscription = GoogleMapsNavigator.setNavInfoListener(
      (event) => _onNavInfoEvent(event),
      numNextStepsToPreview: 0,
    );
  }

  void _clearListeners() {
    _navInfoSubscription?.cancel();
    _navInfoSubscription = null;
  }

  void _onNavInfoEvent(NavInfoEvent event) {
    if (!mounted) return;
    setState(() {
      _navInfo = event.navInfo;
    });
  }

  Future<void> _updateMovingMarker(String markerId, LatLng newLocation) async {
    if (_navigationViewController == null || !_markersMap.containsKey(markerId))
      return;

    final markerData = _markersMap[markerId]!;
    final Marker marker = markerData.marker;

    // Stop any ongoing animation first
    markerData.animationController.stop();
    markerData.animationController.reset();

    // Get current position
    final LatLng currentPosition = marker.options.position;

    // Create the Tween for LatLng
    final LatLngTween latLngTween = LatLngTween(
      begin: currentPosition,
      end: newLocation,
    );

    final Animation<LatLng> animation = latLngTween.animate(
      CurvedAnimation(
        parent: markerData.animationController,
        curve: Curves.linear,
      ),
    );

    // Add a listener to update the marker's position based on animation value
    animation.addListener(() {
      if (_navigationViewController != null) {
        final LatLng animatedPosition = animation.value;

        // Create updated options with the new animated position
        final MarkerOptions updatedMarkerOptions = MarkerOptions(
          position: animatedPosition,
          icon: marker.options.icon,
          infoWindow: marker.options.infoWindow,
        );

        // Update the marker in our map
        final updatedMarker = marker.copyWith(options: updatedMarkerOptions);
        _markersMap[markerId] = markerData.copyWith(marker: updatedMarker);

        // Update marker position smoothly
        _navigationViewController!.updateMarkers([updatedMarker]);
      }
    });

    // Start the animation
    markerData.animationController.forward();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _hideMessage() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  @override
  void dispose() {
    _customMarkerTimer?.cancel();
    _stopLocationTracking();
    _clearListeners();

    // Dispose all animation controllers
    for (final markerData in _markersMap.values) {
      markerData.animationController.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multiple Moving Markers')),
      body: GoogleMapsNavigationView(onViewCreated: _onViewCreated),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNavigation,
        child: const Icon(Icons.navigation),
      ),
    );
  }
}

// Class to hold marker data and its animation controller
class MarkerData {
  final Marker marker;
  final AnimationController animationController;

  MarkerData({required this.marker, required this.animationController});

  MarkerData copyWith({
    Marker? marker,
    AnimationController? animationController,
  }) {
    return MarkerData(
      marker: marker ?? this.marker,
      animationController: animationController ?? this.animationController,
    );
  }
}

class LatLngTween extends Tween<LatLng> {
  LatLngTween({LatLng? begin, LatLng? end}) : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    double latitude = lerpDouble(begin!.latitude, end!.latitude, t)!;
    double longitude = lerpDouble(begin!.longitude, end!.longitude, t)!;

    return LatLng(latitude: latitude, longitude: longitude);
  }
}
