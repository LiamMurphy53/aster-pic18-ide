; Interrupt bench — PIC18F87K22
; Enable INT0, then watch irq_count while triggering RB0 or the INT0 flag.
; Set a breakpoint on INCF inside highISR to catch each interrupt.

PROCESSOR 18F87K22
#include <xc.inc>

CONFIG  RETEN = ON            ; VREG Sleep Enable bit (Enabled)
CONFIG  INTOSCSEL = HIGH      ; LF-INTOSC Low-power Enable bit (LF-INTOSC in 
CONFIG  SOSCSEL = HIGH        ; SOSC Power Selection and mode Configuration bits 
CONFIG XINST = OFF
CONFIG FOSC = INTIO2
CONFIG PLLCFG = OFF
CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor (Disabled)
CONFIG  IESO = OFF            ; Internal External Oscillator Switch Over Mode 
CONFIG  PWRTEN = ON           ; Power Up Timer (Enabled)
CONFIG  BOREN = ON            ; Brown Out Detect (Controlled with SBOREN bit)
CONFIG  BORV = 1              ; Brown-out Reset Voltage bits (2.7V)
CONFIG  BORPWR = ZPBORMV      ; BORMV Power level (ZPBORMV instead of BORMV 
CONFIG WDTEN = OFF
CONFIG  WDTPS = 1048576       ; Watchdog Postscaler (1:1048576)
CONFIG  RTCOSC = SOSCREF      ; RTCC Clock Select (RTCC uses SOSC)
CONFIG  EASHFT = ON           ; External Address Shift bit (Address Shifting 
CONFIG  ABW = MM              ; Address Bus Width Select bits (8-bit 
CONFIG  BW = 16               ; Data Bus Width (16-bit external bus mode)
CONFIG  WAIT = OFF            ; External Bus Wait (Disabled)
CONFIG  CCP2MX = PORTC        ; CCP2 Mux (RC1)
CONFIG  ECCPMX = PORTE        ; ECCP Mux (Enhanced CCP1/3 [P1B/P1C/P3B/P3C] 
CONFIG  MCLRE = ON            ; Master Clear Enable (MCLR Enabled, RG5 Disabled)
CONFIG  STVREN = ON           ; Stack Overflow Reset (Enabled)
CONFIG  BBSIZ = BB2K          ; Boot Block Size (2K word Boot Block size)
CONFIG  CP0 = OFF             ; Code Protect 00800-03FFF (Disabled)
CONFIG  CP1 = OFF             ; Code Protect 04000-07FFF (Disabled)
CONFIG  CP2 = OFF             ; Code Protect 08000-0BFFF (Disabled)
CONFIG  CP3 = OFF             ; Code Protect 0C000-0FFFF (Disabled)
CONFIG  CP4 = OFF             ; Code Protect 10000-13FFF (Disabled)
CONFIG  CP5 = OFF             ; Code Protect 14000-17FFF (Disabled)
CONFIG  CP6 = OFF             ; Code Protect 18000-1BFFF (Disabled)
CONFIG  CP7 = OFF             ; Code Protect 1C000-1FFFF (Disabled)
CONFIG  CPB = OFF             ; Code Protect Boot (Disabled)
CONFIG  CPD = OFF             ; Data EE Read Protect (Disabled)
CONFIG  WRT0 = OFF            ; Table Write Protect 00800-03FFF (Disabled)
CONFIG  WRT1 = OFF            ; Table Write Protect 04000-07FFF (Disabled)
CONFIG  WRT2 = OFF            ; Table Write Protect 08000-0BFFF (Disabled)
CONFIG  WRT3 = OFF            ; Table Write Protect 0C000-0FFFF (Disabled)
CONFIG  WRT4 = OFF            ; Table Write Protect 10000-13FFF (Disabled)
CONFIG  WRT5 = OFF            ; Table Write Protect 14000-17FFF (Disabled)
CONFIG  WRT6 = OFF            ; Table Write Protect 18000-1BFFF (Disabled)
CONFIG  WRT7 = OFF            ; Table Write Protect 1C000-1FFFF (Disabled)
CONFIG  WRTC = OFF            ; Config. Write Protect (Disabled)
CONFIG  WRTB = OFF            ; Table Write Protect Boot (Disabled)
CONFIG  WRTD = OFF            ; Data EE Write Protect (Disabled)
CONFIG  EBRT0 = OFF           ; Table Read Protect 00800-03FFF (Disabled)
CONFIG  EBRT1 = OFF           ; Table Read Protect 04000-07FFF (Disabled)
CONFIG  EBRT2 = OFF           ; Table Read Protect 08000-0BFFF (Disabled)
CONFIG  EBRT3 = OFF           ; Table Read Protect 0C000-0FFFF (Disabled)
CONFIG  EBRT4 = OFF           ; Table Read Protect 10000-13FFF (Disabled)
CONFIG  EBRT5 = OFF           ; Table Read Protect 14000-17FFF (Disabled)
CONFIG  EBRT6 = OFF           ; Table Read Protect 18000-1BFFF (Disabled)
CONFIG  EBRT7 = OFF           ; Table Read Protect 1C000-1FFFF (Disabled)
CONFIG  EBRTB = OFF           ; Table Read Protect Boot (Disabled)

PSECT resetVec, class=CODE, reloc=2
resetVec:
    goto    main

PSECT HiPriISR_Vec, class=CODE, reloc=2
HiPriISR_Vec:
    goto    highISR

PSECT LoPriISR_Vec, class=CODE, reloc=2
LoPriISR_Vec:
    retfie  0

PSECT udata_acs
irq_count: DS 1

PSECT code
main:
    clrf    INTCON, a
    bcf     RCON, 7, a       ; Disable interrupt priority levels
    banksel ANCON1
    clrf    BANKMASK(ANCON1), b ; RB0/AN12 is a digital input
    bsf     TRISB, 0, a     ; RB0 input
    bsf     INTCON2, 6, a   ; INTEDG0: rising edge
    clrf    irq_count, a
    bcf     INTCON, 1, a    ; Clear INT0IF
    bsf     INTCON, 4, a    ; INT0IE
    bsf     INTCON, 7, a    ; GIE
idle:
    nop     ; idle loop
    bra     idle

highISR:
    incf    irq_count, f, a
    bcf     INTCON, 1, a    ; Acknowledge INT0
    retfie  1

END resetVec
