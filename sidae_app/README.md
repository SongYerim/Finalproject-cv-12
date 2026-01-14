# 모바일 개발환경 세팅

## 1. 개발자 설정 열기
### Windows:
'''
start ms-settings:developers
'''

## 2. 앱 폴더로 이동하여 의존성 패키지 설치
```
cd sidae_app
flutter pub get
```

## 3. 앱 실행하기
1. 메인 파일 열기: **lib/main.dart** 파일 열기
2. 디바이스 선택: VS Code 우측 하단 상태 표시줄에서 **실행할 기기(예: Pixel 6 Pro, iPhone 15 등) 선택**
3. 디버깅 시작: 키보드의 **F5**를 누르거나, 상단 메뉴의 **[Run] -> [Start Debugging]** 선택

## sidae_app 구조 (Frontend)
sidae_app/                          # 프로젝트의 최상위 루트 폴더 (앱 이름)
├── android/                        # 안드로이드 네이티브 프로젝트 폴더 (Android Studio 프로젝트 구조)
├── build/                          # (자동 생성) 빌드 결과물이 저장되는 곳. 절대 직접 수정하지 않음
├── ios/                            # iOS 네이티브 프로젝트 폴더 (Xcode 프로젝트 구조)
├── lib/                            # ★ 가장 중요! 우리가 작성하는 실제 Dart 코드가 모여있는 곳
│   ├── models/                     # 데이터 구조(Class)를 정의하는 폴더 (예: User, Product 등)
│   ├── screens/                    # 사용자에게 보여지는 화면(UI) 파일들을 모아둔 폴더
│   ├── services/                   # API 호출, DB 통신 등 비즈니스 로직을 처리하는 폴더
│   └── main.dart                   # 앱의 시작점(Entry Point). 앱 실행 시 가장 먼저 켜지는 파일
├── linux/                          # 리눅스 데스크톱 앱 빌드 설정 폴더
├── macos/                          # macOS 데스크톱 앱 빌드 설정 폴더
├── test/                           # 테스트 코드를 작성하는 폴더
│   └── widget_test.dart            # 위젯(UI) 테스트 예제 파일
├── web/                            # 웹 앱(Web App) 빌드 설정 폴더
├── windows/                        # 윈도우 데스크톱 앱 빌드 설정 폴더
├── analysis_options.yaml           
├── pubspec.lock                    
├── pubspec.yaml                    
└── README.md                       