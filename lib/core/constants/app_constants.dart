/// 阅读App - 全局常量定义
///
/// 包含应用名称、版本号、默认阅读设置、章节正则匹配模式、
/// 支持的文件扩展名以及缓存大小等常量配置。
library;

/// 应用基本信息常量
class AppInfo {
  AppInfo._();

  /// 应用名称
  static const String appName = '阅读';

  /// 应用版本号
  static const String version = '1.0.0';

  /// 应用构建号
  static const int buildNumber = 1;

  /// 应用包名
  static const String packageName = 'com.read.app';
}

/// 默认阅读设置常量
class ReadingDefaults {
  ReadingDefaults._();

  /// 默认字体大小（单位：逻辑像素）
  static const double fontSize = 18.0;

  /// 最小字体大小
  static const double minFontSize = 12.0;

  /// 最大字体大小
  static const double maxFontSize = 36.0;

  /// 默认行间距倍数
  static const double lineHeight = 1.6;

  /// 最小行间距
  static const double minLineHeight = 1.0;

  /// 最大行间距
  static const double maxLineHeight = 3.0;

  /// 默认段间距（单位：逻辑像素）
  static const double paragraphSpacing = 12.0;

  /// 默认页面内边距（单位：逻辑像素）
  static const double pagePadding = 20.0;

  /// 默认字体族
  static const String fontFamily = 'System';

  /// 默认文字颜色（十六进制）
  static const int textColor = 0xFF333333;

  /// 默认背景颜色（十六进制）
  static const int backgroundColor = 0xFFF5F0E8;

  /// 默认TTS朗读语速
  static const double ttsSpeed = 1.0;

  /// TTS最低语速
  static const double ttsMinSpeed = 0.5;

  /// TTS最高语速
  static const double ttsMaxSpeed = 3.0;

  /// 默认TTS音量
  static const double ttsVolume = 1.0;

  /// 默认TTS音调
  static const double ttsPitch = 1.0;

  /// 自动翻页间隔（秒）
  static const int autoPageInterval = 5;

  /// 翻页动画时长（毫秒）
  static const int pageAnimationDuration = 300;

  /// 默认亮度
  static const double brightness = 0.5;

  /// 是否跟随系统亮度
  static const bool followSystemBrightness = true;

  /// 是否显示状态栏
  static const bool showStatusBar = false;

  /// 是否保持屏幕常亮
  static const bool keepScreenOn = true;
}

/// 章节识别正则表达式模式
///
/// 用于TXT文件的智能章节分割，支持多种中英文格式。
class ChapterPatterns {
  ChapterPatterns._();

  /// 所有章节匹配正则模式列表（按优先级排列）
  static const List<String> allPatterns = [
    // 中文数字章节：第一章、第二章、第三章 等
    r'^\s*第[零一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+[章节回集卷部篇].*$',
    // 阿拉伯数字章节：第1章、第2章、第100章 等
    r'^\s*第\s*\d+\s*[章节回集卷部篇].*$',
    // 英文章节：Chapter 1, Chapter 2 等
    r'^\s*[Cc]hapter\s+\d+.*$',
    // 纯数字章节标题：1. 标题、2. 标题 等
    r'^\s*\d+[\.\、]\s+\S+.*$',
    // 卷/册标题：卷一、上册 等
    r'^\s*[卷册]\s*[零一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]+.*$',
    // 序章/尾声等特殊标记
    r'^\s*(序[章言]?|前言|引子|楔子|尾声|后记|番外|附录|结语|终章)\s*.*$',
    // 带括号数字的章节：【1】、（一）、[第一章] 等
    r'^\s*[【\[（(]\s*(第\s*)?[零一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]+\s*[章节回集卷部篇]?\s*[】\]）)].*$',
    // PART/SECTION 格式
    r'^\s*(PART|Part|SECTION|Section)\s+\d+.*$',
  ];

  /// 用于合并的正则 —— 将所有模式用 | 连接
  static String get combinedPattern => allPatterns.join('|');

  /// 默认章节字数上限（超过此字数可能需要再次分割）
  static const int maxChapterWordCount = 50000;

  /// 默认章节字数下限（低于此字数可能需要与相邻章节合并）
  static const int minChapterWordCount = 100;

  /// TXT 文件默认分块大小（当未识别到章节时）
  static const int defaultChunkSize = 5000;
}

/// 支持的文件格式配置
class FileTypes {
  FileTypes._();

  /// 支持的电子书文件扩展名
  static const List<String> supportedExtensions = [
    'epub',
    'txt',
    'pdf',
  ];

  /// 文件选择器允许的扩展名（含点号前缀）
  static const List<String> pickerExtensions = [
    '.epub',
    '.txt',
    '.pdf',
  ];

  /// MIME 类型映射
  static const Map<String, String> mimeTypes = {
    'epub': 'application/epub+zip',
    'txt': 'text/plain',
    'pdf': 'application/pdf',
  };

  /// 文件类型显示名称
  static const Map<String, String> displayNames = {
    'epub': 'ePub 电子书',
    'txt': 'TXT 文本',
    'pdf': 'PDF 文档',
  };
}

/// 缓存配置常量
class CacheConfig {
  CacheConfig._();

  /// 封面图片缓存最大数量
  static const int maxCoverCacheCount = 200;

  /// 封面图片缓存目录名
  static const String coverCacheDirName = 'covers';

  /// 章节内容缓存目录名
  static const String chapterCacheDirName = 'chapters';

  /// 书源网络请求缓存时长（秒）
  static const int networkCacheDuration = 3600;

  /// 书源搜索结果缓存时长（秒）
  static const int searchCacheDuration = 600;

  /// 最大并发下载数
  static const int maxConcurrentDownloads = 3;

  /// HTTP 请求超时时间（毫秒）
  static const int httpConnectTimeout = 15000;

  /// HTTP 读取超时时间（毫秒）
  static const int httpReceiveTimeout = 30000;

  /// 用户代理字符串
  static const String defaultUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';
}

/// 数据库相关常量
class DatabaseConfig {
  DatabaseConfig._();

  /// Isar 数据库文件名
  static const String dbName = 'read_app';

  /// 数据库版本（用于迁移）
  static const int dbVersion = 1;

  /// 数据库目录名
  static const String dbDirName = 'database';
}

/// 阅读统计相关常量
class StatsConfig {
  StatsConfig._();

  /// 自动保存阅读时间的间隔（秒）
  static const int autoSaveInterval = 30;

  /// 最小有效阅读时长（秒），低于此值不计入统计
  static const int minValidDuration = 10;

  /// 判定为"连续阅读"的最大间隔（分钟）
  static const int maxGapMinutes = 30;

  /// 每分钟默认阅读字数（用于估算）
  static const int wordsPerMinute = 500;
}
