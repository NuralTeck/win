import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opscore_pro/main.dart';

void main() {
  testWidgets('OpsCore Pro App initial render test', (WidgetTester tester) async {
    // Set desktop test surface dimensions
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: OpsCoreProApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OpsCoreProApp), findsOneWidget);
  });
}
