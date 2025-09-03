import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/register_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://bbjnsgwawignbrmqrfpj.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiam5zZ3dhd2lnbmJybXFyZnBqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTYyMDM2OTMsImV4cCI6MjA3MTc3OTY5M30.xiCMeaS9mDcjMgFm0K0vCTo_Wi-aj-noQjfKW_QJ_h8',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo with Supabase',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),

      // 👇 keep your original MyHomePage as default
      home: const MyHomePage(title: 'Supabase Demo Home Page'),

      // 👇 add routes for auth screens
      routes: {
        '/register': (context) => RegisterScreen(), // removed const
        '/login': (context) => LoginScreen(), // removed const
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future<void> _testSupabase() async {
    final supabase = Supabase.instance.client;
    final response = await supabase.from('test_table').select();
    debugPrint("Supabase response: $response");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Fetched ${response.length} rows from Supabase")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _testSupabase,
              child: const Text("Test Supabase Connection"),
            ),
            const SizedBox(height: 20),

            // 👇 extra button to jump into Register screen for testing
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/register');
              },
              child: const Text("Go to Register Screen"),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
              child: const Text("Go to Login Screen"),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
