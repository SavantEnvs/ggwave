// Known-answer probe for mayhem/test.sh: round-trips fixed payloads through the encoder and decoder
// of the dynamically linked ggwave build and prints one line per case for the shell to compare.
#include "ggwave/ggwave.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

static void variableCase(const char * name, GGWave::TxProtocolId protocol, const std::string & payload) {
    auto parameters = GGWave::getDefaultParameters();
    GGWave tx(parameters);
    tx.init(payload.size(), payload.data(), protocol, 50);
    const uint32_t nBytes = tx.encode();
    std::vector<uint8_t> wave((const uint8_t *) tx.txWaveform(), (const uint8_t *) tx.txWaveform() + nBytes);

    GGWave rx(parameters);
    rx.decode(wave.data(), wave.size());
    GGWave::TxRxData result;
    const int n = rx.rxTakeData(result);
    std::string text;
    for (int i = 0; i < n; ++i) text.push_back((char) result[i]);
    printf("KAT %s bytes=%u decoded=%d:%s\n", name, nBytes, n, text.c_str());
}

static void fixedCase(const char * name, GGWave::TxProtocolId protocol, const std::string & payload) {
    auto parameters = GGWave::getDefaultParameters();
    parameters.payloadLength = (int) payload.size();
    GGWave tx(parameters);
    tx.init(payload.size(), payload.data(), protocol, 50);
    const uint32_t nBytes = tx.encode();
    std::vector<uint8_t> wave((const uint8_t *) tx.txWaveform(), (const uint8_t *) tx.txWaveform() + nBytes);

    GGWave rx(parameters);
    rx.decode(wave.data(), wave.size());
    GGWave::TxRxData result;
    const int n = rx.rxTakeData(result);
    std::string text;
    for (int i = 0; i < n; ++i) text.push_back((char) result[i]);
    printf("KAT %s bytes=%u decoded=%d:%s\n", name, nBytes, n, text.c_str());
}

int main() {
    GGWave::setLogFile(nullptr);
    variableCase("audible-fastest", GGWAVE_PROTOCOL_AUDIBLE_FASTEST, "hello");
    variableCase("ultrasound-fast", GGWAVE_PROTOCOL_ULTRASOUND_FAST, "a0Z5kR2g");
    variableCase("dt-fastest", GGWAVE_PROTOCOL_DT_FASTEST, "ggwave");
    fixedCase("mt-fast-fixed", GGWAVE_PROTOCOL_MT_FAST, "test1234");
    return 0;
}
