import 'dart:convert';
import 'dart:io'; // Platform 확인용
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/route_model.dart';

class ApiService {
  // 에뮬레이터 환경에 따른 주소 설정
  static final String baseUrl = Platform.isAndroid 
      ? 'http://10.0.2.2:8000/v1' 
      // : 'http://127.0.0.1:8000/v1';
      : 'http://192.168.219.103:8000/v1';

  // 1. 목적지 검색 (텍스트 -> 좌표)
  Future<Map<String, dynamic>?> searchPlace(String query) async {
    final url = Uri.parse('$baseUrl/search/place?query=$query');
    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        // 한글 깨짐 방지를 위한 utf8 decoding
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        debugPrint('검색 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('서버 연결 오류 (Search): $e');
      return null;
    }
  }

  // 2. 경로 탐색 (좌표 -> 경로 리스트) [cite: 60]
  Future<List<RouteSegment>> getRoute(
      double startLat, double startLng, double endLat, double endLng) async {
    final url = Uri.parse(
      '$baseUrl/route/search?start_lat=$startLat&start_lng=$startLng&end_lat=$endLat&end_lng=$endLng'
    );
    
    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(utf8.decode(response.bodyBytes));
        // JSON 리스트를 RouteSegment 객체 리스트로 변환
        return jsonData.map((item) => RouteSegment.fromJson(item)).toList();
      } else {
        debugPrint('경로 탐색 실패: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('서버 연결 오류 (Route): $e');
      return [];
    }
  }
}