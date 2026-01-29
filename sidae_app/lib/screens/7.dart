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
        _ttsService.speak("버스가 감지되었습니다");
      }
    };

    _busDetectorService.onBusCropped = (croppedImage) {
      if (mounted) {
        setState(() {
          _croppedBusImage = croppedImage;
        });
        // TODO: OCR 서버로 전송
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

  /// 카메라 중지
  void _stopCamera() {
    _busDetectorService.stopDetection();
    setState(() {
      _cameraActive = false;
      _currentDetection = null;
      _croppedBusImage = null;
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
    _arrivalService.onArrivalUpdate = null;

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
                    child: Text(
                      _arrival!.statusMsg,
                      style: TextStyle(
                        color: _isBusApproachingStatus(_arrival!.statusMsg)
                            ? Colors.orange
                            : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
            Container(
              width: 120,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: Colors.green,
              child: const Text(
                'Cropped Bus',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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
