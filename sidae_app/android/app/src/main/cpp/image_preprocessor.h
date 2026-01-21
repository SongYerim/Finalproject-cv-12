#ifndef IMAGE_PREPROCESSOR_H
#define IMAGE_PREPROCESSOR_H

#include <cstdint>
#include <cstddef>

namespace image_preprocessor {

// YUV420 → RGB 변환 (90도 회전 포함)
void convertYUV420ToRGB(
    const uint8_t* yPlane, int yStride,
    const uint8_t* uPlane, int uStride,
    const uint8_t* vPlane, int vStride,
    int srcWidth, int srcHeight,
    uint8_t* rgbOutput, int outWidth, int outHeight,
    bool rotate90
);

// 리사이즈 및 패딩 (640x640으로)
void resizeAndPadTo640(
    const uint8_t* rgbInput, int srcWidth, int srcHeight,
    uint8_t* rgbOutput  // 640x640x3 출력
);

// RGB Uint8 → Float32 정규화 (0-255 → 0.0-1.0)
void normalizeRGBToFloat32(
    const uint8_t* rgbInput,  // 640x640x3
    float* floatOutput,       // 640x640x3
    int width, int height
);

// 통합 전처리 함수
void preprocessYUV420ToFloat32Internal(
    const uint8_t* yPlane, int yStride,
    const uint8_t* uPlane, int uStride,
    const uint8_t* vPlane, int vStride,
    int srcWidth, int srcHeight,
    float* output,  // 640x640x3 Float32 배열
    bool rotate90
);

} // namespace image_preprocessor

#endif // IMAGE_PREPROCESSOR_H
