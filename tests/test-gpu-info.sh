#!/bin/bash
# Shell integration tests: every platform probe is mocked.
set -uo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
source "$script_dir/gpu-info.sh"
test_base=$(cd "${TMPDIR:-/private/tmp}" && pwd) || exit 1
test_root=$(mktemp -d "$test_base/gpu-info-tests.XXXXXX") || exit 1
cleanup() {
  case "$test_root" in "$test_base"/gpu-info-tests.??????) rm -r "$test_root";; esac
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -F -q "$2" "$1" || fail "$1 should contain: $2"; }
omits() { if grep -F -q "$2" "$1"; then fail "$1 should omit: $2"; fi; }

sw_vers() { printf 'ProductName: macOS\nProductVersion: 13.7.8\n'; }
system_profiler() {
  if [ "${PROFILER_FAIL:-0}" = 1 ]; then echo 'mock profiler permission denied' >&2; return 7; fi
  case "$1" in
    SPHardwareDataType) printf 'Model Identifier: VMware20,1\nMemory: 16 GB\n';;
    SPSoftwareDataType) printf 'System Version: macOS 13.7.8\n';;
    SPDisplaysDataType)
      echo call >> "$test_root/display-calls.txt"
      printf 'Graphics/Displays:\n    Test GPU:\n      Chipset Model: Test GPU\n      VRAM: 128 MB\n      Displays:\n        Panel:\n          Resolution: 2163 x 1287\n'
      if [ "${MULTI_GPU:-0}" = 1 ]; then
        printf '    GPU two <script>alert(1)</script>:\n      Chipset Model: GPU two | error board\n      Metal Support: Metal 3\n'
      fi
      ;;
    *) return 2;;
  esac
}
ioreg() {
  case "$*" in
    '-r -l -d 1 -w 0 -c IOFramebuffer'|'-r -l -d 1 -w 0 -c IODisplay'|\
    '-r -l -d 1 -w 0 -c IOAccelerator'|'-r -l -d 1 -w 0 -c IOGPU') ;;
    *) echo 'unscoped registry query' >&2; return 2;;
  esac
  if [ "$8" = IOFramebuffer ]; then
    echo '+-o Framebuffer <class IOFramebuffer>'
    local i
    for ((i=0; i<210; i++)); do printf '  "device-id" = <%s>\n' "$i"; done
    # Exercise the old giant-dictionary readability problem.
    printf '  "IOKitDiagnostics" = {'
    for ((i=0; i<4000; i++)); do printf '"Noise"=0,'; done
    printf '}\n  "model" = "last GPU preserved"\n'
  fi
}
defaults() { echo 'mock preferences domain unavailable' >&2; return 1; }
launchctl() {
  case "$*" in
    'getenv DISPLAY') echo ':0';;
    'print system/com.apple.WindowServer') echo 'mock launchctl permission denied' >&2; return 5;;
    *) return 9;;
  esac
}
# Avoid listing real host extensions.
ls() { printf 'AMDRadeonX4000.kext\nAppleHDA.kext\nIOGraphicsFamily.kext\n'; }
kextstat() {
  printf 'Index Refs Address Size Wired Name (Version) UUID <Linked Against>\n'
  printf '1 0 0xffffff 0x100 0x100 com.apple.iokit.IOGraphicsFamily (1.2.3) UUID-SECRET <1 2>\n'
  printf '2 0 0xffffff 0x100 0x100 com.apple.driver.AppleHDA (1.0) UUID-OTHER <1>\n'
}
pgrep() {
  case "$3" in
    WindowServer) echo '100 WindowServer';;
    Xquartz) echo '101 Xquartz';;
    *) return 1;;
  esac
}
find_x_tool() { echo "$1"; }
glxinfo() {
  printf 'CGLChoosePixelFormat error: invalid pixel format\n'
  # Deliberately exits zero with an error.
}
xdpyinfo() { printf 'name of display: :0\nnumber of extensions: 1\n    GLX\n'; }
top() {
  [ "$*" = '-l 2 -s 1 -n 10 -o cpu -stats pid,command,cpu,mem' ] || return 2
  printf 'Processes: 100 total\nCPU usage: 0%% user\nPID COMMAND %%CPU MEM\n1 Invalid First Sample 999.0 1M\n'
  if [ "${TOP_SINGLE:-0}" != 1 ]; then
    printf 'Processes: 100 total\nLoad Avg: 2.00, 1.96, 1.93\nCPU usage: 6.75%% user\nPhysMem: 11G used, 4898M unused\nPID COMMAND %%CPU MEM\n100 WindowServer 5.3 140M\n101 Code - Insiders 1.2 200M\n'
  fi
}
vm_stat() { printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free: 200.\nSwapins: 0.\n'; }
env() { printf 'DISPLAY=:0\nUNRELATED_SECRET=contains-gpu-text\n'; }

valid="$test_root/report with spaces"
mkdir -p "$valid"
touch "$valid/stale.txt"
(main "$valid") > "$test_root/valid.log" 2>&1 || fail 'valid run'
contains "$test_root/valid.log" 'Start here:'
contains "$valid/summary.txt" 'Diagnostics completed.'
contains "$valid/summary.txt" 'Start here: report.md'
omits "$valid/summary.txt" 'stale.txt'
[ -f "$valid/stale.txt" ] || fail 'preserve unrelated files'
for name in system-info hardware display kexts windowserver opengl metal perf env summary; do
  [ -s "$valid/$name.txt" ] || fail "missing $name"
  contains "$valid/summary.txt" "$name.txt"
done
[ "$(wc -l < "$test_root/display-calls.txt" | tr -d ' ')" = 1 ] || fail 'collect display profile once'
contains "$valid/report.md" '| X11 OpenGL renderer probe | FAILED |'
contains "$valid/report.md" '| XQuartz process | OK |'
contains "$valid/report.md" '| Metal field | NOT REPORTED |'
contains "$valid/report.md" '[Raw output](raw/glx.txt)'
contains "$valid/raw/xquartz.txt" 'Command: xquartz_process'
contains "$valid/raw/xquartz.txt" '101 Xquartz'
contains "$valid/report.md" 'Source revision:'
contains "$valid/report.md" 'Script version:'
contains "$valid/report.md" 'Collection started:'
contains "$valid/report.md" 'Collection ended:'
contains "$valid/raw/glx.txt" 'Exit code: 0'
contains "$valid/opengl.txt" 'glxinfo exited 0 but reported an error.'
contains "$valid/opengl.txt" 'The X11 connection succeeded, but the renderer probe failed.'
omits "$valid/opengl.txt" 'Likely cause:'
contains "$valid/raw/IOFramebuffer.txt" 'last GPU preserved'
contains "$valid/raw/IOFramebuffer.txt" '"IOKitDiagnostics"'
omits "$valid/hardware.txt" '"IOKitDiagnostics"'
contains "$valid/hardware.txt" '[More lines omitted; see raw evidence.]'
contains "$valid/display.txt" 'Result: FAILED'
contains "$valid/display.txt" 'mock preferences domain unavailable'
contains "$valid/metal.txt" 'missing Metal field does not prove'
contains "$valid/perf.txt" '100 WindowServer 5.3 140M'
contains "$valid/perf.txt" '101 Code - Insiders 1.2 200M'
omits "$valid/perf.txt" 'Invalid First Sample'
contains "$valid/raw/top.txt" 'Invalid First Sample'
contains "$valid/kexts.txt" 'com.apple.iokit.IOGraphicsFamily (1.2.3)'
omits "$valid/kexts.txt" 'UUID-SECRET'
omits "$valid/kexts.txt" 'AppleHDA'
omits "$valid/raw/environment.txt" 'UNRELATED_SECRET'
omits "$valid/env.txt" 'UNRELATED_SECRET'
for name in hardware perf opengl kexts; do
  awk 'length($0)>100 {exit 1}' "$valid/$name.txt" || fail "$name exceeds readable width"
done
[ -z "$(find "$valid/raw" -perm -004 -print)" ] || fail 'raw files world readable'

# Every relative evidence/report link must reference a file written this run.
links=$(sed -n 's/.*](\([^)]*\.txt\)).*/\1/p' "$valid/report.md")
while IFS= read -r link; do
  [ -f "$valid/$link" ] || fail "broken link: $link"
done <<< "$links"

touch "$test_root/not-a-directory"
if (main "$test_root/not-a-directory") > "$test_root/invalid.log" 2>&1; then fail 'invalid output must fail'; fi
contains "$test_root/invalid.log" 'Cannot create or write report directory:'
omits "$test_root/invalid.log" 'GPU diagnostics saved in:'

partial="$test_root/partial"
mkdir -p "$partial/hardware.txt" "$partial/raw/glx.txt"
if (main "$partial") > "$test_root/partial.log" 2>&1; then fail 'partial writes must fail'; fi
contains "$partial/summary.txt" 'Diagnostics incomplete:'
omits "$test_root/partial.log" 'GPU diagnostics saved in:'
contains "$partial/report.md" '| X11 OpenGL renderer probe | FAILED | Not written |'
omits "$partial/report.md" '[Raw output](raw/glx.txt)'
contains "$partial/report.md" 'hardware: file not written during this run.'

for blocked in summary.txt report.md; do
  mkdir -p "$test_root/blocked-$blocked/$blocked"
  if (main "$test_root/blocked-$blocked") > "$test_root/blocked.log" 2>&1; then fail "$blocked failure must fail"; fi
  omits "$test_root/blocked.log" 'GPU diagnostics saved in:'
done

(PROFILER_FAIL=1; main "$test_root/probe-failure") > "$test_root/probe.log" 2>&1 || fail 'probe failure should write reports'
contains "$test_root/probe-failure/report.md" '| Metal field | FAILED |'
contains "$test_root/probe-failure/raw/displays.txt" 'mock profiler permission denied'
omits "$test_root/probe-failure/metal.txt" 'Result: NOT REPORTED'

(MULTI_GPU=1; main "$test_root/multi") > "$test_root/multi.log" 2>&1 || fail 'multi GPU'
contains "$test_root/multi/report.md" 'Chipset Model: Test GPU'
contains "$test_root/multi/report.md" 'Chipset Model: GPU two | error board'
contains "$test_root/multi/report.md" '| GPU and displays | OK |'
contains "$test_root/multi/report.md" '| Metal field | REPORTED |'
# Dynamic HTML appears only inside indented code, never an executable HTML block.
if grep '<script>' "$test_root/multi/report.md" | grep -v '^    ' >/dev/null; then fail 'unsafe Markdown'; fi

(
  find_x_tool() { echo gpu_info_missing_test_tool; }
  main "$test_root/missing"
) > "$test_root/missing.log" 2>&1 || fail 'missing optional tools'
contains "$test_root/missing/report.md" '| X11 OpenGL renderer probe | TOOL MISSING |'
contains "$test_root/missing/opengl.txt" 'GLX extension: NOT CHECKED'

(
  glxinfo() { echo 'OpenGL renderer string: Test Renderer'; }
  main "$test_root/glx-ok"
) > "$test_root/glx-ok.log" 2>&1 || fail 'successful GLX'
contains "$test_root/glx-ok/report.md" '| X11 OpenGL renderer probe | OK |'
omits "$test_root/glx-ok/opengl.txt" 'Next step:'

(
  glxinfo() { echo 'mock renderer failure' >&2; return 42; }
  xdpyinfo() { echo 'mock display connection failed' >&2; return 1; }
  main "$test_root/x11-failed"
) > "$test_root/x11-failed.log" 2>&1 || fail 'failed connection should still write reports'
contains "$test_root/x11-failed/opengl.txt" 'Exit code: 42'
contains "$test_root/x11-failed/opengl.txt" 'GLX extension: NOT CHECKED'
contains "$test_root/x11-failed/opengl.txt" 'a working X11 connection was not confirmed'

(
  xdpyinfo() { printf 'name of display: :0\n    RANDR\n'; }
  main "$test_root/no-glx-extension"
) > "$test_root/no-glx-extension.log" 2>&1 || fail 'missing GLX extension'
contains "$test_root/no-glx-extension/opengl.txt" 'GLX extension: NOT REPORTED'
contains "$test_root/no-glx-extension/report.md" '| X11 display connection | OK |'

(TOP_SINGLE=1; main "$test_root/single") > "$test_root/single.log" 2>&1 || fail 'single top sample'
contains "$test_root/single/perf.txt" 'Could not identify the second top sample'
omits "$test_root/single/perf.txt" '999.0'

# The real Mac returned this exact defaults error for an optional domain.
(
  defaults() {
    printf '2026-09-09 06:30:45 defaults[100:200]\nDomain com.apple.windowserver does not exist\n' >&2
    return 1
  }
  main "$test_root/optional-preferences"
) > "$test_root/optional.log" 2>&1 || fail 'absent optional preferences'
contains "$test_root/optional-preferences/report.md" '| Display preferences | UNAVAILABLE |'
contains "$test_root/optional-preferences/display.txt" 'Optional display preferences are absent'
omits "$test_root/optional-preferences/display.txt" 'defaults[100:200]'
omits "$test_root/optional-preferences/summary.txt" 'Display preferences: FAILED'
contains "$test_root/optional-preferences/raw/preferences.txt" 'Result: FAILED'
contains "$test_root/optional-preferences/raw/preferences.txt" 'Exit code: 1'
contains "$test_root/optional-preferences/raw/preferences.txt" 'Domain com.apple.windowserver does not exist'

for preference_error in permission wrong-domain wrong-exit; do
  (
    defaults() {
      case "$preference_error" in
        permission) echo 'Permission denied' >&2; return 1;;
        wrong-domain) echo 'Domain com.apple.other does not exist' >&2; return 1;;
        wrong-exit) echo 'Domain com.apple.windowserver does not exist' >&2; return 2;;
      esac
    }
    main "$test_root/preferences-$preference_error"
  ) > "$test_root/preferences-error.log" 2>&1 || fail 'preference error report'
  contains "$test_root/preferences-$preference_error/report.md" '| Display preferences | FAILED |'
  contains "$test_root/preferences-$preference_error/summary.txt" 'Display preferences: FAILED'
