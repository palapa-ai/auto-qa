// A minimal app for auto-qa to drive. The widgets carry stable `ValueKey`s and
// visible text so the agent can find them by `key:` or `text:`.
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'auto-qa example', home: HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Center(
          child: Text(
            'Count: $_count',
            key: const ValueKey('count'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        floatingActionButton: FloatingActionButton(
          key: const ValueKey('increment'),
          tooltip: 'Increment',
          onPressed: () => setState(() => _count++),
          child: const Icon(Icons.add),
        ),
      );
}
