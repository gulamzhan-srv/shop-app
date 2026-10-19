// Координаты телефона для журнала входов (видит только администратор).
// Спрашиваем разрешение у Android; если не разрешили или нет GPS — просто не пишем координаты.

import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  Future<(double, double)?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
      final last = await Geolocator.getLastKnownPosition();
      final pos = last ??
          await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
          );
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
