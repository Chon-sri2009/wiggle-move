import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/shared/widgets/app_card.dart';
import 'package:wiggle_move/shared/widgets/app_snackbar.dart';
import 'package:wiggle_move/shared/widgets/app_text_field.dart';
import 'package:wiggle_move/shared/widgets/async_states.dart';
import 'package:wiggle_move/shared/widgets/primary_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('PrimaryButton fires onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: 'Go', onPressed: () => taps++)),
    );
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('PrimaryButton loading disables and shows spinner', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: 'Go', loading: true, onPressed: () => taps++)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Go'), findsNothing);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);
  });

  testWidgets('AppTextField renders hint and accepts input', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(_wrap(AppTextField(controller: c, hint: 'Email')));
    expect(find.text('Email'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'a@b.c');
    expect(c.text, 'a@b.c');
  });

  testWidgets('AppCard renders child', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppCard(padding: EdgeInsets.all(8), child: Text('hi'))),
    );
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('async state views render', (tester) async {
    await tester.pumpWidget(_wrap(const LoadingView()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      _wrap(const EmptyView(message: 'Nothing', icon: Icons.inbox)),
    );
    expect(find.text('Nothing'), findsOneWidget);
    expect(find.byIcon(Icons.inbox), findsOneWidget);
  });

  testWidgets('ErrorView retry callback fires', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(ErrorView(message: 'Boom', onRetry: () => retries++)),
    );
    expect(find.text('Boom'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('showAppSnackBar shows message', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSnackBar(context, 'Oops', isError: true),
            child: const Text('show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pump();
    expect(find.text('Oops'), findsOneWidget);
  });
}
