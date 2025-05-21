// lib/core/control/location_service.dart - Mejorado
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;
  final String? address;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    required this.timestamp,
    this.address,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'timestamp': timestamp.toIso8601String(),
      'address': address,
      'maps_url': getMapsUrl(),
    };
  }

  String getMapsUrl() {
    return 'https://www.google.com/maps?q=$latitude,$longitude';
  }

  LatLng toLatLng() {
    return LatLng(latitude, longitude);
  }
}

class LocationService {
  /// الحصول على الموقع الحالي بدقة عالية
  Future<LocationData?> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeout = const Duration(seconds: 30),
    bool forceAndroidLocationManager = false,
  }) async {
    try {
      // التحقق من إذن الموقع
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("LocationService: Location services are disabled");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("LocationService: Location permissions are denied");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("LocationService: Location permissions are permanently denied");
        return null;
      }

      // الحصول على الموقع بإعدادات مخصصة
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout,
        forceAndroidLocationManager: forceAndroidLocationManager,
      );
      
      debugPrint("LocationService: Location obtained: ${position.latitude}, ${position.longitude}");
      
      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );
    } catch (e) {
      debugPrint("LocationService: Error getting location: $e");
      return null;
    }
  }

  /// الحصول على آخر موقع معروف (أسرع ولكن قد يكون أقل دقة)
  Future<LocationData?> getLastKnownLocation() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        debugPrint("LocationService: Last known location: ${position.latitude}, ${position.longitude}");
        
        return LocationData(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          altitude: position.altitude,
          speed: position.speed,
          heading: position.heading,
          timestamp: position.timestamp,
        );
      } else {
        debugPrint("LocationService: No last known location available");
        return null;
      }
    } catch (e) {
      debugPrint("LocationService: Error getting last known location: $e");
      return null;
    }
  }

  /// تتبع الموقع بشكل مستمر
  Stream<LocationData> getLocationUpdates({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10,
    bool forceAndroidLocationManager = false,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    ).map((position) => LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp,
    ));
  }

  /// حساب المسافة بين موقعين بالمتر
  double calculateDistance(
    double startLatitude, 
    double startLongitude, 
    double endLatitude, 
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude, 
      startLongitude, 
      endLatitude, 
      endLongitude,
    );
  }
}