import 'package:isar/isar.dart';

part 'book_group.g.dart';

@collection
class BookGroup {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String name;

  int sortOrder = 0;

  DateTime createdAt = DateTime.now();

  BookGroup();
}
