import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'diagnostic_report.dart';

class SourceDiagnosticHistory {
  final String id;
  final String sourceUrl;
  final int score;
  final String reportJson;
  final DateTime createTime;

  SourceDiagnosticHistory({
    required this.id,
    required this.sourceUrl,
    required this.score,
    required this.reportJson,
    required this.createTime,
  });

  DiagnosticReport get report => DiagnosticReport.fromJson(jsonDecode(reportJson));

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceUrl': sourceUrl,
        'score': score,
        'reportJson': reportJson,
        'createTime': createTime.toIso8601String(),
      };

  factory SourceDiagnosticHistory.fromJson(Map<String, dynamic> json) => SourceDiagnosticHistory(
        id: json['id']?.toString() ?? '',
        sourceUrl: json['sourceUrl']?.toString() ?? '',
        score: json['score'] is int ? json['score'] as int : 0,
        reportJson: json['reportJson']?.toString() ?? '{}',
        createTime: json['createTime'] != null
            ? DateTime.tryParse(json['createTime'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );

  // --- Local File JSON Storage Helpers ---
  
  static File? _cachedFile;

  static Future<File> _getDatabaseFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/source_diagnostic_history.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode([]));
    }
    _cachedFile = file;
    return file;
  }

  static Future<List<SourceDiagnosticHistory>> loadAll() async {
    try {
      final file = await _getDatabaseFile();
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content);
      if (list is List) {
        return list.map((item) => SourceDiagnosticHistory.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('Failed to load diagnostic history: $e');
    }
    return [];
  }

  static Future<List<SourceDiagnosticHistory>> getHistoryForSource(String sourceUrl) async {
    final all = await loadAll();
    final filtered = all.where((h) => h.sourceUrl == sourceUrl).toList();
    filtered.sort((a, b) => b.createTime.compareTo(a.createTime));
    return filtered;
  }

  static Future<void> save(SourceDiagnosticHistory record) async {
    try {
      final all = await loadAll();
      all.add(record);
      final file = await _getDatabaseFile();
      await file.writeAsString(jsonEncode(all.map((h) => h.toJson()).toList()));
    } catch (e) {
      print('Failed to save diagnostic history: $e');
    }
  }

  static Future<void> clearHistoryForSource(String sourceUrl) async {
    try {
      final all = await loadAll();
      all.removeWhere((h) => h.sourceUrl == sourceUrl);
      final file = await _getDatabaseFile();
      await file.writeAsString(jsonEncode(all.map((h) => h.toJson()).toList()));
    } catch (e) {
      print('Failed to clear diagnostic history: $e');
    }
  }
}
