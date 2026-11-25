// Example app for flutter-ai-testing: a made-up sign-in, a list and a details
// page, every page root and control keyed. All data is invented.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A pretend session, so the agent tools have something to report.
class Session {
  static bool signedIn = false;
}

const items = ['Alpha', 'Bravo', 'Charlie'];

final GoRouter router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (_, _) => const LoginPage(),
    ),
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (_, _) => const HomePage(),
      routes: [
        GoRoute(
          path: 'item/:index',
          name: 'item',
          builder: (_, state) =>
              ItemPage(index: int.parse(state.pathParameters['index']!)),
        ),
      ],
    ),
    GoRoute(path: '/help', name: 'help', builder: (_, _) => const HelpPage()),
  ],
);

void main() => runApp(MaterialApp.router(routerConfig: router));

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Session.signedIn = true;
    context.goNamed('home');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('login_screen'),
    appBar: AppBar(title: const Text('Sign in')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            key: const ValueKey('login_name_field'),
            controller: _name,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const CircularProgressIndicator()
          else
            ElevatedButton(
              key: const ValueKey('login_sign_in_button'),
              onPressed: _signIn,
              child: const Text('Sign in'),
            ),
          TextButton(
            key: const ValueKey('login_help_link'),
            onPressed: () => context.pushNamed('help'),
            child: const Text('Help'),
          ),
        ],
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _signOut(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            key: const ValueKey('confirm_dialog_cancel_button'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm_dialog_confirm_button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      Session.signedIn = false;
      context.goNamed('login');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('home_screen'),
    appBar: AppBar(
      title: const Text('Items'),
      actions: [
        IconButton(
          key: const ValueKey('home_sign_out_button'),
          icon: const Icon(Icons.logout),
          onPressed: () => _signOut(context),
        ),
      ],
    ),
    body: ListView(
      children: [
        for (var i = 0; i < items.length; i++)
          ListTile(
            key: ValueKey('home_item_$i'),
            title: Text(items[i]),
            onTap: () =>
                context.pushNamed('item', pathParameters: {'index': '$i'}),
          ),
      ],
    ),
  );
}

class ItemPage extends StatelessWidget {
  const ItemPage({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('item_screen'),
    appBar: AppBar(
      leading: BackButton(
        key: const ValueKey('item_back_button'),
        onPressed: () => context.pop(),
      ),
      title: Text(items[index]),
    ),
    body: Center(child: Text('Details of ${items[index]}')),
  );
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('help_screen'),
    appBar: AppBar(
      leading: BackButton(
        key: const ValueKey('help_back_button'),
        onPressed: () => context.pop(),
      ),
      title: const Text('Help'),
    ),
    body: const Center(child: Text('Made-up help text.')),
  );
}
