; $Id$

;**********************************************************************
;                                                                     *
;    Description:   Controller for Victoria Railways multi aspect     *
;                   colour light speed signal with associated         *
;                   positional train detector (placed after signal in *
;                   normal running direction.                         *
;                   Continuosly transmits displayed aspect and        *
;                   detector state to 'previous' signal (in rear)     *
;                   whilst listening for same from 'next' signal (in  *
;                   advance).                                         *
;                   If data received from 'previous' signal this is   *
;                   used to determine section occupation.             *
;                   If data received from 'next' signal this is used  *
;                   to determine aspect to display.  Otherwise aspect *
;                   to display is cycled from red to green at fixed   *
;                   intervals once the train has passed.              *
;                                                                     *
;    Author:        Chris White                                       *
;    Company:       Monitor Computing Services Ltd.                   *
;                                                                     * 
;                                                                     *
;**********************************************************************
;                                                                     *
;    Copyright (C) 2011  Monitor Computing Services Ltd.              *
;                                                                     *
;    This program is free software; you can redistribute it and/or    *
;    modify it under the terms of the GNU General Public License      *
;    as published by the Free Software Foundation; either version 2   *
;    of the License, or any later version.                            *
;                                                                     *
;    This program is distributed in the hope that it will be useful,  *
;    but WITHOUT ANY WARRANTY; without even the implied warranty of   *
;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the    *
;    GNU General Public License for more details.                     *
;                                                                     *
;    You should have received a copy of the GNU General Public        *
;    License (http://www.gnu.org/copyleft/gpl.html) along with this   *
;    program; if not, write to:                                       *
;       The Free Software Foundation Inc.,                            *
;       59 Temple Place - Suite 330,                                  *
;       Boston, MA  02111-1307,                                       *
;       USA.                                                          *
;                                                                     *
;**********************************************************************


;**********************************************************************
; Include and configuration directives
;**********************************************************************

    list      p=16C84

#include <p16C84.inc>

; Configuration word
;  - Code Protection Off
;  - Watchdog timer enabled
;  - Power up timer enabled
;  - Crystal (resonator) oscillator

    __CONFIG   _CP_OFF & _PWRTE_ON & _XT_OSC

; '__CONFIG' directive is used to embed configuration data within .asm file.
; The lables following the directive are located in the respective .inc file.
; See respective data sheet for additional information on configuration word.

; Include serial interface macros
#include <\dev\projects\utility\pic\asyn_srl.inc>
#include <\dev\projects\utility\pic\link_hd.inc>


;**********************************************************************
; Macro definitions
;**********************************************************************
MaxIns      macro   arg1, arg2, instr

#if (arg1 > arg2)
    instr   arg1
#else
    instr   arg2
#endif

    endm

;**********************************************************************
; Constant definitions
;**********************************************************************

; I/O port direction it masks
PORTASTATUS EQU     B'00001000'
PORTBSTATUS EQU     B'00001011'

; Interrupt & timing constants
RTCCINT     EQU     160         ; 10KHz = (1MHz / 100)

INTSERINI   EQU     6           ; Interrupts per initial Rx serial bit @ 2K5
INTSERBIT   EQU     4           ; Interrupts per serial bit @ 2K5 baud
INTLNKDLYRX EQU     0           ; Interrupt cycles for link Rx turnaround delay
INTLNKDLYTX EQU     0           ; Interrupt cycles for link Tx turnaround delay
INTLINKTMOP EQU     25          ; Interrupt cycles for previous link Rx timeout
INTLINKTMON EQU     250         ; Interrupt cycles for next link Rx timeout

#if (0 < high (INTSERINI | INTSERBIT | INTLNKDLYRX | INTLNKDLYTX | INTLINKTMOP | INTLINKTMON))
    error "Timer values must be less than 0xFF to avoid overflow"
#endif

; Next controller serial interface constants (see 'asyn_srl.inc')
RXNFLG      EQU     0           ; Receive byte buffer 'loaded' status bit
RXNERR      EQU     1           ; Receive error status bit
RXNBREAK    EQU     2           ; Received 'break' status bit
RXNSTOP     EQU     3           ; Seeking stop bit status bit
RXNTRIS     EQU     TRISB       ; Rx port direction register
RXNPORT     EQU     PORTB       ; Rx port data register
RXNBIT      EQU     1           ; Rx input bit

TXNFLG      EQU     RXNFLG      ; Transmit byte buffer 'clear' status bit
TXNBREAK    EQU     RXNBREAK    ; Send 'break' status bit
TXNTRIS     EQU     TRISB       ; Tx port direction register
TXNPORT     EQU     PORTB       ; Tx port data register
TXNBIT      EQU     RXNBIT      ; Tx output bit

; Previous controller serial interface constants (see 'asyn_srl.inc')
RXPFLG      EQU     4           ; Receive byte buffer 'loaded' status bit
RXPERR      EQU     5           ; Receive error status bit
RXPBREAK    EQU     6           ; Received 'break' status bit
RXPSTOP     EQU     7           ; Seeking stop bit
RXPTRIS     EQU     TRISB       ; Rx port direction register
RXPPORT     EQU     PORTB       ; Rx port data register
RXPBIT      EQU     2           ; Rx input bit

TXPFLG      EQU     RXPFLG      ; Transmit byte buffer 'clear' status bit
TXPBREAK    EQU     RXPBREAK    ; Send 'break' status bit
TXPTRIS     EQU     TRISB       ; Tx port direction register
TXPPORT     EQU     PORTB       ; Tx port data register
TXPBIT      EQU     RXPBIT      ; Tx output bit

; Timing constants
INTSCLNG    EQU     80 + 1      ; Interrupts scaling for seconds
SECSCLNG    EQU     125         ; Scaled interrupts per second
HALFSEC     EQU     B'11000000' ; Roughly half second scaled interrupts mask

; Detector I/O constants
EMTPORT     EQU     PORTA       ; Emitter drive port
EMTBIT      EQU     2           ; Emmitter drive bit (active low)
SNSPORT     EQU     PORTA       ; Sensor input port
SNSBIT      EQU     3           ; Sensor input bit (active high)
DETPORT     EQU     PORTA       ; Detection indicator port
DETBIT      EQU     4           ; Detection indicator bit (active low)

; Inhibit (force display of red aspect) input constants
INHPORT     EQU     PORTB       ; Inhibit input port
INHBIT      EQU     1           ; Inhibit input bit (active low)

; Special speed input constants
SPDPORT     EQU     PORTB       ; Special speed input port
SPDBIT      EQU     3           ; Special speed input bit (active low)

INPHIGHWTR  EQU     B'10000000' ; Input debounce on threshold mask

; Signalling status constants

; State values
BLOCKCLEAR     EQU  0           ; Block clear state value
TRAINENTERINGF EQU  1           ; Train entering forward state value
BLOCKOCCUPIED  EQU  2           ; Train in block state value
TRAINLEAVINGF  EQU  3           ; Train leaving forward state value
BLOCKSPANNED   EQU  4           ; Train spanning block state value
TRAINENTERINGR EQU  5           ; Train entering reverse state value
TRAINLEAVINGR  EQU  6           ; Train leaving reverse state value
BLKSTATE       EQU  B'00000111' ; Mask to isolate block occupation state bits

; Aspect values
ASPRED      EQU     B'00000000' ; Red aspect value
ASPYELLOW   EQU     B'01000000' ; Yellow aspect value mask
ASPDOUBLE   EQU     B'10000000' ; Double yellow aspect value mask
ASPGREEN    EQU     B'11000000' ; Green aspect value
ASPINCR     EQU     B'01000000' ; Aspect value increment
ASPSTATE    EQU     B'11000000' ; Aspect value mask

REDDUTY     EQU     0xFF        ; PWM duty cycle for red aspect
GRNDUTY     EQU     0           ; PWM duty cycle for green aspect

; Status flags, this controller
REVFLG      EQU     3           ; Line reversed bit in status byte
REVSTATE    EQU     B'00001000' ; Line reversed state bit mask

SPDFLG      EQU     4           ; Special speed bit in status byte
SPDSTATE    EQU     B'00010000' ; Special speed state bit mask

DETFLG      EQU     5           ; Train detection bit in status byte
DETSTATE    EQU     B'00100000' ; Train detection state bit mask

; Status flags, next controller
NRVFLG      EQU     DETFLG      ; Line reversed bit in next block status
NRVSTATE    EQU     DETSTATE    ; Line reversed mask for next block status

; Aspect output constants
ASPPORT     EQU     PORTB       ; Aspect output port
REDOUTU     EQU     7           ; Upper head red aspect output bit
REDMSKU     EQU     B'10000000' ; Mask for upper head red aspect
GREENOUTU   EQU     6           ; Upper head green aspect output bit
GREENMSKU   EQU     B'01000000' ; Mask for upper head speed green aspect
REDOUTL     EQU     5           ; Lower head red aspect output bit
REDMSKL     EQU     B'00100000' ; Mask for lower head red aspect
GREENOUTL   EQU     4           ; Lower head green aspect output bit
GREENMSKL   EQU     B'00010000' ; Mask for lower head green aspect
ASPOUTLSK   EQU     B'11110000' ; Mask for aspect output bits


;**********************************************************************
; Variable registers
;**********************************************************************

            CBLOCK  0x0C

; Status and accumulator storage during interrupt
w_isr           ; 'w' register, accumulator, store during ISR
pclath_isr      ; PCLATH register store during ISR
status_isr      ; status register store during ISR

; Serial interface
srlIfStat       ; Serial I/F status flags (see 'asyn_srl.inc')
                ;
                ;  Next link (half duplex so Rx and Tx flags share bits)
                ;  =====================================================
                ;
                ;   bit 0 - Rx buffer full, Tx buffer clear
                ;   bit 1 - Rx error
                ;   bit 2 - Received or sending break
                ;   bit 3 - Seeking stop bit
                ;
                ;  Previous link (half duplex so Rx and Tx flags share bits)
                ;  =========================================================
                ;
                ;   bit 4 - Rx buffer full, Tx buffer clear
                ;   bit 5 - Rx error
                ;   bit 6 - Received or sending break
                ;   bit 7 - Seeking stop bit

; Next controller interface
serNTimer       ; Interrupt counter for serial bit timing
serNBitCnt      ; Bit down counter
serNReg         ; Data shift register
serNBffr        ; Data byte buffer

lnkNTimer       ; Rx timeout timer
lnkNState       ; Link state register (see 'link_hd.inc')
                ;   bit 0,3 - Current state
                ;          Rx states must be in the range 0 to 3
                ;     0  - Switching to Rx
                ;     1  - Waiting for interface lines to settle
                ;     2  - Receiving data
                ;     3  - Unused
                ;          Tx states must be in the range 4 to 15
                ;     4  - Unused
                ;     5  - Unused
                ;     6  - Switching to Tx
                ;     7  - Waiting for far end to turn around
                ;          'Active' Tx states must be in the range 8 to 15
                ;     8  - Waiting for interface lines to settle
                ;     9  - Transmiting break
                ;     10 - Transmiting data
                ;   bit 4 - Tx enabled
                ;   bit 5 - Rx enabled
                ;   bit 6 - Synchronise, Tx or Rx a break
                ;   bit 7 - Required direction, set = Tx, clear = Rx

; Previous controller interface
serPTimer       ; Interrupt counter for serial bit timing
serPBitCnt      ; Bit down counter
serPReg         ; Data shift register
serPBffr        ; Data byte buffer

lnkPTimer       ; Rx timeout timer
lnkPState       ; Link state register (see 'link_hd.inc')
                ;   bit 0,3 - Current state
                ;          Rx states must be in the range 0 to 3
                ;     0  - Switching to Rx
                ;     1  - Waiting for interface lines to settle
                ;     2  - Receiving data
                ;     3  - Unused
                ;          Tx states must be in the range 4 to 15
                ;     4  - Unused
                ;     5  - Unused
                ;     6  - Switching to Tx
                ;     7  - Waiting for far end to turn around
                ;          'Active' Tx states must be in the range 8 to 15
                ;     8  - Waiting for interface lines to settle
                ;     9  - Transmiting break
                ;     10 - Transmiting data
                ;   bit 4 - Tx enabled
                ;   bit 5 - Rx enabled
                ;   bit 6 - Synchronise, Tx or Rx a break
                ;   bit 7 - Required direction, set = Tx, clear = Rx

intScCount      ; Interrupt scaling counter for second timing
secCount        ; Scaled interrupts counter for second timing

snsAcc          ; Detector sensor match (emitter state) accumulator

detAcc          ; Detection input debounce accumulator
inhAcc          ; Inhibit input debounce accumulator
spdAcc          ; Speed input debounce accumulator

lclState        ; Status for this controller
                ;   bits 0,2 - Occupation block state
                ;     0 - Block clear
                ;     1 - Train entering forward
                ;     2 - Train in block
                ;     3 - Train leaving forward
                ;     4 - Train spanning block
                ;     5 - Train entering reverse
                ;     6 - Train leaving reverse
                ;   bit 3 - Block reversed
                ;   bit 4 - Special speed
                ;   bit 5 - Detection state
                ;   bits 6,7 - Aspect value
                ;     0 - Red
                ;     1 - Yellow
                ;     2 - Double Yellow
                ;     3 - Green

nxtState        ; Status from next controller
                ;   bits 0,3 - Unused
                ;   bit 4 - Special speed
                ;   bit 5 - Line reversed
                ;   bits 6,7 - Aspect value
                ;     0 - Red
                ;     1 - Yellow
                ;     2 - Double Yellow
                ;     3 - Green

prvState        ; Status from previous controller
                ;   bits 0,3 - Unused
                ;   bit 4 - Special speed
                ;   bit 5 - Detection state
                ;   bits 6,7 - Aspect value
                ;     0 - Red
                ;     1 - Yellow
                ;     2 - Double Yellow
                ;     3 - Green

aspectTime      ; Aspect interval for simulating next signal
nxtTimer        ; Second counter for simulating next signal
telemPrv        ; Data last received from previous controller
telemNxt        ; Data last received from next controller

ylwDuty         ; PWM duty cycle for yellow aspect
pwmAcc          ; PWM accumulator for yellow aspect

            ENDC


;**********************************************************************
; EEPROM initialisation
;**********************************************************************

            ORG     0x2100  ; EEPROM data area

EEaspectTime    DE  6       ; Seconds to delay between aspect changes
EEylwDuty       DE  0x50    ; PWM duty cycle value for yellow aspect


;**********************************************************************
; Reset vector
;**********************************************************************

            ORG     0x000   ; Processor reset vector

BootVector
    clrf    INTCON          ; Disable interrupts
    clrf    INTCON          ; Ensure interrupts are disabled
    goto    Boot            ; Jump to beginning of program


;**********************************************************************
; Interrupt Service Routine
;**********************************************************************

            ORG     0x004   ; Interrupt vector location

IntVector
    movwf   w_isr           ; Save off current W register contents
    swapf   STATUS,W        ; Swap status register into W register
    BANKSEL TMR0            ; Ensure register page 0 is selected
    movwf   status_isr      ; save off contents of STATUS register
    movf    PCLATH,W        ; Move PCLATH register into W register
    movwf   pclath_isr      ; save off contents of PCLATH register
    movlw   high IntVector  ; Load ISR address high byte ...
    movwf   PCLATH          ; ... into PCLATH to set code block

    btfss   INTCON,T0IF     ; Test for RTCC Interrupt
    goto    EndISR          ; If not, skip service routine

    ; Re-enable the timer interrupt and reload the timer
    bcf     INTCON,T0IF     ; Reset the RTCC Interrupt bit
    movlw   (RTCCINT - 2)   ; Allow 2 cycles for RTCC write inhibit
    addwf   TMR0,F          ; Reload RTCC

    ; Service next controller link
    ;******************************************************************

    decfsz  serNTimer,W     ; Decrement serial timing counter, skip if zero ...
    movwf   serNTimer       ; ... else update the counter

    SrvcLinkIf  lnkNState, lnkNTimer, LINKTMON, SrvcTxN, SrvcRxN

    ; Service previous controller link
    ;******************************************************************

    decfsz  serPTimer,W     ; Decrement serial timing counter, skip if zero ...
    movwf   serPTimer       ; ... else update the counter

    SrvcLinkIf  lnkPState, lnkPTimer, LINKTMOP, SrvcTxP, SrvcRxP

    ; Run interrupt scaling counter for second timing
    ;******************************************************************

    decfsz  intScCount,W    ; Decrement interrupt scaling counter into W
    movwf   intScCount      ; If result is not zero update the counter

    ; Run detector
    ;******************************************************************

    ; Detector is designed to float at 2.5V, just above TTL off threshold
    ; so will be on if no train present or emitter is on. Will only be off
    ; when train is present and emitter is off.

    btfss   EMTPORT,EMTBIT  ; Skip is emitter is off (active low)...
    goto    EmitterIsOn    ; ... else ignore sensor

EmitterIsOff
    btfsc   SNSPORT,SNSBIT  ; Skip if sensor is off ...
    goto    SensorIsOn      ; ... else jump as sensor not in correspondence

SensorIsOff
    ; Sensing presence of train
    incfsz  snsAcc,W        ; Increment sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator
    bcf     EMTPORT,EMTBIT  ; Turn emitter on (active low)
    goto    SensorEnd

SensorIsOn
    ; Detecting absence of train
    decfsz  snsAcc,W        ; Decrement sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator
    bcf     EMTPORT,EMTBIT  ; Turn emitter on (active low)
    goto    SensorEnd

EmitterIsOn
    bsf     EMTPORT,EMTBIT  ; Turn emitter off (active low)

SensorEnd

    ; Exit Interrupt Service Routine
    ;******************************************************************

EndISR
    movf    pclath_isr,W    ; Retrieve copy of PCLATH register
    movwf   PCLATH          ; Restore pre-isr PCLATH register contents
    swapf   status_isr,W    ; Swap copy of STATUS register into W register
    movwf   STATUS          ; Restore pre-isr STATUS register contents
    swapf   w_isr,F         ; Swap pre-isr W register value nibbles
    swapf   w_isr,W         ; Swap pre-isr W register into W register

    retfie                  ; return from Interrupt


;**********************************************************************
; Main program initialisation code
;**********************************************************************

#include <\dev\projects\utility\pic\eeprom.inc>

Boot
    ; Clear I/O ports
    ;******************************************************************

    clrf    PORTA
    clrf    PORTB

    BANKSEL OPTION_REG

    ; Program I/O port bit directions
    ;******************************************************************

    movlw   PORTASTATUS
    movwf   TRISA
    movlw   PORTBSTATUS
    movwf   TRISB

    ; Set option register:
    ;******************************************************************
    ;   Prescaler assignment - watchdog timer

    clrf    OPTION_REG
    bsf     OPTION_REG,PSA

    BANKSEL TMR0

    ; Initialise ports
    ;******************************************************************

    movlw   PORTASTATUS     ; For Port A need to write one to each bit ...
    movwf   PORTA           ; ... being used for input

    bsf     EMTPORT,EMTBIT  ; Ensure detector emmitter is off
    bsf     DETPORT,DETBIT  ; Ensure detector indicator is off

    ; Initialise RAM to zero
    ;******************************************************************

    movlw   0x2F            ; Address of end of RAM
    movwf   0x0C            ; Ensure first byte of RAM is non zero
    movwf   FSR             ; Point indirect register to end of RAM

ClearRAM
    clrf    INDF            ; Clear byte of RAM addressed by FSR
    decf    FSR,F           ; Decrement FSR to next byte of RAM
    movf    0x0C,F          ; Test first byte of RAM
    btfss   STATUS,Z        ; Skip if byte of RAM now zero ...
    goto    ClearRAM        ; ... else continue to clear RAM

    ; Initialise aspect output PWM
    movlw   low EEylwDuty
    call    GetEEPROM
    movwf   ylwDuty

    ; Initialise timing
    ;******************************************************************

    movlw   low EEaspectTime
    call    GetEEPROM
    movwf   aspectTime      ; Initialise aspect interval for next signal
    movwf   nxtTimer        ; Initialise timer used to simulate next signal

    ; Initialise interrupts
    ;******************************************************************

    movlw   RTCCINT
    movwf   TMR0            ; Initialise RTCC for timer interrupts
    clrf    INTCON          ; Disable all interrupt sources
    bsf     INTCON,T0IE     ; Enable RTCC interrupts
    bsf     INTCON,GIE      ; Enable interrupts

    ;******************************************************************
    ; Top of main processing loop
    ;******************************************************************
Main
    clrwdt                  ; Reset the watchdog timer

    ; Perform timing operations
    ;******************************************************************

Timing
    ; To keep the interrupt service routine as brief as possible timing is
    ; performed by the interrupt service routing decrementing a counter until
    ; it reaches 1.  Here in the main program loop (i.e. outside the interrupt
    ; service routine) the count is tested and if found to be 1 it is reset
    ; and the various timing operations are performed.

    decfsz  intScCount,W    ; Test interrupts scaling counter
    goto    TimingEnd       ; Skip if a interrupt scaling has not elapsed

    movlw   INTSCLNG        ; Reload interrupt scaling counter
    movwf   intScCount

    decfsz  secCount,F      ; Decrement seconds scaled interrupts counter ...
    goto    TimingEnd       ; ... skipping this jump if it has reached zero

    movlw   SECSCLNG        ; Reload one second ...
    movwf   secCount        ; ... scaled interrupts counter low byte

    decfsz  nxtTimer,W      ; Decrement next signal simulation timer into W
    movwf   nxtTimer        ; If result is not zero update the timer

TimingEnd

    ; Check status of detector indicator
    ;******************************************************************

    btfsc   DETPORT,DETBIT  ; Skip if detector indicator is on (active low) ...
    goto    IndicatorIsOff  ; ... else jump if detector indicator is off

    ; Detector indicator is on
    decf    snsAcc,W        ; Test detector correspondence accumulator
    btfsc   STATUS,Z        ; Skip if above off threshold ...

    ; Detector correspondence has fallen to or below off threshold
    bsf     DETPORT,DETBIT  ; ... else turn detector indicator off (active low)
    goto    DetectorEnd

IndicatorIsOff
    ; Detector indicator is off
    movf    snsAcc,W        ; Test if detector correspondence accumulator ...
    andlw   INPHIGHWTR      ; ... is at or above on threshold
    btfsc   STATUS,Z        ; Skip if at or above on threshold ...
    goto    DetectorEnd     ; ... else do nothing

    ; Detector correspondence has risen above on threshold
    bcf     DETPORT,DETBIT  ; Turn detector indicator on (active low)

    clrf    detAcc          ; Set detection accumulator for train detected
    incf    detAcc,F        ; Prevent rollover down through zero

DetectorEnd

    ; Check status of train detection input (active low)
    ;******************************************************************

    btfss   DETPORT,DETBIT  ; Skip if detection input is off (active low) ...
    goto    DecDetectionAcc ; ... else jump if on

    incf    detAcc,W        ; Increment train detection accumulator
    btfsc   STATUS,Z        ; Skip if not rolled over to zero ...
    goto    DetectionEnd    ; ... else do nothing
    
    movwf   detAcc          ; Update the train detection accumulator

    andlw   INPHIGHWTR      ; Test if at or above off threshold
    btfss   STATUS,Z        ; Skip if below off threshold ...
    bcf     lclState,DETFLG ; ... else set detection state to off
    goto    DetectionEnd    

DecDetectionAcc
    decf    detAcc,W        ; Decrement train detection accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   detAcc          ; ... else update the accumulator

    btfsc   STATUS,Z        ; Skip if above on threshold (not reached zero) ...
    bsf     lclState,DETFLG ; ... else set train detection state to on

DetectionEnd

    ; Check status of special speed input (active low)
    ;******************************************************************

    btfss   SPDPORT,SPDBIT  ; Skip if special speed input is set ...
    goto    DecSpeedAcc     ; ... else jump if not set

    incf    spdAcc,W        ; Increment special speed input accumulator
    btfsc   STATUS,Z        ; Skip if not rolled over to zero ...
    goto    SpeedEnd        ; ... else do nothing
    
    movwf   spdAcc          ; Update special speed input accumulator

    andlw   INPHIGHWTR      ; Test if above off threshold
    btfss   STATUS,Z        ; Skip if not above off threshold ...
    bcf     lclState,SPDFLG ; ... else set speed state to normal
    goto    SpeedEnd   

DecSpeedAcc
    decf    spdAcc,W        ; Decrement speed input accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   spdAcc          ; ... else update the accumulator

    btfsc   STATUS,Z        ; Skip if above on threshold (not reached zero) ...
    bsf     lclState,SPDFLG ; ... else set speed state to special

SpeedEnd

    ; Service link with previous controller
    ;******************************************************************

    call    SrvcLinkP           ; Service previous controller link

    btfss   lnkPState,LNKDIRFLG ; Skip if not waiting on reply from previous
    goto    CheckPrevRx         ; ... else skip over previous controller send

    ; Send status to previous controller
    ;******************************************************************

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check these are in low nibble with their ones complement in high nibble

    movf    lclState,W      ; Get local controller status

    andlw   ~DETSTATE       ; Detector state not sent to previous controller
    btfsc   lclState,REVFLG ; Test if this block line reversed flag is set ...
    iorlw   NRVSTATE        ; ... if so propagate this to previous controller
    btfsc   nxtState,NRVFLG ; Test if next block line reversed flag is set ...
    iorlw   NRVSTATE        ; ... if so propagate this to previous controller

    iorlw   0x0F            ; Set up for ones complement nibble later

    movwf   FSR             ; Save local signalling status

    swapf   FSR,F           ; Swap signalling status into low nibble and 0xF

    andlw   0xF0            ; Isolate signalling status to be sent
    xorwf   FSR,F           ; Combined with swapped ones complemnt

    call    LinkTxP         ; Send data to previous block
    btfss   STATUS,Z        ; Skip if data was sent ...
    goto    PrevLinkEnd     ; ... else continue trying to send

    bcf     lnkPState,LNKDIRFLG ; Start waiting on reply from previous

CheckPrevRx
    ; Check for status reply from previous controller
    ;******************************************************************

    call    LinkRxToP       ; Check link reception timeout
    btfsc   STATUS,Z        ; Skip if link not timedout ...
    goto    PrevRxDone      ; ... else resume sending to previous controller

    call    LinkRxP         ; Check for data from previous controller
    btfss   STATUS,Z        ; Skip if data received ...
    goto    PrevLinkEnd     ; ... else continue waiting for reply

    movwf   FSR             ; Store the received data

    ; As a simple error check received data is ignored unless same value
    ; received twice in succession

    xorwf   telemPrv,F      ; Test against last data received
    movwf   telemPrv        ; Replace last data received
    btfss   STATUS,Z        ; Skip if last and just received data match ...
    goto    PrevRxDone      ; ... else ignore received data

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check send these in low nibble with ones complement in high nibble

    swapf   FSR,W           ; Get received data but with nibbles swapped
    comf    FSR,F           ; Ones complement the received data
    xorwf   FSR,F           ; Exclusive or complemented and swapped data
    btfsc   STATUS,Z        ; Skip if result is not zero, i.e. data is bad ...
    movwf   prvState        ; ... else save as previous controller status

PrevRxDone
    bsf     lnkPState,LNKDIRFLG ; Resume sending to previous controller

PrevLinkEnd

    ; Service link with next controller
    ;******************************************************************

    call    SrvcLinkN           ; Service next controller link

    btfss   lnkNState,LNKDIRFLG ; Skip if replying to next controller ...
    goto    CheckNextRx         ; ... else skip over next controller send

    ; Send status reply to next controller
    ;******************************************************************

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check these are in low nibble with their ones complement in high nibble

    movf    lclState,W      ; Get local controller status

    iorlw   0x0F            ; Set up for ones complement nibble later

    movwf   FSR             ; Save local signalling status
    swapf   FSR,F           ; Swap signalling status into low nibble and 0xF

    andlw   0xF0            ; Isolate signalling status to be sent
    xorwf   FSR,F           ; Combined with swapped ones complemnt

    call    LinkTxN         ; Send data to next controller
    btfss   STATUS,Z        ; Skip if data sent ...
    goto    NextLinkEnd     ; ... else continue trying to send

    bcf     lnkNState,LNKDIRFLG ; Resume listening to next controller

CheckNextRx
    ; Look for status received from next controller
    ;******************************************************************

    call    LinkRxN         ; Check for data from next controller
    btfss   STATUS,Z        ; Skip if data received ...
    goto    NextRxEnd       ; ... else skip over next controller receive

    movwf   FSR             ; Store the received data

    ; As next block link is not timed out then ignore inhibit input
    clrf    inhAcc          ; Reset inhibit input for automatic free run
    decf    inhAcc,F        ; Rollover through zero to 'full house'

    ; As a simple error check received data is ignored unless same value
    ; received twice in succession

    xorwf   telemNxt,F      ; Test against last data received
    movwf   telemNxt        ; Replace last data received
    btfss   STATUS,Z        ; Skip if last and just received data match ...
    goto    NextLinkEnd     ; ... else ignore received data

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check send these in low nibble with ones complement in high nibble

    swapf   FSR,W           ; Get received data but with nibbles swapped
    comf    FSR,F           ; Ones complement the received data
    xorwf   FSR,F           ; Exclusive or complemented and swapped data
    btfss   STATUS,Z        ; Skip if result is zero, i.e. data is ok ...
    goto    NextLinkEnd     ; ... else ignore received data

    movwf   nxtState        ; Save received data as next controller status

    bsf     lnkNState,LNKDIRFLG ; Start replying to next controller

    goto    NextLinkEnd

NextRxEnd

    ; Test if next controller link has timedout
    ;******************************************************************

    call    LinkRxToN       ; Check link reception timeout
    btfss   STATUS,Z        ; Skip if link timedout ...
    goto    NextLinkEnd     ; ... else keep waiting for data

    ; Next controller link timed out, clear status other than aspect value
    ;******************************************************************

    bcf     nxtState,NRVFLG ; Clear next block line reversed flag
    bcf     nxtState,SPDFLG ; Clear next signal special speed flag

    ; Next controller link timed out, check signal inhibit input (active low)
    ;******************************************************************

    btfss   INHPORT,INHBIT  ; Skip if inhibit input is off (active low) ...
    goto    DecInhibitAcc   ; ... else jump if on

    incf    inhAcc,W        ; Increment signal inhibit accumulator
    btfsc   STATUS,Z        ; Skip if not rolled over to zero ...
    goto    InhibitEnd      ; ... else do nothing
    
    movwf   inhAcc          ; Update the signal inhibit accumulator

    andlw   INPHIGHWTR      ; Test if at or above off threshold
    btfss   STATUS,Z        ; Skip if below off threshold ...
    nop
    goto    InhibitEnd   

DecInhibitAcc
    decf    inhAcc,W        ; Decrement inhibit input accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   inhAcc          ; ... else  update the accumulator

    btfsc   STATUS,Z        ; Skip if not above on threshold (not yet zero) ...
    goto    InhibitEnd      ; ... else leave do nothing

    movlw   ~ASPSTATE
    andwf   nxtState,W      ; Clear next block's signal aspect (= red)

    goto    SetNextSignal

InhibitEnd

    ; Next controller link timed out, simulate next signal
    ;******************************************************************

    decfsz  nxtTimer,W      ; Test if aspect timer elapsed ...
    goto    NextSignalEnd   ; ... else skip next signal sequencing

    ; Simulate signal changing aspect
    movlw   ASPINCR
    addwf   nxtState,W      ; Increment to next aspect value
    btfss   STATUS,C        ; Skip if overflow, already showing 'green' ...
SetNextSignal
    movwf   nxtState        ; ... else store new aspect value

    ; Load aspect timer for the duration of the new aspect
    movf    aspectTime,W
    movwf   nxtTimer

NextSignalEnd

NextLinkEnd

    ; Run this occupation block state machine
    ;******************************************************************

    ; The signal aspect for this block is dependant on the aspect of the next
    ; signal but for the purpose of this block it doesn't matter if these have
    ; been received or simulated.

    movlw   high BlockTable ; Load jump table address high byte ...
    movwf   PCLATH          ; ... into PCLATH to make jump in same code block
    movf    lclState,W      ; Use current state value ...
BlockStateJump
    andlw   BLKSTATE        ; ... (after removing flag and aspect bits) ...
    addwf   PCL,F           ; ... as offset into state jump table

BlockTable
    goto    BlockClear      ; State 0 - Block clear
    goto    TrainEnteringF  ; State 1 - Train entering forward
    goto    TrainInBlock    ; State 2 - Train in block
    goto    TrainLeavingF   ; State 3 - Train leaving forward
    goto    TrainSpansBlock ; State 4 - Train spanning block
    goto    TrainEnteringR  ; State 5 - Train entering reverse
    goto    TrainLeavingR   ; State 6 - Train leaving reverse
    goto    BlockEnd        ; State 7 - Unused

#if (high BlockTable) != (high $)
    error "Signal block state jump table split across page boundary"
#endif

ChangeBlockState
    iorwf   lclState,F      ; Set at least the desired state
    iorlw   ~BLKSTATE       ; Protect non state bits
    andwf   lclState,F      ; Narrow to the desired state
    goto    BlockStateJump  ; Go directly to the new state


BlockClear      ; State 0 - Block clear

    ; This block's signal aspect value depends on the aspect value of the
    ; next signal such that:
    ; 'Next'     ->    'This'
    ; Red              Yellow
    ; Yellow           Double Yellow
    ; Double Yellow    Green
    ; Green            Green

    movlw   ~ASPSTATE
    andwf   lclState,F      ; Clear signal aspect value bits (= red aspect)

    movlw   ASPINCR
    addwf   nxtState,W      ; Increment next signal aspect value into W
    btfsc   STATUS,C        ; Skip if no overflow ...
    movlw   ASPGREEN        ; ... else set for green aspect
    andlw   ASPSTATE        ; Isolate new aspect value bits   

    btfss   nxtState,NRVFLG ; Skip if next block is line reversed ...
    iorwf   lclState,F      ; ... else set new aspect value

CheckNtrRev
    ; Check for train entering in reverse
    btfss   lclState,DETFLG ; Skip if exit detection on ...
    goto    CheckNtrFwd     ; ... else check for train entering forwards

    ; Train at block exit,
    ; next state = 5 - Train entering reverse
    movlw   TRAINENTERINGR
    goto    ChangeBlockState

CheckNtrFwd
    ; Check for train entering forwards
    btfss   prvState,DETFLG ; Skip if entry detection on ...
    goto    BlockEnd        ; ... else remain in current state

    ; Train at block entrance,
    ; next state = 1 - Train entering forward,
    incf    lclState,F


TrainEnteringF  ; State 1 - Train entering forward

    bcf     lclState,REVFLG ; Clear line reversed flag for this block

ChkSpnFwd
    ; Check for train spanning forward
    btfss   lclState,DETFLG ; Skip if exit detection on ...
    goto    CheckOccFwd     ; ... else check for train occupying forwards

    ; Train at block exit,
    ; next state = 4 - Train spanning block
    movlw   BLOCKSPANNED
    goto    ChangeBlockState

CheckOccFwd
    btfsc   prvState,DETFLG ; Skip if entry detection off ...
    goto    BlockOccupied   ; ... else remain in current state

    ; Train no longer at block entrance,
    ; next state = 2 - Train in block
    incf    lclState,F


TrainInBlock   ; State 2 - Train in block

CheckExtRev
    ; Check for train exiting in reverse
    btfss   prvState,DETFLG ; Skip if entry detection on ...
    goto    CheckExtFwd     ; ... else check for train exiting forwards

    ; Train at block entrance,
    ; next state = 6 - Train leaving reverse
    movlw   TRAINLEAVINGR
    goto    ChangeBlockState

CheckExtFwd
    btfss   lclState,DETFLG ; Skip if exit detection on ...
    goto    BlockOccupied   ; ... else remain in current state

    ; Train detected at block exit,
    ; next state = 3 - Train leaving forward
    incf    lclState,F


TrainLeavingF   ; State 3 - Train leaving forward

    bcf     lclState,REVFLG ; Clear line reversed flag for this block

    ; Load aspect timer with train traversal time if simulating next block
    movf    aspectTime,W
    movwf   nxtTimer

    btfsc   lclState,DETFLG ; Skip if exit detection off ...
    goto    BothOccupied    ; ... else remain in current state

    ; Train no longer at block exit,
    ; next state = 0 - Block clear
    movlw   ~BLKSTATE
    andwf   lclState,F
    goto    BlockClear


TrainSpansBlock    ; State 4 - Train spanning block

CheckTrvRev
    ; Check for train traversal of block in reverse
    btfsc   lclState,DETFLG ; Skip if exit detection off ...
    goto    CheckTrvFwd     ; ... else check for train exiting forwards

    ; Train has left next block, if being simulated signal should be cleared
    call    LinkRxToN       ; Check link reception timeout
    movlw   ASPGREEN
    btfsc   STATUS,Z        ; Skip if link not timedout ...
    iorwf   nxtState,F      ; ... else set next block's signal aspect = green

    ; Train no longer at block exit,
    ; next state = 6 - Train leaving reverse
    movlw   TRAINLEAVINGR
    goto    ChangeBlockState

CheckTrvFwd
    ; Check for train traversal of block forwards
    btfsc   prvState,DETFLG ; Skip if entry detection off ...
    goto    BothOccupied    ; ... else remain in current state

    ; Train no longer at block entrance,
    ; next state = 3 - Train leaving forward
    movlw   TRAINLEAVINGF
    goto    ChangeBlockState


TrainEnteringR  ; State 5 - Train entering reverse

    bsf     lclState,REVFLG ; Set line reversed flag for this block

ChkSpnRev
    ; Check for train spanning in reverse
    btfss   prvState,DETFLG ; Skip if entry detection on ...
    goto    CheckOccRev     ; ... else check for train occupying in reverse

    ; Train at block entrance,
    ; next state = 4 - Train spanning block
    movlw   BLOCKSPANNED
    goto    ChangeBlockState

CheckOccRev
    btfsc   lclState,DETFLG ; Skip if exit detection off ...
    goto    BothOccupied    ; ... else remain in current state

    ; Train has left next block, if being simulated signal should be cleared
    call    LinkRxToN       ; Check link reception timeout
    movlw   ASPGREEN
    btfsc   STATUS,Z        ; Skip if link not timedout ...
    iorwf   nxtState,F      ; ... else set next block's signal aspect = green

    ; Train no longer at block exit,
    ; next state = 2 - Train in block
    movlw   BLOCKOCCUPIED
    goto    ChangeBlockState


TrainLeavingR   ; State 6 - Train leaving reverse

    bcf     lclState,REVFLG ; Clear line reversed flag for this block

    btfsc   prvState,DETFLG ; Skip if entry detection off ...
    goto    BlockOccupied   ; ... else remain in current state

    ; Train no longer at block entrance,
    ; next state = 0 - Block clear
    movlw   ~BLKSTATE
    andwf   lclState,F
    goto    BlockEnd

BothOccupied ; End of block state machine, next & this blocks occupied
    movlw   ~ASPSTATE
    andwf   nxtState,F      ; Clear next block's signal aspect value (= red)

BlockOccupied ; End of block state machine, this block occupied
    movlw   ~ASPSTATE
    andwf   lclState,F      ; Clear this block's signal aspect value (= red)

BlockEnd    ; End of signal block state machine

    ; Set aspect display output
    ;******************************************************************

    movf    nxtState,W      ; Aspect state is run by next controller
    andlw   ASPSTATE        ; Test for red aspect required (isolates aspect)
    btfss   STATUS,Z        ; Skip if zero (= red) ...
    goto    NotRedAspect    ; ... else check for other aspects

RedAspect
    ; Display red aspect - stop
    movlw   (REDMSKU | REDMSKL)
    iorwf   ASPPORT,F
    goto    AspectDone

NotRedAspect
    xorlw   ASPGREEN        ; Test for green aspect required
    andlw   ASPDOUBLE       ; Test for yellow aspect required (inverted by xor)
    btfsc   STATUS,Z        ; Skip if not zero (yellow) ...
    goto    GreenAspect     ; ... else display green aspect

YellowAspect
    ; Display yellow aspect - warning

    bcf     STATUS,C
    movf    ylwDuty,W
    btfss   STATUS,Z
    addwf   pwmAcc,F

    btfsc   lclState,SPDFLG   ; Skip if signal at normal speed ...
    goto    MediumYellow      ; ... else display medium speed yellow aspect

NormalYellow
    ; Display normal speed yellow aspect

    ; Lower head displays red
    bsf     ASPPORT,REDOUTL

YellowUpper
    ; Upper head displays yellow
    btfss   STATUS,C
    bsf     ASPPORT,REDOUTU
    btfsc   STATUS,C
    bcf     ASPPORT,REDOUTU
    goto    AspectDone

MediumYellow
    ; Display medium speed yellow aspect

    ; Upper head displays red
    bsf     ASPPORT,REDOUTU

YellowLower
    ; Lower head displays yellow
    btfss   STATUS,C
    bsf     ASPPORT,REDOUTL
    btfsc   STATUS,C
    bcf     ASPPORT,REDOUTL
    goto    AspectDone

GreenAspect
    ; Display green aspect - clear

    btfsc   lclState,SPDFLG   ; Skip if signal at normal speed ...
    goto    MediumGreen       ; ... else display medium speed green aspect

    btfss   nxtState,SPDFLG   ; ... else skip if next signal medium speed ...
    goto    NormalGreen       ; ... else display aspect as usual

ReduceGreen
    ; Signal at normal speed, next at medium, so display reduce to medium speed

    ; Upper head displays green
    bcf     ASPPORT,REDOUTU
    goto    YellowLower

NormalGreen
    ; Display normal speed green aspect

    ; Upper head displays green
    bcf     ASPPORT,REDOUTU

    ; Lower head displays red
    bsf     ASPPORT,REDOUTL
    goto    AspectDone

MediumGreen
    ; Display medium speed green aspect

    ; Upper head displays red
    bsf     ASPPORT,REDOUTU

    ; Lower head displays green
    bcf     ASPPORT,REDOUTL

AspectDone

    btfsc   ASPPORT,REDOUTU
    bcf     ASPPORT,GREENOUTU
    btfss   ASPPORT,REDOUTU
    bsf     ASPPORT,GREENOUTU
    btfsc   ASPPORT,REDOUTL
    bcf     ASPPORT,GREENOUTL
    btfss   ASPPORT,REDOUTL
    bsf     ASPPORT,GREENOUTL

    ;******************************************************************
    ; End of main processing loop
    ;******************************************************************
    goto    Main


;**********************************************************************
; Instance next block interface routine macros
;**********************************************************************

EnableRxN   EnableRx  RXNTRIS, RXNPORT, RXNBIT
    return

InitRxN     InitRx  srlIfStat, serNTimer, serNBitCnt, serNReg, RXNFLG, RXNERR, RXNBREAK, RXNSTOP
    return

SrvcRxN     ServiceRx srlIfStat, serNTimer, serNBitCnt, serNReg, serNBffr, RXNPORT, RXNBIT, INTSERINI, INTSERBIT, RXNERR, RXNBREAK, RXNSTOP, RXNFLG

SerRxN      SerialRx srlIfStat, serNBffr, RXNFLG

EnableTxN   EnableTx  TXNTRIS, TXNPORT, TXNBIT
    return

InitTxN     InitTx  srlIfStat, serNTimer, serNBitCnt, serNReg, TXNFLG, TXNBREAK
    return

SrvcTxN     ServiceTx srlIfStat, serNTimer, serNBitCnt, serNReg, serNBffr, TXNPORT, TXNBIT, RXNPORT, RXNBIT, INTSERBIT, TXNFLG, TXNBREAK

SerTxN      SerialTx srlIfStat, serNBffr, TXNFLG

IsTxIdleN   IsTxIdle serNBitCnt
    return

SrvcLinkN   SrvcLink   lnkNState, lnkNTimer, serNTimer, INTLNKDLYRX, INTLNKDLYTX, INTLINKTMON, EnableTxN, InitTxN, IsTxIdleN, EnableRxN, InitRxN

LinkRxN     LinkRx lnkNState, SerRxN

LinkTxN     LinkTx lnkNState, SerTxN

LinkRxToN   IsLinkRxTo lnkNState, lnkNTimer
    return

;**********************************************************************
; Instance previous block interface routine macros
;**********************************************************************

EnableRxP   EnableRx  RXPTRIS, RXPPORT, RXPBIT
    return

InitRxP     InitRx  srlIfStat, serPTimer, serPBitCnt, serPReg, RXPFLG, RXPERR, RXPBREAK, RXPSTOP
    return

SrvcRxP     ServiceRx srlIfStat, serPTimer, serPBitCnt, serPReg, serPBffr, RXPPORT, RXPBIT, INTSERINI, INTSERBIT, RXPERR, RXPBREAK, RXPSTOP, RXPFLG

SerRxP      SerialRx srlIfStat, serPBffr, RXPFLG

EnableTxP   EnableTx  TXPTRIS, TXPPORT, TXPBIT
    return

InitTxP     InitTx  srlIfStat, serPTimer, serPBitCnt, serPReg, TXPFLG, TXPBREAK
    return

SrvcTxP     ServiceTx srlIfStat, serPTimer, serPBitCnt, serPReg, serPBffr, TXPPORT, TXPBIT, RXPPORT, RXPBIT, INTSERBIT, TXPFLG, TXPBREAK

SerTxP      SerialTx srlIfStat, serPBffr, TXPFLG

IsTxIdleP   IsTxIdle serPBitCnt
    return

SrvcLinkP   SrvcLink   lnkPState, lnkPTimer, serPTimer, INTLNKDLYRX, INTLNKDLYTX, INTLINKTMOP, EnableTxP, InitTxP, IsTxIdleP, EnableRxP, InitRxP

LinkRxP     LinkRx lnkPState, SerRxP

LinkTxP     LinkTx lnkPState, SerTxP

LinkRxToP   IsLinkRxTo lnkPState, lnkPTimer
    return


;**********************************************************************
; End of source code
;**********************************************************************

#if 0x33F < $
    error "This program is just too big!"
#endif

    end     ; directive 'end of program'
