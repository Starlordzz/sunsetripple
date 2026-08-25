#ifndef SUNSET_PROTOCOL_FRAME_H
#define SUNSET_PROTOCOL_FRAME_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT __attribute__((visibility("default")))
#endif

#define SUNSET_FRAME_HEADER_SIZE 6
/* 必须与 Dart 侧 Frame.maxPayloadSize 及 Kotlin 版 Frame.MAX_PAYLOAD 一致。
   音频走 Opus，一帧几十字节，512 足够。 */
#define SUNSET_MAX_PAYLOAD_SIZE 512

typedef enum {
    SUNSET_FRAME_AUDIO = 0x01,
    SUNSET_FRAME_JOIN_REQ = 0x02,
    SUNSET_FRAME_ROSTER = 0x03,
    SUNSET_FRAME_PTT_STATE = 0x04,
    SUNSET_FRAME_HEARTBEAT = 0x05,
    SUNSET_FRAME_LEAVE = 0x06,
    SUNSET_FRAME_HOST_HANDOVER = 0x07,
} SunsetFrameType;

typedef struct {
    uint8_t type;
    uint8_t sender_id;
    uint16_t seq;
    uint16_t payload_len;
    uint8_t payload[SUNSET_MAX_PAYLOAD_SIZE];
} SunsetNativeFrame;

FFI_EXPORT int sunset_frame_encode(
    uint8_t type,
    uint8_t sender_id,
    uint16_t seq,
    const uint8_t* payload,
    uint16_t payload_len,
    uint8_t* out_buffer,
    size_t out_capacity
);

FFI_EXPORT int sunset_frame_decode(
    const uint8_t* in_buffer,
    size_t in_len,
    SunsetNativeFrame* out_frame
);

#ifdef __cplusplus
}
#endif

#endif // SUNSET_PROTOCOL_FRAME_H

