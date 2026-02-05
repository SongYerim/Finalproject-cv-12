# 시대 (Sidae) 앱 - 사용 기술 정리

시각장애인을 위한 대중교통 네비게이션 앱에서 사용된 모든 기술들을 정리한 문서입니다.

---

## 📍 1. GPS 및 위치 기반 서비스

### 1.1 실시간 위치 추적
- **패키지**: `geolocator: ^10.1.0`
- **기능**:
  - 0.5초 간격으로 GPS 좌표 수신 (High Accuracy 모드)
  - 현재 위치와 목표 지점 간 거리 계산
  - 경로상 가야 할 방향(bearing) 실시간 계산
- **사용처**: `NavigationService`, `RouteTracker`

### 1.2 경로 추적
- **기능**:
  - 경로상 지나간 점들 자동 마킹
  - 구간별 진행률 계산
  - 횡단보도/버스 정류장 근접 감지 (반경 15m)
- **사용처**: `CrosswalkDetector`, `BusStopDetector`, `ProximityDetector`

---

## 🎤 2. 음성 기술

### 2.1 TTS (Text-to-Speech)
- **패키지**: `flutter_tts: ^3.8.3`
- **기능**:
  - 한국어 음성 안내 (ko-KR)
  - 음성 속도 1.2배속 설정
  - 큐(Queue) 기반 순차 음성 재생
  - 완료 콜백 지원
- **사용처**: `TtsService`, 모든 화면에서 안내 멘트 출력

### 2.2 STT (Speech-to-Text)
- **패키지**: `speech_to_text: ^7.0.0`
- **네이티브**: Android `SpeechRecognizer` API
- **기능**:
  - 한국어 음성 인식
  - 부분 결과(Partial) 실시간 표시
  - 최종 결과 VLM 서버로 전송
- **사용처**: `SharedEventChannel`, Screen 4/5의 VLM 기능

### 2.3 Wake Word Detection (웨이크워드)
- **패키지**: `porcupine_flutter: ^4.0.0`
- **기능**:
  - "시대야" 음성 키워드 감지
  - 커스텀 한국어 키워드 파일 (`.ppn`) 사용
  - 한국어 모델 파일 (`.pv`) 사용
  - 백그라운드 상시 마이크 모니터링
- **사용처**: `PorcupineService`, Screen 4/5

---

## 📷 3. 카메라 및 영상 처리

### 3.1 네이티브 카메라
- **네이티브**: Android `CameraX` API
- **기능**:
  - 실시간 카메라 프리뷰 (CameraPreviewView)
  - JPEG 스냅샷 캡처
  - 이미지 크롭 (바운딩 박스 기준)
  - 카메라 세션 관리
- **사용처**: `MainActivity.kt`, 버스 인식 화면, 횡단보도 화면

### 3.2 YOLO 객체 인식
- **네이티브**: TensorFlow Lite (Android)
- **패키지**: `tflite_flutter: ^0.11.0`
- **모델**:
  - `yolo11n_float16.tflite` - YOLO11n FP16 경량 모델
  - `best_float16.tflite` - 커스텀 훈련 모델
  - `yolo11s_float16.tflite` - YOLO11s 모델
- **라벨**:
  - COCO 80개 클래스 (`coco_labels.txt`)
  - 커스텀: `Zebra_Cross`, `R_Signal`, `G_Signal`, `bus` (`custom_labels.txt`)
- **기능**:
  - 실시간 객체 감지 (약 15-30 FPS)
  - 바운딩 박스 오버레이
  - Confidence 필터링
  - NMS (Non-Maximum Suppression)
- **사용처**: `YoloInterpreter`, 버스 감지, 신호등/횡단보도 감지

---

## 🔊 4. 공간 음향 (Spatial Audio)

### 4.1 HRTF 기반 3D 오디오
- **패키지**: `audioplayers: ^6.0.0`
- **네이티브**: Android `Virtualizer` AudioEffect API
- **기능**:
  - 방향에 따른 좌/우 스테레오 패닝
  - 정면에 가까울수록 빠른 비프음
  - 거리에 따른 볼륨 조절
  - 각도 차이 기반 3D 위치화
- **사용처**: `SpatialAudioService`, 방향 안내

### 4.2 방향 안내 시스템
- **개념**:
  - `angleDiff = -90`: 완전히 왼쪽
  - `angleDiff = 0`: 정면 (양쪽 동일)
  - `angleDiff = +90`: 완전히 오른쪽
- **사용처**: 실시간 길안내 화면

---

## 📳 5. 진동 피드백 (Haptic Feedback)

### 5.1 Flutter Haptic
- **기능**:
  - 올바른 방향으로 향할 때 진동 피드백
  - 횡단보도/버스 정류장 도착 시 알림 진동
  - 도착 완료 진동
- **사용처**: `HapticFeedback.vibrate()`, 모든 네비게이션 화면

---

## 🧭 6. 방향 센서

### 6.1 Magnetometer (자기장 센서)
- **패키지**: `sensors_plus: ^6.1.0`
- **네이티브**: Android Sensor API
- **기능**:
  - 디바이스 방향 (Heading) 실시간 측정
  - 60Hz 센서 업데이트
  - EventChannel을 통한 Flutter-Native 통신
- **사용처**: `NavigationService`, 실시간 방향 표시

---

## 🗺️ 7. 지도 서비스

### 7.1 네이버 맵
- **패키지**: `flutter_naver_map: ^1.3.0`
- **기능**:
  - 경로 선(Path Overlay) 그리기
  - 현재 위치 마커
  - 경로 점(Circle Overlay) 표시
  - 카메라 경로 맞춤 (fitBounds)
