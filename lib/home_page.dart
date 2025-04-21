import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;

class TurnByTurnPage extends StatefulWidget {
  const TurnByTurnPage({super.key});

  @override
  State<TurnByTurnPage> createState() => _TurnByTurnPageState();
}

class _TurnByTurnPageState extends State<TurnByTurnPage> {
  bool _navigationRunning = false;
  GoogleNavigationViewController? _navigationViewController;
  StreamSubscription<NavInfoEvent>? _navInfoSubscription;
  NavInfo? _navInfo;

  List<Marker> _markers = <Marker>[];
  ImageDescriptor? _customIcon;

  Marker? _movingMarker;

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

    final List<Marker?> addedMarkers = await _navigationViewController!
        .addMarkers([options]);
    if (addedMarkers.isNotEmpty && addedMarkers.first != null) {
      setState(() {
        _markers.add(addedMarkers.first!);
      });
    }
  }

  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    _navigationViewController = controller;
    setState(() {});
  }

  Future<void> _startNavigation() async {
    _showMessage('Starting navigation.');

    // 🔒 Request location permission
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

    await GoogleMapsNavigator.simulator.setUserLocation(
      const LatLng(latitude: 37.528560, longitude: -122.361996),
    );

    final Destinations msg = Destinations(
      waypoints: <NavigationWaypoint>[
        NavigationWaypoint.withLatLngTarget(
          title: 'Grace Cathedral',
          target: const LatLng(latitude: 37.791957, longitude: -122.412529),
        ),
      ],
      displayOptions: NavigationDisplayOptions(showDestinationMarkers: false),
    );

    final NavigationRouteStatus status =
        await GoogleMapsNavigator.setDestinations(msg);

    if (status == NavigationRouteStatus.statusOk) {
      await GoogleMapsNavigator.startGuidance();
      await GoogleMapsNavigator.simulator.simulateLocationsAlongExistingRoute();
      await _navigationViewController?.followMyLocation(
        CameraPerspective.tilted,
      );

      _hideMessage();
      setState(() {
        _navigationRunning = true;
      });
    } else {
      _showMessage('Starting navigation failed.');
    }
  }

  Future<void> _setupListeners() async {
    _clearListeners();
    _navInfoSubscription = GoogleMapsNavigator.setNavInfoListener(
      _onNavInfoEvent,
      numNextStepsToPreview: 100,
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

    if (_movingMarker == null) {
      // First time adding the moving marker
      final MarkerOptions options = MarkerOptions(
        position: location,
        icon: _customIcon!,
        infoWindow: const InfoWindow(title: 'You', snippet: 'Current location'),
      );

      final List<Marker?> addedMarkers = await _navigationViewController!
          .addMarkers([options]);
      if (addedMarkers.isNotEmpty && addedMarkers.first != null) {
        _movingMarker = addedMarkers.first;
      }
    } else {
      // Update the position of the existing marker
      final updatedMarker = _movingMarker!.copyWith(
        options: _movingMarker!.options.copyWith(position: location),
      );

      final List<Marker?> markers = await _navigationViewController!
          .updateMarkers([updatedMarker]);
      if (markers.isNotEmpty && markers.first != null) {
        _movingMarker = markers.first;
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
    }
  }

  @override
  void dispose() {
    _clearListeners();
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

  void _showSteps(BuildContext context, NavInfo navInfo) {
    showModalBottomSheet(
      context: context,
      builder:
          (_) => Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                SizedBox(
                  height: 300,
                  child: SingleChildScrollView(
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
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turn-by-Turn Navigation')),
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
              alignment: WrapAlignment.center,
              spacing: 10,
              children: [
                ElevatedButton(
                  onPressed: _addCustomMarker,
                  child: Text('Add Marker'),
                ),
                ElevatedButton(
                  onPressed:
                      _navigationRunning ? _stopNavigation : _startNavigation,
                  child: Text(
                    _navigationRunning ? 'Stop navigation' : 'Start navigation',
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
                onPressed: () => _showSteps(context, _navInfo!),
                child: const Text('Show all remaining steps'),
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
