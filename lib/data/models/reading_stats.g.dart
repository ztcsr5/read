// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_stats.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters

extension GetReadingStatsCollection on Isar {
  IsarCollection<ReadingStats> get readingStats => this.collection();
}

const ReadingStatsSchema = CollectionSchema(
  name: r'ReadingStats',
  id: 6003599983390883616,
  properties: {
    r'booksFinished': PropertySchema(
      id: 0,
      name: r'booksFinished',
      type: IsarType.long,
    ),
    r'booksOpened': PropertySchema(
      id: 1,
      name: r'booksOpened',
      type: IsarType.longList,
    ),
    r'booksStarted': PropertySchema(
      id: 2,
      name: r'booksStarted',
      type: IsarType.long,
    ),
    r'date': PropertySchema(
      id: 3,
      name: r'date',
      type: IsarType.dateTime,
    ),
    r'formattedDate': PropertySchema(
      id: 4,
      name: r'formattedDate',
      type: IsarType.string,
    ),
    r'formattedDuration': PropertySchema(
      id: 5,
      name: r'formattedDuration',
      type: IsarType.string,
    ),
    r'pagesRead': PropertySchema(
      id: 6,
      name: r'pagesRead',
      type: IsarType.long,
    ),
    r'readingDurationSeconds': PropertySchema(
      id: 7,
      name: r'readingDurationSeconds',
      type: IsarType.long,
    ),
    r'sessionCount': PropertySchema(
      id: 8,
      name: r'sessionCount',
      type: IsarType.long,
    ),
    r'wordsRead': PropertySchema(
      id: 9,
      name: r'wordsRead',
      type: IsarType.long,
    )
  },
  estimateSize: _readingStatsEstimateSize,
  serialize: _readingStatsSerialize,
  deserialize: _readingStatsDeserialize,
  deserializeProp: _readingStatsDeserializeProp,
  idName: r'id',
  indexes: {
    r'date': IndexSchema(
      id: -7552997827385218417,
      name: r'date',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'date',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _readingStatsGetId,
  getLinks: _readingStatsGetLinks,
  attach: _readingStatsAttach,
  version: '3.0.5',
);

int _readingStatsEstimateSize(
  ReadingStats object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.booksOpened.length * 8;
  bytesCount += 3 + object.formattedDate.length * 3;
  bytesCount += 3 + object.formattedDuration.length * 3;
  return bytesCount;
}

void _readingStatsSerialize(
  ReadingStats object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.booksFinished);
  writer.writeLongList(offsets[1], object.booksOpened);
  writer.writeLong(offsets[2], object.booksStarted);
  writer.writeDateTime(offsets[3], object.date);
  writer.writeString(offsets[4], object.formattedDate);
  writer.writeString(offsets[5], object.formattedDuration);
  writer.writeLong(offsets[6], object.pagesRead);
  writer.writeLong(offsets[7], object.readingDurationSeconds);
  writer.writeLong(offsets[8], object.sessionCount);
  writer.writeLong(offsets[9], object.wordsRead);
}

ReadingStats _readingStatsDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ReadingStats(
    booksFinished: reader.readLongOrNull(offsets[0]) ?? 0,
    booksOpened: reader.readLongList(offsets[1]) ?? const [],
    booksStarted: reader.readLongOrNull(offsets[2]) ?? 0,
    date: reader.readDateTime(offsets[3]),
    pagesRead: reader.readLongOrNull(offsets[6]) ?? 0,
    readingDurationSeconds: reader.readLongOrNull(offsets[7]) ?? 0,
    sessionCount: reader.readLongOrNull(offsets[8]) ?? 0,
    wordsRead: reader.readLongOrNull(offsets[9]) ?? 0,
  );
  object.id = id;
  return object;
}

