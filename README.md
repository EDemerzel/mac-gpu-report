# GPU Diagnostics Script for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

`gpu-info.sh` collects GPU and display diagnostics on macOS. Start with the generated **`gpu-report/report.md`** in Markdown preview for an overview, diagnostic results, and links to the supporting evidence.

## Summary

This script gathers:

- System and OS information
- GPU/display details from `system_profiler`
- Graphics-related I/O Registry signals
- Kernel extension snapshots
- WindowServer state
- OpenGL and Metal visibility checks
- Compact CPU/memory context (`top`, `vm_stat`)
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

Open `gpu-report/report.md` in your editor's Markdown preview. It contains the system/display snapshot, items needing attention, probe results, a compact performance section, and X11/GLX interpretation. `summary.txt` provides a plain-text entry point and the final file-write result.

Each report includes collection start/end timestamps with timezone offset, script version, and Git revision when available. Modified working trees are labeled. Existing report folders are not reformatted automatically: rerun the updated script on the Mac to generate the new layout.

Default output directory:

```text
./gpu-report
```

Use a custom output directory:

```bash
./gpu-info.sh /path/to/output
```

An invalid or unwritable output directory, or a failed report-file write, produces a nonzero exit status. Missing tools and failed diagnostic probes are recorded in the reports and do not prevent collection of other diagnostics. Exit status 0 means the report files were written; it does not mean the GPU or every probe is healthy.

Rerunning replaces the named report files, including evidence files in `raw/`. Unrelated files are preserved and excluded from the generated-file list. A failed write can leave a partial file; check the exit status and `summary.txt` before sharing. New directories/files are created with private permissions using `umask 077`; permissions on existing output paths are unchanged.

## Output Files

The script writes the following files into the output directory:

- `report.md`: main overview with probe results and relative links to evidence
- `summary.txt`: final file-write result, attention items, and this run's file list
- `system-info.txt`: selected OS, hardware, and software facts
- `hardware.txt`: selected graphics registry properties; large dictionaries are omitted
- `display.txt`: GPU/display facts, grouped by device, and display preferences
- `kexts.txt`: loaded graphics drivers first (without addresses/UUIDs), followed by installed files grouped by name family
- `windowserver.txt`: separate service-query and process-presence results
- `opengl.txt`: X11 renderer result, supporting checks, interpretation, and next step
- `metal.txt`: reported Metal fields, with unknown support kept explicit
- `perf.txt`: second `top` sample, up to 10 processes ordered by CPU, and selected page counters
- `env.txt`: display-related environment variables
- `raw/*.txt`: full output of each command as invoked, with status, exit code, and collection metadata

The display profile is collected once and reused across views. Presentation sections shorten lines beyond 96 characters and limit large lists with explicit notices; the raw evidence is not shortened. Markdown treats dynamic command output as code so embedded markup is displayed literally.

Installed driver previews are grouped into Intel, AMD/ATI, NVIDIA/GeForce, Apple/AGX, VMware, and shared graphics families. Each family has its own 12-file preview and total count, so a long list from one family cannot hide another. These are filename-based groups, not proof of the active GPU driver. Full installed and loaded lists remain in `raw/installed.txt` and `raw/loaded.txt`.