done
(
  defaults() { echo 'DisplaySets = fixture'; }
  main "$test_root/preferences-ok"
) > "$test_root/preferences-ok.log" 2>&1 || fail 'available preferences'
contains "$test_root/preferences-ok/report.md" '| Display preferences | OK |'

# Model a local X server becoming visible only after an X11 connection probe.
# The marker persists across command substitutions just as process state does.
(
  glxinfo() { echo 'OpenGL renderer string: Intel HD Graphics 6000'; }
  xdpyinfo() {
    touch "$test_root/x11-ready"
    printf 'name of display: :0\n    GLX\n'
  }
  pgrep() {
    case "$3" in
      WindowServer) echo '100 WindowServer';;
      Xquartz)
        [ -f "$test_root/x11-ready" ] || return 1
        echo '101 Xquartz';;
      *) return 1;;
    esac
  }
  main "$test_root/xquartz-late"
) > "$test_root/xquartz-late.log" 2>&1 || fail 'post-probe process snapshot'
contains "$test_root/xquartz-late/report.md" '| XQuartz process | OK |'
contains "$test_root/xquartz-late/opengl.txt" 'Checked after the X11/GLX probes'
contains "$test_root/xquartz-late/raw/xquartz.txt" '101 Xquartz'
(
  pgrep() { return 1; }
  main "$test_root/xquartz-absent"
) > "$test_root/xquartz-absent.log" 2>&1 || fail 'absent local process'
contains "$test_root/xquartz-absent/report.md" '| XQuartz process | NOT REPORTED |'
contains "$test_root/xquartz-absent/report.md" '| X11 display connection | OK |'

