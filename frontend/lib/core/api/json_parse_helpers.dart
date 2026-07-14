// SmartBiz AI — Shared JSON parsing helpers.
//
// Backend numeric columns (PostgreSQL/MySQL decimal) are serialised by
// Laravel as JSON strings (e.g. "95000.00", "2.0000").  These helpers
// safely parse [String], [num], and [null] without unsafe `as num` casts.

/// Parse a JSON value that may be a [num], a numeric [String], or null.
/// Returns the value as a [double], or `null` when the input is null,
/// empty, or not a valid number.
double? parseJsonDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }
  return null;
}

/// Like [parseJsonDouble] but returns a non-null [double],
/// falling back to [fallback] (default `0.0`).
double parseJsonDoubleOr(dynamic v, [double fallback = 0.0]) {
  return parseJsonDouble(v) ?? fallback;
}
