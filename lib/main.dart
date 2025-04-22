import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:mapbox_flutter_map/custom_marker.dart';
import 'package:mapbox_flutter_map/marker_move.dart';
import 'package:mapbox_flutter_map/marker_page.dart';
import 'package:mapbox_flutter_map/multiple_markers.dart';
import 'package:mapbox_flutter_map/provider/location_provider.dart';
import 'package:mapbox_flutter_map/provider/marker_provider.dart';
import 'package:mapbox_flutter_map/provider/multi_nav.dart';
import 'package:mapbox_flutter_map/provider/navigation_provider.dart';
import 'package:provider/provider.dart';

import 'home_page.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MarkerProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Navigation with Provider',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MultipleMarkerNavigationPage(),
    );
  }
}
