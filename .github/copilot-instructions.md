# Copilot instructions

This workspace targets **macOS 13 Ventura**. The editor may be running on Windows, but `gpu-info.sh` and related shell commands are intended to execute on macOS 13, not Windows or Linux.

- Use macOS 13 as the compatibility baseline.
- Validate shell commands against macOS/BSD behavior and the tools available in macOS 13.
- Do not substitute Linux or Windows commands unless explicitly asked to port the project.
- Do not assume GNU utilities, `/proc`, `systemd`, PowerShell, WMI, or the Windows registry.
- Preserve macOS tools and paths such as `sw_vers`, `system_profiler`, `ioreg`, `launchctl`, `defaults`, `kextstat`, `/System/Library`, and `/private/tmp` when relevant.
- Keep Bash code compatible with the Bash version shipped with macOS 13 unless the task explicitly changes that requirement.
- Be explicit when code was not actually tested on macOS 13; do not report a Windows run as macOS validation.
