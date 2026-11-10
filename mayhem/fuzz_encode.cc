// Fuzzes the ggwave Tx path: payload -> init() -> encode() -> audio waveform in every sample format.
// The Rx path is fuzz_decode's: decoding each produced waveform here cost ~9x the encode and left the
// target at a few execs/s, too slow for Mayhem's libFuzzer start-up probe.
// Input layout: [0] protocol id (mod GGWAVE_PROTOCOL_COUNT)
//               [1] volume (mod 101)
//               [2] sample format (low 3 bits, 1..5) | DSS flag (bit 3) | fixed-length flag (bit 4)
//               [3..] payload bytes
#include "ggwave/ggwave.h"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerInitialize(int *, char ***) {
    GGWave::setLogFile(nullptr);
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 3) return -1;

    const int protocolId = data[0] % GGWAVE_PROTOCOL_COUNT;
    const int volume = data[1] % 101;
    const int format = data[2] & 7;
    if (format < GGWAVE_SAMPLE_FORMAT_U8 || format > GGWAVE_SAMPLE_FORMAT_F32) return -1;

    const int dataSize = (int) size - 3;
    if (dataSize > GGWave::kMaxLengthFixed) return -1;

    auto parameters = GGWave::getDefaultParameters();
    parameters.sampleFormatInp = (GGWave::SampleFormat) format;
    parameters.sampleFormatOut = (GGWave::SampleFormat) format;
    if (data[2] & 8) parameters.operatingMode |= GGWAVE_OPERATING_MODE_USE_DSS;
    if ((data[2] & 16) && dataSize > 0) parameters.payloadLength = dataSize;

    GGWave instance(parameters);
    if (!instance.init(dataSize, (const char *) data + 3, (GGWave::TxProtocolId) protocolId, volume)) return -1;

    if (instance.encode() == 0) return -1;
    return 0;
}
