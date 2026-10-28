/// Defensive JSON readers. API data is validated server-side, but the app never crashes on
/// an unexpected shape.
String str(Object? v) => v is String ? v : (v == null ? '' : v.toString());

String? strOrNull(Object? v) {
  if (v == null) return null;
  final s = str(v);
  return s.isEmpty ? null : s;
}

List<String> strList(Object? v) => v is List ? v.map(str).where((s) => s.isNotEmpty).toList() : const <String>[];

Map<String, dynamic> obj(Object? v) => v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

List<Map<String, dynamic>> objList(Object? v) => v is List ? v.map(obj).toList() : const <Map<String, dynamic>>[];

double? numOrNull(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int intOr(Object? v, int fallback) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);

bool boolOr(Object? v, bool fallback) => v is bool ? v : fallback;

DateTime? dateOrNull(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
