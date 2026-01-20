#include "image_preprocessor.h"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace image_preprocessor {

// YUV → RGB 변환 상수
static constexpr float YUV_R_COEFF = 1.402f;
static constexpr float YUV_G_U_COEFF = -0.344136f;
static constexpr float YUV_G_V_COEFF = -0.714136f;
static constexpr float YUV_B_COEFF = 1.772f;
static constexpr float YUV_OFFSET = 128.0f;
static constexpr float INV_255 = 1.0f / 255.0f;

void convertYUV420ToRGB(
    const uint8_t* yPlane, int yStride,
    const uint8_t* uPlane, int uStride,
    const uint8_t* vPlane, int vStride,
    int srcWidth, int srcHeight,
    uint8_t* rgbOutput, int outWidth, int outHeight,
    bool rotate90) {
    
    for (int y = 0; y < srcHeight; y++) {
        for (int x = 0; x < srcWidth; x++) {
            // YUV 인덱스 계산
            int yIndex = y * yStride + x;
            int uvIndex = (y / 2) * uStride + (x / 2);
            
            uint8_t yValue = yPlane[yIndex];
            uint8_t uValue = uPlane[uvIndex];
            uint8_t vValue = vPlane[uvIndex];
            
            // YUV → RGB 변환
            int r = static_cast<int>(yValue + YUV_R_COEFF * (vValue - YUV_OFFSET));
            int g = static_cast<int>(yValue + YUV_G_U_COEFF * (uValue - YUV_OFFSET) + 
                                     YUV_G_V_COEFF * (vValue - YUV_OFFSET));
            int b = static_cast<int>(yValue + YUV_B_COEFF * (uValue - YUV_OFFSET));
            
            // Clamp to [0, 255]
            r = std::max(0, std::min(255, r));
            g = std::max(0, std::min(255, g));
            b = std::max(0, std::min(255, b));
            
            // 출력 좌표 계산 (90도 회전)
            int outX, outY;
            if (rotate90) {
                outX = srcHeight - 1 - y;
                outY = x;
            } else {
                outX = x;
                outY = y;
            }
            
            int outIndex = (outY * outWidth + outX) * 3;
            rgbOutput[outIndex] = static_cast<uint8_t>(r);
            rgbOutput[outIndex + 1] = static_cast<uint8_t>(g);
            rgbOutput[outIndex + 2] = static_cast<uint8_t>(b);
        }
    }
}

void resizeAndPadTo640(
    const uint8_t* rgbInput, int srcWidth, int srcHeight,
    uint8_t* rgbOutput) {
    
    constexpr int targetSize = 640;
    
    // 스케일 계산 (긴 변을 640으로)
    bool isWidthLonger = srcWidth >= srcHeight;
    int longSide = isWidthLonger ? srcWidth : srcHeight;
    float scale = static_cast<float>(targetSize) / static_cast<float>(longSide);
    
    int newWidth = isWidthLonger ? targetSize : static_cast<int>(srcWidth * scale + 0.5f);
    int newHeight = isWidthLonger ? static_cast<int>(srcHeight * scale + 0.5f) : targetSize;
    
    int padX = (targetSize - newWidth) / 2;
    int padY = (targetSize - newHeight) / 2;
    
    // 출력 버퍼를 0으로 초기화 (검은색 패딩)
    std::memset(rgbOutput, 0, targetSize * targetSize * 3);
    
    // Nearest-neighbor 리사이즈
    for (int y = 0; y < newHeight; y++) {
        int srcY = static_cast<int>(y / scale);
        srcY = std::max(0, std::min(srcHeight - 1, srcY));
        
        for (int x = 0; x < newWidth; x++) {
            int srcX = static_cast<int>(x / scale);
            srcX = std::max(0, std::min(srcWidth - 1, srcX));
            
            int srcIndex = (srcY * srcWidth + srcX) * 3;
            int dstIndex = ((padY + y) * targetSize + (padX + x)) * 3;
            
            rgbOutput[dstIndex] = rgbInput[srcIndex];
            rgbOutput[dstIndex + 1] = rgbInput[srcIndex + 1];
            rgbOutput[dstIndex + 2] = rgbInput[srcIndex + 2];
        }
    }
}

void normalizeRGBToFloat32(
    const uint8_t* rgbInput,
    float* floatOutput,
    int width, int height) {
    
    int pixelCount = width * height;
    for (int i = 0; i < pixelCount; i++) {
        int byteIndex = i * 3;
        floatOutput[byteIndex] = rgbInput[byteIndex] * INV_255;
        floatOutput[byteIndex + 1] = rgbInput[byteIndex + 1] * INV_255;
        floatOutput[byteIndex + 2] = rgbInput[byteIndex + 2] * INV_255;
    }
}

void preprocessYUV420ToFloat32Internal(
    const uint8_t* yPlane, int yStride,
    const uint8_t* uPlane, int uStride,
    const uint8_t* vPlane, int vStride,
    int srcWidth, int srcHeight,
    float* output,
    bool rotate90) {
    
    constexpr int targetSize = 640;
    
    // 회전 후 크기
    int rotatedWidth = rotate90 ? srcHeight : srcWidth;
    int rotatedHeight = rotate90 ? srcWidth : srcHeight;
    
    // 중간 버퍼: 회전된 RGB (최대 1920x1080x3)
    constexpr int maxIntermediateSize = 1920 * 1080 * 3;
    uint8_t* rgbRotated = new uint8_t[maxIntermediateSize];
    
    // 1. YUV → RGB 변환 (회전 포함)
    convertYUV420ToRGB(
        yPlane, yStride,
        uPlane, uStride,
        vPlane, vStride,
        srcWidth, srcHeight,
        rgbRotated, rotatedWidth, rotatedHeight,
        rotate90
    );
    
    // 2. 리사이즈 및 패딩 (640x640)
    uint8_t* rgb640 = new uint8_t[targetSize * targetSize * 3];
    resizeAndPadTo640(rgbRotated, rotatedWidth, rotatedHeight, rgb640);
    
    // 3. Float32 정규화
    normalizeRGBToFloat32(rgb640, output, targetSize, targetSize);
    
    // 메모리 해제
    delete[] rgbRotated;
    delete[] rgb640;
}

} // namespace image_preprocessor