# Large earlier families must not consume Intel's entire preview budget.
(
  ls() {
    local i
    for ((i=0; i<45; i++)); do printf 'AGXFixture%s.kext\n' "$i"; done
    for ((i=0; i<45; i++)); do printf 'AMDController%s.kext\n' "$i"; done
    printf 'AppleIntelBDWGraphics.kext\nAppleIntelBDWGraphicsFramebuffer.kext\n'
    printf 'GeForceFixture.kext\nVMwareGfx.kext\nIOGraphicsFamily.kext\nAppleHDA.kext\n'
  }
  kextstat() {
    echo '1 0 0xffffff 0x100 0x100 com.apple.driver.AppleIntelBDWGraphics (18.0.8) UUID <1>'
  }
  main "$test_root/driver-families"
) > "$test_root/driver-families.log" 2>&1 || fail 'grouped installed drivers'
contains "$test_root/driver-families/kexts.txt" 'Intel (2 files)'
contains "$test_root/driver-families/kexts.txt" 'AMD / ATI (45 files)'
contains "$test_root/driver-families/kexts.txt" 'Apple / AGX (45 files)'
contains "$test_root/driver-families/kexts.txt" 'NVIDIA / GeForce (1 file)'
contains "$test_root/driver-families/kexts.txt" 'VMware (1 file)'
contains "$test_root/driver-families/kexts.txt" 'Shared graphics (1 file)'
contains "$test_root/driver-families/kexts.txt" 'AppleIntelBDWGraphicsFramebuffer.kext'
contains "$test_root/driver-families/kexts.txt" '[More lines omitted; see raw evidence.]'
omits "$test_root/driver-families/kexts.txt" 'AMDController44.kext'
omits "$test_root/driver-families/kexts.txt" 'AGXFixture44.kext'
omits "$test_root/driver-families/kexts.txt" 'AppleHDA'
contains "$test_root/driver-families/raw/installed.txt" 'AMDController44.kext'
contains "$test_root/driver-families/raw/installed.txt" 'AGXFixture44.kext'
awk '
  /^Loaded graphics-related extensions/ { loaded=NR }
  /^Installed graphics-related extensions/ { installed=NR }
  length($0)>100 { exit 1 }
  END { if (!loaded || !installed || loaded >= installed) exit 1 }
' "$test_root/driver-families/kexts.txt" || fail 'driver ordering or width'
(
  kextstat() { echo 'mock loaded-driver query denied' >&2; return 1; }
  main "$test_root/loaded-failed"
) > "$test_root/loaded-failed.log" 2>&1 || fail 'failed loaded-driver query'
contains "$test_root/loaded-failed/kexts.txt" 'mock loaded-driver query denied'
contains "$test_root/loaded-failed/kexts.txt" 'Installed graphics-related extensions'
contains "$test_root/loaded-failed/kexts.txt" 'AMDRadeonX4000.kext'

# Supplemental shell write-error test; /dev/full does not exist on macOS.
if [ -c /dev/full ]; then
  mkdir -p "$test_root/disk-full"
  ln -s /dev/full "$test_root/disk-full/report.md"
  if (main "$test_root/disk-full") > "$test_root/full.log" 2>&1; then fail 'disk full must fail'; fi
  contains "$test_root/disk-full/summary.txt" 'Diagnostics incomplete:'
fi
if [ "${GPU_INFO_SHOW_TEST_REPORT:-0}" = 1 ]; then command cat "$valid/report.md"; fi
echo 'PASS: readable reports, raw evidence, statuses, snapshots, links, and failure handling'
