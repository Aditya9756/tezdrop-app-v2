import 'package:flutter/material.dart';

/// A Blinkit-style avatar: a colored circle showing the user's
/// first initial. No network call, no loading delay, always works.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final double fontSize;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.radius = 20,
    this.fontSize = 16,
  });

  static const List<Color> _palette = [
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF06B6D4),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  Color _colorForName(String n) {
    if (n.isEmpty) return _palette[0];
    final hash = n.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b);
    return _palette[hash % _palette.length];
  }

  String _initialFor(String n) {
    final trimmed = n.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _colorForName(name),
      child: Text(
        _initialFor(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }
}
