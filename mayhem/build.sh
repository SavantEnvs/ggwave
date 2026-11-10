#!/usr/bin/env bash
#
# mayhem/build.sh — builds the ggwave fuzz harnesses (sanitized, DWARF 3) and, with the project's
# normal flags, upstream's own test programs plus the known-answer probe that mayhem/test.sh runs.
# ggwave is a single translation unit (src/ggwave.cpp) with a header-only Reed-Solomon, so it is
# compiled directly: upstream's top-level CMake rewrites tracked files (README.md, setup.py, ...)
# through configure_file(), which a build must not do to the source tree.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
# build-* is covered by upstream's .gitignore, so `git clean -ffdX` removes everything here
B="$SRC/build-mayhem"
rm -rf "$B"
mkdir -p "$B/fuzz" "$B/oracle"

INC="-I$SRC/include -I$SRC/src"
STD="-std=c++11"

# 1) the project, sanitized + SanCov-instrumented (fuzzer-no-link) + DWARF 3.
# UBSan's float-cast-overflow is relaxed on ggwave.cpp only: encode() stores every sample of an I8/U8
# waveform through a uint8_t (src/ggwave.cpp, the GGWAVE_SAMPLE_FORMAT_I8/U8 branches), so the check fires
# on every 8-bit encode and the fuzzer spends its run restarting on that one benign report
# (mayhem/fuzz_encode/known-findings/i8-output-float-to-uint8-cast). ASan and all other UBSan checks halt.
RELAX_UBSAN="-fno-sanitize=float-cast-overflow"
# shellcheck disable=SC2086
$CXX $STD -O1 $SANITIZER_FLAGS $RELAX_UBSAN $DEBUG_FLAGS -fsanitize=fuzzer-no-link $INC -c "$SRC/src/ggwave.cpp" -o "$B/fuzz/ggwave.o"
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/fuzz/lsan_off.o"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c -x c "$STANDALONE_FUZZ_MAIN" -o "$B/fuzz/standalone_main.o"

# 2) each harness twice: libFuzzer binary + run-once standalone reproducer
for h in fuzz_decode fuzz_encode; do
    # shellcheck disable=SC2086
    $CXX $STD -O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $INC -c "$SRC/mayhem/$h.cc" -o "$B/fuzz/$h.o"
    # shellcheck disable=SC2086
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/fuzz/$h.o" "$B/fuzz/ggwave.o" "$B/fuzz/lsan_off.o" -o "/mayhem/$h"
    # shellcheck disable=SC2086
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$B/fuzz/$h.o" "$B/fuzz/ggwave.o" "$B/fuzz/lsan_off.o" "$B/fuzz/standalone_main.o" -o "/mayhem/$h-standalone"
done

# 3) the test suite with the project's NORMAL flags: upstream's two C/C++ test programs + the KAT probe
# shellcheck disable=SC2086
$CXX $STD -O2 $COVERAGE_FLAGS $INC -c "$SRC/src/ggwave.cpp" -o "$B/oracle/ggwave.o"
# shellcheck disable=SC2086
$CXX $STD -O2 $COVERAGE_FLAGS $INC "$SRC/tests/test-ggwave.cpp" "$B/oracle/ggwave.o" -o "$B/oracle/test-ggwave-cpp"
# shellcheck disable=SC2086
$CC -O2 $COVERAGE_FLAGS $INC -c "$SRC/tests/test-ggwave.c" -o "$B/oracle/test-ggwave-c.o"
# shellcheck disable=SC2086
$CXX $COVERAGE_FLAGS "$B/oracle/test-ggwave-c.o" "$B/oracle/ggwave.o" -o "$B/oracle/test-ggwave-c"
# shellcheck disable=SC2086
$CXX $STD -O2 $COVERAGE_FLAGS $INC "$SRC/mayhem/kat.cpp" "$B/oracle/ggwave.o" -o "$B/oracle/kat"
file "$B/oracle/kat" | grep -q 'dynamically linked'
