# Validation

Original development validation: **22 backend checks, 5 interrupt checks, 3 serial transport checks, and 11 native UI checks passed.** This records the original local build, not automated results from every checkout or Mac model.

Validation performed on this Mac with its installed MPLAB X 6.20, pic-as 2.46, and PIC18F-K_DFP 1.13.292.

| Area | Evidence |
| --- | --- |
| MPLAB project support | Opened generated project metadata and built a copy of the user's actual Lab 2 project. |
| File editing | Read/save round trip, rejection of files outside the project, rejection of stale saves after a disk change. |
| Builds | Production HEX/ELF/MAP; deliberate syntax error yields failure and a navigable source location; generated artifacts clean successfully. |
| Real simulator | Loads ELF, reports source locations, steps through instructions with expected WREG values, reads registers and disassembly. |
| Watches | Resolves local assembly RAM variables from relocated listings; edits a live register and reads back the expected value. |
| Breakpoints | Creates, hits, and removes a source breakpoint, including projects whose paths contain spaces. |
| Interrupts | Injected INT0 flag enters ISR; stepping increments the counter; a real simulated RB0 rising edge also enters ISR. |
| Pause | Stops an otherwise infinite running loop and leaves the debugger usable. |
| Serial transport | A local pseudo-terminal verifies exact receive, transmit with LF, and disconnect at the course's baud rate. |
| Native interface | WKWebView tests exercise project opening, editing/saving, configuration application, building, simulation, register display, device reference, and the interrupt workflow. |

PICkit 3 hardware flashing/debugging and a physical serial adapter have not been validated. No board was programmed during these checks.

The backend integration suite, interrupt suite, serial test, and native UI check are separate so simulator correctness is not inferred from a visual mockup. Locally generated results and screenshots in `Tests` are excluded from Git. The public integration suite runs 21 checks by default; the additional local-project build is optional through `ASTER_TEST_PROJECT`. No course assignment is included.

## Breakpoint fix validation — September 17, 2026

All 10 interrupt/backend checks and 16 native UI checks passed. Regression coverage now includes real gutter mouse events on line numbers and the left margin, immediate marker addition/removal, breakpoints set before debugging, stopping at a clicked breakpoint, retaining/reinstalling breakpoints across sessions, INT0 flag injection, and an RB0 rising edge. UI checks used isolated sample projects; the active user session was left running. Physical hardware was not exercised.

## Stopwatch validation — September 17, 2026

All 22 stopwatch simulator checks and 19 native UI checks passed. Timing checks cover NOP, MOVLW, MOVWF, DECF, both BNZ outcomes, RCALL, RETURN, and GOTO; cumulative stepping; continuing to a breakpoint; excluding paused time; reset without moving the CPU; session reset; and 15 instruction cycles taking 7.5 µs at 8 MHz Fosc, matching MDB’s own elapsed-time report. Native UI checks verify visible counts, clock locking during a session, and the stopwatch Reset button. Physical hardware timing is not supported.

## Stopwatch clock and interval correction — September 17, 2026

All 29 stopwatch checks and 20 native UI checks passed. The simulator frequency is now imported from the selected MPLAB configuration, with its instruction-clock units converted to equivalent PIC18 Fosc. Continue resets the measurement by default; cumulative timing is an explicit option. Aster displays MDB’s reported elapsed time directly. Regression checks cover clock import, accumulated steps, and excluding previous runs from breakpoint-to-breakpoint measurements. A separate check on a temporary copy of the current local lab code reproduced both supplied reference readings exactly: 14 cycles / 3.5 µs, then 3,979,672 cycles / 994.918 ms at a 4 MHz instruction clock (16 MHz Fosc). The lab source was not modified or included in the repository.

## Programming confirmation correction — September 23, 2026

MDB 6.20 uses a bare `>` for both its device-confirmation input and its next-command prompt. Aster previously sent the programming command as the answer to the device warning. The session now distinguishes confirmation prompts, obtains a native dialog response, and waits for the actual command completion before continuing. Both production programming and hardware debugging use this handling; warnings are not automatically accepted.

All 14 programming protocol checks, 21 real simulator/build integration checks, and 29 stopwatch checks passed. The native app also built successfully. The protocol tests use a separate fake MDB process, covering the observed warning split at every text boundary, repeated confirmations, user response time excluded from timeout, command ordering, cancellation, embedded greater-than signs, programming failure, and missing completion. These tests do not flash a physical board; a successful upload on the user's PICkit remains to be confirmed.

## Lab 4 capability audit — October 1, 2026

Reviewed the local Lab 4 handout and supplied example assembly. Existing build/vector configuration, debug ELF symbol loading, stopwatch, Timer0 polling, RE3 high/low input controls, register editing, hex/text memory, build listings, and full flash disassembly cover the corresponding workflows. Physical LCD/servo operation and required oscilloscope or logic-analyzer captures remain hardware work.

