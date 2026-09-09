# GPU diagnostic report

> Sanitized sample from a real Mac run. Personal, device-identifying, and session-specific values are redacted where present; collection metadata and diagnostic results are retained. This is a captured example, not a live status report.

    Collection started: 2026-09-09 08:33:42 -0500
    Collection ended:   2026-09-09 08:33:45 -0500
    Script version:     2.2.0
    Source revision:    cee9c63

Collection results and report-file writes are separate. Check the final
details/summary.txt and the script exit status for report-generation success.
Colored symbols are viewer-dependent; the result labels remain authoritative.

## Attention

    No probe or file-write issues requiring attention; this is not a GPU health verdict.

## System and display snapshot

    Operating system
    Result: OK
    ProductName:	macOS
    ProductVersion:	12.7.6
    BuildVersion:	21H1320
    Evidence: raw/os.txt
    
    System hardware
    Result: OK
          Model Name: MacBook Air
          Model Identifier: MacBookAir7,1
          Processor Name: Dual-Core Intel Core i7
          Processor Speed: 2.2 GHz
          Total Number of Cores: 2
          Memory: 8 GB
    Evidence: raw/hardware.txt
    
    System software
    Result: OK
          System Version: macOS 12.7.6 (21H1320)
          Kernel Version: Darwin 21.6.0
          Boot Mode: Normal
          System Integrity Protection: Enabled
          Time since boot: 2:05
    Evidence: raw/software.txt
    
    GPU and displays
    Result: OK
    Graphics/Displays:
        Intel HD Graphics 6000:
          Chipset Model: Intel HD Graphics 6000
          Type: GPU
          VRAM (Dynamic, Max): 1536 MB
          Vendor: Intel
          Metal Family: Supported, Metal GPUFamily macOS 1
          Displays:
            Color LCD:
              Display Type: LCD
              Resolution: 1366 x 768 (WSGA - Wide eXtended Graphics Array)
              Main Display: Yes
              Online: Yes
              Connection Type: Internal
    Evidence: raw/displays.txt
    
## Probe results

OK means the command returned data, not that the GPU passed a health test.
NOT REPORTED means a query returned no data. TOOL MISSING means it could
not run. FAILED means a command or renderer probe reported failure.
UNAVAILABLE means optional display preferences are absent for this session;
the original command failure remains in the raw evidence.

| Check | Result | Evidence |
| --- | --- | --- |
| Operating system | 🟢 OK | [Raw output](raw/os.txt) |
| System hardware | 🟢 OK | [Raw output](raw/hardware.txt) |
| System software | 🟢 OK | [Raw output](raw/software.txt) |
| GPU and displays | 🟢 OK | [Raw output](raw/displays.txt) |
| Registry: IOFramebuffer | 🟢 OK | [Raw output](raw/IOFramebuffer.txt) |
| Registry: IODisplay | 🟢 OK | [Raw output](raw/IODisplay.txt) |
| Registry: IOAccelerator | 🟢 OK | [Raw output](raw/IOAccelerator.txt) |
| Registry: IOGPU | ⚪ NOT REPORTED | [Raw output](raw/IOGPU.txt) |
| Display preferences | 🔵 UNAVAILABLE | [Raw output](raw/preferences.txt) |
| Installed extensions | 🟢 OK | [Raw output](raw/installed.txt) |
| Loaded extensions | 🟢 OK | [Raw output](raw/loaded.txt) |
| WindowServer service | 🟢 OK | [Raw output](raw/windowserver.txt) |
| WindowServer process | 🟢 OK | [Raw output](raw/windowserver_process.txt) |
| X11 OpenGL renderer probe | 🟢 OK | [Raw output](raw/glx.txt) |
| X11 display connection | 🟢 OK | [Raw output](raw/x11.txt) |
| XQuartz process | 🟢 OK | [Raw output](raw/xquartz.txt) |
| CPU and memory snapshot | 🟢 OK | [Raw output](raw/top.txt) |
| Virtual memory counters | 🟢 OK | [Raw output](raw/memory.txt) |
| Display-related environment | 🟢 OK | [Raw output](raw/environment.txt) |
| Metal field | 🔵 REPORTED | [Display output](raw/displays.txt) |

## Performance

    Two samples, one second apart; the second sample is shown.
    Up to 10 processes ordered by CPU. This is not a GPU benchmark.
    
    Result: OK
    Processes: 425 total, 7 running, 3 stuck, 415 sleeping, 1586 threads 
    Load Avg: 11.01, 11.88, 12.97 
    CPU usage: 63.42% user, 19.21% sys, 17.35% idle 
    PhysMem: 8052M used (1314M wired), 139M unused.
    PID   COMMAND         %CPU  MEM   
    273   mds_stores      156.7 57M+  
    397   bird            17.1  7636K+
    400   cloudd          16.1  18M+  
    548   photolibraryd   13.4  23M+  
    2982  top             13.0  1816K+
    0     kernel_task     9.2   107M- 
    516   nsurlsessiond   6.1   4456K 
    103   mds             3.8   17M-  
    534   rtcreportingd   3.5   1216K 
    366   Finder          2.3   76M   
    Evidence: raw/top.txt
    
    Virtual memory counters
    Result: OK
    Mach Virtual Memory Statistics: (page size of 4096 bytes)
    Pages free:                               19386.
    Pages active:                            865369.
    Pages inactive:                          848719.
    Pages wired down:                        336354.
    Pages occupied by compressor:             10519.
    Swapins:                                      0.
    Swapouts:                                     0.
    Evidence: raw/memory.txt
    
    vm_stat values are page counts/counters, not MB or a current swap rate.

## X11 / GLX

    X11 OpenGL renderer probe
    Result: OK
    name of display: /private/tmp/com.apple.launchd.REDACTED/org.xquartz:0
    display: /private/tmp/com.apple.launchd.REDACTED/org.xquartz:0  screen: 0
    direct rendering: Yes
    OpenGL vendor string: Intel Inc.
    OpenGL renderer string: Intel(R) HD Graphics 6000
    OpenGL version string: 2.1 INTEL-18.8.16
    OpenGL shading language version string: 1.20
    Evidence: raw/glx.txt
    
    Scope: X11/GLX renderer query; this is not a native Metal test.
    
    X11 display connection
    Result: OK
    name of display:    /private/tmp/com.apple.launchd.REDACTED/org.xquartz:0
        GLX
    Evidence: raw/x11.txt
    
    XQuartz process
    Result: OK
    Checked after the X11/GLX probes; this is a local process snapshot.
    1555 Xquartz
    Evidence: raw/xquartz.txt
    
    GLX extension: PRESENT
    

## Detailed reports

Open HTML files in a browser for full color, automatic light/dark theme, and clickable evidence links.

- [system-info (color)](details/system-info.html) — [plain text](details/system-info.txt)
- [hardware (color)](details/hardware.html) — [plain text](details/hardware.txt)
- [display (color)](details/display.html) — [plain text](details/display.txt)
- [kexts (color)](details/kexts.html) — [plain text](details/kexts.txt)
- [windowserver (color)](details/windowserver.html) — [plain text](details/windowserver.txt)
- [opengl (color)](details/opengl.html) — [plain text](details/opengl.txt)
- [metal (color)](details/metal.html) — [plain text](details/metal.txt)
- [perf (color)](details/perf.html) — [plain text](details/perf.txt)
- [env (color)](details/env.html) — [plain text](details/env.txt)

Preview sections shorten long lines and large lists with explicit notices.
Raw files retain the full output of each command as invoked.
Reports are not anonymized; review them before sharing.
