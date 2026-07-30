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

- macOS
- Bash
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

## Output Files

The script writes the following files into the output directory:

- `summary.txt`: completion message and generated file list
- `system-info.txt`: `uname`, `sw_vers`, hardware, display, and software profile output
- `hardware.txt`: filtered `ioreg` and graphics hints
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
- Empty or short sections (especially WindowServer/launchctl output):
  - This can happen due to permissions, session type, or virtualization differences.
- Report content includes sensitive environment/process details:
  - Review files before sharing outside your machine.

## Example Notes for the Included Report

The current `gpu-report` in this workspace shows a virtualized macOS environment with a VMware display adapter and modest VRAM, which is expected in many VM setups.

## License (MIT)

This project is licensed under the MIT License.

MIT License summary:

- You can use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software.
- You must include the copyright notice and permission notice in copies or substantial portions.
- The software is provided "as is", without warranty of any kind.

See `LICENSE` for the full MIT license text.