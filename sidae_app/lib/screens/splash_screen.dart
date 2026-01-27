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
        debugPrint("네이버 지도 인증 실패: $ex");
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 고대비: 검은색 배경
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // SIDAE 로고 이미지 - 가로 꽉 차게
            SizedBox(
              width: double.infinity,
              child: Image.asset('assets/sidae_logo.png', fit: BoxFit.fitWidth),
            ),
            const SizedBox(height: 30),
            // 로딩 인디케이터 - 고대비: 노란색
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.yellow),
              strokeWidth: 4,
            ),
          ],
        ),
      ),
    );
  }
}
