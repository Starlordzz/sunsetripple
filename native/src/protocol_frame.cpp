#include "protocol_frame.h"
#include <string.h>

extern "C" {

int sunset_frame_encode(
    uint8_t type,
    uint8_t sender_id,
    uint16_t seq,
    const uint8_t* payload,
    uint16_t payload_len,
    uint8_t* out_buffer,
    size_t out_capacity
) {
    if (!out_buffer || out_capacity < (size_t)(SUNSET_FRAME_HEADER_SIZE + payload_len)) {
        return -1;
    }
    if (payload_len > SUNSET_MAX_PAYLOAD_SIZE) {
        payload_len = SUNSET_MAX_PAYLOAD_SIZE;
    }

    out_buffer[0] = type;
    out_buffer[1] = sender_id;
    out_buffer[2] = (uint8_t)((seq >> 8) & 0xFF);
    out_buffer[3] = (uint8_t)(seq & 0xFF);
    out_buffer[4] = (uint8_t)((payload_len >> 8) & 0xFF);
    out_buffer[5] = (uint8_t)(payload_len & 0xFF);

    if (payload && payload_len > 0) {
        memcpy(out_buffer + SUNSET_FRAME_HEADER_SIZE, payload, payload_len);
    }
    return SUNSET_FRAME_HEADER_SIZE + payload_len;
}

int sunset_frame_decode(
    const uint8_t* in_buffer,
    size_t in_len,
    SunsetNativeFrame* out_frame
) {
    if (!in_buffer || !out_frame || in_len < SUNSET_FRAME_HEADER_SIZE) {
        return -1;
    }

    out_frame->type = in_buffer[0];
    out_frame->sender_id = in_buffer[1];
    out_frame->seq = (uint16_t)(((uint16_t)in_buffer[2] << 8) | in_buffer[3]);
    out_frame->payload_len = (uint16_t)(((uint16_t)in_buffer[4] << 8) | in_buffer[5]);

    if (out_frame->payload_len > SUNSET_MAX_PAYLOAD_SIZE ||
        in_len < (size_t)(SUNSET_FRAME_HEADER_SIZE + out_frame->payload_len)) {
        return -2;
    }

    if (out_frame->payload_len > 0) {
        memcpy(out_frame->payload, in_buffer + SUNSET_FRAME_HEADER_SIZE, out_frame->payload_len);
    }
    return 0;
}

}

