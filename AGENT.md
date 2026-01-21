# AGENT.md

> AI 에이전트 및 개발자를 위한 프로젝트 가이드

## 프로젝트 개요

**SIDAE (시대)** - 시각장애인을 위한 음성 기반 대중교통 길안내 앱

**핵심 기능**: 음성 인식(STT), 음성 안내(TTS), GPS 경로 안내, 대중교통 경로 탐색

**기술 스택**
- 백엔드: FastAPI (Python), Uvicorn
- 프론트엔드: Flutter (Dart), Naver Map
- 외부 API: 네이버 검색/맵, SK TMAP

---

## 빠른 시작

### 백엔드
```bash
cd sidae-server/
python -m venv venv
.\venv\Scripts\activate          # Windows
source venv/bin/activate         # Mac/Linux
pip install -r requirements.txt
# .env 파일에 API 키 설정 필요
uvicorn app.main:app --reload
# 접속: http://localhost:8000/docs
```

### 프론트엔드
```bash
cd sidae_app/
flutter pub get
# .env 파일에 Naver Map Client ID 설정 필요
flutter run                      # 또는 VS Code에서 F5
```

---

## 프로젝트 구조

```
├── sidae-server/              # FastAPI 백엔드
│   ├── app/
│   │   ├── routers/v1/       # API 엔드포인트
│   │   ├── services/         # 외부 API 연동
│   │   ├── schemas/          # 데이터 모델
│   │   └── main.py
│   └── .env                  # API 키 (Git 제외!)
│
└── sidae_app/                 # Flutter 앱
    ├── lib/
    │   ├── screens/          # UI 화면 (1~5.dart)
    │   ├── services/         # API 통신
    │   └── models/           # 데이터 모델
    └── .env                  # 환경 변수
```

---

## 코드 스타일

### Python
- PEP 8 준수, `snake_case`, 타입 힌팅 필수
- 비동기: `async def` 사용

### Dart
- Effective Dart 준수, `camelCase`
- private: `_camelCase`

---

## Git 규칙

**커밋 형식**: `<타입>: <제목>`

**타입**: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

**예시**: `feat: 음성 인식 타임아웃 처리 추가`

---

## 보안

- `.env` 파일은 **절대 Git에 커밋 금지**
- API 키 노출 시 즉시 재발급
- 로그에 민감정보 출력 금지

---

## 핵심 API 응답

### RouteSegment (경로 구간)
```json
{
  "segment_index": 0,
  "move_type": "WALK|BUS|SUBWAY",
  "description": "도보 이동 (357m)",
  "step_description": ["[출발] 27m", "270m 이동"],
  "path_coordinates": [[lat, lng], ...],
  "distance": 357,
  "duration": 255
}
```

---

## 주요 파일

### 백엔드
- `app/routers/v1/route.py` - 경로 탐색 API
- `app/services/path_parser.py` - 경로 파싱 로직
- `app/schemas/common.py` - 데이터 모델

### 프론트엔드
- `lib/screens/1.dart` - 음성 인식
- `lib/screens/3.dart` - 지도 표시
- `lib/screens/4.dart` - 실시간 길안내
- `lib/services/api_service.dart` - API 통신
- `lib/models/route_model.dart` - 데이터 모델

---

## 자주 사용하는 작업

### API 응답 형식 변경
1. `schemas/common.py` 수정
2. `models/route_model.dart` 수정
3. `fromJson()` 메서드 업데이트

### 테스트
- 백엔드: `http://localhost:8000/docs` (Swagger UI)
- 앱: "테스트: route_data.json 로드" 버튼

---

## 문제 해결

- **모듈 import 오류**: 가상환경 활성화 확인
- **API 키 오류**: `.env` 파일 확인
- **음성 인식 안됨**: 마이크/위치 권한 확인
- **네이버 맵 오류**: Client ID 확인

---

**GitHub**: https://github.com/boostcampaitech8/pro-cv-finalproject-cv-12  
**API 문서**: http://localhost:8000/docs
