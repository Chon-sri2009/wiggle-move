import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move_app1/app/app.dart';

void main() {
  testWidgets('app boots to the home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WiggleMoveApp()));
    await tester.pumpAndSettle();
    expect(find.text('Wiggle Move'), findsOneWidget);
  });
}