The performance probe takes two samples one second apart and shows the second. [Apple documents that the first `top` sample has invalid per-process CPU percentages](https://github.com/apple-oss-distributions/top/blob/main/top.1). This is a brief CPU/memory snapshot, not a GPU benchmark. Raw `top` evidence contains both samples with the requested process/column selection; `vm_stat` retains the reported page size and units.

For an idle baseline, collect another report after startup and background activity have settled; retain a separate output folder when comparing runs.

## Understanding results

| Result | Meaning |
| --- | --- |
| OK | A command returned data; this is not a GPU health verdict. |
| FAILED | A command exited unsuccessfully, or the GLX probe reported an error despite exit code 0. |
| TOOL MISSING | A command was unavailable and could not run. |
| UNAVAILABLE | The optional display-preferences domain is absent for this user/session. The original failure, exit code, and error text remain in raw evidence. |
| NOT REPORTED | The command or selected field supplied no data; this does not establish lack of hardware support. |
| REPORTED | A Metal field is present; read its value for the actual support statement. |
| NOT CHECKED | A derived check, such as GLX-extension visibility, could not be evaluated. |

Installed drivers, loaded drivers, running processes, and successful service queries are distinct observations. The report does not infer the active GPU driver from installation alone or label a failed service query as a stopped process.

The XQuartz process snapshot is taken after both X11/GLX probes and labeled with that timing. A local process can still be unreported while an X11 connection works; the report preserves both observations rather than inferring process presence from the connection.

Only exit code 1 with the exact `Domain com.apple.windowserver does not exist` response is classified as informational `UNAVAILABLE` and omitted from Attention. Permission errors, unexpected messages, and other exit codes remain `FAILED`.

## Troubleshooting

- `Permission denied` when running script:
  - Run `chmod +x gpu-info.sh` and retry.
- `Tool not available: <name>` appears in output:
  - The script keeps running and records missing tools instead of failing.
  - On macOS, most required tools are built in. If `glxinfo` is missing, OpenGL X11 probing is skipped.
- `Result: FAILED` appears in `opengl.txt`:
  - Inspect the error excerpt and `raw/glx.txt`. If exit code 0 accompanied an error, the report explains the discrepancy.
  - Check the separate X11 connection result. A successful connection and failed renderer probe can occur together; the cause is not established by those observations alone.
  - If the connection failed, verify `DISPLAY` and the X11 session before repeating the probe.
- `FAILED`, `NOT REPORTED`, or `TOOL MISSING` appears:
  - Command errors include the exit status and captured output. Empty results and unavailable tools are identified separately.
  - Permissions, session type, and virtualization can affect the available information. An absent graphics registry class or Metal line does not by itself prove that the GPU is faulty.
  - On the target Mac, verify the launchd label with `defaults read /System/Library/LaunchDaemons/com.apple.WindowServer.plist Label` if the WindowServer query reports an unknown service. Availability of the preferences domain `com.apple.windowserver` depends on the user/session.
- Report content includes sensitive environment/process details:
  - Reports are not automatically anonymized. Review hostnames, serial numbers, UUIDs, user names, process details, and environment values before sharing or committing them. Custom output directories are not covered by the default `gpu-report` ignore rule.

## Example Notes for the Included Report

The committed `gpu-report-sample` contains historical macOS 13.7.8 output from a VMware virtual machine. Personal host/user names and machine identifiers have been replaced with placeholders. These samples predate the readable overview and raw-evidence layout; they are historical diagnostic evidence, not examples of the current presentation.

## Verification

Run `bash -n gpu-info.sh` and `bash tests/test-gpu-info.sh` for syntax and mocked regression checks. Tests cover readable widths, retained raw evidence, multiple GPUs, literal markup, second-sample CPU data, collected-once display facts, evidence links, diagnostic states, and partial/write failures. Platform probes are mocked; they do not access the host's GPU. Set `GPU_INFO_SHOW_TEST_REPORT=1` when running the tests to print a synthetic Markdown report for inspection.

Regression cases also cover an absent optional preferences domain versus permission errors, a process becoming visible after the X11 probe, and installed-driver lists large enough to require separate family limits.

On macOS 13, also run `./gpu-info.sh` and inspect the reports for your hardware and session. Tests run on another OS validate shell logic only; they do not validate macOS command behavior. The `ioreg` class and subtree options follow [Apple's ioreg documentation](https://github.com/apple-oss-distributions/IOKitTools/blob/main/ioreg.tproj/ioreg.8); driver classes still vary across Intel, Apple Silicon, and VM configurations.

## License (MIT)

This project is licensed under the MIT License.

MIT License summary:

- You can use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software.
- You must include the copyright notice and permission notice in copies or substantial portions.
- The software is provided "as is", without warranty of any kind.

See `LICENSE` for the full MIT license text.
