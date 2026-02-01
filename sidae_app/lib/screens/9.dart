// lib/screens/9.dart - 도착 완료 화면
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tts_service.dart';
import '../services/route_tracker.dart';
import '1.dart';

/// 최종 목적지 도착 완료 화면
class ArrivalScreen extends StatefulWidget {
  final String destinationName;

  const ArrivalScreen({super.key, required this.destinationName});

  @override
  State<ArrivalScreen> createState() => _ArrivalScreenState();
}

class _ArrivalScreenState extends State<ArrivalScreen>
    with SingleTickerProviderStateMixin {
  final TtsService _ttsService = TtsService.instance;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 축하 애니메이션 설정
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // 화면 진입 시 피드백
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playArrivalFeedback();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 도착 피드백 (햅틱 + TTS + 애니메이션)
  Future<void> _playArrivalFeedback() async {
    // 강한 햅틱 피드백 (3회 연속)
    for (int i = 0; i < 3; i++) {
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // 애니메이션 시작
    _animationController.forward();

    // TTS 안내
    await _ttsService.speak('목적지 ${widget.destinationName}에 도착했습니다. 수고하셨습니다!');
  }

  /// 홈으로 돌아가기
  void _goHome() {
    HapticFeedback.heavyImpact();

    // RouteTracker 상태 초기화
    RouteTracker.instance.reset();

    // 모든 화면을 제거하고 HomeScreen으로 이동
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false, // 모든 이전 라우트 제거
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 뒤로가기 방지
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 체크 아이콘 (애니메이션)
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Opacity(
                          opacity: _fadeAnimation.value,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green.shade700,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 80,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 48),

                  // "도착 완료" 텍스트
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      '도착 완료!',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 목적지 이름
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      widget.destinationName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 축하 메시지
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      '안전하게 도착하셨습니다.\n수고하셨습니다!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade400,
                        height: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 64),

                  // 홈으로 돌아가기 버튼
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton.icon(
                        onPressed: _goHome,
                        icon: const Icon(Icons.home, size: 28),
                        label: const Text(
                          '홈으로 돌아가기',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
