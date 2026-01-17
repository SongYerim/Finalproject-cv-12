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
        // 시각장애인 배려: 고대비 및 큰 텍스트 위주
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black, 
      ),
      home: const SplashScreen(),
    );
  }
}