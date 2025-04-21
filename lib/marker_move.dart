import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';

class MarkerMovingPage extends StatefulWidget {
  const MarkerMovingPage({super.key});

  @override
  State<MarkerMovingPage> createState() => _MarkerMovingPageState();
}

class _MarkerMovingPageState extends State<MarkerMovingPage>
    with TickerProviderStateMixin {
  bool _navigationRunning = false;
  GoogleNavigationViewController? _navigationViewController;
  StreamSubscription<NavInfoEvent>? _navInfoSubscription;
  StreamSubscription<Position>? _positionSubscription;
  NavInfo? _navInfo;
  Timer? _customMarkerTimer;
  List<LatLng> _routePolyline = [];
  int _currentIndex = 0;
  List<Marker> _markers = <Marker>[];
  ImageDescriptor? _customIcon;
  Marker? _movingMarker;
  bool _showBottomSheet = false;
  AnimationController? _animationController;

  @override
  void initState() {
    super.initState();
    _addCustomMarker();
  }

  Future<void> _addCustomMarker() async {
    final ByteData byteData = await rootBundle.load('assets/images/car.png');
    final Uint8List imageBytes = byteData.buffer.asUint8List();

    final img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) return;

    final img.Image resized = img.copyResize(
      originalImage,
      width: 90,
      height: 90,
    );
    final Uint8List resizedBytes = Uint8List.fromList(img.encodePng(resized));
    final ByteData resizedByteData = resizedBytes.buffer.asByteData();

    _customIcon = await registerBitmapImage(
      bitmap: resizedByteData,
      imagePixelRatio: 2.0,
    );
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
        // _addMyLocationMarker();
        _updateMovingMarker(newLocation);
      });
    } else {
      _showMessage('Location permission denied for tracking.');
    }
  }

  Future<void> _stopLocationTracking() async {
    if (_positionSubscription != null) {
      await _positionSubscription!.cancel();
      _positionSubscription = null;
    }
  }

  Future<void> _addMyLocationMarker() async {
    if (_customIcon == null) await _addCustomMarker();

    final currentLocation = await _getCurrentLocation();
    if (currentLocation != null && _navigationViewController != null) {
      final MarkerOptions options = MarkerOptions(
        position: currentLocation,
        icon: _customIcon!,
        infoWindow: const InfoWindow(
          title: 'You',
          snippet: 'Your current location',
        ),
      );

      final List<Marker?> addedMarkers = await _navigationViewController!
          .addMarkers([options]);
      if (addedMarkers.isNotEmpty && addedMarkers.first != null) {
        setState(() {
          _markers.add(addedMarkers.first!);
          _movingMarker = addedMarkers.first;
        });
        _startLocationTracking();
      }
    }
  }

  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    _navigationViewController = controller;
    await controller.setMyLocationEnabled(false);

    await _addMyLocationMarker();
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

      if (_movingMarker == null) {
        await _addMyLocationMarker();
      } else {
        await _updateMovingMarker(currentLocation);
      }

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

  Future<void> _updateMovingMarker(LatLng newLocation) async {
    if (_navigationViewController == null || _customIcon == null) return;

    // Use a Tween to animate the position from the current to the new location
    final LatLng currentPosition =
        _movingMarker?.options.position ?? LatLng(latitude: 0, longitude: 0);

    // Create an AnimationController with a duration for smooth movement
    final AnimationController controller = AnimationController(
      vsync: this, // Provide vsync using TickerProviderStateMixin
      duration: const Duration(
        seconds: 2,
      ), // Adjust duration for smoother or faster movement
    );

    // Create the Tween for LatLng (starting position to destination)
    final LatLngTween latLngTween = LatLngTween(
      begin: currentPosition,
      end: newLocation,
    );
    final Animation<LatLng> animation = latLngTween.animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );

    // Add a listener to update the marker's position based on animation value
    animation.addListener(() {
      if (_navigationViewController != null && _movingMarker != null) {
        final LatLng animatedPosition = animation.value;

        // Create updated options with the new animated position
        final MarkerOptions updatedMarkerOptions = MarkerOptions(
          position: animatedPosition,
          icon: _customIcon!,
        );

        // Apply the updated options to the marker before updating
        _movingMarker = _movingMarker!.copyWith(options: updatedMarkerOptions);

        // Update marker position smoothly
        _navigationViewController!.updateMarkers([_movingMarker!]);
      }
    });
    // Start the animation
    controller.forward();
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
    _animationController?.dispose(); // Dispose the controller properly
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Marker Navigation')),
      body: GoogleMapsNavigationView(onViewCreated: _onViewCreated),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNavigation,
        child: const Icon(Icons.navigation),
      ),
    );
  }
}

class LatLngTween extends Tween<LatLng> {
  LatLngTween({LatLng? begin, LatLng? end}) : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    // Interpolating latitude and longitude using a separate Tween for each
    double latitude = lerpDouble(begin!.latitude, end!.latitude, t)!;
    double longitude = lerpDouble(begin!.longitude, end!.longitude, t)!;

    return LatLng(
      latitude: latitude,
      longitude: longitude,
    ); // Return interpolated LatLng
  }
}
