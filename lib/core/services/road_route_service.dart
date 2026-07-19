import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoadRouteService {
  /// Fetches real road path from OSRM, falls back to a straight line
  /// of points if the request fails — mirrors the HTML app's getRoadPath().
  static Future<List<LatLng>> getRoadPath(LatLng from, LatLng to) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson&steps=false',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      final data = jsonDecode(res.body);
      if (data['code'] == 'Ok' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        return coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      }
    } catch (_) {}

    // Fallback: straight line interpolation, same as HTML app
    const steps = 20;
    return List.generate(steps + 1, (i) {
      final lat = from.latitude + (to.latitude - from.latitude) * i / steps;
      final lng = from.longitude + (to.longitude - from.longitude) * i / steps;
      return LatLng(lat, lng);
    });
  }

  /// Bearing in degrees from point1 to point2, for rotating the bike icon.
  static double getBearing(LatLng p1, LatLng p2) {
    final lat1 = p1.latitude * math.pi / 180;
    final lat2 = p2.latitude * math.pi / 180;
    final dLng = (p2.longitude - p1.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  /// Rough distance estimate in km, same heuristic style as HTML app.
  static double estimateDistanceKm(List<LatLng> path) => path.length * 0.015;
}
