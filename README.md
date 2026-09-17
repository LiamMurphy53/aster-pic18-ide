# Aster — PIC18 IDE

A native Mac workspace for PIC18F87K22 assembly development, using MPLAB X 6.20 and XC8 / pic-as 2.46. Edit, build, simulate, inspect registers, and explore interrupts in one app.

**Launch:** open `build/Aster.app`. The app works locally and does not need a server, browser, or Node installation to run. Keep your existing Microchip installation.

## Download and requirements

Once a release is published, download `Aster-PIC18-IDE-v0.1.0-macOS-universal.zip` from this repository's **Releases** section, unzip it, and open **Aster.app**. You can move it into Applications. The **Source code** archives contain the project, not a ready-to-run app.

- **macOS 13 or later.** The download contains Apple Silicon and Intel builds. Runtime verification has been performed on Apple Silicon; Intel has been cross-compiled but not run on a physical Intel Mac.
- **Microchip MPLAB X 6.20**, including its MDB debugger, bundled Java runtime, and **PIC18F-K_DFP 1.13.292** device pack.
- **XC8 / pic-as 2.46**, installed separately from Microchip. Compiler, debugger, Java, and device-pack binaries are not distributed with Aster.
- **PIC18F87K22** projects. Other devices and toolchain versions are not currently validated.

Install Microchip's tools first, then open Aster's **Toolchain settings** (⌘,). The defaults are `/Applications/microchip/mplabx/v6.20` and `/Applications/microchip/xc8/v2.46`. Adjust those directories if needed. For a different installation path or CPU architecture, use **Project → Regenerate Makefiles** before building the included examples or a new project; their generated local makefiles reflect the original development installation.

You can try the editor and device reference without a connected board. Building and simulation require the Microchip tools. Open `Examples/FirstLight.X` to try registers and stepping, or `Examples/InterruptBench.X` for interrupts. No hardware is needed for the simulator.

The app is locally signed but is not Apple Developer ID signed or notarized, so macOS may block a downloaded copy. Building from source is an alternative. Only open software you trust; Apple's [instructions for opening an app from an unidentified developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) explain the system's approval process.

## Start working

1. Choose **Open project** and select your existing `.X` folder. Aster also accepts a prebuilt `.hex` or `.elf`.
2. Edit your assembly source. **⌘S** saves; **⌘B** builds. Clicking a compiler problem opens its source line.
3. Select **Simulator** and click **Start debugging**. Aster saves open edits, builds a debug ELF, loads it into Microchip's real simulator, and pauses at reset.
4. Use **F11** to step an instruction, **F10** to step over, and **F5** to continue or pause. **Shift–F5** stops the session. The toolbar has the same controls.
5. Click the gutter beside a source line while paused to add or remove a breakpoint. Click a watch value to edit one byte of target RAM.

**New project** offers an Assembly starter and an Interrupt bench. Both use normal MPLAB project metadata and the course's reset/high-priority/low-priority vector placements.

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

MPLAB 6.20's generated PIC-AS build flags for this exact device are used. The C compiler's `-mdebugger` option is not passed to PIC-AS, which does not support it. The installed reserved-resource table identifies TOS registers, two stack levels, and programming pins as debug resources for this device.

## Project compatibility and file protection

Existing projects keep their compiler flags, linker placements, configuration selection, and ordinary MPLAB build outputs. Aster adds assembly listings; debug builds are rebuilt so a prior image cannot silently be reused. It leaves generated project settings alone during ordinary editing and builds. **Project → Regenerate Makefiles** invokes Microchip's own generator when generated makefiles are missing or need updating.

The editor preserves UTF-8 or Latin-1 source encoding. It checks that a file has not changed on disk since it was opened before saving. If it has, your edits stay in the editor: copy them, close that tab, and reopen the file to reconcile the changes. Closing a dirty tab or quitting with unsaved edits asks before discarding them.

Assembly watches are one byte. For non-exported `DS` symbols, Aster reads the linker-relocated listing rather than guessing their address. Ambiguous names across modules are not resolved automatically.

## Current scope

This is a working first release for the course's PIC18F87K22 workflow. It includes real editing, building, simulation, debugging, memory views, interrupt stimulation, configuration editing, and serial transport. It is not complete MPLAB feature parity. MCC, visual peripheral code generation, a full stimulus scheduler, multi-device support, and project-wide refactoring are not included. Existing C projects can be built, but the focused editor and verification work target your assembly labs. Physical PICkit programming/debugging and physical serial adapters remain to be checked on your bench.

## Build from source

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

## Package a release

Run `bash package.sh` to create the universal Mac app ZIP and SHA-256 checksum in `dist/`. Upload both to a GitHub Release. This packaging step does not perform Developer ID signing or notarization.

## License and third-party software

Aster's original code is available under the [MIT License](LICENSE). Bundled CodeMirror dependencies and Microchip device metadata retain their own notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), also included inside the app. Aster is an independent project and is not affiliated with or endorsed by Microchip.