P _readingStatsDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 1:
      return (reader.readLongList(offset) ?? const []) as P;
    case 2:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 3:
      return (reader.readDateTime(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 7:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 8:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 9:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _readingStatsGetId(ReadingStats object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _readingStatsGetLinks(ReadingStats object) {
  return [];
}

void _readingStatsAttach(
    IsarCollection<dynamic> col, Id id, ReadingStats object) {
  object.id = id;
}

extension ReadingStatsByIndex on IsarCollection<ReadingStats> {
  Future<ReadingStats?> getByDate(DateTime date) {
    return getByIndex(r'date', [date]);
  }

  ReadingStats? getByDateSync(DateTime date) {
    return getByIndexSync(r'date', [date]);
  }

  Future<bool> deleteByDate(DateTime date) {
    return deleteByIndex(r'date', [date]);
  }

  bool deleteByDateSync(DateTime date) {
    return deleteByIndexSync(r'date', [date]);
  }

  Future<List<ReadingStats?>> getAllByDate(List<DateTime> dateValues) {
    final values = dateValues.map((e) => [e]).toList();
    return getAllByIndex(r'date', values);
  }

  List<ReadingStats?> getAllByDateSync(List<DateTime> dateValues) {
    final values = dateValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'date', values);
  }

  Future<int> deleteAllByDate(List<DateTime> dateValues) {
    final values = dateValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'date', values);
  }

  int deleteAllByDateSync(List<DateTime> dateValues) {
    final values = dateValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'date', values);
  }

  Future<Id> putByDate(ReadingStats object) {
    return putByIndex(r'date', object);
  }

  Id putByDateSync(ReadingStats object, {bool saveLinks = true}) {
    return putByIndexSync(r'date', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByDate(List<ReadingStats> objects) {
    return putAllByIndex(r'date', objects);
  }

  List<Id> putAllByDateSync(List<ReadingStats> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'date', objects, saveLinks: saveLinks);
  }
}

extension ReadingStatsQueryWhereSort
    on QueryBuilder<ReadingStats, ReadingStats, QWhere> {
  QueryBuilder<ReadingStats, ReadingStats, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhere> anyDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'date'),
      );
    });
  }
}

extension ReadingStatsQueryWhere
    on QueryBuilder<ReadingStats, ReadingStats, QWhereClause> {
  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> dateEqualTo(
      DateTime date) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'date',
        value: [date],
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> dateNotEqualTo(
      DateTime date) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [],
              upper: [date],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [date],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [date],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [],
              upper: [date],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> dateGreaterThan(
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [date],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> dateLessThan(
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [],
        upper: [date],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterWhereClause> dateBetween(
    DateTime lowerDate,
    DateTime upperDate, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [lowerDate],
        includeLower: includeLower,
        upper: [upperDate],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ReadingStatsQueryFilter
    on QueryBuilder<ReadingStats, ReadingStats, QFilterCondition> {
  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksFinishedEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'booksFinished',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksFinishedGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'booksFinished',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksFinishedLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'booksFinished',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksFinishedBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'booksFinished',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'booksOpened',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'booksOpened',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'booksOpened',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'booksOpened',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'booksOpened',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'booksOpened',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'booksOpened',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'booksOpened',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'booksOpened',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksOpenedLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'booksOpened',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksStartedEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'booksStarted',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksStartedGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'booksStarted',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksStartedLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'booksStarted',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      booksStartedBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'booksStarted',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition> dateEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      dateGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition> dateLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition> dateBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'date',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'formattedDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'formattedDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'formattedDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'formattedDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'formattedDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'formattedDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'formattedDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'formattedDate',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'formattedDate',
        value: '',
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'formattedDate',
        value: '',
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'formattedDuration',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'formattedDuration',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'formattedDuration',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'formattedDuration',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'formattedDuration',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'formattedDuration',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'formattedDuration',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'formattedDuration',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'formattedDuration',
        value: '',
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      formattedDurationIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'formattedDuration',
        value: '',
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      pagesReadEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pagesRead',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      pagesReadGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pagesRead',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      pagesReadLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pagesRead',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      pagesReadBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pagesRead',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      readingDurationSecondsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'readingDurationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      readingDurationSecondsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'readingDurationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      readingDurationSecondsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'readingDurationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      readingDurationSecondsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'readingDurationSeconds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      sessionCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      sessionCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sessionCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      sessionCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sessionCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      sessionCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sessionCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      wordsReadEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'wordsRead',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      wordsReadGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'wordsRead',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      wordsReadLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'wordsRead',
        value: value,
      ));
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterFilterCondition>
      wordsReadBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'wordsRead',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ReadingStatsQueryObject
    on QueryBuilder<ReadingStats, ReadingStats, QFilterCondition> {}

extension ReadingStatsQueryLinks
    on QueryBuilder<ReadingStats, ReadingStats, QFilterCondition> {}

extension ReadingStatsQuerySortBy
    on QueryBuilder<ReadingStats, ReadingStats, QSortBy> {
  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByBooksFinished() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'booksFinished', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      sortByBooksFinishedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'booksFinished', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByBooksStarted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'booksStarted', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      sortByBooksStartedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'booksStarted', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByFormattedDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDate', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      sortByFormattedDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDate', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      sortByFormattedDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDuration', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      sortByFormattedDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDuration', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByPagesRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pagesRead', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByPagesReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pagesRead', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      sortByReadingDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'readingDurationSeconds', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      sortByReadingDurationSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'readingDurationSeconds', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortBySessionCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionCount', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      sortBySessionCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionCount', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByWordsRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'wordsRead', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> sortByWordsReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'wordsRead', Sort.desc);
    });
  }
}

