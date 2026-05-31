import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';
import 'routes.dart';

class ReadApp extends ConsumerStatefulWidget {
  const ReadApp({super.key});

  @override
  ConsumerState<ReadApp> createState() => _ReadAppState();
}

class _ReadAppState extends ConsumerState<ReadApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final themeType = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);
    final platformBrightness =
        View.maybeOf(context)?.platformDispatcher.platformBrightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    return CupertinoApp.router(
      title: '阅读',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(
        themeType,
        platformBrightness: platformBrightness,
      ),
      routerConfig: router,
      localizationsDelegates: const [
        DefaultCupertinoLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
      ],
    );
  }
}
