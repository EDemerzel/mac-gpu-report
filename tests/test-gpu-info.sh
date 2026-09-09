#!/bin/bash
# Portable shell regression tests; macOS diagnostic commands are mocked.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
source "$script_dir/gpu-info.sh"

test_base=${TMPDIR:-/private/tmp}
test_base=$(cd "$test_base" && pwd) || exit 1
test_root=$(mktemp -d "$test_base/gpu-info-tests.XXXXXX") || exit 1
cleanup() {
  # Only remove the exact temporary directory created above.
  case "$test_root" in
    "$test_base"/gpu-info-tests.??????) rm -r "$test_root" ;;
  esac
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -F -q "$2" "$1" || fail "$1 should contain: $2"; }
omits() { if grep -F -q "$2" "$1"; then fail "$1 should omit: $2"; fi; }

# Functions take precedence over installed commands, so this suite never probes
# the host's GPU, display server, processes, or hardware identity.
uname() { echo 'Darwin sample-mac'; }
sw_vers() { echo 'ProductVersion: 13.7.8'; }
system_profiler() {
  if [ "${PROFILER_FAIL:-0}" -eq 1 ]; then
    echo 'mock profiler permission denied' >&2
    return 7
  fi
  case "$1" in
    SPDisplaysDataType) printf 'Graphics/Displays:\nChipset Model: Test GPU\nVRAM: 128 MB\n' ;;
    SPHardwareDataType) echo 'Hardware Overview: synthetic fixture' ;;
    SPSoftwareDataType) echo 'System Software Overview: synthetic fixture' ;;
    *) return 2 ;;
  esac
}
ioreg() {
  if [ "$*" != '-r -l -d 1 -w 0 -c IOFramebuffer' ] &&
     [ "$*" != '-r -l -d 1 -w 0 -c IODisplay' ] &&
     [ "$*" != '-r -l -d 1 -w 0 -c IOAccelerator' ] &&
     [ "$*" != '-r -l -d 1 -w 0 -c IOGPU' ]; then
    echo 'unexpected unscoped registry query' >&2
    return 2
  fi
  if [ "$8" = IOFramebuffer ]; then
    # More than the old global 200-line cap; the final GPU must survive.
    local i
    for ((i=0; i<210; i++)); do echo "Framebuffer property $i"; done
    echo 'last GPU preserved'
  fi
}
defaults() { echo 'mock preferences domain unavailable' >&2; return 1; }
launchctl() {
  case "$*" in
    'getenv DISPLAY') echo ':0' ;;
    'print system/com.apple.WindowServer') echo 'mock launchctl permission denied' >&2; return 5 ;;
    *) echo 'unexpected launchctl target' >&2; return 9 ;;
  esac
}
kextstat() { echo 'mock kext query failed' >&2; return 3; }
ps() { echo '_windowserver 100 WindowServer'; }
top() { echo 'mock top data'; }
vm_stat() { echo 'mock vm_stat data'; }
env() { printf 'DISPLAY=:0\nUNRELATED_SECRET=contains-gpu-text\n'; }
find_glxinfo() { return 1; }
find_xdpyinfo() { return 1; }
pgrep() { return 1; }

valid="$test_root/report with spaces"
mkdir -p "$valid" || fail 'create valid output directory'
touch "$valid/stale.txt"
(main "$valid") > "$test_root/valid.log" 2>&1 || fail 'valid run'
contains "$test_root/valid.log" 'GPU diagnostics saved in:'
contains "$valid/summary.txt" 'Diagnostics completed.'
omits "$valid/summary.txt" 'stale.txt'
[ -f "$valid/stale.txt" ] || fail 'stale file should be preserved'
for name in system-info hardware display kexts windowserver opengl metal perf env summary; do
  [ -s "$valid/$name.txt" ] || fail "missing report: $name"
  contains "$valid/summary.txt" "$name.txt"
done
contains "$valid/hardware.txt" 'last GPU preserved'
contains "$valid/hardware.txt" 'Chipset Model: Test GPU'
contains "$valid/hardware.txt" 'No data reported.'
omits "$valid/hardware.txt" 'Hardware Overview:'
omits "$valid/hardware.txt" 'unexpected unscoped registry query'
contains "$valid/display.txt" 'Command failed (exit=1): defaults read com.apple.windowserver'
contains "$valid/display.txt" 'mock preferences domain unavailable'
contains "$valid/windowserver.txt" 'Command failed (exit=5): launchctl print system/com.apple.WindowServer'
contains "$valid/kexts.txt" 'mock kext query failed'
contains "$valid/metal.txt" 'No matching data reported.'
contains "$valid/opengl.txt" 'OpenGL tool not available: glxinfo'
contains "$valid/env.txt" 'DISPLAY=:0'
omits "$valid/env.txt" 'UNRELATED_SECRET'

