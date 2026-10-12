import 'package:flutter/material.dart';

class JournalApp extends StatelessWidget {
  const JournalApp({super.key});

  static Widget bootstrapForTest() => const JournalApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('今天'))),
    );
  }
}
