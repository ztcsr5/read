import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:read/widgets/shimmer_loading.dart';

void main() {
  testWidgets('renders book card loading placeholder', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(child: ShimmerBookCard()),
        ),
      ),
    );

    expect(find.byType(ShimmerBookCard), findsOneWidget);
  });
}
