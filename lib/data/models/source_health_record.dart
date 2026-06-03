import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SourceHealthRecord {
  final String sourceUrl;
  final String date; // Format: yyyy-MM-dd
  int searchSuccess;
  int searchTotal;
  int tocSuccess;
  int tocTotal;
  int contentSuccess;
  int contentTotal;
  int avgResponseTimeMs;
  int responseCount;

  SourceHealthRecord({
    required this.sourceUrl,
    required this.date,
    this.searchSuccess = 0,
    this.searchTotal = 0,
    this.tocSuccess = 0,
    this.tocTotal = 0,
    this.contentSuccess = 0,
    this.contentTotal = 0,
    this.avgResponseTimeMs = 0,
    this.responseCount = 0,
  });

  double get successRate {
    final success = searchSuccess + tocSuccess + contentSuccess;
    final total = searchTotal + tocTotal + contentTotal;
    if (total == 0) return 0.0;
    return success / total;
  }

  Map<String, dynamic> toJson() => {
        'sourceUrl': sourceUrl,
        'date': date,
        'searchSuccess': searchSuccess,
        'searchTotal': searchTotal,
        'tocSuccess': tocSuccess,
        'tocTotal': tocTotal,
        'contentSuccess': contentSuccess,
        'contentTotal': contentTotal,
        'avgResponseTimeMs': avgResponseTimeMs,
        'responseCount': responseCount,
      };

  factory SourceHealthRecord.fromJson(Map<String, dynamic> json) => SourceHealthRecord(
        sourceUrl: json['sourceUrl']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        searchSuccess: json['searchSuccess'] is int ? json['searchSuccess'] as int : 0,
        searchTotal: json['searchTotal'] is int ? json['searchTotal'] as int : 0,
        tocSuccess: json['tocSuccess'] is int ? json['tocSuccess'] as int : 0,
        tocTotal: json['tocTotal'] is int ? json['tocTotal'] as int : 0,
        contentSuccess: json['contentSuccess'] is int ? json['contentSuccess'] as int : 0,
        contentTotal: json['contentTotal'] is int ? json['contentTotal'] as int : 0,
        avgResponseTimeMs: json['avgResponseTimeMs'] is int ? json['avgResponseTimeMs'] as int : 0,
        responseCount: json['responseCount'] is int ? json['responseCount'] as int : 0,
      );

  // --- Local Database Helpers ---

  static File? _cachedFile;

  static Future<File> _getDatabaseFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/source_health_records.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode([]));
    }
    _cachedFile = file;
    return file;
  }

  static Future<List<SourceHealthRecord>> loadAll() async {
    try {
      final file = await _getDatabaseFile();
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content);
      if (list is List) {
        return list.map((item) => SourceHealthRecord.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('Failed to load health records: $e');
    }
    return [];
  }

  static Future<List<SourceHealthRecord>> getRecordsForSource(String sourceUrl) async {
    final all = await loadAll();
    final filtered = all.where((r) => r.sourceUrl == sourceUrl).toList();
    // Sort chronological: oldest to newest
    filtered.sort((a, b) => a.date.compareTo(b.date));
    return filtered;
  }

  static Future<void> logRecord(
    String sourceUrl, {
    required bool searchOk,
    required bool tocOk,
    required bool contentOk,
    required int responseTimeMs,
  }) async {
    try {
      final all = await loadAll();
      final now = DateTime.now().toLocal();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Find if we already have a record for this source on this day
      var record = all.firstWhere(
        (r) => r.sourceUrl == sourceUrl && r.date == dateStr,
        orElse: () {
          final newRec = SourceHealthRecord(sourceUrl: sourceUrl, date: dateStr);
          all.add(newRec);
          return newRec;
        },
      );

      record.searchTotal++;
      if (searchOk) record.searchSuccess++;

      record.tocTotal++;
      if (tocOk) record.tocSuccess++;

      record.contentTotal++;
      if (contentOk) record.contentSuccess++;

      // Clipping Filter: limit maximum delay to 5000ms to prevent transient extremum hangs (like CF block loops) from polluting health charts
      final clippedTime = responseTimeMs > 5000 ? 5000 : responseTimeMs;

      final oldTotalTime = record.avgResponseTimeMs * record.responseCount;
      record.responseCount++;
      record.avgResponseTimeMs = ((oldTotalTime + clippedTime) / record.responseCount).round();

      final file = await _getDatabaseFile();
      await file.writeAsString(jsonEncode(all.map((r) => r.toJson()).toList()));
    } catch (e) {
      print('Failed to log health record: $e');
    }
  }

  static Future<void> clearHistoryForSource(String sourceUrl) async {
    try {
      final all = await loadAll();
      all.removeWhere((r) => r.sourceUrl == sourceUrl);
      final file = await _getDatabaseFile();
      await file.writeAsString(jsonEncode(all.map((r) => r.toJson()).toList()));
    } catch (e) {
      print('Failed to clear health records: $e');
    }
  }
}
