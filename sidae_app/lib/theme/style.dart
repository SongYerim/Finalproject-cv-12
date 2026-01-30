import 'package:flutter/material.dart';

class AppTheme {
  // 고대비 테마 (검정 배경 + 노란색강조)
  static final ThemeData highContrastTheme = ThemeData(
    // 1. 기본 색상 팔레트
    scaffoldBackgroundColor: Colors.black,
    primaryColor: Colors.yellowAccent,
    canvasColor: Colors.black,
    dialogBackgroundColor: Colors.black,
    disabledColor: Colors.grey,

    // 2. 텍스트 테마 (기본적으로 모두 흰색/노란색)
    fontFamily: 'Pretendard', // 만약 폰트가 있다면
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 32,
      ),
      displayMedium: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 24,
      ),
      displaySmall: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 20,
      ),
      headlineMedium: TextStyle(
        color: Colors.yellowAccent,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
      bodyLarge: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(color: Colors.white, fontSize: 16),
      labelLarge: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ), // 버튼 텍스트용 (배경이 노랑일 때)
    ),

    // 3. 앱바 테마
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: Colors.yellowAccent,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.yellowAccent, size: 28),
      titleTextStyle: TextStyle(
        color: Colors.yellowAccent,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    ),

    // 4. 아이콘 테마
    iconTheme: const IconThemeData(color: Colors.yellowAccent, size: 28),

    // 5. 버튼 테마
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.yellowAccent, // 버튼 배경 노랑
        foregroundColor: Colors.black, // 글자 검정
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white, width: 2), // 흰색 테두리로 구분감
        ),
        elevation: 4,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.yellowAccent,
        side: const BorderSide(color: Colors.yellowAccent, width: 2),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    // 6. 카드 테마 (컨테이너 대용)
    cardTheme: CardThemeData(
      color: Colors.black,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(
          color: Colors.yellowAccent,
          width: 2,
        ), // 노란 테두리 필수
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    ),

    // 7. Divider
    dividerTheme: const DividerThemeData(color: Colors.white54, thickness: 1),
    colorScheme:
        ColorScheme.fromSwatch(
          primarySwatch: Colors.yellow,
          brightness: Brightness.dark,
        ).copyWith(
          secondary: Colors.cyanAccent, // 보조 강조색
          surface: Colors.black,
        ),
  );
}
