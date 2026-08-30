import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mixoloco/main.dart';

void main() {
  testWidgets('App boots to the menu screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MixolocoApp()));
    expect(find.text('Mixoloco'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });
}
