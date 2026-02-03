import 'dart:async';
import 'package:flutter/services.dart';

/// 공유 EventChannel 서비스 (싱글톤)
///
/// 여러 화면(NavigationService, 8.dart 등)에서 동일한 EventChannel을 사용할 때,
/// 각각 receiveBroadcastStream()을 호출하면 네이티브 측 eventSink가 충돌합니다.
///
/// 이 서비스는 하나의 스트림을 생성하고 asBroadcastStream()으로 변환하여
/// 여러 리스너가 구독/취소해도 네이티브 onCancel이 호출되지 않도록 합니다.
class SharedEventChannel {
  // 싱글톤 인스턴스
  static final SharedEventChannel _instance = SharedEventChannel._internal();
  static SharedEventChannel get instance => _instance;

  // private 생성자
  SharedEventChannel._internal();

  static const EventChannel _eventChannel = EventChannel(
    'com.ctrlcv.sidae_app/yolo_detections',
  );

  // 공유 브로드캐스트 스트림
  Stream<dynamic>? _broadcastStream;
  StreamSubscription<dynamic>? _baseSubscription;

  /// 공유 브로드캐스트 스트림 가져오기
  ///
  /// 처음 호출 시 receiveBroadcastStream()을 한 번만 호출하고,
  /// 이후에는 같은 브로드캐스트 스트림을 반환합니다.
  Stream<dynamic> get stream {
    if (_broadcastStream == null) {
      print('📡 [SharedEventChannel] 브로드캐스트 스트림 생성');
      _broadcastStream = _eventChannel
          .receiveBroadcastStream()
          .asBroadcastStream(
            onListen: (subscription) {
              print('📡 [SharedEventChannel] 리스너 추가됨');
            },
            onCancel: (subscription) {
              print('📡 [SharedEventChannel] 리스너 제거됨');
              // 스트림은 유지 - 다른 리스너가 있을 수 있음
            },
          );
    }
    return _broadcastStream!;
  }

  /// 스트림 완전 중지 (앱 종료 시에만 사용)
  void dispose() {
    _baseSubscription?.cancel();
    _baseSubscription = null;
    _broadcastStream = null;
    print('📡 [SharedEventChannel] 스트림 dispose');
  }
}
