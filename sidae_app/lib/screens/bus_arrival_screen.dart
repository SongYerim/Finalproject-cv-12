import 'package:flutter/material.dart';
import '../services/bus_arrival_service.dart';
import '../services/tts_service.dart';

class BusArrivalScreen extends StatefulWidget {
  final String busNumber;
  final String stationName;

  const BusArrivalScreen({
    super.key,
    required this.busNumber,
    required this.stationName,
  });

  @override
  State<BusArrivalScreen> createState() => _BusArrivalScreenState();
}

class _BusArrivalScreenState extends State<BusArrivalScreen> {
  final BusArrivalService _arrivalService = BusArrivalService();
  final TtsService _ttsService = TtsService.instance;

  BusArrival? _arrival;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _ttsService.initialize();
    await _ttsService.speak("버스 정류장에 도착했습니다. 도착 정보를 확인합니다.");

    _arrivalService.onArrivalUpdate = (arrival) {
      if (!mounted) return;
      setState(() {
        _arrival = arrival;
        _isLoading = false;
        _errorMessage = arrival == null ? "도착 정보를 불러올 수 없습니다" : null;
      });

      // TTS로 도착 정보 안내
      if (arrival != null) {
        _ttsService.speak("${arrival.busNumber}번 버스, ${arrival.statusMsg}");
      }
    };

    await _arrivalService.startTracking(widget.busNumber, widget.stationName);
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _arrivalService.refresh();
  }

  @override
  void dispose() {
    _arrivalService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('버스 도착 정보', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 정류장 정보
                _buildStationCard(),
                const SizedBox(height: 24),

                // 버스 도착 정보
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.blue),
                  )
                else if (_errorMessage != null)
                  _buildErrorCard()
                else if (_arrival != null)
                  _buildArrivalCard(),

                const SizedBox(height: 24),

                // 새로고침 안내
                const Center(
                  child: Text(
                    '1분마다 자동 갱신됩니다\n아래로 당겨서 수동 갱신',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue, size: 24),
              SizedBox(width: 8),
              Text('정류장', style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.stationName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrivalCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 버스 번호
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
                  _arrival!.busNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.directions_bus, color: Colors.blue, size: 28),
            ],
          ),
          const SizedBox(height: 20),

          // 도착 예정
          Row(
            children: [
              const Icon(Icons.access_time, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              Text(
                _arrival!.statusMsg,
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 차량 번호
          if (_arrival!.plateNo.isNotEmpty)
            Row(
              children: [
                const Icon(
                  Icons.confirmation_number,
                  color: Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '차량번호: ${_arrival!.plateNo}',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
