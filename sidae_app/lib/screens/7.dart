import 'dart:async';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../services/bus_arrival_service.dart';
import '../services/bus_detector_service.dart';
import '../services/tts_service.dart';

class BusArrivalScreen extends StatefulWidget {
  final String busNumber;
  final String stationName;
  final bool enableCamera; // 카메라 모드 활성화 파라미터

  const BusArrivalScreen({
    super.key,
    required this.busNumber,
    required this.stationName,
    this.enableCamera = false,
  });

  @override
  State<BusArrivalScreen> createState() => _BusArrivalScreenState();
}

class _BusArrivalScreenState extends State<BusArrivalScreen> {
  final BusArrivalService _arrivalService = BusArrivalService();
  final TtsService _ttsService = TtsService.instance;
  final BusDetectorService _busDetectorService = BusDetectorService();

  BusArrival? _arrival;
  bool _isLoading = true;

  // 카메라 상태
  bool _isBusApproaching = false;
  bool _cameraActive = false;
  String _detectionStatus = '';
  BusDetection? _currentDetection;
  Uint8List? _croppedBusImage;

  // 매칭 상태
  String _matchStatus = ''; // 'MATCH', 'MISMATCH', 'CHECKING', ''
  String _lastOcrResult = '';
  Timer? _mismatchTimer; // MISMATCH 상태 유지 타이머

  @override
  void initState() {
    super.initState();
    _initializeService();

    // enableCamera가 true면 바로 카메라 시작
    if (widget.enableCamera) {
      _isBusApproaching = true;
      _startCamera();
    }
  }

  Future<void> _initializeService() async {
    await _ttsService.initialize();
    await _ttsService.speak("버스 정류장에 도착했습니다. 도착 정보를 확인합니다.");

    _arrivalService.onArrivalUpdate = (arrival) {
      if (!mounted) return;
      setState(() {
        _arrival = arrival;
        _isLoading = false;
      });

      // TTS로 도착 정보 안내
      if (arrival != null) {
        _ttsService.speak("${arrival.busNumber}번 버스, ${arrival.statusMsg}");

        // "곧 도착" 상태 감지 → 카메라 활성화
        if (_isBusApproachingStatus(arrival.statusMsg) && !_cameraActive) {
          _isBusApproaching = true;
          _startCamera();
        }
      }
    };

    await _arrivalService.startTracking(widget.busNumber, widget.stationName);
  }

  /// "곧 도착" 상태인지 확인
  bool _isBusApproachingStatus(String statusMsg) {
    return statusMsg.contains('곧 도착') ||
        statusMsg.contains('잠시 후') ||
        statusMsg.contains('1분') ||
        statusMsg.contains('2분');
  }

  /// 카메라 시작
  Future<void> _startCamera() async {
    if (_cameraActive) return;

    setState(() {
      _detectionStatus = '카메라 시작 중...';
      _matchStatus = '';
    });

    _busDetectorService.onStatusChanged = (status) {
      if (mounted) {
        setState(() {
          _detectionStatus = status;
        });
      }
    };

    _busDetectorService.onBusDetected = (detection) {
      if (mounted) {
        setState(() {
          _currentDetection = detection;
        });
        // _ttsService.speak("버스가 감지되었습니다");
      }
    };

    _busDetectorService.onBusCropped = (croppedImage) {
      if (mounted) {
        setState(() {
          _croppedBusImage = croppedImage;
          // MATCH나 MISMATCH 상태가 아닐 때만 CHECKING으로 변경
          if (_matchStatus != 'MATCH' && _matchStatus != 'MISMATCH') {
            _matchStatus = 'CHECKING';
          }
        });
        // TODO: OCR 서버로 전송 (Service 내부에서 처리됨)
      }
    };

    // OCR 결과 수신
    _busDetectorService.onBusNumberFound = (ocrResult) {
      developer.log(
        '🎯 [7.dart] OCR 콜백 수신: $ocrResult',
        name: 'BusArrivalScreen',
      );
      if (mounted) {
        developer.log(
          '  - mounted: true, _checkMatch 호출',
          name: 'BusArrivalScreen',
        );
        _checkMatch(ocrResult);
      } else {
        developer.log('  - mounted: false, 스킵', name: 'BusArrivalScreen');
      }
    };

    final success = await _busDetectorService.startDetection();
    if (mounted) {
      setState(() {
        _cameraActive = success;
        if (!success) {
          _detectionStatus = '카메라 시작 실패';
        }
      });
    }
  }

