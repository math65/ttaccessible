//
//  OpusShim.c
//  ttaccessible
//

#include "OpusShim.h"

// libopus symbols exported by libTeamTalk5.dylib (resolved at link time against
// the already-linked TeamTalk dylib).
extern OpusEncoder *opus_encoder_create(int32_t Fs, int channels, int application, int *error);
extern int32_t opus_encode(OpusEncoder *st, const int16_t *pcm, int frame_size,
                           unsigned char *data, int32_t max_data_bytes);
extern int opus_encoder_ctl(OpusEncoder *st, int request, ...);
extern void opus_encoder_destroy(OpusEncoder *st);

#define TTAC_OPUS_APPLICATION_AUDIO   2049
#define TTAC_OPUS_SET_BITRATE_REQUEST 4002
#define TTAC_OPUS_GET_LOOKAHEAD_REQUEST 4027

OpusEncoder *ttac_opus_create(int32_t sampleRate, int channels, int *error) {
    return opus_encoder_create(sampleRate, channels, TTAC_OPUS_APPLICATION_AUDIO, error);
}

int ttac_opus_set_bitrate(OpusEncoder *enc, int32_t bitrate) {
    return opus_encoder_ctl(enc, TTAC_OPUS_SET_BITRATE_REQUEST, bitrate);
}

int32_t ttac_opus_lookahead(OpusEncoder *enc) {
    int32_t lookahead = 0;
    opus_encoder_ctl(enc, TTAC_OPUS_GET_LOOKAHEAD_REQUEST, &lookahead);
    return lookahead;
}

int32_t ttac_opus_encode(OpusEncoder *enc, const int16_t *pcm, int frameSize,
                         unsigned char *out, int32_t maxBytes) {
    return opus_encode(enc, pcm, frameSize, out, maxBytes);
}

void ttac_opus_destroy(OpusEncoder *enc) {
    opus_encoder_destroy(enc);
}
