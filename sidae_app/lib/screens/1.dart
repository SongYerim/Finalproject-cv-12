import 'dart:async';
import 'dart:convert';
import 'dart:io'; // File 읽기용
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 진동(HapticFeedback)용
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sidae_app/screens/2.dart';
import 'package:sidae_app/screens/6.dart';
import 'package:sidae_app/screens/3.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';

//화면 단계: 1(ready) / 2(listening) / 3(done) / 4(failed)- UI 변환
enum SttStep { ready, listening, done, failed }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 1. 필요한 도구들 준비
  final stt.SpeechToText _speech = stt.SpeechToText(); // 음성 인식기
  final FlutterTts _flutterTts = FlutterTts();         // 음성 합성기 (말하는 AI)
  final ApiService _apiService = ApiService();         // 서버 통신 담당

  // 2. 상태 변수들
  bool _isSpeechEnabled = false;
  bool _isListening = false;

  // 화면 분기용 단계
  SttStep _step = SttStep.ready;

  // STT 최종 결과(목적지)
  String _recognizedDestination = "";

   // STT 에러 처리 중복 방지
  bool _handlingSttError = false;

  @override
  void initState() {
    super.initState();
    _setupSystem(); // 이 함수 내부에서 권한 요청, TTS 설정, STT 초기화 모두 수행

    // 첫 화면 진입 후 안내 TTS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak("시대 앱이 실행되었습니다. 화면을 눌러 목적지를 말씀해주세요.");
    });
  }

  Future<void> _setupSystem() async {
    await _requestPermissions(); // 1. 권한 요청
    await _initTts();   // 2. TTS 설정
    _initSpeech();      // 3. STT 초기화
  }

  // 초기 권한 요청 함수
  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.speech,    // iOS 필수 권한
      Permission.location,
    ].request();
  }

  // TTS 초기 설정 (한국어 설정)
  Future<void> _initTts() async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
    // iOS 오디오 세션 설정 (말하기/듣기 충돌 방지)
    await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playAndRecord,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker
        ],
    );

    // ✅ 가능하면 await이 “완료까지” 의미 있도록(버전에 따라 없어도 됨)
    try {
      await _flutterTts.awaitSpeakCompletion(true);
    } catch (_) {}
  }

