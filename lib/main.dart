import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:mapbox_flutter_map/custom_marker.dart';
import 'package:mapbox_flutter_map/marker_move.dart';
import 'package:mapbox_flutter_map/marker_page.dart';
import 'package:mapbox_flutter_map/multiple_markers.dart';

import 'home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: MultipleMarkerMovingPage(),
    );
  }
}
