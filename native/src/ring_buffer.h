#ifndef SUNSET_RING_BUFFER_H
#define SUNSET_RING_BUFFER_H

#include <stdint.h>
#include <stddef.h>
#include <atomic>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT __attribute__((visibility("default")))
#endif

/// High-Performance Lock-Free Single-Producer Single-Consumer (SPSC) Audio Ring Buffer.
typedef struct SunsetRingBuffer {
    uint8_t* buffer;
    size_t capacity;
    std::atomic<size_t> head;
    std::atomic<size_t> tail;
} SunsetRingBuffer;

FFI_EXPORT SunsetRingBuffer* sunset_ring_buffer_create(size_t capacity);
FFI_EXPORT void sunset_ring_buffer_free(SunsetRingBuffer* rb);
FFI_EXPORT size_t sunset_ring_buffer_write(SunsetRingBuffer* rb, const uint8_t* data, size_t length);
FFI_EXPORT size_t sunset_ring_buffer_read(SunsetRingBuffer* rb, uint8_t* out_data, size_t length);
FFI_EXPORT size_t sunset_ring_buffer_available_read(const SunsetRingBuffer* rb);
FFI_EXPORT size_t sunset_ring_buffer_available_write(const SunsetRingBuffer* rb);
FFI_EXPORT void sunset_ring_buffer_clear(SunsetRingBuffer* rb);

#ifdef __cplusplus
}
#endif

#endif // SUNSET_RING_BUFFER_H

