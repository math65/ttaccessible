// WebRTCEchoCanceller.mm
// Objective-C++ wrapper bridging the WebRTC AudioProcessing C++ API to C.

#include "../../../Vendor/WebRTC/WebRTCEchoCanceller.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#include "api/audio/audio_processing.h"
#pragma clang diagnostic pop

struct WebRTCAEC {
    rtc::scoped_refptr<webrtc::AudioProcessing> apm;
    webrtc::StreamConfig stream_config;
    int channels;

    WebRTCAEC(int sample_rate, int ch)
        : stream_config(sample_rate, static_cast<size_t>(ch))
        , channels(ch)
    {}
};

WebRTCAECRef webrtc_aec_create(int sample_rate, int channels) {
    auto* aec = new (std::nothrow) WebRTCAEC(sample_rate, channels);
    if (!aec) return nullptr;

    aec->apm = rtc::scoped_refptr<webrtc::AudioProcessing>(
        webrtc::AudioProcessingBuilder().Create()
    );
    if (!aec->apm) {
        delete aec;
        return nullptr;
    }

    webrtc::AudioProcessing::Config config;

    // Echo cancellation (AEC3).
    config.echo_canceller.enabled = true;
    config.echo_canceller.mobile_mode = false;

    // Noise suppression — helps AEC by removing background noise.
    config.noise_suppression.enabled = true;
    config.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kModerate;

    // Multi-channel support.
    config.pipeline.multi_channel_render = (channels > 1);
    config.pipeline.multi_channel_capture = (channels > 1);

    aec->apm->ApplyConfig(config);

    return aec;
}

void webrtc_aec_destroy(WebRTCAECRef aec) {
    if (aec) {
        aec->apm = nullptr;
        delete aec;
    }
}

int webrtc_aec_feed_render(WebRTCAECRef aec, const int16_t* data, int sample_count) {
    if (!aec || !aec->apm || !data) return -1;
    return aec->apm->ProcessReverseStream(
        data,
        aec->stream_config,
        aec->stream_config,
        const_cast<int16_t*>(data)  // output not used, but API requires it
    );
}

int webrtc_aec_process_capture(WebRTCAECRef aec, int16_t* data, int sample_count) {
    if (!aec || !aec->apm || !data) return -1;
    aec->apm->set_stream_delay_ms(0);
    return aec->apm->ProcessStream(
        data,
        aec->stream_config,
        aec->stream_config,
        data
    );
}

void webrtc_aec_set_stream_delay(WebRTCAECRef aec, int delay_ms) {
    if (aec && aec->apm) {
        aec->apm->set_stream_delay_ms(delay_ms);
    }
}
