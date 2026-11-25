#import "GeneratedPluginRegistrant.h"

#import <SunsetOpus/opus.h>

// Swift cannot call C varargs or Opus CTL macros directly.
static inline int sunset_opus_set_bitrate(OpusEncoder *encoder, int bitrate) {
    return opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
}
