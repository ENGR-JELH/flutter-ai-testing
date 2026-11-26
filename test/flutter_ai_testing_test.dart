import 'package:flutter/material.dart';
import 'package:flutter_ai_testing/flutter_ai_testing.dart';
import 'package:flutter_test/flutter_test.dart';

AiTestingConfig config({List<String> stack = const ['home'], bool? signedIn, Map<String, Object?>? state}) =>
    AiTestingConfig(
      namespace: 'sample',
      routeStack: () => stack,
      location: () => '/home',
      isSignedIn: signedIn == null ? null : () => signedIn,
      appState: state == null ? null : () => state,
      loadingWidgetTypes: const {'CircularProgressIndicator', 'SampleLoader'},
    );

class SampleLoader extends StatelessWidget {
  const SampleLoader({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class SampleDialog extends StatelessWidget {
  const SampleDialog({super.key});
  @override
  Widget build(BuildContext context) => const AlertDialog(content: Text('Sample'));
}

void main() {
  testWidgets('lists the *_screen keys on screen, bottom first', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          key: ValueKey('home_screen'),
          body: KeyedSubtree(key: ValueKey('home_list_screen'), child: Text('list')),
        ),
      ),
    );

    final scan = scanScreen(config());
    expect(scan.screens, ['home_screen', 'home_list_screen']);
    expect(scan.dialogs, isEmpty);
    expect(scan.loading, isFalse);
  });

  testWidgets('skips subtrees hidden by Offstage or TickerMode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            SizedBox(key: ValueKey('shown_screen')),
            Offstage(child: SizedBox(key: ValueKey('offstage_screen'))),
            TickerMode(enabled: false, child: SizedBox(key: ValueKey('paused_screen'))),
          ],
        ),
      ),
    );

    expect(scanScreen(config()).screens, ['shown_screen']);
  });

  testWidgets('reports open dialogs by type and loading indicators', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const SampleLoader(),
                TextButton(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => const SampleDialog()),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final scan = scanScreen(config());
    expect(scan.dialogs, containsAll(['SampleDialog', 'AlertDialog']));
    expect(scan.loading, isTrue);
  });

  testWidgets('whereAmI combines the stack, the scan and app facts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox(key: ValueKey('home_screen'))));

    final answer = whereAmI(config(stack: ['home', 'details'], signedIn: true, state: {'tab': 'a'}));
    expect(answer, {
      'location': '/home',
      'stack': ['home', 'details'],
      'visibleScreens': ['home_screen'],
      'dialogs': <String>[],
      'loading': false,
      'signedIn': true,
      'tab': 'a',
    });
  });

  testWidgets('whereAmI leaves out signedIn for apps without sign-in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(whereAmI(config()).containsKey('signedIn'), isFalse);
  });
}
