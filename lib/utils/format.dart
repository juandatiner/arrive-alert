/// "130 min" reads worse than "2 h 10 min" - breaks a minute count into
/// days/hours/minutes, only showing the units that are actually nonzero.
String formatDuration(int totalMinutes) {
  if (totalMinutes <= 0) return '0 min';
  final days = totalMinutes ~/ 1440;
  final hours = (totalMinutes % 1440) ~/ 60;
  final minutes = totalMinutes % 60;
  final parts = [
    if (days > 0) '$days d',
    if (hours > 0) '$hours h',
    if (minutes > 0) '$minutes min',
  ];
  return parts.join(' ');
}
