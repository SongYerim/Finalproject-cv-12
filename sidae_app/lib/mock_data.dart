// lib/mock_data.dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle; // 파일을 읽어오는 도구
import 'models/route_model.dart'; 

class MockData {
  // Future가 붙었습니다. (파일을 다 읽을 때까지 기다려야 함)
  static Future<List<RouteSegment>> loadRoutesFromFile() async {
    try {
      // 1. JSON 파일 내용을 읽어옵니다.
      final String jsonString = await rootBundle.loadString('assets/route_data.json');

      // 2. JSON 파싱
      final List<dynamic> jsonList = jsonDecode(jsonString);

      // 3. RouteSegment.fromJson()을 사용하여 변환 (API 방식과 동일)
      return jsonList
          .map((json) => RouteSegment.fromJson(json as Map<String, dynamic>))
          .toList();
      
    } catch (e) {
      print("파일 읽기 에러: $e");
      return []; // 에러 나면 빈 리스트 반환
    }
  }
}