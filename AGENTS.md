# Workspace instructions

## Target platform

This repository targets **macOS 13 Ventura**. The current development machine may be Windows, but the scripts and shell commands are intended to run on macOS 13, not Windows or Linux.

## Rules for code and answers

- Treat macOS 13 Ventura as the runtime and compatibility baseline.
- Prefer commands and APIs available on macOS 13. Check macOS/BSD behavior before suggesting a command.
- Do not replace macOS commands with Linux or Windows equivalents unless the user explicitly asks for a port.
- Do not assume GNU utilities, Linux paths, `systemd`, `/proc`, PowerShell, WMI, or Windows registry APIs are available.
- Preserve macOS conventions such as `/System/Library`, `/private/tmp`, `launchctl`, `sw_vers`, `system_profiler`, `ioreg`, `defaults`, `kextstat`, `top`, and `vm_stat` where applicable.
- Shell scripts should remain compatible with the Bash version shipped with macOS 13 unless a newer interpreter is explicitly required.
- When a command cannot be verified for macOS 13, say so and provide the assumption or verification step.
- Do not claim that a script was executed successfully on macOS when it was only inspected or run on Windows.
- Keep platform-specific changes focused on macOS 13. Ask before broadening support to other operating systems.
