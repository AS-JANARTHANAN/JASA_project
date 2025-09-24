import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:JASA/screens.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => SplashScreen(),
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/add_product': (context) => AddProductScreen(),
        '/admin_dashboard': (context) => AdminDashboard(),
        '/user_dashboard': (context) => UserDashboard(),
      },
    );
  }
}
