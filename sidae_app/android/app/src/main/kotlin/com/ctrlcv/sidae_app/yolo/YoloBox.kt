package com.ctrlcv.sidae_app.yolo

/**
 * YOLO 객체 감지 결과를 담는 데이터 클래스
 * 
 * @param x1 바운딩 박스 좌상단 X 좌표 (원본 이미지 기준)
 * @param y1 바운딩 박스 좌상단 Y 좌표 (원본 이미지 기준)
 * @param x2 바운딩 박스 우하단 X 좌표 (원본 이미지 기준)
 * @param y2 바운딩 박스 우하단 Y 좌표 (원본 이미지 기준)
 * @param score 감지 신뢰도 (0.0 ~ 1.0)
 * @param classId 클래스 ID (라벨 인덱스)
 */
data class YoloBox(
    val x1: Float,
    val y1: Float,
    val x2: Float,
    val y2: Float,
    val score: Float,
    val classId: Int
) {
    /**
     * 바운딩 박스의 면적
     */
    val area: Float
        get() = (x2 - x1) * (y2 - y1)
    
    /**
     * 바운딩 박스의 너비
     */
    val width: Float
        get() = x2 - x1
    
    /**
     * 바운딩 박스의 높이
     */
    val height: Float
        get() = y2 - y1
    
    /**
     * 바운딩 박스의 중심 X 좌표
     */
    val centerX: Float
        get() = (x1 + x2) / 2f
    
    /**
     * 바운딩 박스의 중심 Y 좌표
     */
    val centerY: Float
        get() = (y1 + y2) / 2f
}
