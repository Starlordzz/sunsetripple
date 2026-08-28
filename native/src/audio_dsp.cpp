#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define FFI_EXPORT __declspec(dllexport)
#else
/* 见 ring_buffer.h：Apple 平台静态链接 + dead_strip 需要 `used`。 */
#define FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

/// High-Performance C/C++ Multi-Stream 16-bit PCM Linear Mixer with SIMD / Saturation.
FFI_EXPORT void sunset_mix_pcm_streams(
    const int16_t* const* input_streams,
    int stream_count,
    int sample_count,
    int16_t* output_buffer
) {
    if (!input_streams || stream_count <= 0 || !output_buffer || sample_count <= 0) {
        return;
    }

    if (stream_count == 1) {
        memcpy(output_buffer, input_streams[0], sample_count * sizeof(int16_t));
        return;
    }

    for (int i = 0; i < sample_count; ++i) {
        int32_t sum = 0;
        for (int s = 0; s < stream_count; ++s) {
            sum += input_streams[s][i];
        }

        // Saturation clamping [-32768, 32767]
        if (sum > 32767) {
            output_buffer[i] = 32767;
        } else if (sum < -32768) {
            output_buffer[i] = -32768;
        } else {
            output_buffer[i] = (int16_t)sum;
        }
    }
}

/// Calculate Root-Mean-Square (RMS) amplitude level [0.0 ~ 1.0].
FFI_EXPORT float sunset_calculate_rms(const int16_t* samples, int sample_count) {
    if (!samples || sample_count <= 0) return 0.0f;

    double sum_squares = 0.0;
    for (int i = 0; i < sample_count; ++i) {
        double val = (double)samples[i];
        sum_squares += val * val;
    }

    double mean = sum_squares / sample_count;
    double rms = 0.0;
    if (mean > 0.0) {
        // sqrt approximation
        double x = mean;
        double y = 1.0;
        for (int iter = 0; iter < 10; ++iter) {
            x = (x + y) / 2.0;
            y = mean / x;
        }
        rms = x;
    }

    float normalized = (float)(rms / 32767.0);
    if (normalized > 1.0f) normalized = 1.0f;
    return normalized;
}

#ifdef __cplusplus
}
#endif

