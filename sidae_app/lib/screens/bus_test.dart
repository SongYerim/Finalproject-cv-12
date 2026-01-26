import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class BusApiTestScreen extends StatefulWidget {
  const BusApiTestScreen({super.key});

  @override
  State<BusApiTestScreen> createState() => _BusApiTestScreenState();
}

class _BusApiTestScreenState extends State<BusApiTestScreen> {
  final TextEditingController _busNumberController = TextEditingController();
  final TextEditingController _stationNameController = TextEditingController();
  final TextEditingController _vehIdController = TextEditingController();

  String _arrivalResponse = '';
  String _locationResponse = '';
  bool _isLoadingArrival = false;
  bool _isLoadingLocation = false;

  // ⚠️ 핸드폰에서 테스트하려면 데스크탑의 로컬 IP 주소로 변경하세요!
  // Windows: ipconfig 실행 -> IPv4 주소 확인
  // 현재 설정: 192.168.0.15 (데스크탑 IP)
  static const String baseUrl = 'http://192.168.0.15:8000';

  @override
  void dispose() {
    _busNumberController.dispose();
    _stationNameController.dispose();
    _vehIdController.dispose();
    super.dispose();
  }

  Future<void> _getArrivalInfo() async {
    final busNumber = _busNumberController.text.trim();
    final stationName = _stationNameController.text.trim();

    if (busNumber.isEmpty || stationName.isEmpty) {
      setState(() {
        _arrivalResponse = '❌ 버스 번호와 정류장 이름을 모두 입력해주세요.';
      });
      return;
    }

    setState(() {
      _isLoadingArrival = true;
      _arrivalResponse = '';
    });

    try {
      final url = Uri.parse(
        '$baseUrl/bus/arrival?bus_number=$busNumber&station_name=$stationName',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));

        // veh_id 자동 입력
        if (data['veh_id'] != null) {
          _vehIdController.text = data['veh_id'];
        }

        setState(() {
          _arrivalResponse =
              '''
✅ 조회 성공!

🚌 버스 번호: ${data['bus_number']}
📍 정류장: ${data['station_name']}
⏰ 도착 정보: ${data['status_msg']}
🚗 차량 번호: ${data['plate_no']}
🆔 차량 ID: ${data['veh_id']}
#️⃣ 정류장 순번: ${data['station_seq']}
''';
        });
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _arrivalResponse =
              '❌ 오류: ${errorData['detail'] ?? 'HTTP ${response.statusCode}'}';
        });
      }
    } catch (e) {
      setState(() {
        _arrivalResponse = '❌ 네트워크 오류: $e';
      });
    } finally {
      setState(() {
        _isLoadingArrival = false;
      });
    }
  }

  Future<void> _getBusLocation() async {
    final vehId = _vehIdController.text.trim();

    if (vehId.isEmpty) {
      setState(() {
        _locationResponse = '❌ 차량 고유 ID를 입력해주세요.';
      });
      return;
    }

    setState(() {
      _isLoadingLocation = true;
      _locationResponse = '';
    });

    try {
      final url = Uri.parse('$baseUrl/bus/location?veh_id=$vehId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _locationResponse =
              '''
✅ 위치 조회 성공!

🆔 차량 ID: ${data['veh_id']}
📍 경도 (tmX): ${data['tmX']}
📍 위도 (tmY): ${data['tmY']}
🕐 수집 시간: ${data['data_tm'] ?? 'N/A'}
''';
        });
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _locationResponse =
              '❌ 오류: ${errorData['detail'] ?? 'HTTP ${response.statusCode}'}';
        });
      }
    } catch (e) {
      setState(() {
        _locationResponse = '❌ 네트워크 오류: $e';
      });
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _fillExample() {
    _busNumberController.text = '1711';
    _stationNameController.text = '신교동';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '버스 API 테스트',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF667eea),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 버스 도착 정보 섹션
            _buildSectionTitle('🚌 버스 도착 정보 조회'),
            const SizedBox(height: 16),
            _buildCard(
              child: Column(
                children: [
                  TextField(
                    controller: _busNumberController,
                    decoration: const InputDecoration(
                      labelText: '버스 번호',
                      hintText: '예: 1711',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.directions_bus),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stationNameController,
                    decoration: const InputDecoration(
                      labelText: '정류장 이름',
                      hintText: '예: 신교동',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _fillExample,
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('예제 데이터'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoadingArrival ? null : _getArrivalInfo,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667eea),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _isLoadingArrival
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  '조회',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  if (_arrivalResponse.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildResponseBox(_arrivalResponse),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 버스 위치 조회 섹션
            _buildSectionTitle('📍 실시간 버스 위치 조회'),
            const SizedBox(height: 16),
            _buildCard(
              child: Column(
                children: [
                  TextField(
                    controller: _vehIdController,
                    decoration: const InputDecoration(
                      labelText: '차량 고유 ID',
                      hintText: '도착 정보 조회 후 자동 입력됩니다',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.confirmation_number),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoadingLocation ? null : _getBusLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF764ba2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isLoadingLocation
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              '위치 조회',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  if (_locationResponse.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildResponseBox(_locationResponse),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2d3748),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: child,
    );
  }

  Widget _buildResponseBox(String text) {
    final isError = text.startsWith('❌');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFfff5f5) : const Color(0xFFf0fdf4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFfca5a5) : const Color(0xFF86efac),
          width: 2,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: isError ? const Color(0xFFdc2626) : const Color(0xFF15803d),
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
