# 백엔드 개발환경 세팅
## 1. 가상 환경 생성
```
cd sidae-server/
python -m venv venv # 최초 1회 실행
```

## 2. 가상 환경 활성화
### Windows:
```
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser # 최초 1회 실행
.\venv\Scripts\activate
```
### Mac/Linux:
```
source venv/bin/activate
```

## 3. 패키지 설치
```
pip install -r requirements.txt
```

## 4. sidae-server/.env 파일 생성
```
# 최초 1회 실행
NCP_MAPS_CLIENT_ID=여기에 NAVER CLOUD PLATFORM Client ID
NCP_MAPS_CLIENT_SECRET=여기에 NAVER CLOUD PLATFORM Client Secret

NAVER_SEARCH_CLIENT_ID=여기에 NAVER Developers Client ID
NAVER_SEARCH_CLIENT_SECRET=여기에 NAVER Developers Client Secret

SK_API_KEY=여기에 SK open API appKey
```

## 5. 백엔드 구동
```
uvicorn app.main:app --reload
```
구동 이후 `http://localhost:8000/docs`로 접속하여 Swagger UI를 통해 api 테스트

## sidae-server 구조 (Backend)
```
sidae-server/
├── app/
│   ├── AI/                   # 버스 번호 인식 및 OCR 관련 서버 측 로직 저장소
│   ├── core/
│   │   └── config.py         # 환경변수 로드
│   ├── routers/
│   │   ├── route.py          # 경로 계산 API 엔드포인트
│   │   └── search.py         # 검색 API 엔드포인트
│   ├── schemas/
│   │   ├── route_dto.py          # 경로 관련 입출력 모델
│   │   └── search_dto.py         # 검색 관련 입출력 모델
│   ├── services/
│   │   ├── naver_common.py         # Naver 공통 DTO/Error
│   │   ├── naver_geo_service.py    # Naver Geocoding
│   │   ├── naver_place_service.py  # 위치 정보 Orchestration (Facade)
│   │   ├── naver_search_service.py # Naver Local Search
│   │   ├── path_parser.py          # 경로 파싱 로직
│   │   ├── route_service.py        # 경로 비즈니스 로직
│   │   └── sk_api.py               # TMAP 경로 탐색
│   ├── dependencies.py       # 의존성 주입 (DI) 정의
│   └── main.py               # FastAPI 앱 초기화 및 라우터 등록, 로깅 설정
├── .env                      # API Key 저장
├── pyproject.toml
├── README.md
└── requirements.txt          # 패키지 목록 (PyTorch CPU URL 포함)
```