Fixed Memory's inability to resolve non-exported labels such as `LCDstr` and `BYTESTR`. Address lookup uses final symbol tables and generated preprocessed input for objects in the current debug link. It excludes unlinked stale listings, EQU constants, and ambiguous names across modules. Added ROM-at-TBLPTR and RAM-at-FSR0 buttons in Memory and Bench, Timer3/5/7 watch groups, nested `editor-fold` section folding, and IRP/IRPC/LOCAL directive recognition.

All **13 new Lab 4 checks** and **26 native interface checks** passed. Simulator coverage includes local ROM/RAM lookup, IRPC-generated bytes, buffer reads, three-byte table pointers above 64 KiB, two-byte RAM pointers, rejection of invalid inputs, and real Timer0 rollover polling with interrupts disabled. Native checks exercise folding/unfolding, named ROM reads with hex/text, both pointer buttons, additional timer watches, and the existing editing/build/debug/breakpoint workflow. The supplied example also compiled successfully and its `LCDstr`, `LCDs`, `BYTESTR`, `COUNT`, and `main` labels resolved correctly in a disposable simulator project.

The complete backend regression run passed: 21 integration checks, 10 interrupt checks, 29 stopwatch checks, 14 programming-protocol checks, 3 serial checks, and the watch persistence, project discovery, and Bench suites. The native app was rebuilt successfully. UI tests used an isolated copy with a separate app identity; no board was programmed.

## Default clock update — October 1, 2026

Aster's initial clock field, backend defaults, and missing/invalid project-clock fallback now use 16 MHz Fosc. Both new-project templates and bundled examples use 4 MHz instruction frequency, equivalent to 16 MHz Fosc. Explicit existing project clocks continue to take precedence. All 29 stopwatch checks passed, and the native app was rebuilt.


## Lab 5 capability audit — October 28, 2026

Reviewed the five-page Fall 2026 handout and both supplied starters. Consulted all seven supporting PDFs: Introduction to C, the XC8 compiler manual (especially types, volatile, configuration, and interrupts), the embedded-engineers XC8 guide, NI encoder tutorial, Bourns 3315 datasheet, and the scanned Peatman LCD/RPG chapters. The older examples target different hardware in places; the course starter and installed PIC18F87K22 device headers determine Aster's register mappings.

Corrected CCP1/CCP2 flag injection to PIR3 bits 1/2 on both desktop backends and updated the watch groups to include PIR3/PIE3/IPR3. Added starter extension-byte and PORTD watch groups. Fixed the configuration editor to read/change/remove individual fields in comma-separated C pragmas while retaining adjacent settings and comments. Added all eight Lab 5 PDF references with a local file picker and remembered folder; PDFs and course source remain outside the distributed app.

The complete Mac backend suite passed, including the new XC8 C production/debug build, full 16-bit counter watch, low-priority Timer0 ISR breakpoint, and CCP flag preservation tests. The Windows backend/shared configuration suite passed all 15 tests on macOS; this is not a Windows hardware test. The native Mac app built successfully. Physical PICkit, servo/LCD/RPG behavior, and AD2 acquisition were not tested. The provided C starter intentionally has unfinished assignments and is not claimed to compile unchanged.

`Tests/Lab5.swift` also accepts a second argument pointing to a local Lab 5 folder to compile and load its unmodified `lab5a_orig.asm` in a disposable project and check extension-byte watches. No course files are committed.

The optional check against the actual local assembly starter also passed production/debug compilation and extension-byte watches. One repeat hit an MDB simulator startup timeout; a subsequent full repeat passed. The Mac ZIP was extracted outside iCloud and passed strict code-signature verification (Finder metadata is reattached to app folders on the synced Desktop).


## Complete C and measurement workflow — October 28, 2026

Added explorer actions to create/register C, header, and assembly files; import a starter into the active editor without changing the original; and export source for submission. New files become MPLAB build inputs, with automatic makefile regeneration. C source-line stepping is available beside instruction stepping. Uppercase C/header extensions select C syntax highlighting consistently.

C debug builds now explicitly select the documented XC8 debugger flag for Simulator or PICkit 3 and restore the generated makefile afterward. Microchip's headless generator was observed to emit `-mdebugger=none` even when the project tool was PICkit 3. Real XC8 compilation/linking verified a multi-file C program, a header, PICkit 3 debug flags, simulator loading, 16-bit watches, and timer ISR entry. No physical probe was programmed.

The Instruments panel supports waveform zoom/pan, complete-cycle pulse width and period ranges, peak-to-peak width variation, sample interval, pulse CSV, edge CSV, and SVG waveform export. Statistics use actual logic capture edge positions and sample rate. Partial cycles are excluded. Scope waveform display remains downsampled. Synthetic edge fixtures verify measurement/export calculations; physical AD2 capture is still unverified.

All **35 native WKWebView checks** and **18 Windows/shared JavaScript tests** passed. Native tests exercised C project creation, multi-file editing/building, every field on comma-separated configuration pragmas, C source stepping, and measurement/zoom/export controls, as well as existing assembly workflows. The screenshot was visually inspected. Windows tests additionally verify filename protection, project metadata registration, and restoration of C debug flags on build failure. The Mac application was rebuilt and packaged.
