import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/database/database_provider.dart';
import 'data/parsers/legado/legado_session_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 设置状态栏样式
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // 强制竖屏
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // 初始化数据库
    final isar = await DatabaseHelper.init();
    await LegadoSessionStore.restorePersistedSessions();

    runApp(
      ProviderScope(
        overrides: [isarProvider.overrideWithValue(isar)],
        child: const ReadApp(),
      ),
    );
  } catch (e, stack) {
    runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: const Color(0xFFFFFFFF),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Text(
              'App Initialization Error:\n\n$e\n\n$stack',
              style: const TextStyle(color: Color(0xFFFF0000), fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
