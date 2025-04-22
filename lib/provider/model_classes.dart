// model classes
import 'dart:isolate';
import 'dart:math' show sin, cos, sqrt, asin, pi;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

class MarkerData {
  final Marker marker;
  final AnimationController animationController;
  final LatLng lastPosition;

  MarkerData({
    required this.marker,
    required this.animationController,
    required this.lastPosition,
  });

  MarkerData copyWith({
    Marker? marker,
    AnimationController? animationController,
    LatLng? lastPosition,
  }) {
    return MarkerData(
      marker: marker ?? this.marker,
      animationController: animationController ?? this.animationController,
      lastPosition: lastPosition ?? this.lastPosition,
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
