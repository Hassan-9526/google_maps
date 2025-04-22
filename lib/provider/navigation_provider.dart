// navigation_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:provider/provider.dart';
import 'marker_provider.dart';
import 'location_provider.dart';

class NavigationProvider extends ChangeNotifier {
  StreamSubscription<NavInfoEvent>? _navInfoSubscription;
  NavInfo? _navInfo;

  NavInfo? get navInfo => _navInfo;

  Future<void> setupListeners() async {
    clearListeners();
    _navInfoSubscription = GoogleMapsNavigator.setNavInfoListener(
      (event) => _onNavInfoEvent(event),
      numNextStepsToPreview:
          0, // Reduce number of previewed steps for better performance
    );
  }

  void clearListeners() {
    _navInfoSubscription?.cancel();
    _navInfoSubscription = null;
  }

  void _onNavInfoEvent(NavInfoEvent event) {
    _navInfo = event.navInfo;
    notifyListeners();
  }

  Future<bool> startNavigation(BuildContext context) async {
    final locationProvider = Provider.of<LocationProvider>(
      context,
      listen: false,
    );
    final markerProvider = Provider.of<MarkerProvider>(context, listen: false);

    if (!await GoogleMapsNavigator.areTermsAccepted()) {
      await GoogleMapsNavigator.showTermsAndConditionsDialog(
        'Navigation Sample',
        'My Company',
      );
    }

    await GoogleMapsNavigator.initializeNavigationSession();
    await setupListeners();

    final currentLocation = await locationProvider.getCurrentLocation();
    if (currentLocation != null) {
      await GoogleMapsNavigator.simulator.setUserLocation(currentLocation);

      // Update all markers with current location
      markerProvider.updateAllMarkers(currentLocation);

      locationProvider.setNavigationRunning(true);
      await locationProvider.startLocationTracking(context);
    } else {
      return false;
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
      return true;
    } else {
      locationProvider.setNavigationRunning(false);
      return false;
    }
  }

  void dispose() {
    clearListeners();
    super.dispose();
  }
}
