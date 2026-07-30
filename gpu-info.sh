#!/bin/bash
set -uo pipefail

OUTDIR="${1:-./gpu-report}"
mkdir -p "$OUTDIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

report_missing() {
  local tool="$1"
  echo "Tool not available: $tool"
}

find_glxinfo() {
  local candidates=(
    "/System/Library/Frameworks/OpenGL.framework/Versions/A/Resources/glxinfo"
    "/opt/X11/bin/glxinfo"
    "/usr/local/bin/glxinfo"
    "/usr/X11/bin/glxinfo"
  )

  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  if command -v glxinfo >/dev/null 2>&1; then
    command -v glxinfo
    return 0
  fi

  return 1
}

log "Starting GPU diagnostics"

{
  echo "=== uname ==="
  uname -a 2>&1 || echo "uname failed"
  echo
  echo "=== sw_vers ==="
  sw_vers 2>&1 || echo "sw_vers failed"
  echo
  echo "=== system_profiler SPHardwareDataType ==="
  if command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPHardwareDataType 2>&1 || echo "system_profiler SPHardwareDataType failed"
  else
    report_missing system_profiler
  fi
  echo
  echo "=== system_profiler SPDisplaysDataType ==="
  if command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPDisplaysDataType 2>&1 || echo "system_profiler SPDisplaysDataType failed"
  else
    report_missing system_profiler
  fi
  echo
  echo "=== system_profiler SPSoftwareDataType ==="
  if command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPSoftwareDataType 2>&1 || echo "system_profiler SPSoftwareDataType failed"
  else
    report_missing system_profiler
  fi
} > "$OUTDIR/system-info.txt" 2>&1

{
  echo "=== ioreg ==="
  if command -v ioreg >/dev/null 2>&1; then
    ioreg -l 2>&1 | grep -iE 'GPU|display|vga|accelerat|vendor|device-id|model' | head -200 || true
  else
    report_missing ioreg
  fi
  echo
  echo "=== system_profiler SPHardwareDataType | grep -i 'Graphics' ==="
  if command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPHardwareDataType 2>&1 | grep -i 'Graphics' || true
  else
    report_missing system_profiler
  fi
} > "$OUTDIR/hardware.txt" 2>&1

{
  echo "=== system_profiler SPDisplaysDataType ==="
  if command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPDisplaysDataType 2>&1 || echo "system_profiler SPDisplaysDataType failed"
  else
    report_missing system_profiler
  fi
  echo
  echo "=== defaults read com.apple.windowserver.plist | grep -i 'Display' ==="
  if command -v defaults >/dev/null 2>&1; then
    defaults read com.apple.windowserver.plist 2>/dev/null | grep -i 'Display' || true
  else
    report_missing defaults
  fi
} > "$OUTDIR/display.txt" 2>&1

{
  echo "=== ls /System/Library/Extensions ==="
  if [ -d /System/Library/Extensions ]; then
    ls /System/Library/Extensions 2>&1 | grep -iE 'Apple|Intel|AMD|NVIDIA|GeForce|Metal|IOAccelerator' | head -200 || true
  else
    echo "Directory not found: /System/Library/Extensions"
  fi
  echo
  echo "=== kextstat | grep -i -E 'Apple|Intel|AMD|NVIDIA|GeForce' ==="
  if command -v kextstat >/dev/null 2>&1; then
    kextstat 2>&1 | grep -i -E 'Apple|Intel|AMD|NVIDIA|GeForce' || true
  else
    report_missing kextstat
  fi
} > "$OUTDIR/kexts.txt" 2>&1

{
  echo "=== launchctl print system/com.apple.windowserver ==="
  if command -v launchctl >/dev/null 2>&1; then
    launchctl print system/com.apple.windowserver 2>/dev/null | head -200 || true
  else
    report_missing launchctl
  fi
  echo
  echo "=== ps aux | grep WindowServer ==="
  ps aux 2>&1 | grep -i '[W]indowServer' || true
} > "$OUTDIR/windowserver.txt" 2>&1

{
  echo "=== OpenGL renderer ==="
  GLXINFO_BIN=""
  if GLXINFO_BIN=$(find_glxinfo 2>/dev/null); then
    "$GLXINFO_BIN" 2>/dev/null | grep -i 'renderer' || true
  else
    echo "OpenGL tool not available: glxinfo"
  fi
  echo
  echo "=== OpenGL vendor ==="
  GLXINFO_BIN=""
  if GLXINFO_BIN=$(find_glxinfo 2>/dev/null); then
    "$GLXINFO_BIN" 2>/dev/null | grep -i 'vendor' || true
  else
    echo "OpenGL tool not available: glxinfo"
  fi
  echo
  echo "=== OpenGL version ==="
  GLXINFO_BIN=""
  if GLXINFO_BIN=$(find_glxinfo 2>/dev/null); then
    "$GLXINFO_BIN" 2>/dev/null | grep -i 'version' || true
  else
    echo "OpenGL tool not available: glxinfo"
  fi
} > "$OUTDIR/opengl.txt" 2>&1

{
  echo "=== Metal system info ==="
  if command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPDisplaysDataType 2>/dev/null | grep -i 'Metal' || true
  else
    report_missing system_profiler
  fi
  echo
  echo "=== available GPUs ==="
  if command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPDisplaysDataType 2>/dev/null | grep -i 'Chipset Model\|VRAM' || true
  else
    report_missing system_profiler
  fi
} > "$OUTDIR/metal.txt" 2>&1

{
  echo "=== hardware perf ==="
  if command -v top >/dev/null 2>&1; then
    top -l 1 -s 0 2>&1 | head -80 || true
  else
    report_missing top
  fi
  echo
  echo "=== vm_stat ==="
  if command -v vm_stat >/dev/null 2>&1; then
    vm_stat 2>&1 || echo "vm_stat failed"
  else
    report_missing vm_stat
  fi
} > "$OUTDIR/perf.txt" 2>&1

{
  echo "=== Network and display environment ==="
  env 2>&1 | grep -iE 'DISPLAY|GPU|OPENGL|METAL|VMWARE|VIRTUAL' || true
} > "$OUTDIR/env.txt" 2>&1

{
  echo "Diagnostics completed."
  echo
  echo "Generated files:"
  ls -1 "$OUTDIR" 2>/dev/null || true
} > "$OUTDIR/summary.txt" 2>&1

log "Report written to $OUTDIR"

echo "GPU diagnostics saved in: $OUTDIR"