// STT 초기화
  void _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (s) async {
          debugPrint('[HomeScreen][STT][status] $s');

          // status가 done으로 끝났는데 finalResult가 안 온 경우(무음/timeout 등) 대비
          if (s == 'done') {
            await Future.delayed(const Duration(milliseconds: 200));
            await _handleSttDoneWithoutResult();
          }
        },
        onError: (e) async {
          debugPrint('[HomeScreen][STT][error] ${e.errorMsg}');
          // timeout/error 시 실패 화면 -> TTS -> ready 복귀
          await _handleSttError(e.errorMsg);
        },
      );

      if (!mounted) return;
      setState(() => _isSpeechEnabled = available);
    } catch (e) {
      debugPrint("STT 초기화 실패: $e");
      if (!mounted) return;
      setState(() => _isSpeechEnabled = false);
    }
  }

  // 텍스트 읽어주기 함수 (TTS 말하기)
  Future<void> _speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  // STT 에러(특히 timeout) 발생 시: 실패 화면 -> TTS -> ready로 복귀
  Future<void> _handleSttError(String errorMsg) async {
    if (_handlingSttError) return;
    _handlingSttError = true;

    try {
      // listening 세션 정리
      try { await _speech.stop(); } catch (_) {}

      if (!mounted) return;

      // 1) 실패 화면으로 전환
      setState(() {
        _isListening = false;
        _step = SttStep.failed; // 실패 UI
      });

      // 2) 실패 안내 TTS
      await _speak("음성인식에 실패했습니다");

      // 3) 잠깐 실패 화면 보여준 뒤 1-1(ready)로 복귀
      // await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      // 3) 1-1 화면으로 복귀
      setState(() {
        _step = SttStep.ready;
      });

      // 4) 다시 안내
      await _speak("화면을 눌러 목적지를 말해주세요.");
    } finally {
      _handlingSttError = false;
    }
  }

  // status가 done인데 finalResult가 안 온 경우(무음/timeout 등) 대비
  Future<void> _handleSttDoneWithoutResult() async {
    if (_step == SttStep.listening && _recognizedDestination.trim().isEmpty) {
      await _handleSttError("done_without_result");
    }
  }

  // 3. 핵심 기능: 음성 인식 시작 -> 위치 확인 -> 서버 전송
  void _listen() async {
    // 음성 인식 초기화
    if (!_isSpeechEnabled) {
      _initSpeech();
      _speak("아직 준비 중입니다. 잠시 후 다시 시도해주세요.");
      return;
    }
    
    await _flutterTts.stop();

    if (!_isListening) {
      setState(() {
        _isListening = true;
         // 1-2 화면으로 전환
        _step = SttStep.listening;
        _recognizedDestination = "";
      });
      
      // 진동 피드백 (기획서 3.5: 중요 액션에 진동)
      HapticFeedback.mediumImpact(); 
      try{
        _speech.listen(
          onResult: (val) {
            if (val.finalResult) {
              _speech.stop();

              String destination = val.recognizedWords;
              setState(() {
                _isListening = false;
              // 1-3 화면으로 전환 + 결과 저장
                _step = SttStep.done;
                _recognizedDestination = destination;
              });

              if (destination.isNotEmpty) {
                _speak("음성인식 완료. 목적지는 $destination 입니다. 맞으면 확인을 눌러주세요.");
              } else {
                _speak("음성 인식 결과가 없습니다. 다시 말씀해주세요.");
              }
            }
          },
          localeId: 'ko_KR',
          listenFor: const Duration(seconds: 10), 
          pauseFor: const Duration(seconds: 3),
        );

      } catch (e) {
       debugPrint("Listen 에러: $e");
        // 예외도 동일하게 실패 처리로 통일
        await _handleSttError("listen_exception");
      }
    } else {
       // 이미 듣고 있는 상태면 stop 처리
      await _speech.stop();
      setState(() {
        _isListening = false;
        _step = SttStep.ready;
      });
    }
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
          return; // 여기서 함수 종료 (에러 방지)
        }
      }

      // 2. 권한이 '영구적으로' 거부된 상태라면 (설정 앱 유도)
      if (permission == LocationPermission.deniedForever) {
        _speak("위치 권한이 꺼져 있습니다. 스마트폰 설정에서 권한을 켜주세요.");
        if (!mounted) return;
        setState(() {
          _step = SttStep.ready;
        });
        
        // (선택) 설정 화면으로 바로 보내주는 코드
        await Geolocator.openAppSettings(); 
        return;
      }
      // 1) 현재 위치(GPS) 가져오기
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      
      debugPrint("내 위치: ${position.latitude}, ${position.longitude}");

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

      // 3) 경로 탐색 (내 위치 -> 목적지 좌표)
      // 이 단계는 2.dart(RouteSearchScreen)에서 수행합니다.
      if (!mounted) return;

      debugPrint("[1.dart] RouteSearchScreen으로 이동 시작");
      debugPrint("[1.dart] startLat: ${position.latitude}, startLng: ${position.longitude}");
      debugPrint("[1.dart] endLat: $endLat, endLng: $endLng");
      debugPrint("[1.dart] destinationName: $placeName");

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
      
      debugPrint("[1.dart] Navigator.push 완료");

    } catch (e) {
      // 에러 핸들링 (print 대신 debugPrint 사용 권장)
      debugPrint("에러 발생: $e");
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
    return Scaffold(
      backgroundColor: Colors.white,

      // 화면 아무 곳이나 누르면 듣기 시작 (요구사항 유지)
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // ready 화면에서만 시작하도록(2/3화면에서 오작동 방지)
          if (_step == SttStep.ready) _listen();
        },
        child: SafeArea(
          child: _buildByStep(),
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

  // route_data.json 파일을 읽어서 파싱하는 함수 (assets에서)
  Future<void> _loadRouteDataJson() async {
    try {
      // assets에서 route_data.json 읽기
      final String jsonString = await rootBundle.loadString('assets/route_data.json');
      
      // JSON 파싱
      final List<dynamic> jsonData = json.decode(jsonString);
      
      // RouteSegment 리스트로 변환 (API 방식과 동일)
      final List<RouteSegment> routes = jsonData
          .map((item) => RouteSegment.fromJson(item as Map<String, dynamic>))
          .toList();
      
      if (!mounted) return;
      
      // 3.dart로 이동
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapResultScreen(
            routes: routes,
            destinationName: "테스트 목적지 (route_data.json)",
          ),
        ),
      );
      
      debugPrint("[1.dart] route_data.json 로드 완료, ${routes.length}개 구간");
    } catch (e) {
      debugPrint("[1.dart] route_data.json 로드 실패: $e");
      if (!mounted) return;
      _speak("경로 데이터를 불러오는데 실패했습니다.");
    }
  }

  // route_data_2.json 파일을 읽어서 파싱하는 함수 (앱 내부 저장소 또는 assets에서)
  Future<void> _loadRouteData2Json() async {
    try {
      String jsonString;
      
      // 1. 먼저 앱 내부 저장소에서 route_data_2.json 읽기 시도
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/route_data_2.json');
        
        if (await file.exists()) {
          jsonString = await file.readAsString(encoding: utf8);
          debugPrint("[1.dart] 앱 내부 저장소에서 route_data_2.json 로드 성공");
        } else {
          // 2. 파일이 없으면 assets에서 route_data_2.json 읽기
          jsonString = await rootBundle.loadString('assets/route_data_2.json');
          debugPrint("[1.dart] assets에서 route_data_2.json 로드 성공");
        }
      } catch (e) {
        // 3. 앱 내부 저장소 읽기 실패 시 assets에서 읽기
        debugPrint("[1.dart] 앱 내부 저장소 읽기 실패, assets에서 시도: $e");
        jsonString = await rootBundle.loadString('assets/route_data_2.json');
        debugPrint("[1.dart] assets에서 route_data_2.json 로드 성공");
      }
      
      // JSON 파싱
      final List<dynamic> jsonData = json.decode(jsonString);
      
      // RouteSegment 리스트로 변환 (API 방식과 동일)
      final List<RouteSegment> routes = jsonData
          .map((item) => RouteSegment.fromJson(item as Map<String, dynamic>))
          .toList();
      
      if (!mounted) return;
      
      // 3.dart로 이동
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapResultScreen(
            routes: routes,
            destinationName: "테스트 목적지 (route_data_2.json)",
          ),
        ),
      );
      
      debugPrint("[1.dart] route_data_2.json 로드 완료, ${routes.length}개 구간");
    } catch (e) {
      debugPrint("[1.dart] route_data_2.json 로드 실패: $e");
      if (!mounted) return;
      _speak("경로 데이터를 불러오는데 실패했습니다.");
    }
  }

  // YOLO 테스트 화면 열기
  void _openYoloTest() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const YoloTestScreen(),
      ),
    );
  }

  //  1) 첫 화면 (목적지를 말해주세요)
  Widget _buildReadyUI() {
    return Column(
      children: [
        const SizedBox(height: 80),
        const Text(
          '목적지를\n말해주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black,
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
              panelColor: const Color(0xFFF1EFFE), // 연보라 박스
              micColor: const Color(0xFF8B86B8),   // 보라 마이크 원
            ),
          ),
        ),
        // 테스트 버튼 추가: 양옆 배치
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _loadRouteDataJson,
                      child: const Text(
                        '테스트: route_data.json',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _loadRouteData2Json,
                      child: const Text(
                        '테스트: route_data_2.json',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // YOLO 테스트 버튼 추가
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _openYoloTest,
              child: const Text(
                '테스트: YOLO 객체 감지',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
        const Text(
          '음성인식 중...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 40),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _micPanel(
              panelColor: const Color(0xFFFFEAEA), // 연핑크 박스
              micColor: const Color(0xFFD9534F),   // 빨간 마이크 원
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
          text: const TextSpan(
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            children: [
              TextSpan(text: '음성인식 '),
              TextSpan(text: '실패', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _micPanel(
              panelColor: const Color(0xFFFFEAEA), // 연핑크
              micColor: const Color(0xFFD9534F),   // 빨강
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
          text: const TextSpan(
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            children: [
              TextSpan(text: '음성인식 '),
              TextSpan(text: '완료', style: TextStyle(color: Colors.green)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 목적지 표시 박스
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '목적지 : ${_recognizedDestination.isEmpty ? "(없음)" : _recognizedDestination}',
              style: const TextStyle(fontSize: 16),
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
                color: const Color(0xFFE7F7E7), // 연녹색
                borderRadius: BorderRadius.circular(18),
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
                        debugPrint("[1.dart] 확인 버튼 클릭됨");
                        debugPrint("[1.dart] _recognizedDestination: $_recognizedDestination");
                        
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
                          debugPrint("[1.dart] _processNavigation 완료");
                        } catch (e) {
                          debugPrint("[1.dart] _processNavigation 에러: $e");
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
                        backgroundColor: const Color(0xFFFFB3B3),
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
                          Icon(Icons.mic, color: Colors.white, size: 26),
                          SizedBox(width: 10),
                          Text(
                            '다시 말하기',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
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

  // 공통 마이크 패널(중복 최소화)
  Widget _micPanel({required Color panelColor, required Color micColor}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Center(
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: micColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 8),
                color: Colors.black.withValues(alpha: 0.12),
              ),
            ],
          ),
          child: const Icon(Icons.mic, size: 44, color: Colors.white),
        ),
      ),
    );
  }
}