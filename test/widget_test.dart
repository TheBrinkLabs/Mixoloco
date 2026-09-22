import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mixoloco/core/widgets/game_logo.dart';
import 'package:mixoloco/main.dart';

void main() {
  testWidgets('App boots to the menu screen with helpful instructions', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MixolocoApp()));

    expect(find.byType(GameLogo), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });
}
