import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../data/models/book.dart';
import '../../../data/models/chapter.dart';
import '../../../data/models/book_group.dart';
import '../../../data/parsers/epub_parser.dart';
import '../../../data/parsers/txt_parser.dart';
import '../../../data/repositories/book_repository.dart';

class BookshelfState {
  final List<Book> allBooks;
  final List<Book> recentBooks;
  final List<BookGroup> groups;
  final bool isLoading;
  final String? error;

  BookshelfState({
    this.allBooks = const [],
    this.recentBooks = const [],
    this.groups = const [],
    this.isLoading = false,
    this.error,
  });

  BookshelfState copyWith({
    List<Book>? allBooks,
    List<Book>? recentBooks,
    List<BookGroup>? groups,
    bool? isLoading,
    String? error,
  }) {
    return BookshelfState(
      allBooks: allBooks ?? this.allBooks,
      recentBooks: recentBooks ?? this.recentBooks,
      groups: groups ?? this.groups,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class BookshelfViewModel extends StateNotifier<BookshelfState> {
  final BookRepository _bookRepository;

  BookshelfViewModel(this._bookRepository) : super(BookshelfState()) {
    loadBooks();
  }

  /// Load all books from repository and sort recent books.
  Future<void> loadBooks() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final books = await _bookRepository.getAllBooks();
      final groups = await _bookRepository.getAllBookGroups();

      // Sort for recent books based on lastReadTime (fallback to dateAdded)
      final recent = List<Book>.from(books)
        ..sort((a, b) {
          final aTime = a.lastReadTime ?? a.dateAdded;
          final bTime = b.lastReadTime ?? b.dateAdded;
          return bTime.compareTo(aTime);
        });

      state = state.copyWith(
        allBooks: books,
        recentBooks: recent.take(5).toList(), // top 5 recent
        groups: groups,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Prompt the user to pick a file (txt, epub) and parse it, then save it to the database.
  Future<void> importLocalBook() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      // Allow user to pick .txt or .epub file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub'],
        withData: true, // Need this for web support and robust parsing
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final extension = file.extension?.toLowerCase();

        Map<String, dynamic> parsedData;
        if (extension == 'txt') {
          parsedData = await TxtParser.parse(file);
        } else if (extension == 'epub') {
          parsedData = await EpubParser.parse(file);
        } else {
          throw Exception('Unsupported file type: $extension');
        }

        final book = parsedData['book'] as Book;
        final chapters = parsedData['chapters'] as List<Chapter>;

        // 1. Save Book to DB to get its ID
        final bookId = await _bookRepository.saveBook(book);

        // 2. Assign bookId to all parsed chapters
        for (var chapter in chapters) {
          chapter.bookId = bookId;
        }

        // 3. Save Chapters
        await _bookRepository.saveChapters(chapters);

        // 4. Reload books
        await loadBooks();
      } else {
        // User canceled picker
        state = state.copyWith(isLoading: false);
      }
    } catch (e, st) {
      print('Import Error: $e\n$st');
      state = state.copyWith(isLoading: false, error: '导入失败: $e');
    }
  }

  Future<int?> importBookFromPath(String filePath) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final normalizedPath = _normalizeImportPath(filePath);
      final extension = path
          .extension(normalizedPath)
          .replaceFirst('.', '')
          .toLowerCase();
      final file = PlatformFile(
        name: path.basename(normalizedPath),
        path: normalizedPath,
        size: 0,
      );

      Map<String, dynamic> parsedData;
      if (extension == 'txt') {
        parsedData = await TxtParser.parse(file);
      } else if (extension == 'epub') {
        parsedData = await EpubParser.parse(file);
      } else {
        throw Exception('不支持的文件类型: $extension');
      }

      final book = parsedData['book'] as Book;
      final chapters = parsedData['chapters'] as List<Chapter>;
      final bookId = await _bookRepository.saveBook(book);
      for (var chapter in chapters) {
        chapter.bookId = bookId;
      }
      await _bookRepository.saveChapters(chapters);
      await loadBooks();
      return bookId;
    } catch (e, st) {
      print('External Import Error: $e\n$st');
      state = state.copyWith(isLoading: false, error: '导入失败: $e');
      return null;
    }
  }

  String _normalizeImportPath(String filePath) {
    if (!filePath.startsWith('file://')) {
      return filePath;
    }
    try {
      return Uri.parse(filePath).toFilePath();
    } catch (_) {
      return filePath.replaceFirst(RegExp(r'^file://'), '');
    }
  }

  /// Delete a book from the repository by ID and reload the list.
  Future<void> deleteBook(int bookId) async {
    try {
      await _bookRepository.deleteBook(bookId);
      await loadBooks();
    } catch (e) {
      state = state.copyWith(error: '删除失败: $e');
    }
  }

  // --- Group Methods ---

  Future<void> createGroup(String name) async {
    try {
      final group = BookGroup()..name = name;
      await _bookRepository.saveBookGroup(group);
      await loadBooks();
    } catch (e) {
      state = state.copyWith(error: '创建分组失败: $e');
    }
  }

  Future<void> deleteGroup(int groupId) async {
    try {
      await _bookRepository.deleteBookGroup(groupId);
      await loadBooks();
    } catch (e) {
      state = state.copyWith(error: '删除分组失败: $e');
    }
  }

  Future<void> moveBookToGroup(Book book, int? groupId) async {
    try {
      final updatedBook = book.copyWith(groupId: groupId);
      await _bookRepository.saveBook(updatedBook);
      await loadBooks();
    } catch (e) {
      state = state.copyWith(error: '移动失败: $e');
    }
  }
}

/// Riverpod Provider for BookshelfViewModel
final bookshelfViewModelProvider =
    StateNotifierProvider<BookshelfViewModel, BookshelfState>((ref) {
      final repo = ref.watch(bookRepositoryProvider);
      return BookshelfViewModel(repo);
    });

final pendingImportFilePathProvider = StateProvider<String?>((ref) => null);
