#include "ring_buffer.h"
#include <stdlib.h>
#include <string.h>
#include <algorithm>

extern "C" {

SunsetRingBuffer* sunset_ring_buffer_create(size_t capacity) {
    if (capacity == 0) capacity = 65536; // default 64KB
    SunsetRingBuffer* rb = (SunsetRingBuffer*)malloc(sizeof(SunsetRingBuffer));
    if (!rb) return NULL;

    rb->buffer = (uint8_t*)malloc(capacity);
    if (!rb->buffer) {
        free(rb);
        return NULL;
    }

    rb->capacity = capacity;
    rb->head.store(0, std::memory_order_relaxed);
    rb->tail.store(0, std::memory_order_relaxed);
    return rb;
}

void sunset_ring_buffer_free(SunsetRingBuffer* rb) {
    if (!rb) return;
    if (rb->buffer) free(rb->buffer);
    free(rb);
}

size_t sunset_ring_buffer_available_write(const SunsetRingBuffer* rb) {
    if (!rb) return 0;
    size_t head = rb->head.load(std::memory_order_acquire);
    size_t tail = rb->tail.load(std::memory_order_acquire);
    if (head >= tail) {
        return rb->capacity - (head - tail) - 1;
    } else {
        return tail - head - 1;
    }
}

size_t sunset_ring_buffer_available_read(const SunsetRingBuffer* rb) {
    if (!rb) return 0;
    size_t head = rb->head.load(std::memory_order_acquire);
    size_t tail = rb->tail.load(std::memory_order_acquire);
    if (head >= tail) {
        return head - tail;
    } else {
        return rb->capacity - (tail - head);
    }
}

size_t sunset_ring_buffer_write(SunsetRingBuffer* rb, const uint8_t* data, size_t length) {
    if (!rb || !data || length == 0) return 0;

    size_t avail = sunset_ring_buffer_available_write(rb);
    size_t to_write = std::min(length, avail);
    if (to_write == 0) return 0;

    size_t head = rb->head.load(std::memory_order_relaxed);
    size_t first_chunk = std::min(to_write, rb->capacity - head);
    memcpy(rb->buffer + head, data, first_chunk);

    if (to_write > first_chunk) {
        memcpy(rb->buffer, data + first_chunk, to_write - first_chunk);
    }

    rb->head.store((head + to_write) % rb->capacity, std::memory_order_release);
    return to_write;
}

size_t sunset_ring_buffer_read(SunsetRingBuffer* rb, uint8_t* out_data, size_t length) {
    if (!rb || !out_data || length == 0) return 0;

    size_t avail = sunset_ring_buffer_available_read(rb);
    size_t to_read = std::min(length, avail);
    if (to_read == 0) return 0;

    size_t tail = rb->tail.load(std::memory_order_relaxed);
    size_t first_chunk = std::min(to_read, rb->capacity - tail);
    memcpy(out_data, rb->buffer + tail, first_chunk);

    if (to_read > first_chunk) {
        memcpy(out_data + first_chunk, rb->buffer, to_read - first_chunk);
    }

    rb->tail.store((tail + to_read) % rb->capacity, std::memory_order_release);
    return to_read;
}

void sunset_ring_buffer_clear(SunsetRingBuffer* rb) {
    if (!rb) return;
    rb->head.store(0, std::memory_order_release);
    rb->tail.store(0, std::memory_order_release);
}

}

