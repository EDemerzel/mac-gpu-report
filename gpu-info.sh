#!/bin/bash
# macOS GPU diagnostics. Bash 3.2-compatible; no third-party parser required.
set -uo pipefail

SCRIPT_VERSION="2.2.0"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Each command is collected once. Structured status is kept separately from its
# output: words such as "error" in a device name cannot change a probe result.
capture_probe() {
  local id="$1" title="$2"
  shift 2
  local i=${#probe_ids[@]} output="" status="OK" code=0
  if ! command -v "$1" >/dev/null 2>&1; then
    status="TOOL MISSING"
    code=127
    output="Tool not available: $1"
  else
    output=$("$@" 2>&1) || code=$?
    if [ "$code" -ne 0 ]; then
      status="FAILED"
      # pgrep uses exit 1 for a successful search with no matching processes.
      if [ "$1" = pgrep ] && [ "$code" -eq 1 ]; then status="NOT REPORTED"; fi
    elif [ -z "$output" ]; then
      status="NOT REPORTED"
    fi
  fi
  probe_ids[i]="$id"
  probe_titles[i]="$title"
  probe_states[i]="$status"
  probe_codes[i]="$code"
  probe_commands[i]="$*"
  probe_outputs[i]="$output"
  probe_notes[i]=""
}

select_probe() {
  local i
  for ((i=0; i<${#probe_ids[@]}; i++)); do
    if [ "${probe_ids[i]}" = "$1" ]; then PROBE_INDEX=$i; return 0; fi
  done
  return 1
}

was_written() {
  local i
  for ((i=0; i<${#generated_files[@]}; i++)); do
    if [ "${generated_files[i]}" = "$1" ]; then return 0; fi
  done
  return 1
}

write_report() {
  local filename="$1" content=""
  shift
  if content=$("$@" 2>&1) && printf '%s\n' "$content" > "$OUTDIR/$filename"; then
    generated_files+=("$filename")
  else
    printf 'Could not write report: %s/%s\n' "$OUTDIR" "$filename" >&2
    failed_files+=("$filename")
    write_failed=1
  fi
}

metadata() {
  printf 'Collection started: %s\nCollection ended:   %s\n' "$started_at" "$ended_at"
  printf 'Script version:     %s\nSource revision:    %s\n' "$SCRIPT_VERSION" "$source_revision"
}

text_header() {
  printf '%s\n%s\n' "$1" '========================================================================'
  metadata
  echo
}

# Only presentation output is bounded. Complete command output stays in raw/.
preview() {
  local limit="$1"
  awk -v limit="$limit" '
    NR <= limit {
      if (length($0) > 96) { print substr($0, 1, 93) "..."; clipped=1 }
      else print
    }
    END {
      if (NR > limit) print "[More lines omitted; see raw evidence.]"
      if (clipped) print "[Long lines shortened; see raw evidence.]"
    }
  '
}

raw_probe() {
  local i="$1"
  local raw_state="${probe_states[i]}"
  # UNAVAILABLE is a presentation classification of a known optional-domain
  # failure; retain FAILED and its original exit code in the command evidence.
  if [ "$raw_state" = UNAVAILABLE ]; then raw_state=FAILED; fi
  metadata
  printf '\nProbe: %s\nResult: %s\nExit code: %s\nCommand: %s\n\n' \
    "${probe_titles[i]}" "$raw_state" "${probe_codes[i]}" "${probe_commands[i]}"
  if [ "${probe_states[i]}" = UNAVAILABLE ]; then
    echo "Report classification: UNAVAILABLE (optional data)"
  fi
  if [ -n "${probe_notes[i]}" ]; then printf 'Note: %s\n\n' "${probe_notes[i]}"; fi
  printf '%s\n' "${probe_outputs[i]}"
}

# The same command may supply several views (e.g. displays and Metal).
# Missing fields are different from a failed command or unsupported hardware.
section() {
  local id="$1" pattern="${2:-}" limit="${3:-20}" body="" state=""
  select_probe "$id" || return 1
  local i="$PROBE_INDEX"
  body="${probe_outputs[i]}"
  state="${probe_states[i]}"
  if [ "$state" = UNAVAILABLE ]; then body=""; fi
  if [ "$state" = OK ] && [ -n "$pattern" ]; then
    body=$(printf '%s\n' "$body" | grep -iE "$pattern") || body=""
    if [ -z "$body" ]; then state="NOT REPORTED"; fi
  fi
  printf '%s\nResult: %s\n' "${probe_titles[i]}" "$state"
  if [ "$state" = FAILED ]; then printf 'Exit code: %s\n' "${probe_codes[i]}"; fi
  if [ -n "${probe_notes[i]}" ]; then printf '%s\n' "${probe_notes[i]}"; fi
  if [ -n "$body" ]; then printf '%s\n' "$body" | preview "$limit"
  elif [ "$state" != UNAVAILABLE ]; then echo "No matching data reported."
  fi
  if was_written "raw/$id.txt"; then echo "Evidence: ${EVIDENCE_PREFIX:-raw}/$id.txt"
  else echo "Evidence: file could not be written."
  fi
  echo
}

find_x_tool() {
  local name="$1" candidate
  for candidate in "/opt/X11/bin/$name" "/usr/local/bin/$name" \
    "/usr/X11/bin/$name" "/opt/homebrew/bin/$name"; do
    if [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
  done
  command -v "$name" 2>/dev/null
}

resolve_display() {
  if [ -n "${DISPLAY:-}" ]; then printf '%s\n' "$DISPLAY"; return; fi
  local value=""
  if command -v launchctl >/dev/null 2>&1; then
    value=$(launchctl getenv DISPLAY 2>/dev/null || true)
  fi
  printf '%s\n' "${value:-:0}"
}

xquartz_process() {
  pgrep -l -x Xquartz && return 0
  pgrep -l -x X11.bin && return 0
  return 0
}

display_environment() {
  # Limit collection itself: raw evidence must not contain the entire environment.
  env | awk -F= 'toupper($1) ~ /DISPLAY|XAUTHORITY|GPU|OPENGL|METAL|VMWARE|VIRTUAL/'
}

collect_probes() {
  capture_probe os "Operating system" sw_vers
  capture_probe hardware "System hardware" system_profiler SPHardwareDataType
  capture_probe software "System software" system_profiler SPSoftwareDataType
  capture_probe displays "GPU and displays" system_profiler SPDisplaysDataType
  local graphics_class
  for graphics_class in IOFramebuffer IODisplay IOAccelerator IOGPU; do
    capture_probe "$graphics_class" "Registry: $graphics_class" \
      ioreg -r -l -d 1 -w 0 -c "$graphics_class"
  done
  capture_probe preferences "Display preferences" defaults read com.apple.windowserver
  select_probe preferences
  # Only the exact absent-domain response observed on the Mac is informational.
  # Permission errors, other exit codes, and unexpected failures stay FAILED.
  if [ "${probe_states[PROBE_INDEX]}" = FAILED ] &&
     [ "${probe_codes[PROBE_INDEX]}" -eq 1 ] &&
     printf '%s\n' "${probe_outputs[PROBE_INDEX]}" |
       grep -Fx 'Domain com.apple.windowserver does not exist' >/dev/null; then
    probe_states[PROBE_INDEX]="UNAVAILABLE"
    probe_notes[PROBE_INDEX]="Optional display preferences are absent for this user/session."
  fi
  capture_probe installed "Installed extensions" ls -1 /System/Library/Extensions
  capture_probe loaded "Loaded extensions" kextstat
  capture_probe windowserver "WindowServer service" launchctl print system/com.apple.WindowServer
  capture_probe windowserver_process "WindowServer process" pgrep -l -x WindowServer
  local display_arg="" glx_bin="" xdpy_bin=""
  display_arg=$(resolve_display)
  glx_bin=$(find_x_tool glxinfo) || glx_bin=glxinfo
  xdpy_bin=$(find_x_tool xdpyinfo) || xdpy_bin=xdpyinfo
  capture_probe glx "X11 OpenGL renderer probe" "$glx_bin" -display "$display_arg" -B
  select_probe glx
  # Some glxinfo builds return zero even when their GL probe fails.
  if [ "${probe_states[PROBE_INDEX]}" = OK ] &&
     printf '%s\n' "${probe_outputs[PROBE_INDEX]}" |
       grep -iE 'unable to open display|xlib:|error:' >/dev/null; then
    probe_states[PROBE_INDEX]="FAILED"
    probe_notes[PROBE_INDEX]="glxinfo exited 0 but reported an error."
  fi
  capture_probe x11 "X11 display connection" "$xdpy_bin" -display "$display_arg"
  # Take the local process snapshot after both connection probes, so it cannot
  # describe an earlier process state than the successful X11/GLX checks.
  capture_probe xquartz "XQuartz process" xquartz_process
  select_probe xquartz
  probe_notes[PROBE_INDEX]="Checked after the X11/GLX probes; this is a local process snapshot."
  # Apple's top documentation states that first-sample per-process CPU is invalid.
  capture_probe top "CPU and memory snapshot" top -l 2 -s 1 -n 10 -o cpu \
    -stats pid,command,cpu,mem
  capture_probe memory "Virtual memory counters" vm_stat
  capture_probe environment "Display-related environment" display_environment
}

system_report() {
  if [ "${1:-}" != body ]; then text_header "System overview"; fi
  section os
  section hardware 'Model Name:|Model Identifier:|Processor Name:|Processor Speed:|Total Number of Cores:|Memory:'
  section software 'System Version:|Kernel Version:|Boot Mode:|System Integrity Protection:|Time since boot:'
}

display_report() {
  text_header "GPU and displays"
  # Preserve headings/indentation to associate values with each GPU and display.
  section displays '^[[:space:]]*[^:]+:$|Chipset Model:|Type:|Vendor|VRAM|Metal|Resolution:|Framebuffer|Main Display:|Mirror:|Online:' 50
  section preferences 'Display' 12
}

hardware_report() {
  text_header "Graphics registry overview"
  echo "GPU names, VRAM and resolution: display.txt"
  echo "An absent registry class does not establish a GPU fault."
  echo
  local graphics_class
  for graphics_class in IOFramebuffer IODisplay IOAccelerator IOGPU; do
    # Select useful properties; suppress large nested dictionaries.
    section "$graphics_class" '^[[:space:]|+\\-]*o |"(IOClass|IOProviderClass|model|vendor-id|device-id|VRAM,totalMB|IOFBMemorySize|DisplayProductID|DisplayVendorID)"[[:space:]]*=' 12
  done
}

loaded_graphics_report() {
  select_probe loaded
  if [ "${probe_states[PROBE_INDEX]}" != OK ]; then section loaded; return; fi
  echo "Loaded graphics-related extensions"
  local drivers=""
  drivers=$(printf '%s\n' "${probe_outputs[PROBE_INDEX]}" | awk '
    /AGX|AMD|ATI|Intel.*(Graphics|Framebuffer)|NVIDIA|GeForce|Metal|IOAccelerator|IOGraphics|AppleGraphics|GPU|VMware/ {
      for (i=1; i<NF; i++) if ($i ~ /^com\./) print $i, $(i+1)
    }
  ')
  if [ -n "$drivers" ]; then
    echo "Result: OK"
    printf '%s\n' "$drivers" | preview 30
  else
    echo "Result: NOT REPORTED"
    echo "No matching driver names reported."
  fi
  if was_written raw/loaded.txt; then echo "Evidence: ${EVIDENCE_PREFIX:-raw}/loaded.txt"; fi
}

installed_graphics_report() {
  select_probe installed
  if [ "${probe_states[PROBE_INDEX]}" != OK ]; then section installed; return; fi
  local installed="${probe_outputs[PROBE_INDEX]}" family="" drivers="" count=0 total=0 unit=""
  echo "Installed graphics-related extensions (grouped by name family)"
  echo "Each family shows up to 12 files; full lists are in ${EVIDENCE_PREFIX:-raw}/installed.txt."
  for family in Intel "AMD / ATI" "NVIDIA / GeForce" "Apple / AGX" VMware "Shared graphics"; do
    drivers=$(printf '%s\n' "$installed" | awk -v wanted="$family" '
      {
        name=tolower($0); family=""
        if (name ~ /intel.*(graphics|framebuffer)/) family="Intel"
        else if (name ~ /amd|^ati/) family="AMD / ATI"
        else if (name ~ /nvidia|geforce/) family="NVIDIA / GeForce"
        else if (name ~ /vmware/) family="VMware"
        else if (name ~ /^agx/) family="Apple / AGX"
        else if (name ~ /metal|ioaccelerator|iographics|applegraphics|gpu/) family="Shared graphics"
        if (family == wanted) print
      }
    ')
    if [ -n "$drivers" ]; then
      count=$(printf '%s\n' "$drivers" | awk 'END {print NR}')
      total=$((total+count))
      unit=files
      if [ "$count" -eq 1 ]; then unit="file"; fi
      printf '\n%s (%s %s)\n' "$family" "$count" "$unit"
      printf '%s\n' "$drivers" | preview 12
    fi
  done
  echo
  if [ "$total" -gt 0 ]; then
    printf 'Result: OK (%s matching installed files)\n' "$total"
  else
    echo "Result: NOT REPORTED"
    echo "No matching installed files reported."
  fi
  if was_written raw/installed.txt; then echo "Evidence: ${EVIDENCE_PREFIX:-raw}/installed.txt"
  else echo "Evidence: file could not be written."
  fi
}

kext_report() {
  text_header "Graphics-related drivers"
  echo "Loaded drivers are shown first; installed files are grouped by name family."
  echo "Neither list alone establishes which driver is active for a GPU."
  echo
  loaded_graphics_report
  echo
  installed_graphics_report
}

windowserver_report() {
  text_header "WindowServer"
  section windowserver_process
  section windowserver 'state =|pid =|program =|runs =|last exit code' 12
  echo "A service-query failure does not imply the process is stopped."
}

opengl_report() {
  if [ "${1:-}" != body ]; then text_header "X11 / GLX diagnostics"; fi
  section glx '' 12
  echo "Scope: X11/GLX renderer query; this is not a native Metal test."
  echo
  section x11 'name of display:|GLX' 8
  section xquartz '' 4
  local glx_state="" x11_state=""
  select_probe glx; glx_state="${probe_states[PROBE_INDEX]}"
  select_probe x11; x11_state="${probe_states[PROBE_INDEX]}"
  if [ "$x11_state" = OK ]; then
    if printf '%s\n' "${probe_outputs[PROBE_INDEX]}" |
       grep -E '^[[:space:]]*GLX[[:space:]]*$' >/dev/null; then
      echo "GLX extension: PRESENT"
    else
      echo "GLX extension: NOT REPORTED"
    fi
  else
    echo "GLX extension: NOT CHECKED (no successful X11 connection query)"
  fi
  echo
  if [ "$glx_state" = FAILED ]; then
    echo "Interpretation:"
    if [ "$x11_state" = OK ]; then
      echo "  The X11 connection succeeded, but the renderer probe failed."
      echo "  The cause is not established by these checks."
      echo "Next step: inspect the GLX error above and any available raw X11 evidence."
    else
      echo "  The renderer probe failed; a working X11 connection was not confirmed."
      echo "Next step: verify DISPLAY and the X11 session, then repeat the probe."
    fi
  elif [ "$glx_state" = "TOOL MISSING" ]; then
    echo "Next step: provide glxinfo if X11 renderer diagnostics are needed."
  fi
}

metal_state() {
  select_probe displays
  if [ "${probe_states[PROBE_INDEX]}" != OK ]; then
    printf '%s\n' "${probe_states[PROBE_INDEX]}"
  elif printf '%s\n' "${probe_outputs[PROBE_INDEX]}" | grep -i 'Metal' >/dev/null; then
    echo "REPORTED"
  else
    echo "NOT REPORTED"
  fi
}

metal_report() {
  text_header "Metal visibility"
  printf 'Result: %s\n' "$(metal_state)"
  section displays 'Metal' 12
  echo "Read the reported value for support details."
  echo "A missing Metal field does not prove that Metal is unsupported."
  echo "GPU identity and display configuration: display.txt"
}

# Extract the final top sample without splitting process names on whitespace.
last_top_sample() {
  awk '
    /^Processes:/ { samples++; block="" }
    { block=block $0 "\n" }
    END { if (samples >= 2) printf "%s", block; else exit 1 }
  '
}

performance_report() {
  if [ "${1:-}" != body ]; then text_header "Performance snapshot"; fi
  echo "Two samples, one second apart; the second sample is shown."
  echo "Up to 10 processes ordered by CPU. This is not a GPU benchmark."
  echo
  select_probe top
  if [ "${probe_states[PROBE_INDEX]}" = OK ]; then
    local sample=""
    if sample=$(printf '%s\n' "${probe_outputs[PROBE_INDEX]}" | last_top_sample); then
      echo "Result: OK"
      printf '%s\n' "$sample" | awk '
        /^Processes:|^Load Avg:|^CPU usage:|^PhysMem:|^PID[[:space:]]/ ||
        /^[0-9]+[+*-]?[[:space:]]/ { print }
      ' | preview 20
    else
      echo "Result: NOT REPORTED"
      echo "Could not identify the second top sample; inspect ${EVIDENCE_PREFIX:-raw}/top.txt."
    fi
    if was_written raw/top.txt; then echo "Evidence: ${EVIDENCE_PREFIX:-raw}/top.txt"; fi
    echo
  else
    section top
  fi
  section memory 'page size|Pages free:|Pages active:|Pages inactive:|Pages wired down:|Pages occupied by compressor:|Swapins:|Swapouts:' 10
  echo "vm_stat values are page counts/counters, not MB or a current swap rate."
}

environment_report() {
  text_header "Display environment"
  section environment '' 20
  echo "Environment values can contain sensitive information; review before sharing."
}

attention_items() {
  local i count=0
  for ((i=0; i<${#probe_ids[@]}; i++)); do
    case "${probe_states[i]}" in
      FAILED|"TOOL MISSING")
        printf '%s: %s\n' "${probe_titles[i]}" "${probe_states[i]}"
        count=$((count+1))
        ;;
    esac
  done
  if [ "$(metal_state)" = "NOT REPORTED" ]; then
    echo "Metal: not reported (support is undetermined)."
    count=$((count+1))
  fi
  for ((i=0; i<${#failed_files[@]}; i++)); do
    printf 'File write failed: %s\n' "${failed_files[i]}"
    count=$((count+1))
  done
  if [ "$count" -eq 0 ]; then
    echo "No probe or file-write issues requiring attention; this is not a GPU health verdict."
  fi
}

status_symbol() {
  case "$1" in
    OK) printf '🟢';;
    FAILED) printf '🔴';;
    "TOOL MISSING") printf '🟡';;
    UNAVAILABLE|REPORTED|PRESENT) printf '🔵';;
    *) printf '⚪';;
  esac
}

detail_text_report() {
  local EVIDENCE_PREFIX=../raw
  "$@"
}

# Resolve the exact directory before moving anything. Never archive a symlink,
# a filesystem root, or a directory containing the user's home/cwd/script.
resolve_output_directory() {
  local parent leaf protected physical
  while [ "$OUTDIR" != / ] && [ "${OUTDIR%/}" != "$OUTDIR" ]; do OUTDIR="${OUTDIR%/}"; done
  leaf="${OUTDIR##*/}"
  case "$leaf" in ''|.|..|.git|.agents|.codex)
    printf 'Unsafe report directory: %s\n' "$OUTDIR" >&2; return 1;;
  esac
  case "$OUTDIR" in /*|./*|../*) ;; *) OUTDIR="./$OUTDIR";; esac
  parent="${OUTDIR%/*}"
  [ -n "$parent" ] || parent=/
  if ! mkdir -p "$parent" || ! parent=$(cd -P "$parent" && pwd -P); then
    printf 'Cannot create or write report directory: %s\n' "$OUTDIR" >&2; return 1
  fi
  OUTDIR="$parent/$leaf"
  # Direct children of / and common system/container directories are not report folders.
  case "$OUTDIR" in
    /private|/private/var|/private/tmp|/private/etc|/Volumes/*|/Users/*)
      case "$parent" in /|/private|/Volumes|/Users)
        printf 'Unsafe report directory: %s\n' "$OUTDIR" >&2; return 1;;
      esac;;
  esac
  if [ "$parent" = / ]; then
    printf 'Unsafe report directory: %s\n' "$OUTDIR" >&2; return 1
  fi
  for protected in "$SCRIPT_DIR" "$PWD" "${HOME:-}"; do
    [ -n "$protected" ] && [ -d "$protected" ] || continue
    physical=$(cd -P "$protected" && pwd -P) || return 1
    # File identity also handles case aliases on typical macOS filesystems.
    while [ "$physical" != / ]; do
      if [ "$OUTDIR" -ef "$physical" ]; then
        printf 'Unsafe report directory (contains home, working directory, or script): %s\n' "$OUTDIR" >&2
        return 1
      fi
      physical="${physical%/*}"
      [ -n "$physical" ] || physical=/
    done
  done
  if [ -L "$OUTDIR" ] || { [ -e "$OUTDIR" ] && [ ! -d "$OUTDIR" ]; }; then
    printf 'Cannot create or write report directory: %s (not a real directory)\n' "$OUTDIR" >&2
    return 1
  fi
}

# Hold this lock for the entire collection, not just the rename. main runs in a
# subshell, so its exit/signal traps do not replace a caller's traps.
prepare_output_directory() {
  local archive_root stamp
  OUTPUT_LOCK="$OUTDIR.lock"
  if ! mkdir "$OUTPUT_LOCK"; then
    printf 'Cannot acquire report lock: %s (another run or a stale lock; no reports moved)\n' "$OUTPUT_LOCK" >&2
    return 1
  fi
  trap 'rmdir "$OUTPUT_LOCK" || printf "Could not remove report lock: %s\n" "$OUTPUT_LOCK" >&2' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # Recheck after locking, before any move.
  if [ -L "$OUTDIR" ] || { [ -e "$OUTDIR" ] && [ ! -d "$OUTDIR" ]; }; then
    printf 'Report directory changed during startup; stopping: %s\n' "$OUTDIR" >&2; return 1
  fi
  if [ -d "$OUTDIR" ]; then
    stamp=$(date -u '+%Y%m%dT%H%M%SZ') || return 1
    # An exclusively created private container prevents timestamp collisions
    # and ensures mv cannot overwrite or nest inside an existing destination.
    archive_root=$(mktemp -d "$OUTDIR.archive-$stamp.XXXXXX") || {
      printf 'Cannot create report archive; previous reports unchanged: %s\n' "$OUTDIR" >&2
      return 1
    }
    ARCHIVED_REPORT="$archive_root/${OUTDIR##*/}"
    if ! mv "$OUTDIR" "$ARCHIVED_REPORT"; then
      printf 'Cannot archive report directory; stopping before collection: %s\n' "$OUTDIR" >&2
      rmdir "$archive_root" 2>/dev/null || true
      return 1
    fi
    printf 'Previous reports archived at: %s\n' "$ARCHIVED_REPORT"
  fi
  # No -p for the output root: refuse a directory that appeared concurrently.
  if ! mkdir "$OUTDIR" || ! mkdir "$OUTDIR/raw" "$OUTDIR/details"; then
    printf 'Cannot create fresh report directory: %s\n' "$OUTDIR" >&2
    return 1
  fi
}

# Self-contained HTML: escape every captured line before adding trusted markup.
# No JavaScript, remote assets, or untrusted values in HTML attributes.
html_detail_report() {
  local id="$1" title="$2" evidence_paths="" i
  for ((i=0; i<${#probe_ids[@]}; i++)); do
    if was_written "raw/${probe_ids[i]}.txt"; then
      evidence_paths="$evidence_paths ../raw/${probe_ids[i]}.txt"
    fi
  done
  printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n'
  printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<title>%s — GPU diagnostics</title>\n' "$title"
  printf '%s\n' '<style>
:root { color-scheme: light dark; --bg:#f5f7fb; --panel:#fff; --fg:#172033; --border:#c4ccda; --link:#174ea6; --ok:#17652d; --fail:#a11724; --warn:#795000; --info:#174ea6; --muted:#50596a; }
@media (prefers-color-scheme:dark) { :root { --bg:#141922; --panel:#1e2633; --fg:#edf1f7; --border:#56647a; --link:#9fc5ff; --ok:#8bdfa1; --fail:#ff9ca5; --warn:#f6d074; --info:#9fc5ff; --muted:#bdc6d5; } }
* { box-sizing:border-box; } body { margin:0 auto; max-width:76rem; padding:1.5rem; background:var(--bg); color:var(--fg); font:1rem/1.6 system-ui,sans-serif; }
a { color:var(--link); text-underline-offset:.2em; } a:focus-visible { outline:3px solid var(--link); outline-offset:4px; }
nav { display:flex; flex-wrap:wrap; gap:1rem; } h1 { line-height:1.2; } pre { background:var(--panel); border:1px solid var(--border); border-radius:.6rem; padding:1rem; white-space:pre-wrap; overflow-wrap:anywhere; font: .9rem/1.65 ui-monospace,Menlo,Consolas,monospace; }
.badge { font-weight:700; border:1px solid currentColor; border-radius:.3rem; padding:.1em .35em; } .ok { color:var(--ok); } .failed { color:var(--fail); } .warning { color:var(--warn); } .info { color:var(--info); } .neutral { color:var(--muted); }
@media print { :root { color-scheme:light; --bg:white; --panel:white; --fg:black; --border:#777; --link:#174ea6; --ok:#17652d; --fail:#a11724; --warn:#795000; --info:#174ea6; --muted:#50596a; } body { padding:0; } pre { border:0; } }
</style></head><body><nav aria-label="Report navigation">'
  if was_written "details/$id.txt"; then
    printf '<a href="%s.txt">Plain-text copy</a>\n' "$id"
  fi
  echo '<a href="../report.md">Main overview (Markdown)</a>'
  echo '</nav>'
  printf '<h1>%s</h1>\n' "$title"
  echo '<p>View the main overview in Markdown preview. Status colors supplement the labels; OK means data was returned, not a GPU health verdict.</p>'
  echo '<pre>'
  awk -v evidence_paths="$evidence_paths" '
    BEGIN {
      n=split(evidence_paths, paths, " ")
      for (j=1; j<=n; j++) evidence[paths[j]]=1
    }
    function escape(s, out, i, c) {
      out=""
      for (i=1; i<=length(s); i++) {
        c=substr(s,i,1)
        if (c == "&") out=out "&amp;"
        else if (c == "<") out=out "&lt;"
        else if (c == ">") out=out "&gt;"
        else if (c == "\"") out=out "&quot;"
        else out=out c
      }
      return out
    }
    {
      line=escape($0); class=""
      if ($0 ~ /^Result: OK([ (]|$)/) class="ok"
      else if ($0 ~ /^Result: FAILED$/) class="failed"
      else if ($0 ~ /^Result: TOOL MISSING$/) class="warning"
      else if ($0 ~ /^Result: (UNAVAILABLE|REPORTED)$/ || $0 == "GLX extension: PRESENT") class="info"
      else if ($0 ~ /^Result: NOT REPORTED$/ || $0 ~ /^GLX extension: NOT (REPORTED|CHECKED)/) class="neutral"
      if (class != "") print "<span class=\"badge " class "\">" line "</span>"
      else if ($0 ~ /^Evidence: \.\.\/raw\/[A-Za-z0-9_-]+\.txt$/ && (substr($0,11) in evidence)) {
        path=substr($0,11); print "Evidence: <a href=\"" path "\">" escape(path) "</a>"
      } else print line
    }
  ' "$OUTDIR/details/$id.txt" || return 1
  echo '</pre><p>Preview text may be shortened; evidence links contain the full captured output. Reports are not anonymized. Review before sharing.</p></body></html>'
}

# Dynamic text is rendered as indented code, never executable HTML or Markdown.
markdown_report() {
  echo "# GPU diagnostic report"
  echo
  metadata | sed 's/^/    /'
  echo
  echo "Collection results and report-file writes are separate. Check the final"
  echo "details/summary.txt and the script exit status for report-generation success."
  echo "Colored symbols are viewer-dependent; the result labels remain authoritative."
  echo
  echo "## Attention"
  echo
  attention_items | sed 's/^/    /'
  echo
  echo "## System and display snapshot"
  echo
  system_report body | sed 's/^/    /'
  section displays '^[[:space:]]*[^:]+:$|Chipset Model:|Type:|Vendor|VRAM|Metal|Resolution:|Main Display:|Online:' 40 | sed 's/^/    /'
  echo "## Probe results"
  echo
  echo "OK means the command returned data, not that the GPU passed a health test."
  echo "NOT REPORTED means a query returned no data. TOOL MISSING means it could"
  echo "not run. FAILED means a command or renderer probe reported failure."
  echo "UNAVAILABLE means optional display preferences are absent for this session;"
  echo "the original command failure remains in the raw evidence."
  echo
  echo "| Check | Result | Evidence |"
  echo "| --- | --- | --- |"
  local i id
  for ((i=0; i<${#probe_ids[@]}; i++)); do
    id="${probe_ids[i]}"
    printf '| %s | %s %s | ' "${probe_titles[i]}" "$(status_symbol "${probe_states[i]}")" "${probe_states[i]}"
    if was_written "raw/$id.txt"; then printf '[Raw output](raw/%s.txt) |\n' "$id"
    else echo "Not written |"
    fi
  done
  printf '| Metal field | %s %s | ' "$(status_symbol "$(metal_state)")" "$(metal_state)"
  if was_written raw/displays.txt; then echo '[Display output](raw/displays.txt) |'
  else echo 'Not written |'
  fi
  echo
  echo "## Performance"
  echo
  performance_report body | sed 's/^/    /'
  echo
  echo "## X11 / GLX"
  echo
  opengl_report body | sed 's/^/    /'
  echo
  echo "## Detailed reports"
  echo
  echo "Open HTML files in a browser for full color, automatic light/dark theme, and clickable evidence links."
  echo
  for id in system-info hardware display kexts windowserver opengl metal perf env; do
    if was_written "details/$id.html"; then printf -- '- [%s (color)](details/%s.html)' "$id" "$id"
    else printf -- '- %s: HTML file not written during this run.' "$id"
    fi
    if was_written "details/$id.txt"; then printf ' — [plain text](details/%s.txt)\n' "$id"
    else printf ' — %s: file not written during this run.\n' "$id"
    fi
  done
  echo
  echo "Preview sections shorten long lines and large lists with explicit notices."
  echo "Raw files retain the full output of each command as invoked."
  echo "Reports are not anonymized; review them before sharing."
}

summary_report() {
  text_header "GPU diagnostics summary"
  if [ -n "${ARCHIVED_REPORT:-}" ]; then printf 'Previous reports archived at: %s\n\n' "$ARCHIVED_REPORT"; fi
  if [ "$write_failed" -eq 0 ]; then
    echo "Diagnostics completed. Report files were written."
  else
    echo "Diagnostics incomplete: one or more report files could not be written."
  fi
  if was_written report.md; then echo "Start here: ../report.md (open in Markdown preview)."; fi
  echo
  echo "Attention:"
  attention_items
  echo
  echo "Generated files (this run only; paths relative to output directory):"
  local i
  for ((i=0; i<${#generated_files[@]}; i++)); do printf '  %s\n' "${generated_files[i]}"; done
  echo "  details/summary.txt"
}

main() (
  local EVIDENCE_PREFIX=raw
  OUTDIR="${1-./gpu-report}"
  ARCHIVED_REPORT=""
  umask 077
  # Stable English labels for parsing; no change to the parent shell environment.
  export LC_ALL=C
  resolve_output_directory || return 1
  prepare_output_directory || return 1
  generated_files=() failed_files=()
  probe_ids=() probe_titles=() probe_states=() probe_codes=()
  probe_commands=() probe_outputs=() probe_notes=()
  write_failed=0
  started_at=$(date '+%Y-%m-%d %H:%M:%S %z')
  source_revision="unavailable (source archive or Git not installed)"
  if command -v git >/dev/null 2>&1; then
    source_revision=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null) ||
      source_revision="unavailable"
    if [ "$source_revision" != unavailable ] &&
       [ -n "$(git -C "$SCRIPT_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      source_revision="$source_revision (working tree modified)"
    fi
  fi
  log "Collecting GPU diagnostics"
  collect_probes
  ended_at=$(date '+%Y-%m-%d %H:%M:%S %z')
  local i
  for ((i=0; i<${#probe_ids[@]}; i++)); do
    write_report "raw/${probe_ids[i]}.txt" raw_probe "$i"
  done
  write_report details/system-info.txt detail_text_report system_report
  write_report details/hardware.txt detail_text_report hardware_report
  write_report details/display.txt detail_text_report display_report
  write_report details/kexts.txt detail_text_report kext_report
  write_report details/windowserver.txt detail_text_report windowserver_report
  write_report details/opengl.txt detail_text_report opengl_report
  write_report details/metal.txt detail_text_report metal_report
  write_report details/perf.txt detail_text_report performance_report
  write_report details/env.txt detail_text_report environment_report
  local id title
  for id in system-info hardware display kexts windowserver opengl metal perf env; do
    case "$id" in
      system-info) title="System overview";; hardware) title="Graphics registry";;
      display) title="GPU and displays";; kexts) title="Graphics drivers";;
      windowserver) title="WindowServer";; opengl) title="X11 / GLX";;
      metal) title="Metal visibility";; perf) title="Performance snapshot";;
      env) title="Display environment";;
    esac
    if was_written "details/$id.txt"; then
      write_report "details/$id.html" html_detail_report "$id" "$title"
    fi
  done
  write_report report.md markdown_report
  write_report details/summary.txt summary_report
  if [ "$write_failed" -ne 0 ]; then
    printf 'GPU diagnostics incomplete; check errors and reports in: %s\n' "$OUTDIR" >&2
    return 1
  fi
  echo "GPU diagnostics saved in: $OUTDIR"
  echo "Start here: $OUTDIR/report.md"
)

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
