import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/book.dart';
import '../models/chapter.dart';

class EpubParser {
  /// Parse an ePub file into a Book and a list of Chapters.
  static Future<Map<String, dynamic>> parse(PlatformFile file) async {
    // 1. Get bytes handling Web safely
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null && !kIsWeb) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      throw Exception('Failed to read ePub file bytes');
    }

    // 2. Read ePub book using epubx
    final epubBook = await EpubReader.readBook(bytes);
    
    // 3. Extract chapters recursively
    final chapters = <Chapter>[];
    int bookId = 0; // Temporary
    
    void extractChapters(List<EpubChapter> epubChapters) {
      for (var epubChapter in epubChapters) {
        final html = epubChapter.HtmlContent;
        String content = '';
        
        if (html != null) {
          final document = html_parser.parse(html);
          final pTags = document.getElementsByTagName('p');
          
          if (pTags.isNotEmpty) {
            content = pTags
                .map((e) => e.text.trim())
                .where((e) => e.isNotEmpty)
                .join('\n');
          } else {
            content = document.body?.text.trim() ?? '';
          }
        }
        
        chapters.add(
          Chapter(
            bookId: bookId,
            title: epubChapter.Title ?? 'Chapter ${chapters.length + 1}',
            index: chapters.length,
            content: content,
            wordCount: content.length,
            isDownloaded: true,
          ),
        );
        
        // Handle nested sub-chapters
        if (epubChapter.SubChapters != null && epubChapter.SubChapters!.isNotEmpty) {
          extractChapters(epubChapter.SubChapters!);
        }
      }
    }

    if (epubBook.Chapters != null) {
      extractChapters(epubBook.Chapters!);
    }

    // 4. Extract CoverImage and convert to base64 data URI
    String? coverBase64;
    try {
      final images = epubBook.Content?.Images?.values;
      if (images != null && images.isNotEmpty) {
        EpubByteContentFile? coverImg;
        // Find image with 'cover' in its name
        for (var img in images) {
          if (img.FileName?.toLowerCase().contains('cover') == true) {
            coverImg = img;
            break;
          }
        }
        // Fallback to first image
        coverImg ??= images.first;
        
        if (coverImg.Content != null) {
          final mimeType = coverImg.ContentMimeType ?? 'image/jpeg';
          final base64String = base64Encode(coverImg.Content!);
          coverBase64 = 'data:$mimeType;base64,$base64String';
        }
      }
    } catch (_) {
      // Ignored if fail to get cover image
    }

    final String fileName = file.name;
    final String title = epubBook.Title ?? fileName.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
    
    // Create book model
    final book = Book(
      title: title,
      author: epubBook.Author ?? '未知作者',
      coverPath: coverBase64,
      filePath: kIsWeb ? 'web_$fileName' : file.path!,
      fileType: 'epub',
      totalChapters: chapters.length,
      fileSize: bytes.length,
      isFromSource: false,
    );

    return {'book': book, 'chapters': chapters};
  }
}
