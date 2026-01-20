#include "image_preprocessor_ffi.h"
#include "image_preprocessor.h"

extern "C" {

void preprocessYUV420ToFloat32(
    const uint8_t* yPlane, int yStride,
    const uint8_t* uPlane, int uStride,
    const uint8_t* vPlane, int vStride,
    int srcWidth, int srcHeight,
    float* output,
    bool rotate90) {
    
    image_preprocessor::preprocessYUV420ToFloat32Internal(
        yPlane, yStride,
        uPlane, uStride,
        vPlane, vStride,
        srcWidth, srcHeight,
        output,
        rotate90
    );
}

} // extern "C"
