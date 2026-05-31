// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_source.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters

extension GetBookSourceCollection on Isar {
  IsarCollection<BookSource> get bookSources => this.collection();
}

const BookSourceSchema = CollectionSchema(
  name: r'BookSource',
  id: 3407291549206200867,
  properties: {
    r'bookSourceGroup': PropertySchema(
      id: 0,
      name: r'bookSourceGroup',
      type: IsarType.string,
    ),
    r'bookSourceName': PropertySchema(
      id: 1,
      name: r'bookSourceName',
      type: IsarType.string,
    ),
    r'bookSourceType': PropertySchema(
      id: 2,
      name: r'bookSourceType',
      type: IsarType.long,
    ),
    r'bookSourceUrl': PropertySchema(
      id: 3,
      name: r'bookSourceUrl',
      type: IsarType.string,
    ),
    r'customConfig': PropertySchema(
      id: 4,
      name: r'customConfig',
      type: IsarType.string,
    ),
    r'enabled': PropertySchema(
      id: 5,
      name: r'enabled',
      type: IsarType.bool,
    ),
    r'exploreUrl': PropertySchema(
      id: 6,
      name: r'exploreUrl',
      type: IsarType.string,
    ),
    r'ruleBookInfo': PropertySchema(
      id: 7,
      name: r'ruleBookInfo',
      type: IsarType.string,
    ),
    r'ruleContent': PropertySchema(
      id: 8,
      name: r'ruleContent',
      type: IsarType.string,
    ),
    r'ruleExplore': PropertySchema(
      id: 9,
      name: r'ruleExplore',
      type: IsarType.string,
    ),
    r'ruleSearch': PropertySchema(
      id: 10,
      name: r'ruleSearch',
      type: IsarType.string,
    ),
    r'ruleToc': PropertySchema(
      id: 11,
      name: r'ruleToc',
      type: IsarType.string,
    ),
    r'searchUrl': PropertySchema(
      id: 12,
      name: r'searchUrl',
      type: IsarType.string,
    ),
    r'weight': PropertySchema(
      id: 13,
      name: r'weight',
      type: IsarType.long,
    )
  },
  estimateSize: _bookSourceEstimateSize,
  serialize: _bookSourceSerialize,
  deserialize: _bookSourceDeserialize,
  deserializeProp: _bookSourceDeserializeProp,
  idName: r'id',
  indexes: {
    r'bookSourceName': IndexSchema(
      id: 5034252118557357802,
      name: r'bookSourceName',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'bookSourceName',
          type: IndexType.value,
          caseSensitive: true,
        )
      ],
    ),
    r'bookSourceUrl': IndexSchema(
      id: 4282228791356572158,
      name: r'bookSourceUrl',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'bookSourceUrl',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _bookSourceGetId,
  getLinks: _bookSourceGetLinks,
  attach: _bookSourceAttach,
  version: '3.0.5',
);

int _bookSourceEstimateSize(
  BookSource object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.bookSourceGroup;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.bookSourceName.length * 3;
  bytesCount += 3 + object.bookSourceUrl.length * 3;
  {
    final value = object.customConfig;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.exploreUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleBookInfo;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleContent;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleExplore;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleSearch;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleToc;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.searchUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _bookSourceSerialize(
  BookSource object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.bookSourceGroup);
  writer.writeString(offsets[1], object.bookSourceName);
  writer.writeLong(offsets[2], object.bookSourceType);
  writer.writeString(offsets[3], object.bookSourceUrl);
  writer.writeString(offsets[4], object.customConfig);
  writer.writeBool(offsets[5], object.enabled);
  writer.writeString(offsets[6], object.exploreUrl);
  writer.writeString(offsets[7], object.ruleBookInfo);
  writer.writeString(offsets[8], object.ruleContent);
  writer.writeString(offsets[9], object.ruleExplore);
  writer.writeString(offsets[10], object.ruleSearch);
  writer.writeString(offsets[11], object.ruleToc);
  writer.writeString(offsets[12], object.searchUrl);
  writer.writeLong(offsets[13], object.weight);
}

BookSource _bookSourceDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = BookSource();
  object.bookSourceGroup = reader.readStringOrNull(offsets[0]);
  object.bookSourceName = reader.readString(offsets[1]);
  object.bookSourceType = reader.readLong(offsets[2]);
  object.bookSourceUrl = reader.readString(offsets[3]);
  object.customConfig = reader.readStringOrNull(offsets[4]);
  object.enabled = reader.readBool(offsets[5]);
  object.exploreUrl = reader.readStringOrNull(offsets[6]);
  object.id = id;
  object.ruleBookInfo = reader.readStringOrNull(offsets[7]);
  object.ruleContent = reader.readStringOrNull(offsets[8]);
  object.ruleExplore = reader.readStringOrNull(offsets[9]);
  object.ruleSearch = reader.readStringOrNull(offsets[10]);
  object.ruleToc = reader.readStringOrNull(offsets[11]);
  object.searchUrl = reader.readStringOrNull(offsets[12]);
  object.weight = reader.readLong(offsets[13]);
  return object;
}

