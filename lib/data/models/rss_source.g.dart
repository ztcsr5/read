// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rss_source.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters

extension GetRssSourceCollection on Isar {
  IsarCollection<RssSource> get rssSources => this.collection();
}

const RssSourceSchema = CollectionSchema(
  name: r'RssSource',
  id: 1202442659025810076,
  properties: {
    r'customConfig': PropertySchema(
      id: 0,
      name: r'customConfig',
      type: IsarType.string,
    ),
    r'enabled': PropertySchema(
      id: 1,
      name: r'enabled',
      type: IsarType.bool,
    ),
    r'enabledCookieJar': PropertySchema(
      id: 2,
      name: r'enabledCookieJar',
      type: IsarType.bool,
    ),
    r'ruleArticles': PropertySchema(
      id: 3,
      name: r'ruleArticles',
      type: IsarType.string,
    ),
    r'ruleContent': PropertySchema(
      id: 4,
      name: r'ruleContent',
      type: IsarType.string,
    ),
    r'ruleDescription': PropertySchema(
      id: 5,
      name: r'ruleDescription',
      type: IsarType.string,
    ),
    r'ruleImage': PropertySchema(
      id: 6,
      name: r'ruleImage',
      type: IsarType.string,
    ),
    r'ruleLink': PropertySchema(
      id: 7,
      name: r'ruleLink',
      type: IsarType.string,
    ),
    r'ruleNextPage': PropertySchema(
      id: 8,
      name: r'ruleNextPage',
      type: IsarType.string,
    ),
    r'rulePubDate': PropertySchema(
      id: 9,
      name: r'rulePubDate',
      type: IsarType.string,
    ),
    r'ruleTitle': PropertySchema(
      id: 10,
      name: r'ruleTitle',
      type: IsarType.string,
    ),
    r'sortUrl': PropertySchema(
      id: 11,
      name: r'sortUrl',
      type: IsarType.string,
    ),
    r'sourceComment': PropertySchema(
      id: 12,
      name: r'sourceComment',
      type: IsarType.string,
    ),
    r'sourceGroup': PropertySchema(
      id: 13,
      name: r'sourceGroup',
      type: IsarType.string,
    ),
    r'sourceIcon': PropertySchema(
      id: 14,
      name: r'sourceIcon',
      type: IsarType.string,
    ),
    r'sourceName': PropertySchema(
      id: 15,
      name: r'sourceName',
      type: IsarType.string,
    ),
    r'sourceUrl': PropertySchema(
      id: 16,
      name: r'sourceUrl',
      type: IsarType.string,
    ),
    r'style': PropertySchema(
      id: 17,
      name: r'style',
      type: IsarType.string,
    )
  },
  estimateSize: _rssSourceEstimateSize,
  serialize: _rssSourceSerialize,
  deserialize: _rssSourceDeserialize,
  deserializeProp: _rssSourceDeserializeProp,
  idName: r'id',
  indexes: {
    r'sourceName': IndexSchema(
      id: -2945396089433473114,
      name: r'sourceName',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sourceName',
          type: IndexType.value,
          caseSensitive: true,
        )
      ],
    ),
    r'sourceUrl': IndexSchema(
      id: -4622358680545194972,
      name: r'sourceUrl',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'sourceUrl',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _rssSourceGetId,
  getLinks: _rssSourceGetLinks,
  attach: _rssSourceAttach,
  version: '3.0.5',
);

int _rssSourceEstimateSize(
  RssSource object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.customConfig;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleArticles;
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
    final value = object.ruleDescription;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleImage;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleLink;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleNextPage;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.rulePubDate;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ruleTitle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.sortUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.sourceComment;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.sourceGroup;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.sourceIcon;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.sourceName.length * 3;
  bytesCount += 3 + object.sourceUrl.length * 3;
  {
    final value = object.style;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _rssSourceSerialize(
  RssSource object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.customConfig);
  writer.writeBool(offsets[1], object.enabled);
  writer.writeBool(offsets[2], object.enabledCookieJar);
  writer.writeString(offsets[3], object.ruleArticles);
  writer.writeString(offsets[4], object.ruleContent);
  writer.writeString(offsets[5], object.ruleDescription);
  writer.writeString(offsets[6], object.ruleImage);
  writer.writeString(offsets[7], object.ruleLink);
  writer.writeString(offsets[8], object.ruleNextPage);
  writer.writeString(offsets[9], object.rulePubDate);
  writer.writeString(offsets[10], object.ruleTitle);
  writer.writeString(offsets[11], object.sortUrl);
  writer.writeString(offsets[12], object.sourceComment);
  writer.writeString(offsets[13], object.sourceGroup);
  writer.writeString(offsets[14], object.sourceIcon);
  writer.writeString(offsets[15], object.sourceName);
  writer.writeString(offsets[16], object.sourceUrl);
  writer.writeString(offsets[17], object.style);
}

RssSource _rssSourceDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = RssSource();
  object.customConfig = reader.readStringOrNull(offsets[0]);
  object.enabled = reader.readBool(offsets[1]);
  object.enabledCookieJar = reader.readBool(offsets[2]);
  object.id = id;
  object.ruleArticles = reader.readStringOrNull(offsets[3]);
  object.ruleContent = reader.readStringOrNull(offsets[4]);
  object.ruleDescription = reader.readStringOrNull(offsets[5]);
  object.ruleImage = reader.readStringOrNull(offsets[6]);
  object.ruleLink = reader.readStringOrNull(offsets[7]);
  object.ruleNextPage = reader.readStringOrNull(offsets[8]);
  object.rulePubDate = reader.readStringOrNull(offsets[9]);
  object.ruleTitle = reader.readStringOrNull(offsets[10]);
  object.sortUrl = reader.readStringOrNull(offsets[11]);
  object.sourceComment = reader.readStringOrNull(offsets[12]);
  object.sourceGroup = reader.readStringOrNull(offsets[13]);
  object.sourceIcon = reader.readStringOrNull(offsets[14]);
  object.sourceName = reader.readString(offsets[15]);
  object.sourceUrl = reader.readString(offsets[16]);
  object.style = reader.readStringOrNull(offsets[17]);
  return object;
}

