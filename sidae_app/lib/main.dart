import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer' as developer;
import 'screens/splash_screen.dart';
import 'theme/style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 플러터 엔진 초기화

  // Navigation Bar와 Status Bar 숨기기 (슬라이드하면 나타남)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // .env 파일 로드
  try {
    developer.log('📂 .env 파일 로딩 시작...', name: 'Main');
    await dotenv.load(fileName: ".env");
    developer.log('✅ .env 파일 로드 완료!', name: 'Main');
    developer.log(
      '  - dotenv.isInitialized: ${dotenv.isInitialized}',
      name: 'Main',
    );
    developer.log(
      '  - SIDAE_SERVER_CLOUD_URL: ${dotenv.env['SIDAE_SERVER_CLOUD_URL']}',
      name: 'Main',
    );
    developer.log('  - 모든 환경 변수: ${dotenv.env.keys.toList()}', name: 'Main');
  } catch (e) {
    developer.log('❌ .env 파일 로드 실패: $e', name: 'Main', error: e);
  }

  runApp(const SidaeApp());
}

class SidaeApp extends StatelessWidget {
  const SidaeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '시대 (Sidae)',
      debugShowCheckedModeBanner: false, // 오른쪽 위 'DEBUG' 띠 제거 (선택)
      theme: AppTheme.highContrastTheme,

      home: const SplashScreen(),
    );
  }
}
