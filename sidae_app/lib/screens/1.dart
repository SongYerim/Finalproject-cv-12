import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// speech_to_text 플러그인 제거 - 네이티브 STT 사용
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sidae_app/screens/2.dart';
import '../services/api_service.dart';
import '../services/tts_service.dart';

//화면 단계: 1(ready) / 2(listening) / 3(done) / 4(failed)- UI 변환
enum SttStep { ready, listening, done, failed }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // 1. 네이티브 STT를 위한 MethodChannel/EventChannel
  static const MethodChannel _channel = MethodChannel(
    'com.ctrlcv.sidae_app/yolo_native',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.ctrlcv.sidae_app/yolo_detections',
  );

  StreamSubscription? _sttSubscription;

  final ApiService _apiService = ApiService();
  final TtsService _ttsService = TtsService.instance;

  // 2. 상태 변수들
  bool _isSpeechEnabled = true; // 네이티브 STT는 항상 사용 가능으로 가정
  bool _isListening = false;

  // 화면 분기용 단계
  SttStep _step = SttStep.ready;

  // STT 최종 결과(목적지)
  String _recognizedDestination = "";

  // STT 에러 처리 중복 방지
  bool _handlingSttError = false;

  // 펀스 애니메이션 컨트롤러
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // 주기적 진동 피드백 타이머
  Timer? _hapticTimer;

  // 더블 탭 종료를 위한 변수
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();

    // 펀스 애니메이션 초기화
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _setupSystem(); // 이 함수 내부에서 권한 요청, TTS 설정, STT 초기화 모두 수행

    // 첫 화면 진입 후 안내 TTS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak("시대 앱이 실행되었습니다. 화면을 눌러 목적지를 말씀해주세요.");
    });
  }

  Future<void> _setupSystem() async {
    await _requestPermissions();
    await _ttsService.initialize();
    _initSpeech();
  }

  // 초기 권한 요청 함수
  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.speech, // iOS 필수 권한
      Permission.location,
    ].request();
  }

  // 네이티브 STT EventChannel 구독 초기화
  void _initSpeech() {
    try {
      _sttSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
        if (event is Map && event['type'] == 'stt') {
          final eventType = event['eventType'] as String?;
          final data = event['data'] as String?;

          switch (eventType) {
            case 'status':
              // status handling
              break;
            case 'result':
              // 최종 결과
              _handleSttResult(data ?? '');
              break;
            case 'partial':
              // 부분 결과 (필요시 UI 업데이트용)
              // partial result
              break;
            case 'error':
              // 에러 처리
              _handleSttError(data ?? 'unknown_error');
              break;
          }
        }
      }, onError: (error) {});

      if (!mounted) return;
      setState(() => _isSpeechEnabled = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSpeechEnabled = false);
    }
  }

  // STT 최종 결과 처리
  void _handleSttResult(String text) {
    if (!mounted) return;

    // 피드백 중지
    _stopListeningFeedback();

    setState(() {
      _isListening = false;
      _step = SttStep.done;
      _recognizedDestination = text;
    });

    if (text.isNotEmpty) {
      _speak("음성인식 완료. 목적지는 $text 입니다. 맞으면 확인을 눌러주세요.");
    } else {
      _speak("음성 인식 결과가 없습니다. 다시 말씀해주세요.");
    }
  }

  @override
  void dispose() {
    _stopListeningFeedback();
    _pulseController.dispose();
    _sttSubscription?.cancel();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    await _ttsService.speak(text);
  }

  // STT 에러(특히 timeout) 발생 시: 실패 화면 -> TTS -> ready로 복귀
  Future<void> _handleSttError(String errorMsg) async {
    if (_handlingSttError) return;
    _handlingSttError = true;

    try {
      // 피드백 중지
      _stopListeningFeedback();

      try {
        await _channel.invokeMethod('stopListening');
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _isListening = false;
        _step = SttStep.failed;
      });

      await _speak("음성인식에 실패했습니다");

      if (!mounted) return;
      setState(() {
        _step = SttStep.ready;
      });

      await _speak("화면을 눌러 목적지를 말해주세요.");
    } finally {
      _handlingSttError = false;
    }
  }

  // 3. 핵심 기능: 네이티브 음성 인식 시작
  void _listen() async {
    if (!_isSpeechEnabled) {
      _initSpeech();
      _speak("아직 준비 중입니다. 잠시 후 다시 시도해주세요.");
      return;
    }

    await _ttsService.stop();

    if (!_isListening) {
      setState(() {
        _isListening = true;
        // 1-2 화면으로 전환
        _step = SttStep.listening;
        _recognizedDestination = "";
      });

      // 진동 피드백 (기획서 3.5: 중요 액션에 진동) - heavyImpact로 상향
      HapticFeedback.heavyImpact();

      // ✅ TTS 안내 추가
      await _speak("말씀하세요");

      // ✅ 펀스 애니메이션 & 주기적 진동 시작
      _startListeningFeedback();

      try {
        // 네이티브 MethodChannel로 음성인식 시작
        await _channel.invokeMethod('startListening');
      } catch (e) {
        // 예외도 동일하게 실패 처리로 통일
        await _handleSttError("listen_exception");
      }
    } else {
      // 이미 듣고 있는 상태면 stop 처리
      _stopListeningFeedback();
      try {
        await _channel.invokeMethod('stopListening');
      } catch (_) {}
      setState(() {
        _isListening = false;
        _step = SttStep.ready;
      });
    }
  }

  /// 음성인식 중 피드백 시작 (펀스 애니메이션 + 주기적 진동)
  void _startListeningFeedback() {
    // 펀스 애니메이션 시작 (반복)
    _pulseController.repeat(reverse: true);

    // 주기적 진동 (1.5초마다) - light -> medium으로 상향
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!_isListening) {
        timer.cancel();
        return;
      }
      HapticFeedback.mediumImpact();
    });
  }

  /// 음성인식 피드백 중지
  void _stopListeningFeedback() {
    _pulseController.stop();
    _pulseController.reset();
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  // 4. 서버 통신 및 경로 처리 로직
  Future<void> _processNavigation(String destination) async {
    try {
      // 위치 권한 상태 먼저 확인
      LocationPermission permission = await Geolocator.checkPermission();

      // 1. 권한이 거부된 상태라면 다시 요청
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _speak("위치 권한을 허용해주셔야 길을 찾을 수 있습니다.");
          if (!mounted) return;
          setState(() {
            _step = SttStep.ready;
          });
          return;
        }
      }

      // 2. 권한이 '영구적으로' 거부된 상태라면
      if (permission == LocationPermission.deniedForever) {
        _speak("위치 권한이 꺼져 있습니다. 스마트폰 설정에서 권한을 켜주세요.");
        if (!mounted) return;
        setState(() {
          _step = SttStep.ready;
        });
        await Geolocator.openAppSettings();
        return;
      }

      // 1) 현재 위치(GPS) 가져오기
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 2) 목적지 검색 (텍스트 -> 좌표)
      final placeData = await _apiService.searchPlace(destination);

      if (placeData == null) {
        _speak("목적지를 찾을 수 없습니다. 다시 말씀해주세요.");
        if (!mounted) return;
        setState(() {
          _step = SttStep.ready;
        });
        return;
      }

      double endLat = placeData['latitude'];
      double endLng = placeData['longitude'];
      String placeName = placeData['name'];

      // 3) 경로 탐색 화면으로 이동
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RouteSearchScreen(
            startLat: position.latitude,
            startLng: position.longitude,
            endLat: endLat,
            endLng: endLng,
            destinationName: placeName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _speak("오류가 발생했습니다. 잠시 후 다시 시도해주세요.");
      setState(() {
        _step = SttStep.ready;
      });
    }
  }

  // UI: 상태 → build 분기 → UI
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 더블 탭 종료 처리
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 3)) {
          // 첫 번째 뒤로가기
          _lastBackPressTime = now;
          // medium -> heavy로 상향
          HapticFeedback.heavyImpact();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.exit_to_app, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text(
                      '종료하려면 한 번 더 눌러주세요',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.redAccent,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
          await _speak("종료하려면 한 번 더 눌러주세요");
        } else {
          // 두 번째 뒤로가기 - 종료
          if (context.mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
          }
          // heavy -> vibrate로 상향
          HapticFeedback.vibrate();
          await _speak("앱을 종료합니다");
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        // 화면 아무 곳이나 누르면 듣기 시작
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (_step == SttStep.ready) _listen();
          },
          child: SafeArea(child: _buildByStep()),
        ),
      ),
    );
  }

  Widget _buildByStep() {
    switch (_step) {
      case SttStep.ready:
        return _buildReadyUI();
      case SttStep.listening:
        return _buildListeningUI();
      case SttStep.done:
        return _buildDoneUI();
      case SttStep.failed:
        return _buildFailedUI();
    }
  }

  //  1) 첫 화면 (목적지를 말해주세요)
  Widget _buildReadyUI() {
    return Column(
      children: [
        const SizedBox(height: 80),
        Text(
          '목적지를\n말해주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 40),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _micPanel(
              panelColor: Colors.grey[900]!, // 어두운 배경
              micColor: Theme.of(context).primaryColor, // 노란색 마이크
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  //  2) 두 번째 화면 (음성인식 중...)
  Widget _buildListeningUI() {
    return Column(
      children: [
        const SizedBox(height: 80),
        Text(
          '음성인식 중...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 40),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _micPanel(
              panelColor: Colors.grey[900]!,
              micColor: Colors.redAccent,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // 4) 실패 화면 (음성인식 실패)
  Widget _buildFailedUI() {
    return Column(
      children: [
        const SizedBox(height: 80),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).primaryColor,
            ),
            children: const [
              TextSpan(text: '음성인식 '),
              TextSpan(
                text: '실패',
                style: TextStyle(color: Colors.redAccent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _micPanel(
              panelColor: Colors.grey[900]!,
              micColor: Colors.redAccent,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // 3) 세 번째 화면 (음성인식 완료 + 목적지 + 확인/다시말하기)
  Widget _buildDoneUI() {
    return Column(
      children: [
        const SizedBox(height: 60),

        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).primaryColor,
            ),
            children: const [
              TextSpan(text: '음성인식 '),
              TextSpan(
                text: '완료',
                style: TextStyle(color: Colors.greenAccent),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 목적지 표시 박스
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).primaryColor),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '목적지 : ${_recognizedDestination.isEmpty ? "(없음)" : _recognizedDestination}',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ),

        const SizedBox(height: 18),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white),
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 확인 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7BC96F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        // 2.dart/경로 탐색로 연결

                        if (_recognizedDestination.isEmpty) {
                          _speak("목적지가 없습니다. 다시 말씀해주세요.");
                          return;
                        }

                        // 로딩 상태 표시 (선택사항)
                        // setState(() {
                        //   _statusText = "경로를 찾는 중입니다...";
                        // });

                        try {
                          await _processNavigation(_recognizedDestination);
                        } catch (e) {
                          if (!mounted) return;
                          _speak("경로 탐색 중 오류가 발생했습니다.");
                          setState(() {
                            _step = SttStep.ready;
                          });
                        }
                      },
                      child: const Text(
                        '확인',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 다시 말하기 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        setState(() {
                          _recognizedDestination = "";
                          _step = SttStep.ready;
                        });
                        _speak("화면을 눌러 목적지를 말씀해주세요.");
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.mic, color: Colors.black, size: 26),
                          SizedBox(width: 10),
                          Text(
                            '다시 말하기',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // 공통 마이크 패널(중복 최소화) - 펀스 애니메이션 적용
  Widget _micPanel({required Color panelColor, required Color micColor}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(32),
        // 음성인식 중일 때 빨간색 테두리 추가
        border: _isListening
            ? Border.all(color: Colors.redAccent, width: 3)
            : null,
      ),
      child: Center(
        // 펀스 애니메이션 적용
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = _isListening ? _pulseAnimation.value : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: micColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: _isListening ? 28 : 18,
                      offset: const Offset(0, 8),
                      color: _isListening
                          ? micColor.withValues(alpha: 0.5)
                          : Colors.black.withValues(alpha: 0.12),
                    ),
                  ],
                ),
                child: const Icon(Icons.mic, size: 44, color: Colors.white),
              ),
            );
          },
        ),
      ),
    );
  }
}
