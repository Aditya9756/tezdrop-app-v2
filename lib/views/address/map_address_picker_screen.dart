import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/location_service.dart';
import '../../providers/app_state_provider.dart';

/// Blinkit-style "confirm your location" map screen.
/// A fixed pin sits in the center of the screen; the map moves underneath
/// it as the user drags, and reverse-geocoding updates the address text
/// live once dragging stops.
class MapAddressPickerScreen extends StatefulWidget {
  const MapAddressPickerScreen({super.key});

  @override
  State<MapAddressPickerScreen> createState() => _MapAddressPickerScreenState();
}

class _MapAddressPickerScreenState extends State<MapAddressPickerScreen> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(28.6315, 77.2167); // fallback until GPS resolves
  String _addressText = 'Move the map to set your location';
  bool _resolving = true;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _useCurrentLocation();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _resolving = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      _center = LatLng(pos.latitude, pos.longitude);
      _mapController.move(_center, 16);
    }
    await _resolveAddress();
  }

  Future<void> _resolveAddress() async {
    setState(() => _resolving = true);
    final addr = await LocationService.getAddressFromCoords(_center.latitude, _center.longitude);
    if (mounted) setState(() { _addressText = addr; _resolving = false; });
  }

  void _confirm() {
    context.read<AppStateProvider>().setManualAddress(
      _addressText,
      lat: _center.latitude,
      lng: _center.longitude,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  _center = pos.center;
                  if (!_dragging) setState(() => _dragging = true);
                }
              },
              onMapEvent: (event) {
                if (event is MapEventMoveEnd) {
                  setState(() => _dragging = false);
                  _resolveAddress();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tezdrop.app',
              ),
            ],
          ),

          // Fixed center pin — the map moves, this stays put (Blinkit-style)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: AnimatedScale(
                scale: _dragging ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: const Icon(Icons.location_pin, color: AppColors.primary, size: 46),
              ),
            ),
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _circleButton(Icons.arrow_back, () => Navigator.pop(context)),
                  const Spacer(),
                  _circleButton(Icons.my_location, _useCurrentLocation),
                ],
              ),
            ),
          ),

          // Bottom confirm sheet
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      const Text('Delivering to', style: TextStyle(fontSize: 12, color: AppColors.textGrey, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _resolving
                      ? const Row(children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text('Finding address...', style: TextStyle(color: AppColors.textGrey)),
                        ])
                      : Text(_addressText, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      onPressed: _resolving ? null : _confirm,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Confirm Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
        child: Icon(icon, color: AppColors.textDark, size: 20),
      ),
    );
  }
}