touch "$test_root/not-a-directory"
if (main "$test_root/not-a-directory") > "$test_root/invalid.log" 2>&1; then
  fail 'invalid output must fail'
fi
contains "$test_root/invalid.log" 'Cannot create or write report directory:'
omits "$test_root/invalid.log" 'Starting GPU diagnostics'
omits "$test_root/invalid.log" 'GPU diagnostics saved in:'

(
  mkdir() { return 1; }
  main "$test_root/mkdir-failed"
) > "$test_root/mkdir.log" 2>&1 && fail 'directory creation failure must fail'
contains "$test_root/mkdir.log" 'Cannot create or write report directory:'

partial="$test_root/partial"
mkdir -p "$partial/hardware.txt" || fail 'prepare blocked report path'
if (main "$partial") > "$test_root/partial.log" 2>&1; then
  fail 'partial write must fail'
fi
contains "$partial/summary.txt" 'Diagnostics incomplete:'
omits "$partial/summary.txt" 'hardware.txt'
contains "$partial/summary.txt" 'env.txt'
omits "$test_root/partial.log" 'GPU diagnostics saved in:'

mkdir -p "$test_root/summary-blocked/summary.txt"
if (main "$test_root/summary-blocked") > "$test_root/summary.log" 2>&1; then
  fail 'summary write failure must fail'
fi
omits "$test_root/summary.log" 'GPU diagnostics saved in:'

(PROFILER_FAIL=1; main "$test_root/probe-failure") > "$test_root/probe.log" 2>&1 || fail 'probe errors should still write reports'
contains "$test_root/probe-failure/metal.txt" 'Command failed (exit=7): system_profiler SPDisplaysDataType'
contains "$test_root/probe-failure/metal.txt" 'mock profiler permission denied'
[ -z "$(find "$test_root/probe-failure" -perm -004 -print)" ] || fail 'new reports must not be world readable'
[ -z "$(find "$test_root/probe-failure" -perm -040 -print)" ] || fail 'new reports must not be group readable'

# Exercise the disk-full write path where /dev/full exists (WSL/Linux only).
# This is supplemental shell error handling, not macOS device validation.
if [ -c /dev/full ]; then
  mkdir -p "$test_root/disk-full"
  ln -s /dev/full "$test_root/disk-full/hardware.txt"
  if (main "$test_root/disk-full") > "$test_root/full.log" 2>&1; then
    fail 'disk-full write must fail'
  fi
  contains "$test_root/disk-full/summary.txt" 'Diagnostics incomplete:'
  omits "$test_root/disk-full/summary.txt" 'hardware.txt'
  omits "$test_root/full.log" 'GPU diagnostics saved in:'
fi

# A command may print more than a pipe buffer. Truncation must not turn its
# successful exit into a spurious SIGPIPE failure, or hide that it was truncated.
large_output() { local i; for ((i=0; i<10000; i++)); do echo "line $i"; done; }
run_diagnostic '' 2 large_output > "$test_root/truncated.txt"
contains "$test_root/truncated.txt" '[Output truncated after 2 lines.]'
omits "$test_root/truncated.txt" 'Command failed'

run_diagnostic '' 0 gpu_info_deliberately_missing_tool > "$test_root/missing.txt"
contains "$test_root/missing.txt" 'Tool not available:'

# Confirm glxinfo's exit-zero-with-error case still triggers diagnostics.
(
  find_glxinfo() { echo mock_glxinfo; }
  mock_glxinfo() { echo 'Error: unable to open display'; return 0; }
  run_glxinfo_probe 'test GLX' -B
) > "$test_root/glx.txt"
contains "$test_root/glx.txt" 'glxinfo exited 0 but reported an error'
contains "$test_root/glx.txt" '=== X11/GLX diagnostics ==='

# No report succeeds: the summary must handle an empty array under nounset.
(
  OUTDIR="$test_root"
  generated_files=()
  write_failed=1
  summary_report
) > "$test_root/empty-summary.txt" || fail 'empty summary array'
contains "$test_root/empty-summary.txt" 'Diagnostics incomplete:'

echo 'PASS: output handling, summaries, diagnostic failures, registry scope, and GLX regressions'