P _rssSourceDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readBool(offset)) as P;
    case 2:
      return (reader.readBool(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
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
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readString(offset)) as P;
    case 16:
      return (reader.readString(offset)) as P;
    case 17:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _rssSourceGetId(RssSource object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _rssSourceGetLinks(RssSource object) {
  return [];
}

void _rssSourceAttach(IsarCollection<dynamic> col, Id id, RssSource object) {
  object.id = id;
}

extension RssSourceByIndex on IsarCollection<RssSource> {
  Future<RssSource?> getBySourceUrl(String sourceUrl) {
    return getByIndex(r'sourceUrl', [sourceUrl]);
  }

  RssSource? getBySourceUrlSync(String sourceUrl) {
    return getByIndexSync(r'sourceUrl', [sourceUrl]);
  }

  Future<bool> deleteBySourceUrl(String sourceUrl) {
    return deleteByIndex(r'sourceUrl', [sourceUrl]);
  }

  bool deleteBySourceUrlSync(String sourceUrl) {
    return deleteByIndexSync(r'sourceUrl', [sourceUrl]);
  }

  Future<List<RssSource?>> getAllBySourceUrl(List<String> sourceUrlValues) {
    final values = sourceUrlValues.map((e) => [e]).toList();
    return getAllByIndex(r'sourceUrl', values);
  }

  List<RssSource?> getAllBySourceUrlSync(List<String> sourceUrlValues) {
    final values = sourceUrlValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'sourceUrl', values);
  }

  Future<int> deleteAllBySourceUrl(List<String> sourceUrlValues) {
    final values = sourceUrlValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'sourceUrl', values);
  }

  int deleteAllBySourceUrlSync(List<String> sourceUrlValues) {
    final values = sourceUrlValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'sourceUrl', values);
  }

  Future<Id> putBySourceUrl(RssSource object) {
    return putByIndex(r'sourceUrl', object);
  }

  Id putBySourceUrlSync(RssSource object, {bool saveLinks = true}) {
    return putByIndexSync(r'sourceUrl', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllBySourceUrl(List<RssSource> objects) {
    return putAllByIndex(r'sourceUrl', objects);
  }

  List<Id> putAllBySourceUrlSync(List<RssSource> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'sourceUrl', objects, saveLinks: saveLinks);
  }
}

extension RssSourceQueryWhereSort
    on QueryBuilder<RssSource, RssSource, QWhere> {
  QueryBuilder<RssSource, RssSource, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhere> anySourceName() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'sourceName'),
      );
    });
  }
}

extension RssSourceQueryWhere
    on QueryBuilder<RssSource, RssSource, QWhereClause> {
  QueryBuilder<RssSource, RssSource, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> idBetween(
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

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceNameEqualTo(
      String sourceName) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'sourceName',
        value: [sourceName],
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceNameNotEqualTo(
      String sourceName) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sourceName',
              lower: [],
              upper: [sourceName],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sourceName',
              lower: [sourceName],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sourceName',
              lower: [sourceName],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sourceName',
              lower: [],
              upper: [sourceName],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceNameGreaterThan(
    String sourceName, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'sourceName',
        lower: [sourceName],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceNameLessThan(
    String sourceName, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'sourceName',
        lower: [],
        upper: [sourceName],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceNameBetween(
    String lowerSourceName,
    String upperSourceName, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'sourceName',
        lower: [lowerSourceName],
        includeLower: includeLower,
        upper: [upperSourceName],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceNameStartsWith(
      String SourceNamePrefix) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'sourceName',
        lower: [SourceNamePrefix],
        upper: ['$SourceNamePrefix\u{FFFFF}'],
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'sourceName',
        value: [''],
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.lessThan(
              indexName: r'sourceName',
              upper: [''],
            ))
            .addWhereClause(IndexWhereClause.greaterThan(
              indexName: r'sourceName',
              lower: [''],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.greaterThan(
              indexName: r'sourceName',
              lower: [''],
            ))
            .addWhereClause(IndexWhereClause.lessThan(
              indexName: r'sourceName',
              upper: [''],
            ));
      }
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceUrlEqualTo(
      String sourceUrl) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'sourceUrl',
        value: [sourceUrl],
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterWhereClause> sourceUrlNotEqualTo(
      String sourceUrl) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sourceUrl',
              lower: [],
              upper: [sourceUrl],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sourceUrl',
              lower: [sourceUrl],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sourceUrl',
              lower: [sourceUrl],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sourceUrl',
              lower: [],
              upper: [sourceUrl],
              includeUpper: false,
            ));
      }
    });
  }
}

