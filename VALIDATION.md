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
