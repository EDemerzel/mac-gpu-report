#!/bin/bash
set -uo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

report_missing() {
  local tool="$1"
  echo "Tool not available: $tool"
}

# Capture status before filtering so errors cannot disappear into a blank section.
# An unavailable diagnostic is report content, not a report-file write failure.
run_diagnostic() {
  local pattern="$1" limit="$2"
  shift 2
  local output="" status=0
  if ! command -v "$1" >/dev/null 2>&1; then
    report_missing "$1"
    return 0
  fi
  output=$("$@" 2>&1) || status=$?
  if [ "$status" -ne 0 ]; then
    printf 'Command failed (exit=%s): %s\n' "$status" "$*"
    printf '%s\n' "$output"
    return 0
  fi
  if [ -n "$pattern" ]; then
    output=$(printf '%s\n' "$output" | grep -iE "$pattern") || {
      echo "No matching data reported."
      return 0
    }
  fi
  if [ -z "$output" ]; then
    echo "No data reported."
  elif [ "$limit" -gt 0 ]; then
    # Consume all input to avoid SIGPIPE with pipefail, and mark truncation.
    printf '%s\n' "$output" | awk -v limit="$limit" '
      NR <= limit { print }
      END { if (NR > limit) print "[Output truncated after " limit " lines.]" }
    '
  else
    printf '%s\n' "$output"
  fi
}

