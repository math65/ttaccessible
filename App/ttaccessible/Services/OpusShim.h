//
//  OpusShim.h
//  ttaccessible
//
//  Thin, non-variadic wrappers around the libopus encoder that ships inside
//  libTeamTalk5.dylib (its opus_* symbols are exported). Lets Swift build an
//  Opus stream for the device-stream loopback without a separate libopus.
//

#ifndef OpusShim_h
#define OpusShim_h

#include <stdint.h>

typedef struct OpusEncoder OpusEncoder;

/// Create an Opus encoder (OPUS_APPLICATION_AUDIO). Returns NULL on failure.
OpusEncoder *ttac_opus_create(int32_t sampleRate, int channels, int *error);

/// OPUS_SET_BITRATE. Returns 0 (OPUS_OK) on success.
int ttac_opus_set_bitrate(OpusEncoder *enc, int32_t bitrate);

/// Encoder delay in samples (OPUS_GET_LOOKAHEAD) — the Ogg pre-skip.
int32_t ttac_opus_lookahead(OpusEncoder *enc);

/// Encode one frame of interleaved int16 PCM. Returns bytes written, or <0 on error.
int32_t ttac_opus_encode(OpusEncoder *enc, const int16_t *pcm, int frameSize,
                         unsigned char *out, int32_t maxBytes);

void ttac_opus_destroy(OpusEncoder *enc);

#endif /* OpusShim_h */
