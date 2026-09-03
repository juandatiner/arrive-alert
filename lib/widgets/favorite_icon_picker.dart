import 'package:flutter/material.dart';

/// Icon choices for a favorite place, keyed by what's persisted in
/// `Place.icon`. Order here is the order shown in the picker.
const favoritePlaceIcons = <String, IconData>{
  'home': Icons.home_rounded,
  'work': Icons.work_rounded,
  'school': Icons.school_rounded,
  'gym': Icons.fitness_center_rounded,
  'restaurant': Icons.restaurant_rounded,
  'shopping': Icons.shopping_cart_rounded,
  'health': Icons.local_hospital_rounded,
  'transit': Icons.directions_bus_rounded,
  'heart': Icons.favorite_rounded,
  'star': Icons.star_rounded,
};

IconData iconForKey(String? key) => favoritePlaceIcons[key] ?? Icons.star_rounded;

/// A grid of tappable icon choices; tapping the already-selected one clears
/// it back to the default star.
class FavoriteIconPicker extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const FavoriteIconPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: favoritePlaceIcons.entries.map((entry) {
        final isSelected = selected == entry.key;
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(isSelected ? null : entry.key),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? Colors.amber.withValues(alpha: 0.25)
                  : Colors.grey.withValues(alpha: 0.08),
              border: isSelected
                  ? Border.all(color: Colors.amber.shade600, width: 1.5)
                  : null,
            ),
            child: Icon(entry.value, size: 19),
          ),
        );
      }).toList(),
    );
  }
}
