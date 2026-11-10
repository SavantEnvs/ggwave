// Regenerates the starter seeds in mayhem/fuzz_*/testsuite/ (not run by the build):
//   clang++ -std=c++11 -Iinclude mayhem/gen_seeds.cc src/ggwave.cpp -o /tmp/gen_seeds && /tmp/gen_seeds mayhem
#include "ggwave/ggwave.h"

#include <cstdio>
#include <string>
#include <vector>

static void writeFile(const std::string & path, const std::vector<uint8_t> & bytes) {
    FILE * f = fopen(path.c_str(), "wb");
    if (!f) { perror(path.c_str()); return; }
    fwrite(bytes.data(), 1, bytes.size(), f);
    fclose(f);
}

int main(int argc, char ** argv) {
    const std::string root = argc > 1 ? argv[1] : "mayhem";
    GGWave::setLogFile(nullptr);

    struct Case { const char * name; GGWave::TxProtocolId protocol; const char * payload; bool fixed; };
    const Case cases[] = {
        { "audible-fastest", GGWAVE_PROTOCOL_AUDIBLE_FASTEST,   "hello",    false },
        { "ultrasound-fastest", GGWAVE_PROTOCOL_ULTRASOUND_FASTEST, "ggwave", false },
        { "dt-fastest",      GGWAVE_PROTOCOL_DT_FASTEST,        "test",     false },
        { "mt-fastest",      GGWAVE_PROTOCOL_MT_FASTEST,        "a0Z5kR2g", true  },
        { "audible-fast-fixed", GGWAVE_PROTOCOL_AUDIBLE_FAST,   "data1234", true  },
    };

    for (const auto & c : cases) {
        const std::string payload = c.payload;

        // decode seed: samples in I16 (format 4)
        auto parameters = GGWave::getDefaultParameters();
        parameters.sampleFormatOut = GGWAVE_SAMPLE_FORMAT_I16;
        parameters.sampleFormatInp = GGWAVE_SAMPLE_FORMAT_I16;
        if (c.fixed) parameters.payloadLength = (int) payload.size();
        GGWave tx(parameters);
        tx.init(payload.size(), payload.data(), c.protocol, 50);
        const uint32_t nBytes = tx.encode();

        std::vector<uint8_t> dec = { (uint8_t) GGWAVE_SAMPLE_FORMAT_I16, (uint8_t) (c.fixed ? payload.size() : 0), 0 };
        dec.insert(dec.end(), (const uint8_t *) tx.txWaveform(), (const uint8_t *) tx.txWaveform() + nBytes);
        writeFile(root + "/fuzz_decode/testsuite/" + c.name, dec);

        // encode seed
        std::vector<uint8_t> enc = { (uint8_t) c.protocol, 50, (uint8_t) (GGWAVE_SAMPLE_FORMAT_I16 | (c.fixed ? 16 : 0)) };
        enc.insert(enc.end(), payload.begin(), payload.end());
        writeFile(root + "/fuzz_encode/testsuite/" + c.name, enc);
    }
    return 0;
}
