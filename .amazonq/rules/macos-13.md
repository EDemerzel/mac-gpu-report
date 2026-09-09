# Workspace platform rule

The target runtime for this repository is **macOS 13 Ventura**. The VS Code host may be Windows, but scripts and shell commands are for macOS 13, not Windows or Linux.

Use macOS 13 as the compatibility baseline. Prefer macOS/BSD commands and paths, including `sw_vers`, `system_profiler`, `ioreg`, `launchctl`, `defaults`, `kextstat`, `/System/Library`, and `/private/tmp`. Do not assume GNU utilities, Linux `/proc` or `systemd`, PowerShell, WMI, or Windows registry APIs. Do not provide Linux or Windows substitutions unless the user explicitly requests a port. Keep Bash compatible with the version shipped with macOS 13. Clearly distinguish inspection or testing on Windows from actual validation on macOS 13.
