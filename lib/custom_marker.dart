import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart'; // Import for location services

class CustomMarkerPage extends StatefulWidget {
  const CustomMarkerPage({super.key});

  @override
  State<CustomMarkerPage> createState() => _CustomMarkerPageState();
}

class _CustomMarkerPageState extends State<CustomMarkerPage> {
  bool _navigationRunning = false;
  GoogleNavigationViewController? _navigationViewController;
  StreamSubscription<NavInfoEvent>? _navInfoSubscription;
  StreamSubscription<Position>?
  _positionSubscription; // Add position subscription
  NavInfo? _navInfo;
  Timer? _simulationTrackingTimer;
  List<LatLng> _routePolyline = []; // Your route's polyline points
  int _currentIndex = 0;
  Timer? _customMarkerTimer;
  List<Marker> _markers = <Marker>[];
  ImageDescriptor? _customIcon;
  Marker? _movingMarker;
  bool _showBottomSheet = false; // Track bottom sheet visibility

  @override
  void initState() {
    super.initState();
    // Initialize marker resources
    _addCustomMarker();
  }

  Future<void> _addCustomMarker() async {
    final ByteData byteData = await rootBundle.load('assets/images/car2.png');
    final Uint8List imageBytes = byteData.buffer.asUint8List();

    final img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) return;

    final img.Image resized = img.copyResize(
      originalImage,
      width: 90,
      height: 90,
    );
    final Uint8List resizedBytes = Uint8List.fromList(img.encodePng(resized));

    // Convert to ByteData
    final ByteData resizedByteData = resizedBytes.buffer.asByteData();

    // Register marker icon
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

