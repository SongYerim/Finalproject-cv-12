import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:camera/camera.dart';

/// FFI 함수 타입 정의 (top-level)
typedef NativePreprocessFunction =
    Void Function(
      Pointer<Uint8> yPlane,
      Int32 yStride,
      Pointer<Uint8> uPlane,
      Int32 uStride,
      Pointer<Uint8> vPlane,
      Int32 vStride,
      Int32 srcWidth,
      Int32 srcHeight,
      Pointer<Float> output,
      Bool rotate90,
    );

typedef DartPreprocessFunction =
    void Function(
      Pointer<Uint8> yPlane,
      int yStride,
      Pointer<Uint8> uPlane,
      int uStride,
      Pointer<Uint8> vPlane,
      int vStride,
      int srcWidth,
      int srcHeight,
      Pointer<Float> output,
      bool rotate90,
    );

/// 네이티브 이미지 전처리 FFI 바인딩
/// C++ 라이브러리를 통해 YUV420 → RGB → 리사이즈 → 패딩 → Float32 변환 수행
class ImagePreprocessorFFI {
  static DynamicLibrary? _lib;
  static bool _initialized = false;
  static bool _available = false;
  static DartPreprocessFunction? _preprocessFunc;

  /// FFI 초기화
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libimage_preprocessor.so');
        _preprocessFunc = _lib!
            .lookup<NativeFunction<NativePreprocessFunction>>(
              'preprocessYUV420ToFloat32',
            )
            .asFunction<DartPreprocessFunction>();
        _available = true;
      }
    } catch (e) {
      print('⚠️ [FFI] 네이티브 라이브러리 로드 실패: $e');
      _available = false;
    }
  }

  /// 네이티브 전처리 사용 가능 여부
  static bool isAvailable() {
    if (!_initialized) initialize();
    return _available && _preprocessFunc != null;
  }

  /// 이미지 전처리 수행 (바이트 데이터 직접 사용, TransferableTypedData 최적화)
  ///
  /// [yPlaneBytes] Y 평면 바이트 데이터
  /// [yStride] Y 평면 stride
  /// [uPlaneBytes] U 평면 바이트 데이터
  /// [uStride] U 평면 stride
  /// [vPlaneBytes] V 평면 바이트 데이터
  /// [vStride] V 평면 stride
  /// [width] 이미지 너비
  /// [height] 이미지 높이
  /// [rotate90] 90도 회전 여부
  ///
  /// Returns: Float32List (640x640x3 = 1,228,800 floats)
  static Float32List? preprocessFromBytes(
    Uint8List yPlaneBytes,
    int yStride,
    Uint8List uPlaneBytes,
    int uStride,
    Uint8List vPlaneBytes,
    int vStride,
    int width,
    int height, {
    bool rotate90 = true,
  }) {
    if (!isAvailable()) {
      return null;
    }

    try {
      // YUV 평면 데이터를 네이티브 메모리에 복사
      final yPlanePtr = malloc<Uint8>(yPlaneBytes.length);
      yPlanePtr.asTypedList(yPlaneBytes.length).setAll(0, yPlaneBytes);

      final uPlanePtr = malloc<Uint8>(uPlaneBytes.length);
      uPlanePtr.asTypedList(uPlaneBytes.length).setAll(0, uPlaneBytes);

      final vPlanePtr = malloc<Uint8>(vPlaneBytes.length);
      vPlanePtr.asTypedList(vPlaneBytes.length).setAll(0, vPlaneBytes);

      // 출력 버퍼 할당 (640x640x3 = 1,228,800 floats)
      const int outputSize = 640 * 640 * 3;
      final outputPtr = malloc<Float>(outputSize);

      // 네이티브 함수 호출
      _preprocessFunc!(
        yPlanePtr,
        yStride,
        uPlanePtr,
        uStride,
        vPlanePtr,
        vStride,
        width,
        height,
        outputPtr,
        rotate90,
      );

      // 결과를 Float32List로 복사
      final result = Float32List.fromList(
        outputPtr.asTypedList(outputSize).toList(),
      );

      // 메모리 해제
      malloc.free(yPlanePtr);
      malloc.free(uPlanePtr);
      malloc.free(vPlanePtr);
      malloc.free(outputPtr);

      return result;
    } catch (e, stackTrace) {
      print('⚠️ [FFI] 전처리 실패: $e');
      print('⚠️ [FFI] StackTrace: $stackTrace');
      return null;
    }
  }

  /// 이미지 전처리 수행 (CameraImage 버전, 호환성 유지)
  ///
  /// [cameraImage] 카메라 이미지 (YUV420)
  /// [rotate90] 90도 회전 여부
  ///
  /// Returns: Float32List (640x640x3 = 1,228,800 floats)
  static Float32List? preprocess(
    CameraImage cameraImage, {
    bool rotate90 = true,
  }) {
    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];

    return preprocessFromBytes(
      yPlane.bytes,
      yPlane.bytesPerRow,
      uPlane.bytes,
      uPlane.bytesPerRow,
      vPlane.bytes,
      vPlane.bytesPerRow,
      cameraImage.width,
      cameraImage.height,
      rotate90: rotate90,
    );
  }
}
