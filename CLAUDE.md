# Aster — PIC18 IDE

Liam Murphy's desktop IDE for the PIC18F87K22 on an EasyPIC PRO v7 board (CU Boulder ASEN 4067 Microavionics). It wraps Microchip's real tools rather than simulating anything itself. MIT licensed. Remote: github.com/LiamMurphy53/aster-pic18-ide, branch `main`.

## Repository rules

- This folder is Aster's only working copy. Never create an Aster checkout, source tree or build output in the school folder (`~/Library/Mobile Documents/com~apple~CloudDocs/School/CU Fall 2026/micro avionics`).
- Commit or push only when Liam asks. Preserve uncommitted work; check `git status` before anything destructive.
- Don't register extra local app copies (old Windows or test builds made macOS open the wrong Aster).

## Toolchain (validated versions)

- MPLAB X 6.20: `/Applications/microchip/mplabx/v6.20` (make, MDB simulator/debugger)
- XC8 / pic-as 2.46: `/Applications/microchip/xc8/v2.46`
- PIC18F-K_DFP 1.13.292
- WaveForms runtime: `/Library/Frameworks/dwf.framework` (Analog Discovery 2)

Other versions and devices are not validated.

## Layout

- `Sources/Core.swift`: project metadata, toolchain processes, build, MDB debug sessions, watches, symbols, memory, serial, stopwatch
- `Sources/App.swift`: AppKit + WKWebView shell; `perform(op,args)` is the single dispatcher for every UI operation
- `Sources/Bridge.swift`: Claude bridge (file-based request/response folder, see README)
- `Sources/ad2_capture.c`: AD2 capture helper, loads the WaveForms runtime dynamically
- `Web/`: shared UI (`app.js`, `index.html`, `style.css`, `config.js`, `measurements.js`); `editor.bundle.js` is built from `editor-source.js`
- `Windows/`: Electron edition (`main.cjs`, `core.cjs`, `preload.cjs`); duplicates backend logic from `Core.swift`
- `Resources/`: `device.json` register reference, `references.json`, project templates
- `Tests/`: real compiler/simulator, protocol, serial and UI checks
- `.github/workflows/desktop-build.yml`: Mac/Windows packaging and release

## Commands

```
bash build.sh               # build/Aster.app for this Mac
bash build.sh --universal   # arm64 + x86_64
bash package.sh             # dist/ release zip + sha256
zsh Tests/run-tests.sh      # full backend suite (real XC8 + MDB)
pnpm install --frozen-lockfile && pnpm bundle   # after editing Web/editor-source.js
cd Windows && npm ci && npm test                # Windows/shared JS tests
```

Run with the bridge on: `open build/Aster.app --args --bridge ~/Desktop/Github/.aster-bridge`. Test the bridge with `node Tools/aster-bridge.cjs ping`.

Record test results in `VALIDATION.md`. Keep simulator results separate from hardware results; physical PICkit programming, AD2 capture through Aster and Windows toolchain runs are still unverified.

## Current state (Oct 28, 2026)

- `3e9b219` (pushed): Lab 5 work — XC8 C projects, CCP/24-bit extension watches, `#pragma config` editing, reference picker, AD2 instruments.
- Uncommitted, not yet compiled: the Claude bridge (`Sources/Bridge.swift`, `App.swift` bridge section, `Web/app.js` sync, `Web/index.html` status item, `Tools/aster-bridge.cjs`, `build.sh`, README section). Next step: `bash build.sh`, fix any compile errors, launch with `--bridge`, run a ping/open/build/debugStart round trip, then commit.
- Mac builds are ad-hoc signed (not notarized); Windows builds are unsigned.

## Style

- Short, simple explanations. Code comments are short, lowercase, no trailing periods.
- Keep changes in the existing dense style of each file; don't add abstractions without a reason.
- Prioritize what the current lab needs. Lab 5 = timers, interrupts, CCP, 24-bit software timer extension, first XC8 C program.

## Related

- Coursework and lab context: the school folder above (its `CLAUDE.md`, `Claude handoff/00_HANDOFF_REPORT.txt`).
- Student lab projects: `~/MPLABXProjects` (each `.X` is an MPLAB project; keep its Makefile and nbproject metadata).
