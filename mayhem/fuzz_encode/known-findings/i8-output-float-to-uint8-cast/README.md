# I8 output format: negative float stored through a uint8_t pointer

`repro` = protocol 1, volume 50, format I8, payload `hello`. `fuzz_encode-standalone repro` reports
`src/ggwave.cpp:1019:41: runtime error: -1.59129 is outside the range of representable values of type 'unsigned char'`.

Cause: in `GGWave::encode()` the `GGWAVE_SAMPLE_FORMAT_I8` branch writes `128*m_tx.outputResampled[i]` through a
`uint8_t *`, so every negative sample is a float-to-unsigned conversion out of range (undefined behaviour).

Impact: UB on every I8 encode; typically still yields the intended two's-complement byte on x86/arm, so this is
silent without UBSan.

Upstream fix: write through an `int8_t *` in the I8 branch (and clamp to [-128, 127]).

Fuzzing status: `mayhem/build.sh` compiles `src/ggwave.cpp` with `-fno-sanitize=float-cast-overflow` for the
fuzz binaries, because this report fired on every 8-bit encode and kept `fuzz_encode` restarting instead of
fuzzing. The repro therefore runs clean against the shipped binaries; rebuild without that flag to see it.