extension ReadingStatsQuerySortThenBy
    on QueryBuilder<ReadingStats, ReadingStats, QSortThenBy> {
  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByBooksFinished() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'booksFinished', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      thenByBooksFinishedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'booksFinished', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByBooksStarted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'booksStarted', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      thenByBooksStartedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'booksStarted', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByFormattedDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDate', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      thenByFormattedDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDate', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      thenByFormattedDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDuration', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      thenByFormattedDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDuration', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByPagesRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pagesRead', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByPagesReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pagesRead', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      thenByReadingDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'readingDurationSeconds', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      thenByReadingDurationSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'readingDurationSeconds', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenBySessionCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionCount', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy>
      thenBySessionCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionCount', Sort.desc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByWordsRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'wordsRead', Sort.asc);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QAfterSortBy> thenByWordsReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'wordsRead', Sort.desc);
    });
  }
}

extension ReadingStatsQueryWhereDistinct
    on QueryBuilder<ReadingStats, ReadingStats, QDistinct> {
  QueryBuilder<ReadingStats, ReadingStats, QDistinct>
      distinctByBooksFinished() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'booksFinished');
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct> distinctByBooksOpened() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'booksOpened');
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct> distinctByBooksStarted() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'booksStarted');
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct> distinctByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'date');
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct> distinctByFormattedDate(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'formattedDate',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct>
      distinctByFormattedDuration({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'formattedDuration',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct> distinctByPagesRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pagesRead');
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct>
      distinctByReadingDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'readingDurationSeconds');
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct> distinctBySessionCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sessionCount');
    });
  }

  QueryBuilder<ReadingStats, ReadingStats, QDistinct> distinctByWordsRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'wordsRead');
    });
  }
}

extension ReadingStatsQueryProperty
    on QueryBuilder<ReadingStats, ReadingStats, QQueryProperty> {
  QueryBuilder<ReadingStats, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ReadingStats, int, QQueryOperations> booksFinishedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'booksFinished');
    });
  }

  QueryBuilder<ReadingStats, List<int>, QQueryOperations>
      booksOpenedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'booksOpened');
    });
  }

  QueryBuilder<ReadingStats, int, QQueryOperations> booksStartedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'booksStarted');
    });
  }

  QueryBuilder<ReadingStats, DateTime, QQueryOperations> dateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'date');
    });
  }

  QueryBuilder<ReadingStats, String, QQueryOperations> formattedDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'formattedDate');
    });
  }

  QueryBuilder<ReadingStats, String, QQueryOperations>
      formattedDurationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'formattedDuration');
    });
  }

  QueryBuilder<ReadingStats, int, QQueryOperations> pagesReadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pagesRead');
    });
  }

  QueryBuilder<ReadingStats, int, QQueryOperations>
      readingDurationSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'readingDurationSeconds');
    });
  }

  QueryBuilder<ReadingStats, int, QQueryOperations> sessionCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sessionCount');
    });
  }

  QueryBuilder<ReadingStats, int, QQueryOperations> wordsReadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'wordsRead');
    });
  }
}
