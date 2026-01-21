#ifndef IMAGE_PREPROCESSOR_FFI_H
#define IMAGE_PREPROCESSOR_FFI_H

#include <cstdint>
#include <cstdbool>

#ifdef __cplusplus
extern "C" {
#endif

// FFI C 인터페이스: YUV420 → RGB → 리사이즈 → 패딩 → Float32 정규화
// 
// Parameters:
//   yPlane, uPlane, vPlane: YUV420 평면 데이터 포인터
//   yStride, uStride, vStride: 각 평면의 stride (bytesPerRow)
//   srcWidth, srcHeight: 원본 이미지 크기
//   output: 출력 Float32 배열 (640x640x3 = 1,228,800 floats)
//   rotate90: 90도 회전 여부
void preprocessYUV420ToFloat32(
    const uint8_t* yPlane, int yStride,
    const uint8_t* uPlane, int uStride,
    const uint8_t* vPlane, int vStride,
    int srcWidth, int srcHeight,
    float* output,
    bool rotate90
);

#ifdef __cplusplus
}
#endif

#endif // IMAGE_PREPROCESSOR_FFI_H
