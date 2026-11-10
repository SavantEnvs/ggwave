# encode() after init() with an empty payload: division by zero

`repro` (3 bytes) = protocol 0, volume 50, format I16, empty payload. `fuzz_encode-standalone repro` reports
`src/ggwave.cpp:806:97: runtime error: division by zero` (a SIGFPE without UBSan).

Cause: `GGWave::init(0, ...)` returns `true` for an empty payload but leaves `m_tx.hasData == false` and
`m_tx.protocol` zero-initialised, so `GGWave::encode()` computes `... / m_tx.protocol.bytesPerTx` with
`bytesPerTx == 0`.

Impact: any caller that encodes an empty string crashes the process.

Upstream fix: make `init()` return `false` for `dataSize == 0` on a Tx instance, or return 0 from `encode()` when
`m_tx.hasData` is false.