P _bookSourceDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _bookSourceGetId(BookSource object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _bookSourceGetLinks(BookSource object) {
  return [];
}

void _bookSourceAttach(IsarCollection<dynamic> col, Id id, BookSource object) {
  object.id = id;
}

extension BookSourceByIndex on IsarCollection<BookSource> {
  Future<BookSource?> getByBookSourceUrl(String bookSourceUrl) {
    return getByIndex(r'bookSourceUrl', [bookSourceUrl]);
  }

  BookSource? getByBookSourceUrlSync(String bookSourceUrl) {
    return getByIndexSync(r'bookSourceUrl', [bookSourceUrl]);
  }

  Future<bool> deleteByBookSourceUrl(String bookSourceUrl) {
    return deleteByIndex(r'bookSourceUrl', [bookSourceUrl]);
  }

  bool deleteByBookSourceUrlSync(String bookSourceUrl) {
    return deleteByIndexSync(r'bookSourceUrl', [bookSourceUrl]);
  }

  Future<List<BookSource?>> getAllByBookSourceUrl(
      List<String> bookSourceUrlValues) {
    final values = bookSourceUrlValues.map((e) => [e]).toList();
    return getAllByIndex(r'bookSourceUrl', values);
  }

  List<BookSource?> getAllByBookSourceUrlSync(
      List<String> bookSourceUrlValues) {
    final values = bookSourceUrlValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'bookSourceUrl', values);
  }

  Future<int> deleteAllByBookSourceUrl(List<String> bookSourceUrlValues) {
    final values = bookSourceUrlValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'bookSourceUrl', values);
  }

  int deleteAllByBookSourceUrlSync(List<String> bookSourceUrlValues) {
    final values = bookSourceUrlValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'bookSourceUrl', values);
  }

  Future<Id> putByBookSourceUrl(BookSource object) {
    return putByIndex(r'bookSourceUrl', object);
  }

  Id putByBookSourceUrlSync(BookSource object, {bool saveLinks = true}) {
    return putByIndexSync(r'bookSourceUrl', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByBookSourceUrl(List<BookSource> objects) {
    return putAllByIndex(r'bookSourceUrl', objects);
  }

  List<Id> putAllByBookSourceUrlSync(List<BookSource> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'bookSourceUrl', objects, saveLinks: saveLinks);
  }
}

extension BookSourceQueryWhereSort
    on QueryBuilder<BookSource, BookSource, QWhere> {
  QueryBuilder<BookSource, BookSource, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhere> anyBookSourceName() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'bookSourceName'),
      );
    });
  }
}