extension RssSourceQueryFilter
    on QueryBuilder<RssSource, RssSource, QFilterCondition> {
  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      customConfigIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'customConfig',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      customConfigIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'customConfig',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> customConfigEqualTo(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> customConfigBetween(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      customConfigContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'customConfig',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> customConfigMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'customConfig',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      customConfigIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'customConfig',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      customConfigIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'customConfig',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> enabledEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'enabled',
        value: value,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      enabledCookieJarEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'enabledCookieJar',
        value: value,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> idBetween(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleArticles',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleArticles',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleArticlesEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleArticles',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleArticles',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleArticles',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleArticlesBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleArticles',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleArticles',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleArticles',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleArticles',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleArticlesMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleArticles',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleArticles',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleArticlesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleArticles',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleContentIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleContent',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleContentIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleContent',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleContentEqualTo(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleContentLessThan(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleContentBetween(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleContentEndsWith(
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

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleContentContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleContentMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleContent',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleContentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleContent',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleContentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleContent',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleDescription',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleDescription',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleDescription',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleDescription',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleDescription',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleDescription',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleDescription',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleDescription',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleDescription',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleDescription',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleDescription',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleDescriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleDescription',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleImage',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleImageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleImage',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleImageGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleImage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleImage',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleImageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleImage',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleImageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleImage',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleLink',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleLinkIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleLink',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleLink',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleLink',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleLink',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleLink',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleLink',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleLink',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleLink',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleLink',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleLinkIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleLink',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleLinkIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleLink',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleNextPage',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleNextPage',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleNextPageEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleNextPage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleNextPage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleNextPage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleNextPageBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleNextPage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleNextPage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleNextPage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleNextPage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleNextPageMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleNextPage',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleNextPage',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleNextPageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleNextPage',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      rulePubDateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'rulePubDate',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      rulePubDateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'rulePubDate',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> rulePubDateEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rulePubDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      rulePubDateGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'rulePubDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> rulePubDateLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'rulePubDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> rulePubDateBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'rulePubDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      rulePubDateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'rulePubDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> rulePubDateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'rulePubDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> rulePubDateContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'rulePubDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> rulePubDateMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'rulePubDate',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      rulePubDateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rulePubDate',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      rulePubDateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'rulePubDate',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ruleTitle',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleTitleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ruleTitle',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleTitleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ruleTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ruleTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ruleTitle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ruleTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ruleTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ruleTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ruleTitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> ruleTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ruleTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      ruleTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ruleTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sortUrl',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sortUrl',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sortUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sortUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sortUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sortUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sortUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sortUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sortUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sortUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sortUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sortUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sourceComment',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sourceComment',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceComment',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sourceComment',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sourceComment',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sourceComment',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sourceComment',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sourceComment',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sourceComment',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sourceComment',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceComment',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceCommentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sourceComment',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceGroupIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sourceGroup',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceGroupIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sourceGroup',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceGroupEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceGroupGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceGroupLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceGroupBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sourceGroup',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceGroupStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceGroupEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceGroupContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sourceGroup',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceGroupMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sourceGroup',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceGroupIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceGroup',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceGroupIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sourceGroup',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceIconIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sourceIcon',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceIconIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sourceIcon',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceIconEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceIcon',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceIconGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sourceIcon',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceIconLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sourceIcon',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceIconBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sourceIcon',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceIconStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sourceIcon',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceIconEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sourceIcon',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceIconContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sourceIcon',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceIconMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sourceIcon',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceIconIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceIcon',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceIconIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sourceIcon',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sourceName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceNameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sourceName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceNameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sourceName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceName',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sourceName',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceUrlEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceUrlGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceUrlLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceUrlBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sourceUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceUrlContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sourceUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceUrlMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sourceUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> sourceUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition>
      sourceUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sourceUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'style',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'style',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'style',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'style',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'style',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'style',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'style',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'style',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'style',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'style',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'style',
        value: '',
      ));
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterFilterCondition> styleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'style',
        value: '',
      ));
    });
  }
}

