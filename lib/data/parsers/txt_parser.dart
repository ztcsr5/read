import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/chapter.dart';

class TxtParser {
  /// Parse a TXT file into a Book and a list of Chapters.
  static Future<Map<String, dynamic>> parse(PlatformFile file) async {
    // 1. Get bytes handling Web safely
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null && !kIsWeb) {
      bytes = await File(file.path!).readAsBytes();
    }
    
    if (bytes == null) {
      throw Exception('Failed to read file bytes');
    }

    // 2. Decode content: try UTF-8 first, fallback to GBK using fast_gbk
    String content;
    try {
      // Use strict utf8 decoder to catch errors and fallback
      content = const Utf8Codec(allowMalformed: false).decode(bytes);
    } catch (_) {
      content = gbk.decode(bytes);
    }

    // 3. Regex for chapters
    final regex = RegExp(r'(第.{1,6}[章回节]\s+.*|Chapter\s*\d+\s+.*)', caseSensitive: false);
    final matches = regex.allMatches(content).toList();
    
    final List<Chapter> chapters = [];
    int bookId = 0; // Temporary, will be set by repository after book is saved.
    
    // 4. Split and create chapters
    if (matches.isEmpty) {
      // Catch-all: If no chapters found, split every 10k characters
      const int splitLength = 10000;
      int index = 0;
      for (int i = 0; i < content.length; i += splitLength) {
        int end = (i + splitLength < content.length) ? i + splitLength : content.length;
        String body = content.substring(i, end);
        chapters.add(Chapter(
          bookId: bookId,
          title: '第 ${index + 1} 部分',
          index: index,
          content: body.trim(),
          wordCount: body.length,
          isDownloaded: true,
        ));
        index++;
      }
    } else {
      int currentIndex = 0;
      
      // Check for prologue (text before first chapter)
      if (matches[0].start > 0) {
        final prologueText = content.substring(0, matches[0].start).trim();
        if (prologueText.isNotEmpty) {
          chapters.add(Chapter(
            bookId: bookId,
            title: '序言',
            index: currentIndex,
            content: prologueText,
            wordCount: prologueText.length,
            isDownloaded: true,
          ));
          currentIndex++;
        }
      }
      
      for (int i = 0; i < matches.length; i++) {
        final match = matches[i];
        final start = match.start;
        final end = (i + 1 < matches.length) ? matches[i + 1].start : content.length;
        
        final chapterText = content.substring(start, end).trim();
        final lines = chapterText.split('\n');
        
        // Ensure we have at least one line for title
        final title = lines.isNotEmpty ? lines.first.trim() : '未知章节';
        final body = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';

        chapters.add(Chapter(
          bookId: bookId,
          title: title,
          index: currentIndex,
          content: body,
          wordCount: body.length,
          isDownloaded: true,
        ));
        
        currentIndex++;
      }
    }

    final String fileName = file.name;
    final String title = fileName.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
    
    // Create book model
    final book = Book(
      title: title,
      author: '未知作者',
      filePath: kIsWeb ? 'web_$fileName' : file.path!,
      fileType: 'txt',
      totalChapters: chapters.length,
      fileSize: bytes.length,
      isFromSource: false,
    );

    return {'book': book, 'chapters': chapters};
  }
}
