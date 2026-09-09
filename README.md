# GPU Diagnostics Script for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

`gpu-info.sh` collects GPU and display diagnostics on macOS and writes a report folder with text files you can review or share for troubleshooting.

## Summary

This script gathers:

- System and OS information
- GPU/display details from `system_profiler`
- Graphics-related I/O Registry signals
- Kernel extension snapshots
- WindowServer state
- OpenGL and Metal visibility checks
- Lightweight performance context (`top`, `vm_stat`)
- Display-related environment variables (for X11/XQuartz context)

It is designed for quick diagnostics on physical Macs and virtualized macOS environments.

## Requirements

- macOS 13 Ventura (compatibility baseline)
- `/bin/bash` (compatible with macOS's Bash 3.2)
- Built-in macOS tools used when available (for example: `system_profiler`, `ioreg`, `launchctl`, `top`, `vm_stat`)
- Optional: `glxinfo` (for X11 OpenGL probe). If unavailable or incompatible, the script records detailed diagnostics and remediation hints.

## Usage

From this folder:

```bash
chmod +x gpu-info.sh
./gpu-info.sh
```

Default output directory:

```text
./gpu-report
```

Use a custom output directory:

```bash
./gpu-info.sh /path/to/output
```

An invalid or unwritable output directory, or a failed report-file write, produces a nonzero exit status. Missing tools and failed diagnostic probes are recorded in the reports and do not prevent collection of other diagnostics. Exit status 0 means the report files were written; it does not mean the GPU or every probe is healthy.

Rerunning replaces the named report files. Unrelated files in the directory are preserved and excluded from the generated-file list. A failed write can leave a partial file; check the exit status and `summary.txt` before sharing. New directories/files are created with private permissions using `umask 077`; permissions on existing output paths are unchanged.

## Output Files

The script writes the following files into the output directory:

- `summary.txt`: completion message and generated file list
- `system-info.txt`: `uname`, `sw_vers`, hardware, display, and software profile output
- `hardware.txt`: scoped `ioreg` graphics-class queries and the full display profile
- `display.txt`: display profile and WindowServer display defaults
- `kexts.txt`: graphics-related extension listing and filtered `kextstat`
- `windowserver.txt`: WindowServer launchd/process snapshot
- `opengl.txt`: display/OpenGL summary plus optional `glxinfo -B` probe
- `metal.txt`: Metal support lines and available GPU VRAM/model lines
- `perf.txt`: single-sample system load/memory context (`top`, `vm_stat`)
- `env.txt`: environment variables related to display/GPU/OpenGL/Metal/virtualization

## Troubleshooting

- `Permission denied` when running script:
  - Run `chmod +x gpu-info.sh` and retry.
- `Tool not available: <name>` appears in output:
  - The script keeps running and records missing tools instead of failing.
  - On macOS, most required tools are built in. If `glxinfo` is missing, OpenGL X11 probing is skipped.
- `OpenGL probe failed (...)` appears in `opengl.txt`:
  - The report now includes captured `glxinfo` error text plus an `X11/GLX diagnostics` section.
  - If you see `unable to open display`, start XQuartz and verify `DISPLAY`.
  - If you see `CGLChoosePixelFormat error: invalid pixel format`, the X server is reachable but a compatible GL pixel format is not available (common on virtualized GPUs).
- `Command failed`, `No matching data reported`, or `No data reported` appears:
  - Command errors include the exit status and captured output. Successful queries with no results are identified separately.
  - Permissions, session type, and virtualization can affect the available information. An absent graphics registry class or Metal line does not by itself prove that the GPU is faulty.
  - On the target Mac, verify the launchd label with `defaults read /System/Library/LaunchDaemons/com.apple.WindowServer.plist Label` if the WindowServer query reports an unknown service. Availability of the preferences domain `com.apple.windowserver` depends on the user/session.
- Report content includes sensitive environment/process details:
  - Reports are not automatically anonymized. Review hostnames, serial numbers, UUIDs, user names, process details, and environment values before sharing or committing them. Custom output directories are not covered by the default `gpu-report` ignore rule.

## Example Notes for the Included Report

The committed `gpu-report-sample` contains historical macOS 13.7.8 output from a VMware virtual machine. Personal host/user names and machine identifiers have been replaced with placeholders. These samples were collected before the current error reporting and scoped registry queries; blank sections and broad registry output reflect the older script, not a fresh validation run.

## Verification

Run `bash -n gpu-info.sh` and `bash tests/test-gpu-info.sh` for syntax and mocked regression checks. The tests cover output failures, partial reports, stale files, diagnostic errors/empty results, and scoped registry queries without requiring real GPU hardware. They use Bash 3.2-compatible syntax and macOS/BSD commands.

On macOS 13, also run `./gpu-info.sh` and inspect the reports for your hardware and session. Tests run on another OS validate shell logic only; they do not validate macOS command behavior. The `ioreg` class and subtree options follow [Apple's ioreg documentation](https://github.com/apple-oss-distributions/IOKitTools/blob/main/ioreg.tproj/ioreg.8); driver classes still vary across Intel, Apple Silicon, and VM configurations.

## License (MIT)

This project is licensed under the MIT License.

MIT License summary:

- You can use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software.
- You must include the copyright notice and permission notice in copies or substantial portions.
- The software is provided "as is", without warranty of any kind.

See `LICENSE` for the full MIT license text.