  // Start location tracking
  Future<void> _startLocationTracking() async {
    // Cancel any existing subscription
    await _stopLocationTracking();

    final locationStatus = await Permission.location.request();
    if (locationStatus.isGranted) {
      // Use a more frequent update interval when in navigation mode
      final int distanceFilter =
          _navigationRunning
              ? 5
              : 10; // More frequent updates during navigation

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter, // Update every X meters
        ),
      ).listen((Position position) {
        final newLocation = LatLng(
          latitude: position.latitude,
          longitude: position.longitude,
        );

        // Update the marker with the new position
        _updateMovingMarker(newLocation);
      });
    } else {
      _showMessage('Location permission denied for tracking.');
    }
  }

  // Stop location tracking
  Future<void> _stopLocationTracking() async {
    if (_positionSubscription != null) {
      await _positionSubscription!.cancel();
      _positionSubscription = null;
    }
  }

  Future<void> _addMyLocationMarker() async {
    if (_customIcon == null) {
      await _addCustomMarker();
    }
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
          _movingMarker = addedMarkers.first; // Set as the moving marker
        });

        // Start tracking location to update this marker
        _startLocationTracking();
      }
    }
  }

  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    _navigationViewController = controller;
    // Add the custom marker for the initial location after the view is created
    await _addMyLocationMarker();
    setState(() {});
  }

  void _startCustomMarkerSimulation() {
    _currentIndex = 0;
    _customMarkerTimer?.cancel();

    _customMarkerTimer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      if (_currentIndex >= _routePolyline.length) {
        timer.cancel();
        return;
      }

      final LatLng point = _routePolyline[_currentIndex];
      _updateMovingMarker(point); // your custom marker movement method
      _currentIndex++;
    });
  }

  Future<void> _startNavigation() async {
    _showMessage('Starting navigation.');

    // 🔒 Request location permission (already requested in _getCurrentLocation)
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

      // Ensure we have a marker at the current location
      if (_movingMarker == null) {
        await _addMyLocationMarker();
      } else {
        await _updateMovingMarker(currentLocation);
      }

      // Restart location tracking with higher frequency for navigation
      setState(() {
        _navigationRunning = true;
      });
      await _startLocationTracking();
    } else {
      _showMessage('Could not get current location to start navigation.');
      return;
    }

    final Destinations msg = Destinations(
      waypoints: <NavigationWaypoint>[
        NavigationWaypoint.withLatLngTarget(
          title: 'Samnabad',
          target: const LatLng(latitude: 31.5336, longitude: 74.2988),
        ),
      ],
      displayOptions: NavigationDisplayOptions(showDestinationMarkers: false),
    );

    final NavigationRouteStatus status =
        await GoogleMapsNavigator.setDestinations(msg);

    if (status == NavigationRouteStatus.statusOk) {
      await GoogleMapsNavigator.startGuidance();
      await GoogleMapsNavigator.simulator.simulateLocationsAlongExistingRoute();
      _startCustomMarkerSimulation();

      await _navigationViewController?.followMyLocation(
        CameraPerspective.tilted,
      );

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
      (onNavInfo) => _onNavInfoEvent,
      numNextStepsToPreview: 10,
    );
  }

  void _clearListeners() {
    _navInfoSubscription?.cancel();
    _navInfoSubscription = null;
  }

  void _onNavInfoEvent(NavInfoEvent event) async {
    if (!mounted) return;
    setState(() {
      _navInfo = event.navInfo;
    });
  }

  Future<void> _updateMovingMarker(LatLng location) async {
    if (_customIcon == null) {
      await _addCustomMarker();
    }

    if (_movingMarker == null &&
        _navigationViewController != null &&
        _customIcon != null) {
      // First time adding the moving marker
      final MarkerOptions options = MarkerOptions(
        position: location,
        icon: _customIcon!,
        infoWindow: const InfoWindow(title: 'You', snippet: 'Current location'),
      );

      final List<Marker?> addedMarkers = await _navigationViewController!
          .addMarkers([options]);
      if (addedMarkers.isNotEmpty && addedMarkers.first != null) {
        setState(() {
          _movingMarker = addedMarkers.first;
        });
      }
    } else if (_movingMarker != null && _navigationViewController != null) {
      // Update the position of the existing marker
      final updatedMarker = _movingMarker!.copyWith(
        options: _movingMarker!.options.copyWith(position: location),
      );

      try {
        final List<Marker?> markers = await _navigationViewController!
            .updateMarkers([updatedMarker]);
        if (markers.isNotEmpty && markers.first != null) {
          setState(() {
            _movingMarker = markers.first;
          });
        }
      } catch (e) {
        // Handle marker update errors silently to avoid crashes
        log('Error updating marker: $e');
      }
    }
  }

  Future<void> _stopNavigation() async {
    _clearListeners();
    _navInfo = null;
    if (_navigationRunning) {
      await GoogleMapsNavigator.cleanup();
      setState(() {
        _navigationRunning = false;
      });

      // Restart location tracking with normal frequency
      await _startLocationTracking();
    }
  }

  @override
  void dispose() {
    _clearListeners();
    _stopLocationTracking(); // Make sure to stop tracking when disposing
    if (_navigationRunning) {
      GoogleMapsNavigator.cleanup();
    }
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _hideMessage() {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  String formatRemainingDistance(int meters) {
    return meters > 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '$meters m';
  }

  String formatRemainingDuration(Duration duration) {
    final int minutes = duration.inMinutes;
    return minutes > 60
        ? '${duration.inHours} hr ${minutes % 60} min'
        : '$minutes min';
  }

  Widget _getNavInfoWidgetForStep(
    BuildContext context,
    StepInfo stepInfo,
    int? metersToStep,
  ) {
    final double screenWidth = MediaQuery.of(context).size.width;
    const TextStyle textStyle = TextStyle(fontSize: 12, color: Colors.white);

    return Card(
      color: Colors.green.shade400,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: <Widget>[
            Container(
              width: screenWidth / 4,
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Text(
                    'Maneuver',
                    style: textStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(stepInfo.maneuver.name, style: textStyle),
                  if (metersToStep != null)
                    Text(
                      formatRemainingDistance(metersToStep),
                      style: textStyle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Step #${stepInfo.stepNumber}', style: textStyle),
                    const SizedBox(height: 5),
                    Text('Road: ${stepInfo.fullRoadName}', style: textStyle),
                    const SizedBox(height: 5),
                    Text(
                      'Instructions: ${stepInfo.fullInstructions}',
                      style: textStyle,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBottomSheetSteps(BuildContext context, NavInfo navInfo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Make it controllable and take more space
      builder:
          (_) => DraggableScrollableSheet(
            // Wrap with DraggableScrollableSheet
            initialChildSize: 0.5, // Initial height of the sheet (0.0 to 1.0)
            minChildSize: 0.25, // Minimum height the sheet can shrink to
            maxChildSize: 0.9, // Maximum height the sheet can expand to
            expand: false, // Prevent it from always expanding to maxChildSize
            builder: (BuildContext context, ScrollController scrollController) {
              return Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Steps', style: TextStyle(fontSize: 20)),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                    Expanded(
                      // Use Expanded to allow scrolling within the sheet
                      child: SingleChildScrollView(
                        controller:
                            scrollController, // Pass the scroll controller
                        child: Column(
                          children:
                              navInfo.remainingSteps.map((step) {
                                return _getNavInfoWidgetForStep(
                                  context,
                                  step,
                                  null,
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turn-by-Turn Navigation')),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: GoogleMapsNavigationView(
                    onMarkerDrag: (markerId, newPosition) {
                      log(newPosition.latitude.toString());
                    },
                    onViewCreated: _onViewCreated,
                    onMarkerClicked: (markerId) {
                      log("Marker clicked");
                    },
                    initialNavigationUIEnabledPreference:
                        NavigationUIEnabledPreference.automatic,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: _addMyLocationMarker,
                      child: const Text('Add My Location Marker'),
                    ),
                    ElevatedButton(
                      onPressed:
                          _navigationRunning
                              ? _stopNavigation
                              : _startNavigation,
                      child: Text(
                        _navigationRunning
                            ? 'Stop navigation'
                            : 'Start navigation',
                      ),
                    ),
                    ElevatedButton(
                      onPressed:
                          _navigationRunning
                              ? () async {
                                final bool header =
                                    await _navigationViewController!
                                        .isNavigationHeaderEnabled();
                                final bool footer =
                                    await _navigationViewController!
                                        .isNavigationFooterEnabled();
                                await _navigationViewController!
                                    .setNavigationHeaderEnabled(!header);
                                await _navigationViewController!
                                    .setNavigationFooterEnabled(!footer);
                              }
                              : null,
                      child: const Text('Toggle header/footer'),
                    ),
                  ],
                ),
                if (_navInfo != null) _getNavInfoWidgets(_navInfo!),
                if (_navInfo != null)
                  ElevatedButton(
                    onPressed: () => _showBottomSheetSteps(context, _navInfo!),
                    child: const Text('Show/Hide all remaining steps'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsBottomSheet(BuildContext context, NavInfo navInfo) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Material(
        // Wrap with Material for proper theming
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Steps', style: TextStyle(fontSize: 20)),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showBottomSheet = false;
                    });
                  },
                  child: const Text('Close'),
                ),
              ],
            ),
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: Column(
                  children:
                      navInfo.remainingSteps.map((step) {
                        return _getNavInfoWidgetForStep(context, step, null);
                      }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getNavInfoWidgets(NavInfo navInfo) {
    const TextStyle style = TextStyle(fontSize: 12, color: Colors.white);

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (navInfo.currentStep != null)
            _getNavInfoWidgetForStep(
              context,
              navInfo.currentStep!,
              navInfo.distanceToCurrentStepMeters,
            ),
          const SizedBox(height: 5),
          Card(
            color: Colors.green.shade400,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                children: [
                  if (navInfo.timeToFinalDestinationSeconds != null &&
                      navInfo.distanceToFinalDestinationMeters != null)
                    Text(
                      '${formatRemainingDuration(Duration(seconds: navInfo.timeToFinalDestinationSeconds!))} and ${formatRemainingDistance(navInfo.distanceToFinalDestinationMeters!)} to final destination.',
                      style: style,
                    ),
                  if (navInfo.timeToCurrentStepSeconds != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '${formatRemainingDuration(Duration(seconds: navInfo.timeToCurrentStepSeconds!))} to current step.',
                        style: style,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
