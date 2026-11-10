// Fuzzes the ggwave Rx path: raw audio samples -> GGWave::decode() -> rxTakeData().
// Input layout: [0] sample format (low 3 bits, 1..5) | DSS flag (bit 3)
//               [1] fixed payload length (0 = variable length, 1..64 = fixed)
//               [2] input sample rate selector
//               [3..] waveform bytes in the selected sample format
#include "ggwave/ggwave.h"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerInitialize(int *, char ***) {
    GGWave::setLogFile(nullptr);
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    static const float kRates[8] = { 48000.0f, 44100.0f, 16000.0f, 96000.0f, 8000.0f, 22050.0f, 24000.0f, 32000.0f };

    if (size < 3) return -1;

    const int format = data[0] & 7;
    if (format < GGWAVE_SAMPLE_FORMAT_U8 || format > GGWAVE_SAMPLE_FORMAT_F32) return -1;
    const int fixedLength = data[1];
    if (fixedLength > GGWave::kMaxLengthFixed) return -1;

    auto parameters = GGWave::getDefaultParameters();
    parameters.operatingMode = GGWAVE_OPERATING_MODE_RX;
    if (data[0] & 8) parameters.operatingMode |= GGWAVE_OPERATING_MODE_USE_DSS;
    parameters.payloadLength = fixedLength;
    parameters.sampleRateInp = kRates[data[2] & 7];
    parameters.sampleFormatInp = (GGWave::SampleFormat) format;

    GGWave instance(parameters);
    instance.decode(data + 3, size - 3);

    GGWave::TxRxData result;
    instance.rxTakeData(result);
    return 0;
}
