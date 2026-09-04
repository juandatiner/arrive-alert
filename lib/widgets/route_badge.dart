import 'package:flutter/material.dart';
import '../models/transit_route.dart';
import '../screens/route_picker_sheet.dart' show kindColor;

/// The service code as riders read it - "B13", "K86", "6-4" - on the colour
/// of its service type.
class RouteBadge extends StatelessWidget {
  final String shortName;
  final TransitKind kind;
  final bool compact;

  const RouteBadge({
    super.key,
    required this.shortName,
    required this.kind,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: kindColor(kind),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      // Codes run from "2" to "M86-K86", so shrink rather than clip.
      child: Text(
        shortName,
        maxLines: 1,
        style: TextStyle(
          fontSize: compact ? 10.5 : 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