write_report() {
  local filename="$1" content=""
  shift
  if ! content=$("$@" 2>&1); then
    printf 'Could not collect report: %s\n' "$filename" >&2
    write_failed=1
    return 0
  fi
  if printf '%s\n' "$content" > "$OUTDIR/$filename"; then
    generated_files+=("$filename")
  else
    printf 'Could not write report: %s/%s\n' "$OUTDIR" "$filename" >&2
    write_failed=1
  fi
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

resolve_display() {
  if [ -n "${DISPLAY:-}" ]; then
    echo "$DISPLAY"
    return 0
  fi

  if command -v launchctl >/dev/null 2>&1; then
    local launch_display=""
    launch_display=$(launchctl getenv DISPLAY 2>/dev/null || true)
    if [ -n "$launch_display" ]; then
      echo "$launch_display"
      return 0
    fi
  fi

  if [ -n "${XAUTHORITY:-}" ] && [ -S /private/tmp/.X11-unix/X0 ]; then
    echo ":0"
    return 0
  fi

  echo ":0"
}

run_glxinfo_probe() {
  local label="$1"
  shift

  local glxinfo_bin=""
  if ! glxinfo_bin=$(find_glxinfo 2>/dev/null); then
    echo "=== $label ==="
    echo "OpenGL tool not available: glxinfo"
    return 0
  fi

  echo "=== $label ==="
  local display_arg=""
  display_arg=$(resolve_display)
  if [ -n "$display_arg" ]; then
    echo "DISPLAY=$display_arg"
  fi

  local glx_output=""
  glx_output=$("$glxinfo_bin" -display "$display_arg" "$@" 2>&1)
  local glx_exit=$?
  local glx_has_error=0

  if printf '%s\n' "$glx_output" | grep -qiE 'unable to open display|xlib:|error:'; then
    glx_has_error=1
  fi

  if [ "$glx_exit" -eq 0 ] && [ "$glx_has_error" -eq 0 ]; then
    printf '%s\n' "$glx_output"
    return 0
  fi

  if [ "$glx_exit" -eq 0 ] && [ "$glx_has_error" -eq 1 ]; then
    echo "OpenGL probe failed (glxinfo exited 0 but reported an error)."
  else
    echo "OpenGL probe failed (exit=$glx_exit)."
  fi
  echo "glxinfo error output:"
  printf '%s\n' "$glx_output" | head -40

  if printf '%s\n' "$glx_output" | grep -qi "CGLChoosePixelFormat error"; then
    echo
    echo "Hint: the X server is reachable, but no compatible OpenGL pixel format is available."
    echo "Hint: this is common in virtualized GPUs or limited XQuartz/driver combinations."
  fi

  echo
  echo "Likely cause: glxinfo and the active X server are not compatible for GLX probing."
  echo
  diagnose_glx_probe "$display_arg"
}

find_xdpyinfo() {
  local candidates=(
    "/opt/X11/bin/xdpyinfo"
    "/usr/local/bin/xdpyinfo"
    "/usr/X11/bin/xdpyinfo"
  )

  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  if command -v xdpyinfo >/dev/null 2>&1; then
    command -v xdpyinfo
    return 0
  fi

  return 1
}

diagnose_glx_probe() {
  local display_arg="$1"
  echo "=== X11/GLX diagnostics ==="

  if pgrep -x Xquartz >/dev/null 2>&1 || pgrep -x X11.bin >/dev/null 2>&1; then
    echo "XQuartz process: detected"
  else
    echo "XQuartz process: not detected"
    echo "Hint: start XQuartz, then rerun the script."
  fi

  if [ -S /private/tmp/.X11-unix/X0 ]; then
    echo "X11 socket /private/tmp/.X11-unix/X0: present"
  else
    echo "X11 socket /private/tmp/.X11-unix/X0: not found"
    echo "Hint: XQuartz may not be fully initialized yet."
  fi

  if [ -n "${XAUTHORITY:-}" ]; then
    echo "XAUTHORITY: ${XAUTHORITY}"
  else
    echo "XAUTHORITY: not set"
  fi

  local xdpyinfo_bin=""
  if ! xdpyinfo_bin=$(find_xdpyinfo 2>/dev/null); then
    echo "xdpyinfo: not available"
    echo "Hint: install XQuartz tools to enable deeper X11 checks."
    return 0
  fi

  local xdpy_out=""
  if xdpy_out=$("$xdpyinfo_bin" -display "$display_arg" 2>&1); then
    echo "xdpyinfo: display connection OK"
    if printf '%s\n' "$xdpy_out" | grep -q "GLX"; then
      echo "GLX extension: present"
    else
      echo "GLX extension: not reported"
      echo "Hint: this X server does not expose GLX; glxinfo -B cannot report OpenGL renderer details here."
    fi
  else
    echo "xdpyinfo: failed to connect to DISPLAY=$display_arg"
    printf '%s\n' "$xdpy_out" | head -20
    echo "Hint: verify DISPLAY and XQuartz permissions."
    echo "Hint: from an XQuartz terminal, try: echo \$DISPLAY"
  fi
}

system_report() {
  echo "=== uname ==="
  run_diagnostic "" 0 uname -a
  echo
  echo "=== sw_vers ==="
  run_diagnostic "" 0 sw_vers
  echo
  echo "=== system_profiler SPHardwareDataType ==="
  run_diagnostic "" 0 system_profiler SPHardwareDataType
  echo
  echo "=== system_profiler SPDisplaysDataType ==="
  run_diagnostic "" 0 system_profiler SPDisplaysDataType
  echo
  echo "=== system_profiler SPSoftwareDataType ==="
  run_diagnostic "" 0 system_profiler SPSoftwareDataType
}

hardware_report() {
  local graphics_class
  # Class matching includes subclasses. Depth 1 excludes unrelated descendants;
  # no global line cap can discard a later GPU. Classes vary by driver/hardware.
  for graphics_class in IOFramebuffer IODisplay IOAccelerator IOGPU; do
    echo "=== ioreg: $graphics_class ==="
    run_diagnostic "" 0 ioreg -r -l -d 1 -w 0 -c "$graphics_class"
    echo
  done
  echo "=== system_profiler SPDisplaysDataType ==="
  run_diagnostic "" 0 system_profiler SPDisplaysDataType
}

display_report() {
  echo "=== system_profiler SPDisplaysDataType ==="
  run_diagnostic "" 0 system_profiler SPDisplaysDataType
  echo
  echo "=== defaults read com.apple.windowserver (Display lines) ==="
  run_diagnostic 'Display' 0 defaults read com.apple.windowserver
}

kext_report() {
  echo "=== ls /System/Library/Extensions ==="
  if [ -d /System/Library/Extensions ]; then
    run_diagnostic 'Apple|Intel|AMD|NVIDIA|GeForce|Metal|IOAccelerator' 200 ls /System/Library/Extensions
  else
    echo "Directory not found: /System/Library/Extensions"
  fi
  echo
  echo "=== kextstat | grep -i -E 'Apple|Intel|AMD|NVIDIA|GeForce' ==="
  run_diagnostic 'Apple|Intel|AMD|NVIDIA|GeForce' 0 kextstat
}

windowserver_report() {
  echo "=== launchctl print system/com.apple.WindowServer ==="
  run_diagnostic "" 200 launchctl print system/com.apple.WindowServer
  echo
  echo "=== ps aux | grep WindowServer ==="
  run_diagnostic '[W]indowServer' 0 ps aux
}

opengl_report() {
  echo "=== macOS display/OpenGL summary ==="
  run_diagnostic 'Chipset Model|VRAM|Metal|Resolution|Framebuffer|Displays' 0 system_profiler SPDisplaysDataType
  echo
  run_glxinfo_probe "X11 OpenGL probe (-B)" -B
}

metal_report() {
  echo "=== Metal system info ==="
  run_diagnostic 'Metal' 0 system_profiler SPDisplaysDataType
  echo
  echo "=== available GPUs ==="
  run_diagnostic 'Chipset Model|VRAM' 0 system_profiler SPDisplaysDataType
}

performance_report() {
  echo "=== hardware perf ==="
  run_diagnostic "" 80 top -l 1 -s 0
  echo
  echo "=== vm_stat ==="
  run_diagnostic "" 0 vm_stat
}

environment_report() {
  echo "=== Network and display environment ==="
  # Match names, not unrelated variables whose values contain a GPU keyword.
  run_diagnostic '^[^=]*(DISPLAY|GPU|OPENGL|METAL|VMWARE|VIRTUAL)[^=]*=' 0 env
}

summary_report() {
  if [ "$write_failed" -eq 0 ]; then
    echo "Diagnostics completed. Probe failures, if any, are recorded in the reports."
  else
    echo "Diagnostics incomplete: one or more report files could not be written."
  fi
  echo
  echo "Generated files:"
  local filename
  # Iterating by count also works with nounset and an empty array in Bash 3.2.
  local index
  for ((index=0; index<${#generated_files[@]}; index++)); do
    filename="${generated_files[index]}"
    printf '%s\n' "$filename"
  done
  echo "summary.txt"
}

main() {
  OUTDIR="${1:-./gpu-report}"
  # Reports contain machine, user, and process details.
  umask 077
  case "$OUTDIR" in
    /*|./*|../*) ;;
    *) OUTDIR="./$OUTDIR" ;;
  esac
  if ! mkdir -p "$OUTDIR" || [ ! -d "$OUTDIR" ] || [ ! -w "$OUTDIR" ]; then
    printf 'Cannot create or write report directory: %s\n' "$OUTDIR" >&2
    return 1
  fi

  generated_files=()
  write_failed=0
  log "Starting GPU diagnostics"
  write_report system-info.txt system_report
  write_report hardware.txt hardware_report
  write_report display.txt display_report
  write_report kexts.txt kext_report
  write_report windowserver.txt windowserver_report
  write_report opengl.txt opengl_report
  write_report metal.txt metal_report
  write_report perf.txt performance_report
  write_report env.txt environment_report
  write_report summary.txt summary_report

  if [ "$write_failed" -ne 0 ]; then
    printf 'GPU diagnostics incomplete; check errors and reports in: %s\n' "$OUTDIR" >&2
    return 1
  fi
  log "Report written to $OUTDIR"
  echo "GPU diagnostics saved in: $OUTDIR"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
