import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // 플러터 엔진 초기화

  runApp(const SidaeApp());
}

class SidaeApp extends StatelessWidget {
  const SidaeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '시대 (Sidae)',
      debugShowCheckedModeBanner: false, // 오른쪽 위 'DEBUG' 띠 제거 (선택)
      theme: ThemeData(
        // 시각장애인 배려: 고대비 테마
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.yellow,
        colorScheme: const ColorScheme.dark(
          primary: Colors.yellow,
          secondary: Colors.yellow,
          surface: Color(0xFF1E1E1E),
          background: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.yellow,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontSize: 18),
          bodyMedium: TextStyle(color: Colors.white, fontSize: 16),
          bodySmall: TextStyle(color: Colors.white70, fontSize: 14),
          displayLarge: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          displayMedium: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          displaySmall: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.yellow,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.yellow,
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
