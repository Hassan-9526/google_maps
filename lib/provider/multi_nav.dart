// multiple_marker_navigation_page.dart
import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'marker_provider.dart';
import 'location_provider.dart';
import 'navigation_provider.dart';

class MultipleMarkerNavigationPage extends StatefulWidget {
  const MultipleMarkerNavigationPage({super.key});

  @override
  State<MultipleMarkerNavigationPage> createState() =>
      _MultipleMarkerNavigationPageState();
}

class _MultipleMarkerNavigationPageState
    extends State<MultipleMarkerNavigationPage>
    with TickerProviderStateMixin {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();

    // Use a post-frame callback for smoother initialization
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _initializeAfterFrameRendered();
    });
  }

  Future<void> _initializeAfterFrameRendered() async {
    // Load marker icons in advance
    await Provider.of<MarkerProvider>(
      context,
      listen: false,
    ).loadMarkerIcons(this);
  }

  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    if (_isInitialized) return;
    _isInitialized = true;

    final markerProvider = Provider.of<MarkerProvider>(context, listen: false);
    markerProvider.setNavigationViewController(controller);

    // Disable "my location" to improve performance
    await controller.setMyLocationEnabled(false);

    // Load location and markers in the background
    Future.microtask(() async {
      final locationProvider = Provider.of<LocationProvider>(
        context,
        listen: false,
      );
      final currentLocation = await locationProvider.getCurrentLocation();

      if (currentLocation != null && mounted) {
        await markerProvider.addAllMarkers(currentLocation, this);
        await locationProvider.startLocationTracking(context);
      }
    });
  }

  Future<void> _startNavigation() async {
    final navigationProvider = Provider.of<NavigationProvider>(
      context,
      listen: false,
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Starting navigation...')));

    final success = await navigationProvider.startNavigation(context);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting navigation failed.')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  @override
  void dispose() {
    // Clean up providers
    Provider.of<LocationProvider>(context, listen: false).dispose();
    Provider.of<MarkerProvider>(context, listen: false).dispose();
    Provider.of<NavigationProvider>(context, listen: false).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multiple Markers with Provider')),
      body: GoogleMapsNavigationView(onViewCreated: _onViewCreated),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNavigation,
        child: const Icon(Icons.navigation),
      ),
    );
  }
}
