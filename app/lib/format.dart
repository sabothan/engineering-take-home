const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String formatTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// "Tuesday, 13 October"
String formatLongDate(DateTime day) =>
    '${_weekdays[day.weekday - 1]}, ${day.day} ${_months[day.month - 1]}';

/// "Today", "Yesterday" or "Sat 10 Oct"
String formatDayHeading(DateTime day, DateTime today) {
  final daysAgo = dayOf(today).difference(day).inDays;
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  return '${_weekdays[day.weekday - 1].substring(0, 3)} ${day.day} '
      '${_months[day.month - 1].substring(0, 3)}';
}

/// "1 October 2026"
String formatDate(DateTime day) => '${day.day} ${_months[day.month - 1]} ${day.year}';

/// "1 October 2026 – 7 October 2026"
String formatDateRange(DateTime from, DateTime to) => '${formatDate(from)} – ${formatDate(to)}';

/// "1 October 2026 at 10:03"
String formatDateTime(DateTime value) => '${formatDate(value.toLocal())} at ${formatTime(value)}';

/// Parses a plain "YYYY-MM-DD" calendar date — a share's from_date/to_date — into its
/// year/month/day components directly, with no timezone conversion: these are calendar days,
/// not instants.
DateTime parseCalendarDate(String value) {
  final parts = value.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// The inverse of [parseCalendarDate], for sending a calendar day back to the API.
String formatCalendarDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