  // 매칭 로직
  void _checkMatch(String ocrResult) {
    developer.log('🔍 [7.dart] _checkMatch 시작', name: 'BusArrivalScreen');
    developer.log('  - ocrResult: $ocrResult', name: 'BusArrivalScreen');
    developer.log(
      '  - widget.busNumber: ${widget.busNumber}',
      name: 'BusArrivalScreen',
    );

    _lastOcrResult = ocrResult;

    // 1. 버스 번호 매칭 (문자열 포함 여부)
    bool isNumberMatch = ocrResult.contains(widget.busNumber);
    developer.log(
      '  - isNumberMatch: $isNumberMatch',
      name: 'BusArrivalScreen',
    );

    // 2. 번호판 매칭 (뒤 4자리)
    bool isPlateMatch = false;
    if (_arrival != null && _arrival!.plateNo.isNotEmpty) {
      String plate = _arrival!.plateNo;
      // 뒤 4자리 추출
      String last4 = plate.length >= 4
          ? plate.substring(plate.length - 4)
          : plate;
      isPlateMatch = ocrResult.contains(last4);
      developer.log(
        '  - plateNo: $plate, last4: $last4, isPlateMatch: $isPlateMatch',
        name: 'BusArrivalScreen',
      );
    }

    if (isNumberMatch || isPlateMatch) {
      developer.log('✅ [7.dart] 매칭 성공!', name: 'BusArrivalScreen');
      setState(() {
        _matchStatus = 'MATCH';
      });
      _ttsService.speak("탑승할 버스입니다! ${widget.busNumber}번");

      // 매칭 성공 시 추론 중지 (배터리 절약)
      _busDetectorService.stopInference();
    } else {
      developer.log('❌ [7.dart] 매칭 실패', name: 'BusArrivalScreen');
      if (_matchStatus != 'MATCH') {
        setState(() {
          _matchStatus = 'MISMATCH';
        });

        // 5초 후 MISMATCH 상태 해제 (새로운 감지 허용)
        _mismatchTimer?.cancel();
        _mismatchTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && _matchStatus == 'MISMATCH') {
            setState(() {
              _matchStatus = '';
            });
          }
        });
        // _ttsService.speak("다른 버스입니다.");
      }
    }
  }

  /// 탑승 시뮬레이션 시작 (Debug)
  Future<void> _startBoardingSimulation() async {
    developer.log('🚀 탑승 시뮬레이션 시작', name: 'BusArrivalScreen');

    setState(() {
      _matchStatus = 'MATCH';
    });

    // 시뮬레이션 시작 시 추론 중지
    await _busDetectorService.stopInference();

    // 5초 대기 (탑승 준비)
    for (int i = 5; i > 0; i--) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("탑승 준비 중... ${i}초"),
          duration: const Duration(milliseconds: 800),
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
    }

    // 3회 루프 (태그기 인식 시도)
    for (int i = 1; i <= 3; i++) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("태그기 찾는 중... ($i/3)"),
          duration: const Duration(milliseconds: 800),
        ),
      );

      // 캡쳐 요청 및 대기
      final completer = Completer<Uint8List>();
      _busDetectorService.onSnapshotCaptured = (image) {
        if (!completer.isCompleted) completer.complete(image);
      };

      await _busDetectorService.requestSnapshot();

      try {
        // 3초 타임아웃
        final image = await completer.future.timeout(
          const Duration(seconds: 3),
        );

        // 캡쳐된 이미지를 화면에 표시 (크롭 이미지 뷰 재사용)
        if (mounted) {
          setState(() {
            _croppedBusImage = image;
          });
        }

        await _busDetectorService.sendToVlmDummy(image);
      } catch (e) {
        developer.log("❌ 캡쳐/전송 실패: $e", name: 'BusArrivalScreen');
      }

      // 약간의 간격
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✅ 탑승 완료! (시뮬레이션 종료)"),
        backgroundColor: Colors.green,
      ),
    );
    developer.log("✅ 탑승 시뮬레이션 종료", name: 'BusArrivalScreen');
  }

  /// 카메라 중지
  void _stopCamera() {
    _busDetectorService.stopDetection();
    setState(() {
      _cameraActive = false;
      _currentDetection = null;
      _croppedBusImage = null;
      _matchStatus = '';
    });
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _arrivalService.refresh();
  }

  @override
  void dispose() {
    developer.log(
      '🗑️ [BusArrivalScreen] dispose() 시작',
      name: 'BusArrivalScreen',
    );

    // 카메라가 활성화된 경우 명시적으로 중지
    if (_cameraActive) {
      developer.log('  - 카메라 활성화 상태, 명시적 중지', name: 'BusArrivalScreen');
      _busDetectorService.stopDetection();
      _cameraActive = false;
    }

    // 콜백 제거
    developer.log('  - 콜백 제거', name: 'BusArrivalScreen');
    _busDetectorService.onStatusChanged = null;
    _busDetectorService.onBusDetected = null;
    _busDetectorService.onBusCropped = null;
    _busDetectorService.onBusNumberFound = null;
    _arrivalService.onArrivalUpdate = null;

    // 타이머 정리
    _mismatchTimer?.cancel();
    _mismatchTimer = null;

    // 서비스 정리
    developer.log('  - 서비스 정리', name: 'BusArrivalScreen');
    _arrivalService.dispose();
    _busDetectorService.dispose();

    developer.log(
      '✅ [BusArrivalScreen] dispose() 완료',
      name: 'BusArrivalScreen',
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 카메라 토글 버튼
          IconButton(
            icon: Icon(
              _cameraActive ? Icons.videocam : Icons.videocam_off,
              color: _cameraActive ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              if (_cameraActive) {
                _stopCamera();
              } else {
                _startCamera();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. 전체 화면 카메라 프리뷰 (배경)
          _buildFullCameraPreview(),

          // 2. 바운딩 박스 오버레이 (네이티브에서 처리하므로 Flutter 페인터 제거)
          // if (_currentDetection != null) _buildBoundingBoxOverlay(),

          // 매칭 결과 오버레이 (성공 시 화면 테두리 등 효과)
          if (_matchStatus == 'MATCH')
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 8),
                ),
              ),
            ),

          // 3. 하단 정보 패널
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomInfoPanel(),
          ),

          // 4. Crop 이미지 프리뷰 (우측 하단)
          if (_croppedBusImage != null)
            Positioned(
              right: 16,
              bottom: 140,
              child: _buildCroppedImagePreview(),
            ),

          // 5. 감지 상태 표시 (좌측 상단)
          Positioned(top: 100, left: 16, child: _buildDetectionStatusBadge()),

          // 6. 매칭 결과 텍스트 (중앙 상단)
          if (_matchStatus == 'MATCH')
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  color: Colors.green,
                  child: const Text(
                    "탑승할 버스입니다!",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
          else if (_matchStatus == 'MISMATCH')
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  color: Colors.red.withOpacity(0.8),
                  child: Text(
                    "다른 버스입니다 ($_lastOcrResult)",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),

          // 7. DEBUG 버튼 (좌측 하단)
          Positioned(
            left: 16,
            bottom: 140,
            child: ElevatedButton(
              onPressed: _startBoardingSimulation,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text("DEBUG: 매칭 성공"),
            ),
          ),
        ],
      ),
    );
  }

  /// 전체 화면 카메라 프리뷰
  Widget _buildFullCameraPreview() {
    if (!_cameraActive || !_busDetectorService.isActive) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.green),
              const SizedBox(height: 16),
              Text(
                _detectionStatus.isEmpty ? '카메라 준비 중...' : _detectionStatus,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // 네이티브 AndroidView 사용 (6.dart 참조)
    return const SizedBox.expand(child: AndroidView(viewType: 'cameraPreview'));
  }

  /// 하단 정보 패널
  Widget _buildBottomInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 정류장 + 버스 정보
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.stationName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 버스 번호 + 상태
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.busNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_arrival != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _arrival!.statusMsg,
                          style: TextStyle(
                            color: _isBusApproachingStatus(_arrival!.statusMsg)
                                ? Colors.orange
                                : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // 차량 번호 (있는 경우에만 표시)
                        if (_arrival!.plateNo.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              _arrival!.plateNo,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else if (_isLoading)
                  const Text(
                    '도착 정보 확인 중...',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Crop 이미지 프리뷰
  Widget _buildCroppedImagePreview() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 이미지
            Image.memory(
              _croppedBusImage!,
              width: 120,
              height: 80,
              fit: BoxFit.cover,
            ),

            // 라벨
          ],
        ),
      ),
    );
  }

  /// 감지 상태 배지
  Widget _buildDetectionStatusBadge() {
    final isDetected = _currentDetection != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDetected
            ? Colors.green.withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDetected ? Colors.green : Colors.grey,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDetected ? Icons.check_circle : Icons.search,
            color: isDetected ? Colors.white : Colors.grey,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            isDetected
                ? '버스 감지됨 (${(_currentDetection!.confidence * 100).toStringAsFixed(0)}%)'
                : _detectionStatus,
            style: TextStyle(
              color: isDetected ? Colors.white : Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
