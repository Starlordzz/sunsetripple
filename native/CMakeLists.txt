cmake_minimum_required(VERSION 3.10)
project(sunset_ripple_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(sunset_ripple_native SHARED
    src/audio_dsp.cpp
)

target_include_directories(sunset_ripple_native PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

if (MSVC)
    target_compile_options(sunset_ripple_native PRIVATE /W4 /O2)
else()
    target_compile_options(sunset_ripple_native PRIVATE -Wall -Wextra -O3 -fPIC)
endif()