extension BookSourceQueryWhere
    on QueryBuilder<BookSource, BookSource, QWhereClause> {
  QueryBuilder<BookSource, BookSource, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<BookSource, BookSource, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause> idBetween(
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

  QueryBuilder<BookSource, BookSource, QAfterWhereClause> bookSourceNameEqualTo(
      String bookSourceName) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'bookSourceName',
        value: [bookSourceName],
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause>
      bookSourceNameNotEqualTo(String bookSourceName) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookSourceName',
              lower: [],
              upper: [bookSourceName],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookSourceName',
              lower: [bookSourceName],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookSourceName',
              lower: [bookSourceName],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookSourceName',
              lower: [],
              upper: [bookSourceName],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause>
      bookSourceNameGreaterThan(
    String bookSourceName, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'bookSourceName',
        lower: [bookSourceName],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause>
      bookSourceNameLessThan(
    String bookSourceName, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'bookSourceName',
        lower: [],
        upper: [bookSourceName],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause> bookSourceNameBetween(
    String lowerBookSourceName,
    String upperBookSourceName, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'bookSourceName',
        lower: [lowerBookSourceName],
        includeLower: includeLower,
        upper: [upperBookSourceName],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause>
      bookSourceNameStartsWith(String BookSourceNamePrefix) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'bookSourceName',
        lower: [BookSourceNamePrefix],
        upper: ['$BookSourceNamePrefix\u{FFFFF}'],
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause>
      bookSourceNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'bookSourceName',
        value: [''],
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause>
      bookSourceNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.lessThan(
              indexName: r'bookSourceName',
              upper: [''],
            ))
            .addWhereClause(IndexWhereClause.greaterThan(
              indexName: r'bookSourceName',
              lower: [''],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.greaterThan(
              indexName: r'bookSourceName',
              lower: [''],
            ))
            .addWhereClause(IndexWhereClause.lessThan(
              indexName: r'bookSourceName',
              upper: [''],
            ));
      }
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause> bookSourceUrlEqualTo(
      String bookSourceUrl) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'bookSourceUrl',
        value: [bookSourceUrl],
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterWhereClause>
      bookSourceUrlNotEqualTo(String bookSourceUrl) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookSourceUrl',
              lower: [],
              upper: [bookSourceUrl],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookSourceUrl',
              lower: [bookSourceUrl],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookSourceUrl',
              lower: [bookSourceUrl],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'bookSourceUrl',
              lower: [],
              upper: [bookSourceUrl],
              includeUpper: false,
            ));
      }
    });
  }
}

extension BookSourceQueryFilter
    on QueryBuilder<BookSource, BookSource, QFilterCondition> {
  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'bookSourceGroup',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'bookSourceGroup',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookSourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'bookSourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'bookSourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'bookSourceGroup',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'bookSourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'bookSourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'bookSourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'bookSourceGroup',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookSourceGroup',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceGroupIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'bookSourceGroup',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookSourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'bookSourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'bookSourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'bookSourceName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'bookSourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'bookSourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'bookSourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'bookSourceName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookSourceName',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'bookSourceName',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceTypeEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookSourceType',
        value: value,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceTypeGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'bookSourceType',
        value: value,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceTypeLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'bookSourceType',
        value: value,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceTypeBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'bookSourceType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookSourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'bookSourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'bookSourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'bookSourceUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'bookSourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'bookSourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'bookSourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'bookSourceUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bookSourceUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      bookSourceUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'bookSourceUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'customConfig',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'customConfig',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'customConfig',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'customConfig',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'customConfig',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'customConfig',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'customConfig',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'customConfig',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'customConfig',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'customConfig',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'customConfig',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      customConfigIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'customConfig',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> enabledEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'enabled',
        value: value,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'exploreUrl',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'exploreUrl',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> exploreUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'exploreUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'exploreUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'exploreUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> exploreUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'exploreUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'exploreUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'exploreUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'exploreUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> exploreUrlMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'exploreUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'exploreUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      exploreUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'exploreUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> idBetween(
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

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleBookInfo',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleBookInfo',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleBookInfo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleBookInfo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleBookInfo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleBookInfo',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleBookInfo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleBookInfo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleBookInfo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleBookInfo',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleBookInfo',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleBookInfoIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleBookInfo',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleContent',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleContent',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleContent',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleContent',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleContent',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleContentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleContent',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleExplore',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleExplore',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleExplore',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleExplore',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleExplore',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleExplore',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleExplore',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleExplore',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleExplore',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleExplore',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleExplore',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleExploreIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleExplore',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleSearch',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleSearch',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleSearchEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleSearch',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleSearch',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleSearch',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleSearchBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleSearch',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleSearch',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleSearch',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleSearch',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleSearchMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleSearch',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleSearch',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleSearchIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleSearch',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleToc',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleTocIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleToc',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleToc',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleTocGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleToc',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleToc',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleToc',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleToc',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleToc',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleToc',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleToc',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> ruleTocIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleToc',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      ruleTocIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleToc',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      searchUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'searchUrl',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      searchUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'searchUrl',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> searchUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'searchUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      searchUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'searchUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> searchUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'searchUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> searchUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'searchUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      searchUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'searchUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> searchUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'searchUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> searchUrlContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'searchUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> searchUrlMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'searchUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      searchUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'searchUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition>
      searchUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'searchUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> weightEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'weight',
        value: value,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> weightGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'weight',
        value: value,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> weightLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'weight',
        value: value,
      ));
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterFilterCondition> weightBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'weight',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension BookSourceQueryObject
    on QueryBuilder<BookSource, BookSource, QFilterCondition> {}

