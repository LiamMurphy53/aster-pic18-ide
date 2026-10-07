# Aster — PIC18 IDE

A desktop workspace for PIC18F87K22 assembly development, using MPLAB X 6.20 and XC8 / pic-as 2.46. Edit, build, simulate, inspect registers, and explore interrupts in one app. Available for **macOS** and **Windows**.

## Install Aster

Download an app from [GitHub Releases](https://github.com/LiamMurphy53/aster-pic18-ide/releases). Expand **Assets** under the newest release, including a Windows preview if marked **Pre-release**. The **Source code** ZIP and TAR files are for developers; use an application download below to install Aster.

| Operating system | Download | Install |
| --- | --- | --- |
| macOS 13 or later, Apple Silicon or Intel | `Aster-PIC18-IDE-v0.1.0-macOS-universal.zip` | Unzip, move **Aster.app** to **Applications**, then open it. |
| Windows 10 or 11, 64-bit Intel/AMD | `Aster-PIC18-IDE-v0.1.0-Windows-x64-Setup.exe` | Run the installer, choose your installation folder, and launch **Aster** from Start or the desktop shortcut. Administrator access is not required for the default per-user installation. |
| Windows portable option | `Aster-PIC18-IDE-v0.1.0-Windows-x64.zip` | Extract the entire ZIP into a folder and run **Aster.exe** inside it. Keep its supporting files beside it. |

You do **not** need Node.js, Swift, Xcode, or a separate browser to run the downloaded app. Aster runs locally. Building and simulation additionally require the Microchip tools below. Windows ARM64 and 32-bit Windows do not have native builds.

The Mac download is locally signed but is not Developer ID signed or notarized; Windows downloads are not Authenticode signed. Your operating system may show an unknown-publisher warning. Follow [Apple's instructions for opening trusted apps](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) on Mac. On Windows, a SmartScreen dialog may offer **More info → Run anyway** for a download you trust; a managed computer may require your administrator's approval.

**Windows preview status:** local checks cover the desktop shell, editor bridge, project file protection, and debugger command/confirmation handling. The included GitHub workflow builds the installer on Windows and checks packaged app startup; this must pass before a release is published. Real Microchip compilation and simulation on Windows, physical PICkit programming/debugging, and serial adapters still need bench validation. The Mac simulator has been tested on Apple Silicon; Intel is cross-compiled.

### Install the Microchip tools on either OS

1. Install **[MPLAB X IDE 6.20](https://www.microchip.com/en-us/tools-resources/develop/mplab-x-ide)** for your operating system. Earlier versions are available from Microchip's download archive. Include the MDB debugger and bundled Java runtime.
2. Install **[MPLAB XC8 2.46](https://www.microchip.com/en-us/tools-resources/develop/mplab-xc-compilers/xc8)** separately; Aster uses its **pic-as** assembler. Use the archived 2.46 installer if the current download is newer.
3. In MPLAB X's pack manager, ensure **Microchip PIC18F-K_DFP 1.13.292** is installed. Aster currently targets **PIC18F87K22**; other devices and toolchain versions are not validated. Microchip compiler, Java, debugger, and device-pack binaries are not included in Aster.
4. Open Aster and choose **Project → Toolchain Settings**. Select the installation roots, not a `bin` folder or an executable:

   | Tool | Default macOS directory | Default Windows directory |
   | --- | --- | --- |
   | MPLAB X | `/Applications/microchip/mplabx/v6.20` | `C:\Program Files\Microchip\MPLABX\v6.20` |
   | XC8 | `/Applications/microchip/xc8/v2.46` | `C:\Program Files\Microchip\xc8\v2.46` |

   If installed elsewhere (including `Program Files (x86)`), enter that actual location. All five tool checks should report **FOUND**. Settings and recent projects are saved per user; Windows stores them under `%APPDATA%\Aster`.
5. Choose **Open project**, select your MPLAB `.X` folder, then choose **Project → Regenerate Makefiles** before the first build on a different computer or operating system. This uses Microchip's generator to replace machine-specific paths in generated build files. The included templates and examples originally contain Mac paths; regeneration is required on Windows. Use **New project** to create a blank project, assembly starter, or interrupt bench.
6. Click **Build**, select **Simulator**, then click **Start debugging**. No board is needed for simulation. A connected PICkit 3 and an externally powered board are needed for hardware programming/debugging.

You can use the editor and device reference before installing Microchip's tools. Downloaded course PDFs are not bundled; put the named references in **Downloads**. The assembler manual comes from your XC8 installation.

### Keyboard shortcuts

Use **Command** on macOS and **Ctrl** on Windows: **S** saves, **B** builds, **O** opens a project, **K** finds a command or file, and **F** searches the editor. **F11** steps an instruction, **F10** steps over, **F5** continues/pauses, and **Shift+F5** stops debugging. The toolbar offers the same actions.

## Start working

1. Choose **Open project** and select your existing `.X` folder. Aster also accepts a prebuilt `.hex` or `.elf`.
2. Edit your assembly source. **⌘S** saves; **⌘B** builds. Clicking a compiler problem opens its source line.
3. Select **Simulator** and click **Start debugging**. Aster saves open edits, builds a debug ELF, loads it into Microchip's real simulator, and pauses at reset.
4. Use **F11** to step an instruction, **F10** to step over, and **F5** to continue or pause. **Shift–F5** stops the session. The toolbar has the same controls.
5. Click a line number or the margin to its left to add or remove a breakpoint. A red dot appears immediately. Set breakpoints before starting debugging or while paused, then press **Continue (F5)** to run to them. Breakpoints stay selected when you stop and restart the session. Click a watch value to edit one byte of target RAM.

**New project** offers a **Blank project** with an empty `main.asm`, plus the Assembly starter and Interrupt bench examples. All use normal MPLAB project metadata and the course's reset/high-priority/low-priority vector placements. Choose Blank project to write your own code from scratch; add your program before building or debugging.

## Debug stopwatch

The Debug Inspector shows the simulator's instruction-cycle count and elapsed-time reading. Aster imports the selected MPLAB configuration's simulator clock automatically. **Clock (Fosc)** displays the equivalent oscillator frequency: a 4 MHz instruction clock is 16 MHz Fosc on PIC18. New projects and missing clock settings default to **16 MHz Fosc** (4 MHz instruction clock). Saved project clock settings still take precedence. You can override Fosc before starting; opening a project or switching configuration restores that project's clock. Older global clock overrides are ignored.

By default, the stopwatch resets on each Continue, matching MPLAB's normal stopwatch behavior. Pause at your starting breakpoint, then continue to the ending breakpoint to measure only that interval. Individual steps accumulate within the current run. Enable **Accumulate across runs** before starting a session if you want a cumulative measurement instead. The stopwatch **Reset** clears the measurement without moving the CPU. Paused time is excluded, and the reading refreshes at each stop. Stopwatch timing is available with Simulator only.

## Interrupt debugging

The **Pause** button stops a running target, including an infinite loop. It preserves the session for register, memory, and source inspection.

To explore PIC interrupt handlers, create an **Interrupt bench** project or open `Examples/InterruptBench.X`:

1. Start the simulator. Add `irq_count` to Watches.
2. Put a breakpoint on the `nop` in `idle`, then continue. This lets the initialization code enable INT0 and global interrupts.
3. Remove the idle breakpoint and put a breakpoint on `incf irq_count` in `highISR`.
4. Open **Interrupts**. Select **INT0** and click **Raise flag**, then continue. Execution stops inside the ISR. Step once to see `irq_count` increment.
5. To test the physical input path in simulation, set **RB0 low**, step once, then set **RB0 high** and continue. The rising edge triggers INT0.

The panel can raise INT0, INT1, INT2, Timer0, Timer1, Timer2, or ADC flags. Firmware must enable the relevant interrupt; the panel does not change enable or priority bits. Source breakpoints and stepping use the same debugger inside and outside ISRs. Pin and flag injection is available only while the simulator is paused. Hardware interrupt inputs come from your board.

## Other tools

- **Device:** search 236 SFR definitions and their bit fields, add watches, and inspect the 80-pin package signal list.
- **Configuration:** choose compiler-supported configuration values and apply them to the active assembly file. Existing `EBTR` / `EBRT` aliases are recognized. Changes remain unsaved until you save or build.
- **Memory:** read file registers, flash, configuration memory, or EEPROM; select Disassembly for program instructions.
- **Debug console:** send individual MDB commands. This is an advanced console; use the main debug controls for session state changes.
- **Serial terminal:** connect a listed serial port. The course default is 19200 baud, 8-N-1, with LF endings. No port is opened automatically.
- **Course references:** shortcuts open locally supplied lab PDFs and manuals in your Mac's PDF reader. Course PDFs are not distributed; these shortcuts require the named files in Downloads. The assembler manual comes from the XC8 installation.
- **⌘K:** find a command or open a project file. **⌘F** searches the editor; the left Search view searches source files.

## PICkit 3

Select PICkit 3 as the debug target, use **Detect tools**, and choose its reported index. The board must have its own power. Aster explicitly disables power supplied by PICkit before connecting.

The upload button builds a production image and programs it through MPLAB 6.20's MDB. Aster reports success only when MDB confirms it. Hardware debugging similarly loads the debug ELF through PICkit 3. These connections still require testing with your physical board and probe; simulator success is not a hardware validation.

When MDB asks you to confirm the attached device and voltage, Aster displays the warning in a native dialog. Check your connected board before choosing **Continue**. Aster waits for that answer and for the connection to finish before sending the programming command. **Cancel** closes the programmer session. The time you spend reading the confirmation does not count toward the connection timeout.

MPLAB 6.20's generated PIC-AS build flags for this exact device are used. The C compiler's `-mdebugger` option is not passed to PIC-AS, which does not support it. The installed reserved-resource table identifies TOS registers, two stack levels, and programming pins as debug resources for this device.

## Project compatibility and file protection

Existing projects keep their compiler flags, linker placements, configuration selection, and ordinary MPLAB build outputs. Aster adds assembly listings; debug builds are rebuilt so a prior image cannot silently be reused. It leaves generated project settings alone during ordinary editing and builds. **Project → Regenerate Makefiles** invokes Microchip's own generator when generated makefiles are missing or need updating.

The editor preserves UTF-8 or Latin-1 source encoding. It checks that a file has not changed on disk since it was opened before saving. If it has, your edits stay in the editor: copy them, close that tab, and reopen the file to reconcile the changes. Closing a dirty tab or quitting with unsaved edits asks before discarding them.

Assembly watches are one byte. For non-exported `DS` symbols, Aster reads the linker-relocated listing rather than guessing their address. Ambiguous names across modules are not resolved automatically.

## Current scope

This is a working first release for the course's PIC18F87K22 workflow. It includes real editing, building, simulation, debugging, memory views, interrupt stimulation, configuration editing, and serial transport. It is not complete MPLAB feature parity. MCC, visual peripheral code generation, a full stimulus scheduler, multi-device support, and project-wide refactoring are not included. Existing C projects can be built, but the focused editor and verification work target your assembly labs. Physical PICkit programming/debugging and physical serial adapters remain to be checked on your bench.

## Build from source

### macOS

Download the repository using **Code → Download ZIP** and unzip it, or clone it with Git. On a Mac with a current Swift compiler from Xcode or Command Line Tools, open Terminal in this directory and run:

```sh
bash build.sh
open build/Aster.app
```

If developer tools are missing, run `xcode-select --install` and complete Apple's installer first. Compiling Aster itself does not require Microchip's tools. Use `bash build.sh --universal` to build for Apple Silicon and Intel.

The local CodeMirror bundle is already included; the native app does not depend on npm at runtime. If the editor source changes, install the pinned dependencies with `pnpm install --frozen-lockfile` and run `pnpm bundle` before rebuilding. The build signs the app in a temporary local staging folder because iCloud adds Finder metadata to app bundles.

Implementation: Swift with AppKit and WKWebView; bundled CodeMirror 6; native process and serial connections. There is no local HTTP listener. Web content has a restrictive content policy and communicates through a main-frame-only native bridge.

The test sources in `Tests` exercise the actual compiler, debugger, project files, and a local pseudo-terminal. They operate on disposable project copies. They do not program hardware. See `VALIDATION.md` for the delivered build's results.

With the exact Microchip toolchain above installed at the default paths, run `zsh Tests/run-tests.sh`. Set `ASTER_TEST_PROJECT` to the full path of an additional local `.X` project to test a temporary copy of it; personal projects are not included. Test output and generated project copies are ignored by Git.

### Windows

Install **Node.js 22 LTS** (including npm) and Git, then open PowerShell:

```powershell
git clone https://github.com/LiamMurphy53/aster-pic18-ide.git
cd aster-pic18-ide\Windows
npm ci
npm test
npm start
```

To build the installer and portable ZIP:

```powershell
npm run dist
```

The downloads appear in `dist/windows/` at the repository root. This packages the checked-in CodeMirror bundle; it does not require Swift or Visual Studio. The Windows app uses Electron with an isolated, sandboxed editor and native Node process/serial connections. It uses the same Microchip tools and project format as the Mac app. The Mac app retains its Swift/AppKit/WKWebView implementation.

## Package a release

Run `bash package.sh` on macOS for the universal Mac ZIP, or `npm run dist` in `Windows/` on Windows for the installer and portable ZIP. GitHub Actions builds both OS packages on pushes and pull requests, tests the Windows backend, and launches the packaged Windows app to verify its editor bridge. Pushing a version tag (`v*`) publishes both downloads and SHA-256 checksums in a GitHub Release after both builds pass. The workflow can also be run manually with a new `release_tag`; the initial `[release]` commit publishes the Windows preview. Tags containing `preview` produce a pre-release. These builds do not perform Developer ID signing, notarization, or Windows Authenticode signing. See [the build workflow](.github/workflows/desktop-build.yml).

## License and third-party software

Aster's original code is available under the [MIT License](LICENSE). Bundled CodeMirror dependencies and Microchip device metadata retain their own notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), also included inside the app. Aster is an independent project and is not affiliated with or endorsed by Microchip.

Source files placed inside a project folder (including subfolders) appear in Aster’s explorer, even when they are not listed in MPLAB metadata. Return to Aster or click **Refresh project files** beside the project name to discover added files. Opening and refreshing preserve unsaved editor tabs. Build inputs still follow the MPLAB project settings; copying a file into the folder does not automatically add it to the linked program.

The **Bench** panel adds timer, I/O, and LCD/table-pointer register watch groups and shortcuts to program memory, build listings, and simulator inputs. **Inputs / flags** supports RE3 high/low levels without enabling interrupts. **Memory** accepts numeric addresses or symbols present in the loaded image, shows hexadecimal bytes alongside text, and can open a read-only full flash disassembly (including unused flash). The Lab 4 handout is available in Course references. These tools inspect your program; they do not supply lab solutions or replace physical oscilloscope/logic-analyzer measurements.

Watches are saved automatically per project on this Mac when added or removed, including Bench watch groups. Reopening a project restores its last watch list, including an empty list. Projects without saved watches start empty.

For Lab 4, **Memory** also resolves local ROM and RAM labels (for example `LCDstr` and `BYTESTR`) from the current debug build. Select Program memory for ROM strings and File registers for RAM buffers. **At TBLPTR** reads ROM at the current three-byte table pointer; **At FSR0** reads RAM at the current indirect pointer. The same shortcuts are in **Bench**, alongside Timer3, Timer5, and Timer7 watch groups. These reads require a paused session. For the supplied Lab 4 example, set **Clock (Fosc)** to **16 MHz** before starting if the project clock differs. Unlinked files and ambiguous local names are excluded from address lookup.

Assembly sections marked with `// <editor-fold …>` and `// </editor-fold>` can be collapsed and expanded with the editor gutter arrows, including nested sections in the Lab 4 example. `IRP`, `IRPC`, and `LOCAL` are included in directive highlighting and completion.
