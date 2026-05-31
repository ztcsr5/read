import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../data/models/book.dart';
import '../app/theme/colors.dart';

class BookCover extends StatelessWidget {
  final Book book;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double iconSize;

  const BookCover({
    super.key,
    required this.book,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.iconSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    final cover = book.coverPath;
    if (cover != null && cover.isNotEmpty) {
      if (cover.startsWith('data:')) {
        final comma = cover.indexOf(',');
        if (comma > 0) {
          try {
            return Image.memory(
              base64Decode(cover.substring(comma + 1)),
              width: width,
              height: height,
              fit: fit,
            );
          } catch (_) {}
        }
      }
      if (cover.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: cover,
          width: width,
          height: height,
          fit: fit,
          placeholder: (_, _) => _placeholder(context),
          errorWidget: (_, _, _) => _placeholder(context),
        );
      }
      if (!kIsWeb && File(cover).existsSync()) {
        return Image.file(File(cover), width: width, height: height, fit: fit);
      }
    }

    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: AppColors.primaryBlue.withOpacity(0.1),
      child: Center(
        child: Icon(
          CupertinoIcons.book,
          size: iconSize,
          color: AppColors.primaryBlue,
        ),
      ),
    );
  }
}