extension BookSourceQueryLinks
    on QueryBuilder<BookSource, BookSource, QFilterCondition> {}

extension BookSourceQuerySortBy
    on QueryBuilder<BookSource, BookSource, QSortBy> {
  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByBookSourceGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceGroup', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy>
      sortByBookSourceGroupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceGroup', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByBookSourceName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceName', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy>
      sortByBookSourceNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceName', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByBookSourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceType', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy>
      sortByBookSourceTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceType', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByBookSourceUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceUrl', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByBookSourceUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceUrl', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByCustomConfig() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customConfig', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByCustomConfigDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customConfig', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByExploreUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exploreUrl', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByExploreUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exploreUrl', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleBookInfo() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleBookInfo', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleBookInfoDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleBookInfo', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleContent', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleContent', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleExplore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleExplore', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleExploreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleExplore', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleSearch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleSearch', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleSearchDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleSearch', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleToc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleToc', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByRuleTocDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleToc', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortBySearchUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'searchUrl', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortBySearchUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'searchUrl', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByWeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weight', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> sortByWeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weight', Sort.desc);
    });
  }
}

extension BookSourceQuerySortThenBy
    on QueryBuilder<BookSource, BookSource, QSortThenBy> {
  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByBookSourceGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceGroup', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy>
      thenByBookSourceGroupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceGroup', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByBookSourceName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceName', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy>
      thenByBookSourceNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceName', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByBookSourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceType', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy>
      thenByBookSourceTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceType', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByBookSourceUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceUrl', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByBookSourceUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookSourceUrl', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByCustomConfig() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customConfig', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByCustomConfigDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customConfig', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByExploreUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exploreUrl', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByExploreUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exploreUrl', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleBookInfo() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleBookInfo', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleBookInfoDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleBookInfo', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleContent', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleContent', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleExplore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleExplore', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleExploreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleExplore', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleSearch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleSearch', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleSearchDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleSearch', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleToc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleToc', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByRuleTocDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleToc', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenBySearchUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'searchUrl', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenBySearchUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'searchUrl', Sort.desc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByWeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weight', Sort.asc);
    });
  }

  QueryBuilder<BookSource, BookSource, QAfterSortBy> thenByWeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weight', Sort.desc);
    });
  }
}

extension BookSourceQueryWhereDistinct
    on QueryBuilder<BookSource, BookSource, QDistinct> {
  QueryBuilder<BookSource, BookSource, QDistinct> distinctByBookSourceGroup(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bookSourceGroup',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByBookSourceName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bookSourceName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByBookSourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bookSourceType');
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByBookSourceUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bookSourceUrl',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByCustomConfig(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'customConfig', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'enabled');
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByExploreUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'exploreUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByRuleBookInfo(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleBookInfo', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByRuleContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleContent', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByRuleExplore(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleExplore', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByRuleSearch(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleSearch', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByRuleToc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleToc', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctBySearchUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'searchUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookSource, BookSource, QDistinct> distinctByWeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'weight');
    });
  }
}

extension BookSourceQueryProperty
    on QueryBuilder<BookSource, BookSource, QQueryProperty> {
  QueryBuilder<BookSource, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations>
      bookSourceGroupProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bookSourceGroup');
    });
  }

  QueryBuilder<BookSource, String, QQueryOperations> bookSourceNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bookSourceName');
    });
  }

  QueryBuilder<BookSource, int, QQueryOperations> bookSourceTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bookSourceType');
    });
  }

  QueryBuilder<BookSource, String, QQueryOperations> bookSourceUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bookSourceUrl');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations> customConfigProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'customConfig');
    });
  }

  QueryBuilder<BookSource, bool, QQueryOperations> enabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'enabled');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations> exploreUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'exploreUrl');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations> ruleBookInfoProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleBookInfo');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations> ruleContentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleContent');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations> ruleExploreProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleExplore');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations> ruleSearchProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleSearch');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations> ruleTocProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleToc');
    });
  }

  QueryBuilder<BookSource, String?, QQueryOperations> searchUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'searchUrl');
    });
  }

  QueryBuilder<BookSource, int, QQueryOperations> weightProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'weight');
    });
  }
}
