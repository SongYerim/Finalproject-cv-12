cmake_minimum_required(VERSION 3.22.1)
project(image_preprocessor)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 최적화 플래그 (Android NDK는 -march=native를 지원하지 않으므로 제거)
# Android는 크로스 컴파일이므로 타겟 아키텍처는 자동으로 설정됨
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")

add_library(image_preprocessor SHARED
    image_preprocessor_ffi.cpp
    image_preprocessor.cpp
)

target_include_directories(image_preprocessor PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)
