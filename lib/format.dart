String formatClock(num seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final secs = total % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

String formatBytes(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  if (b >= 1 << 10) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '$b B';
}

String formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n.toString();
}

/// "menos de 1 min", "~3 min", "~1 h 20 min".
String formatEta(int seconds) {
  if (seconds < 60) return 'menos de 1 min';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '~$minutes min';
  return '~${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
}
