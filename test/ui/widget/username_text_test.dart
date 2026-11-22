import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/ui/widget/username_text.dart';

void main() {
  testWidgets('renders the full username as plain text without a color badge', (
    tester,
  ) async {
    const username = '👩‍💻Alice';
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(),
        child: const MaterialApp(
          home: Scaffold(body: UsernameText(username: username, uid: 1)),
        ),
      ),
    );

    // 首字彩色块已取消：用户名整体平铺，不再单独上色第一个字
    expect(_badgeContainers(tester), findsNothing);
    expect(find.bySemanticsLabel(username), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('highlights the last four nickname graphemes after UID:', (
    tester,
  ) async {
    const username = 'UID:甲乙👩‍💻丁戊';
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(),
        child: const MaterialApp(
          home: Scaffold(body: UsernameText(username: username, uid: 1)),
        ),
      ),
    );

    expect(_badgeText(tester, 0).data, '乙👩‍💻丁戊');
    expect(find.bySemanticsLabel(username), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('navigates by uid when it is available', (tester) async {
    final navigation = await _tapUsername(
      tester,
      const UsernameText(username: 'Alice', uid: 42),
    );

    expect(navigation.queryParameters, {'uid': '42'});
  });

  testWidgets('falls back to username navigation when uid is absent', (
    tester,
  ) async {
    final navigation = await _tapUsername(
      tester,
      const UsernameText(username: 'Alice Smith'),
    );

    expect(navigation.queryParameters, {'name': 'Alice Smith'});
  });

  testWidgets('does not navigate anonymous or empty usernames', (tester) async {
    var userRouteVisits = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: UsernameText(username: '#anony_0123456789abcdef'),
          ),
        ),
        GoRoute(
          path: '/user',
          builder: (context, state) {
            userRouteVisits++;
            return const SizedBox.shrink();
          },
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.byType(UsernameText));
    await tester.pumpAndSettle();

    expect(userRouteVisits, 0);
    expect(find.byType(InkWell), findsNothing);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(),
        child: const MaterialApp(
          home: Scaffold(body: UsernameText(username: '', uid: 1)),
        ),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
  });
}

Future<Uri> _tapUsername(WidgetTester tester, UsernameText username) async {
  late Uri navigation;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: username),
      ),
      GoRoute(
        path: '/user',
        builder: (context, state) {
          navigation = state.uri;
          return const SizedBox.shrink();
        },
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.byType(UsernameText));
  await tester.pumpAndSettle();
  return navigation;
}

Finder _badgeContainers(WidgetTester tester) {
  return find.descendant(
    of: find.byType(UsernameText),
    matching: find.byType(Container),
  );
}

Text _badgeText(WidgetTester tester, int index) {
  final badges = _badgeContainers(tester);
  final text = find.descendant(
    of: badges.at(index),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(text);
}
