import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '1.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 초기화 작업과 2초 대기를 병렬로 처리
    await Future.wait([
      // 초기화 작업 수행
      _performInitialization(),
      // 최소 2초 대기
      Future.delayed(const Duration(seconds: 2)),
    ]);

    // 초기화 완료 후 홈 화면으로 이동
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  Future<void> _performInitialization() async {
    await dotenv.load(fileName: ".env");

    String mapClientId = dotenv.env['NCP_MAPS_CLIENT_ID'] ?? '';

    await FlutterNaverMap().init(
      clientId: mapClientId,
      onAuthFailed: (ex) {
        // 인증 실패 처리
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // SIDAE 로고 이미지 - 가로 꽉 차게
            Container(
              color: Colors.white, // 로고가 투명이 아닐 수 있으므로 배경 흰색 박스 추가
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              child: Image.asset('assets/sidae_logo.png', fit: BoxFit.fitWidth),
            ),
            const SizedBox(height: 30),
            // 로딩 인디케이터
            CircularProgressIndicator(color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );
  }
}
