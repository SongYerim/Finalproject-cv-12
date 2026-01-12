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

### VScode interpreter 경로 설정 오류 -> 해결
현재 최상단 폴더를 기준으로 venv 파일을 찾는데 현재 SIDAE/sidae-server 안에 venv 가 있어서 인터프리터가 찾지 못함
직접 경로를 지정해도 안되는 경우 SIDAE 폴더 안에 .vscode 폴더 생성 그리고 settings.json 파일을 만들어
setting.json 에 아래 코드를 입력해주면 됨
{
    "python.defaultInterpreterPath": "${workspaceFolder}/sidae-server/venv/bin/python",
    "python.terminal.activateEnvironment": true
}

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
│   │   ├── config.py         # 환경변수 로드
│   │   └── events.py         # 서버 시작/종료 시 실행될 이벤트
│   ├── routers/
│   │   └── v1/
│   │       ├── route.py      # 경로 계산 API 엔드포인트
│   │       └── search.py     # 검색 API 엔드포인트
│   ├── schemas/
│   │   └── common.py         # 데이터 검증 및 입출력 모델 (Pydantic)
│   ├── services/
│   │   ├── naver_api.py      # STT 목적지명을 좌표값으로 변환
│   │   ├── path_parser.py    # 핵심 파싱 로직
│   │   └── sk_api.py         # 경로 탐색
│   └── main.py               # FastAPI 앱 초기화 및 라우터 등록, 미들웨어 설정
├── utils/                    # 거리 계산 유틸리티, 텍스트 정규화
├── venv
├── .env                      # API Key 저장
├── pyproject.toml
├── README.md
└── requirements.txt          # 패키지 목록 (PyTorch CPU URL 포함)
```