extension RssSourceQueryObject
    on QueryBuilder<RssSource, RssSource, QFilterCondition> {}

extension RssSourceQueryLinks
    on QueryBuilder<RssSource, RssSource, QFilterCondition> {}

extension RssSourceQuerySortBy on QueryBuilder<RssSource, RssSource, QSortBy> {
  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByCustomConfig() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customConfig', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByCustomConfigDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customConfig', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByEnabledCookieJar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabledCookieJar', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy>
      sortByEnabledCookieJarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabledCookieJar', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleArticles() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleArticles', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleArticlesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleArticles', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleContent', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleContent', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleDescription', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleDescription', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleImage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleImage', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleImageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleImage', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleLink() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleLink', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleLinkDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleLink', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleNextPage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleNextPage', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleNextPageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleNextPage', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRulePubDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rulePubDate', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRulePubDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rulePubDate', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleTitle', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByRuleTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleTitle', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySortUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortUrl', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySortUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortUrl', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceComment() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceComment', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceCommentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceComment', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceGroup', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceGroupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceGroup', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceIcon() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceIcon', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceIconDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceIcon', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceName', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceName', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceUrl', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortBySourceUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceUrl', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByStyle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'style', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> sortByStyleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'style', Sort.desc);
    });
  }
}

extension RssSourceQuerySortThenBy
    on QueryBuilder<RssSource, RssSource, QSortThenBy> {
  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByCustomConfig() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customConfig', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByCustomConfigDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customConfig', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByEnabledCookieJar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabledCookieJar', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy>
      thenByEnabledCookieJarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabledCookieJar', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleArticles() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleArticles', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleArticlesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleArticles', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleContent', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleContent', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleDescription', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleDescription', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleImage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleImage', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleImageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleImage', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleLink() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleLink', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleLinkDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleLink', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleNextPage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleNextPage', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleNextPageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleNextPage', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRulePubDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rulePubDate', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRulePubDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rulePubDate', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleTitle', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByRuleTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ruleTitle', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySortUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortUrl', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySortUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortUrl', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceComment() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceComment', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceCommentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceComment', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceGroup', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceGroupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceGroup', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceIcon() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceIcon', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceIconDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceIcon', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceName', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceName', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceUrl', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenBySourceUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceUrl', Sort.desc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByStyle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'style', Sort.asc);
    });
  }

  QueryBuilder<RssSource, RssSource, QAfterSortBy> thenByStyleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'style', Sort.desc);
    });
  }
}

extension RssSourceQueryWhereDistinct
    on QueryBuilder<RssSource, RssSource, QDistinct> {
  QueryBuilder<RssSource, RssSource, QDistinct> distinctByCustomConfig(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'customConfig', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'enabled');
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByEnabledCookieJar() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'enabledCookieJar');
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByRuleArticles(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleArticles', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByRuleContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleContent', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByRuleDescription(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleDescription',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByRuleImage(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleImage', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByRuleLink(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleLink', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByRuleNextPage(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleNextPage', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByRulePubDate(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rulePubDate', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByRuleTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ruleTitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctBySortUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sortUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctBySourceComment(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceComment',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctBySourceGroup(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceGroup', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctBySourceIcon(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceIcon', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctBySourceName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctBySourceUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<RssSource, RssSource, QDistinct> distinctByStyle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'style', caseSensitive: caseSensitive);
    });
  }
}

extension RssSourceQueryProperty
    on QueryBuilder<RssSource, RssSource, QQueryProperty> {
  QueryBuilder<RssSource, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> customConfigProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'customConfig');
    });
  }

  QueryBuilder<RssSource, bool, QQueryOperations> enabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'enabled');
    });
  }

  QueryBuilder<RssSource, bool, QQueryOperations> enabledCookieJarProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'enabledCookieJar');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> ruleArticlesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleArticles');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> ruleContentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleContent');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> ruleDescriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleDescription');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> ruleImageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleImage');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> ruleLinkProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleLink');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> ruleNextPageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleNextPage');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> rulePubDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rulePubDate');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> ruleTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ruleTitle');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> sortUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sortUrl');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> sourceCommentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceComment');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> sourceGroupProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceGroup');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> sourceIconProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceIcon');
    });
  }

  QueryBuilder<RssSource, String, QQueryOperations> sourceNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceName');
    });
  }

  QueryBuilder<RssSource, String, QQueryOperations> sourceUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceUrl');
    });
  }

  QueryBuilder<RssSource, String?, QQueryOperations> styleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'style');
    });
  }
}