- **사용처**: Screen 5 (경로 추적 지도)

### 7.2 Flutter Map
- **패키지**: `flutter_map: ^8.2.2`, `latlong2: ^0.9.1`
- **사용처**: 보조 지도 기능

---

## 🌐 8. 서버 통신

### 8.1 REST API
- **패키지**: `http: ^1.1.0`
- **기능**:
  - 버스 도착 정보 조회
  - 경로 검색 API 호출
  - 이미지 업로드 (Multipart)
- **사용처**: `ApiService`, `BusArrivalService`

### 8.2 OCR 서비스
- **기능**:
  - 버스 번호판 인식
  - 차량 번호 추출
  - 크롭된 이미지 전송
- **사용처**: `OcrService`

### 8.3 VLM (Vision Language Model) 서비스
- **기능**:
  - 태그 인식 (tag_)
  - 이미지 + 텍스트 프롬프트 전송
  - 시각 정보 음성 설명 생성
- **사용처**: `VlmService`, "시대야" 기능

---

## 🔧 9. 네이티브 통신

### 9.1 MethodChannel
- **채널명**: `com.ctrlcv.sidae_app/yolo_native`
- **기능**:
  - Flutter ↔ Kotlin 양방향 통신
  - 카메라 제어, YOLO 추론, 센서 데이터
  - STT 시작/중지
- **사용처**: 모든 네이티브 기능

### 9.2 EventChannel
- **채널명**: `com.ctrlcv.sidae_app/detection_events`
- **기능**:
  - 실시간 감지 결과 스트리밍
  - 센서 데이터 실시간 전송
  - STT 부분/최종 결과 전송
- **사용처**: `SharedEventChannel`

---

## 🚦 10. 신호등 상태 머신

### 10.1 State Machine 기반 신호 판정
- **기능**:
  - 최근 10개 프레임 버퍼링
  - 6개 이상 동일 신호 시 과반수 판정
  - 상태 전이: INIT → WAIT_FOR_GREEN → CROSSING
  - 상태별 음성 안내
- **사용처**: `SignalStateService`

---

## 📦 11. 기타 유틸리티

### 11.1 환경 변수 관리
- **패키지**: `flutter_dotenv: ^5.1.0`
- **기능**: API 키, 서버 URL 등 관리

### 11.2 권한 관리
- **패키지**: `permission_handler: ^11.0.1`
- **권한**: 카메라, 마이크, 위치

### 11.3 파일 시스템
- **패키지**: `path_provider: ^2.1.0`
- **기능**: 로컬 파일 저장/읽기

### 11.4 이미지 처리
- **패키지**: `image: ^4.0.0`
- **기능**: 이미지 크롭, 리사이즈

### 11.5 FFI (Foreign Function Interface)
- **패키지**: `ffi: ^2.1.0`
- **기능**: 네이티브 C/C++ 라이브러리 바인딩

---

## 📊 기술 스택 요약

| 카테고리 | 기술 | 용도 |
|---------|------|------|
| 위치 | Geolocator | GPS 추적, 거리/방향 계산 |
| 음성 출력 | Flutter TTS | 한국어 음성 안내 |
| 음성 입력 | Porcupine + STT | 웨이크워드 + 음성 인식 |
| 객체 인식 | TFLite + YOLO11 | 버스, 신호등, 횡단보도 감지 |
| 공간 음향 | Android Virtualizer | 3D 방향 음향 |
| 카메라 | CameraX | 실시간 영상 처리 |
| 지도 | 네이버 맵 | 경로 시각화 |
| 센서 | Magnetometer | 디바이스 방향 측정 |
| 진동 | HapticFeedback | 촉각 피드백 |
| AI 서버 | VLM + OCR | 이미지 분석, 텍스트 인식 |

---

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter (Dart)                           │
├─────────────────────────────────────────────────────────────┤
│  Screens (UI)                                               │
│  ├── SplashScreen, RouteSearchScreen                       │
│  ├── Screen4 (실시간 길안내)                                 │
│  ├── Screen5 (경로 추적 지도)                                │
│  ├── Screen6 (횡단보도 카메라)                               │
│  └── Screen7 (버스 도착 카메라)                              │
├─────────────────────────────────────────────────────────────┤
│  Services (비즈니스 로직)                                    │
│  ├── NavigationService (GPS + 센서)                         │
│  ├── TtsService (음성 출력)                                  │
│  ├── PorcupineService (웨이크워드)                           │
│  ├── SpatialAudioService (공간 음향)                         │
│  ├── RouteTracker (경로 추적)                                │
│  ├── BusDetectorService (버스 감지)                          │
│  ├── SignalStateService (신호등 상태)                        │
│  └── OcrService / VlmService (AI 서버 통신)                  │
├─────────────────────────────────────────────────────────────┤
│  Platform Channels                                          │
│  ├── MethodChannel (양방향 호출)                              │
│  └── EventChannel (실시간 스트리밍)                           │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                  Android Native (Kotlin)                    │
├─────────────────────────────────────────────────────────────┤
│  ├── CameraX (카메라 제어)                                   │
│  ├── TensorFlow Lite (YOLO 추론)                            │
│  ├── SpeechRecognizer (STT)                                 │
│  ├── Sensor API (Magnetometer)                              │
│  └── Virtualizer (공간 음향)                                 │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                    Backend Server                           │
├─────────────────────────────────────────────────────────────┤
│  ├── 경로 검색 API                                           │
│  ├── 버스 도착 정보 API                                       │
│  ├── OCR API (버스 번호 인식)                                 │
│  └── VLM API (시각 정보 분석)                                 │
└─────────────────────────────────────────────────────────────┘
```

---

*마지막 업데이트: 2026-02-05*
