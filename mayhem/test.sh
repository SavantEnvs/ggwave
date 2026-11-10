#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Oracle: upstream's own test programs (tests/test-ggwave.c, tests/test-ggwave.cpp) judge themselves
# by exit code only, and the sabotage shim makes every non-system binary exit 0 at load. So each
# result is asserted from the program's OUTPUT (empty stdout from a neutered binary fails), and the
# KAT probe adds known-answer round trips (exact encoded size + decoded payload) on top.
O="$SRC/build-mayhem/oracle"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
passed=0 ; failed=0

pass() { echo "PASS $1"; passed=$((passed+1)); }
fail() { echo "FAIL $1" >&2; failed=$((failed+1)); }

for t in test-ggwave-c test-ggwave-cpp kat; do
  [ -x "$O/$t" ] || { echo "missing $O/$t — mayhem/build.sh must build it" >&2; emit_ctrf "ggwave-kat" 0 1 0; exit 1; }
done

# 1) upstream C API test: must exit 0 and print four successful decodes of 'test'
"$O/test-ggwave-c" > "$OUT/c.out" 2>&1; rc=$?
n=$(grep -c "^Received sound data successfully: 'test'$" "$OUT/c.out")
if [ "$rc" -eq 0 ] && [ "$n" -eq 4 ]; then pass "test-ggwave-c (4 decodes of 'test')"; else fail "test-ggwave-c rc=$rc decodes=$n (want 0/4)"; fi

# 2) upstream C++ test: 64 sample-rate round trips + 12 protocol/format sweeps, every decode successful
"$O/test-ggwave-cpp" > "$OUT/cpp.out" 2>&1; rc=$?
nsr=$(grep -c "^Testing: sample rate = " "$OUT/cpp.out")
npr=$(grep -c "^Testing: protocol = " "$OUT/cpp.out")
nok=$(grep -c "^Received sound data successfully" "$OUT/cpp.out")
if [ "$rc" -eq 0 ] && [ "$nsr" -eq 64 ] && [ "$npr" -eq 12 ] && [ "$nok" -ge 64 ]; then
  pass "test-ggwave-cpp (sample-rate=$nsr protocols=$npr decodes=$nok)"
else
  fail "test-ggwave-cpp rc=$rc sample-rate=$nsr protocols=$npr decodes=$nok (want 0/64/12/>=64)"
fi

# 3) KAT probe: exact waveform size and decoded payload per protocol
"$O/kat" > "$OUT/kat.out" 2>&1 || true
check_kat() {
  if grep -qxF "$2" "$OUT/kat.out"; then pass "kat $1"; else fail "kat $1: expected line '$2'"; fi
}
check_kat audible-fastest 'KAT audible-fastest bytes=180224 decoded=5:hello'
check_kat ultrasound-fast 'KAT ultrasound-fast bytes=253952 decoded=8:a0Z5kR2g'
check_kat dt-fastest      'KAT dt-fastest bytes=290816 decoded=6:ggwave'
check_kat mt-fast-fixed   'KAT mt-fast-fixed bytes=589824 decoded=8:test1234'

emit_ctrf "ggwave-kat" "$passed" "$failed" 0
