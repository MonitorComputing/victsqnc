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

; Include serial link interface macros
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

; Block state values
BLOCKCLEAR     EQU  0           ; Block clear
TRAINENTERINGF EQU  1           ; Train entering forward
BLOCKOCCUPIED  EQU  2           ; Train in block
TRAINLEAVINGF  EQU  3           ; Train leaving forward
BLOCKSPANNED   EQU  4           ; Train spanning block
TRAINENTERINGR EQU  5           ; Train entering reverse
TRAINLEAVINGR  EQU  6           ; Train leaving reverse
BLKSTATE       EQU  B'00000111' ; Mask to isolate block

; Aspect values
ASPRED      EQU     B'00000000' ; Red aspect value
ASPYELLOW   EQU     B'01000000' ; Yellow aspect value mask
ASPDOUBLE   EQU     B'10000000' ; Double yellow aspect value mask
ASPGREEN    EQU     B'11000000' ; Green aspect value
ASPINCR     EQU     B'01000000' ; Aspect value increment
ASPSTATE    EQU     B'11000000' ; Aspect value mask

REDDUTY     EQU     0xFF        ; PWM duty cycle for red aspect
GRNDUTY     EQU     0           ; PWM duty cycle for green aspect

; Controller status flags
ENTFLG      EQU     1           ; Entrance detection bit in status byte
ENTMSK      EQU     B'00000010' ; Entrance detection state bit mask

REVFLG      EQU     3           ; Line reversed bit in status byte
REVMSK      EQU     B'00001000' ; Line reversed state bit mask

INHFLG      EQU     4           ; Signal inhibited bit in status byte
INHMSK      EQU     B'00010000' ; Signal inhibited state bit mask

SPDFLG      EQU     4           ; Special speed bit in status byte
SPDMSK      EQU     B'00010000' ; Special speed state bit mask

EXTFLG      EQU     5           ; Exit detection bit in status byte
EXTMSK      EQU     B'00100000' ; Exit detection state bit mask

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

INPACTV     EQU     7           ; Indicates debounce accumulator > high water


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

lclCntlr        ; Status of this controller
                ;   bits 0,2 - Occupation block state
                ;     0 - Block clear
                ;     1 - Train entering forward
                ;     2 - Train in block
                ;     3 - Train leaving forward
                ;     4 - Train spanning block
                ;     5 - Train entering reverse
                ;     6 - Train leaving reverse
                ;   bit 3    - Unused
                ;   bit 4    - Signal inhibit (display red aspect)
                ;   bit 5    - Exit detection
                ;   bits 6,7 - Aspect value
                ;     0 - Red
                ;     1 - Yellow
                ;     2 - Double Yellow
                ;     3 - Green

nxtCntlr        ; Status received from next controller
                ;   bits 0,3 - Ignored (ones complement of bits 4 to 7)
                ;   bit 4    - Special speed
                ;   bit 5    - Line reversed
                ;   bits 6,7 - Aspect value (as for this controller)

prvCntlr        ; Status received from previous controller
                ;   bit 0    - Ignored
                ;   bit 1    - Entrance detection
                ;   bits 2,3 - Ignored
                ; Status sent to previous controller
                ;   bit 4    - Special speed
                ;   bit 5    - Line reversed
                ;   bits 6,7 - Aspect value (as for this controller)

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
    goto    EmitterOn       ; ... else ignore sensor

EmitterOff
    btfsc   SNSPORT,SNSBIT  ; Skip if sensor is off ...
    goto    SensorOn        ; ... else jump as sensor not in correspondence

SensorOff
    ; Sensing presence of train
    incfsz  snsAcc,W        ; Increment sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator
    goto    EmitterOffEnd

SensorOn
    ; Detecting absence of train
    decfsz  snsAcc,W        ; Decrement sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator

EmitterOffEnd
    bcf     EMTPORT,EMTBIT  ; Turn emitter on (active low)
    goto    SensorEnd

EmitterOn
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
; Subroutine to read EEPROM
;**********************************************************************

ReadEEPROM
    movwf   EEADR           ; Set address of EEPROM location to read
    BANKSEL EECON1
    bsf     EECON1,RD       ; Trigger EEPROM read
    BANKSEL EEDATA
    movf    EEDATA,W        ; Get EEPROM data read
    BANKSEL TMR0
    return


;**********************************************************************
; Main program initialisation code
;**********************************************************************

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

    incf    snsAcc,F        ; Prevent accumulator rollover down through zero

    ; Initialise timing
    ;******************************************************************

    movlw   low EEylwDuty
    call    ReadEEPROM
    movwf   ylwDuty         ; Initialise yellow aspect PWM duty cycle

    movlw   low EEaspectTime
    call    ReadEEPROM
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

    ; Check status of train detector
    ;******************************************************************

    decf    snsAcc,W        ; Test detector correspondence accumulator
    btfsc   STATUS,Z        ; Skip if above off threshold ...
    bsf     DETPORT,DETBIT  ; ... else turn detector indicator off (active low)

    btfsc   snsAcc,INPACTV  ; Skip if below on threshold ...
    bcf     DETPORT,DETBIT  ; ... else turn detector indicator o (active low)

    ; Check status of train detection input (active low)
    ;******************************************************************

    btfsc   DETPORT,DETBIT  ; Skip if detection input is on (active low) ...
    goto    DecDetectionAcc ; ... else jump if on

    incf    detAcc,W        ; Increment train detection debounce accumulator
    btfss   STATUS,Z        ; Skip if rolled over to zero ...
    movwf   detAcc          ; ... else update the train detection accumulator

    btfsc   detAcc,INPACTV  ; Skip if below on threshold ...
    bsf     lclCntlr,EXTFLG ; ... else set detection state to on
    goto    DetectionEnd    

DecDetectionAcc
    movf    detAcc,F        ; Test train detection debounce accumulator

    btfss   STATUS,Z        ; Skip if zero ...
    decf    detAcc,F        ; ... else decrement the accumulator

    btfsc   STATUS,Z        ; Skip if above off threshold (not zero) ...
    bcf     lclCntlr,EXTFLG ; ... else set train detection state to off

DetectionEnd

    ; Check status of special speed input (active low)
    ;******************************************************************

    btfsc   SPDPORT,SPDBIT  ; Skip if special speed is on (active low) ...
    goto    DecSpeedAcc     ; ... else jump if not set

    incf    spdAcc,W        ; Increment special speed debounce accumulator
    btfss   STATUS,Z        ; Skip if rolled over to zero ...
    movwf   spdAcc          ; ... else update special speed input accumulator

    btfsc   spdAcc,INPACTV  ; Skip if below on threshold ...
    bsf     prvCntlr,SPDFLG ; ... else set speed state to special
    goto    SpeedEnd   

DecSpeedAcc
    movf    spdAcc,F        ; Test special speed input debounce accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    decf    spdAcc,F        ; ... else decrement the accumulator

    btfsc   STATUS,Z        ; Skip if above off threshold (not zero) ...
    bcf     prvCntlr,SPDFLG ; ... else set speed state to special

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

    movf    prvCntlr,W      ; Get status for previous controller

    btfsc   nxtCntlr,REVFLG ; Test if next block line reversed flag is set ...
    iorlw   REVMSK          ; ... if so propagate this to previous controller

    iorlw   0x0F            ; Set up for ones complement low nibble later

    movwf   FSR             ; Save local signalling status
    swapf   FSR,F           ; Swap signalling status into low nibble

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

    xorwf   telemPrv,F      ; Test against last received data
    movwf   telemPrv        ; Replace last received data
    btfss   STATUS,Z        ; Skip if last and just received data match ...
    goto    PrevRxDone      ; ... else ignore just received data

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check send these in low nibble with ones complement in high nibble

    movf    FSR,W           ; Signalling in low nibble, ones complement in high
    comf    FSR,F           ; Ones complement the received data
    xorwf   FSR,F           ; Exclusive or complemented and swapped data
    btfsc   STATUS,Z        ; Skip if result is zero, i.e. data is ok ...
    goto    PrevRxDone      ; ... else ignore just received data

    andlw   0x0F            ; Clear ones complement from received data
    iorwf   prvCntlr,F      ; OR received data into previous controller status
    iorlw   0xF0            ; Protect high nibble of controller status
    andwf   prvCntlr,F      ; Mask received data in previous controller status

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

    movf    lclCntlr,W      ; Get local controller status

    iorlw   0x0F            ; Set up for ones complement high nibble later

    movwf   FSR             ; Save local signalling status
    swapf   FSR,F           ; Swap nibbles, signalling status - low, 0xF - high

    andlw   0xF0            ; Isolate signalling status for ones complement
    xorwf   FSR,F           ; Ones complement high and signalling status in low

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

    ; As next block link is not timed out then ignore inhibit input
    bcf     lclCntlr,INHFLG ; Reset inhibit input for automatic free run
    clrf    inhAcc          ; Clear inhibit input debounce accumulator
    incf    inhAcc,F        ; Prevent rollover down through zero

    movwf   FSR             ; Store the received data

    ; As a simple error check received data is ignored unless same value
    ; received twice in succession

    xorwf   telemNxt,F      ; Test against last received data
    movwf   telemNxt        ; Replace last received data
    btfss   STATUS,Z        ; Skip if last and just received data match ...
    goto    NextLinkEnd     ; ... else ignore just received data

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check send these in low nibble with ones complement in high nibble

    swapf   FSR,W           ; Signalling in high nibble, ones complement in low
    comf    FSR,F           ; Ones complement the received data
    xorwf   FSR,F           ; Exclusive or complemented and swapped data
    btfss   STATUS,Z        ; Skip if result is zero, i.e. data is ok ...
    goto    NextLinkEnd     ; ... else ignore received data

    movwf   nxtCntlr        ; Save received data as next controller status

    bsf     lnkNState,LNKDIRFLG ; Start replying to next controller

    goto    NextLinkEnd

NextRxEnd

    ; Test if next controller link has timedout
    ;******************************************************************

    call    LinkRxToN       ; Check link reception timeout
    btfss   STATUS,Z        ; Skip if link timedout ...
    goto    NextLinkEnd     ; ... else keep waiting for data

    ; Next controller link timed out, simulate it
    ;******************************************************************

    bcf     nxtCntlr,REVFLG ; Clear next block line reversed flag
    bcf     nxtCntlr,SPDFLG ; Clear next signal special speed flag

    decfsz  nxtTimer,W      ; Test if aspect timer elapsed ...
    goto    NextSignalEnd   ; ... else skip next signal sequencing

    ; Simulate signal changing aspect
    movlw   ASPINCR
    addwf   nxtCntlr,W      ; Increment to next aspect value
    btfss   STATUS,C        ; Skip if overflow, already showing 'green' ...
    movwf   nxtCntlr        ; ... else store new aspect value

    ; Load aspect timer for the duration of the new aspect
    movf    aspectTime,W
    movwf   nxtTimer

NextSignalEnd

    ; Next controller link timed out, check signal inhibit input (active low)
    ;******************************************************************

    btfsc   INHPORT,INHBIT  ; Skip if inhibit input is on (active low) ...
    goto    DecInhibitAcc   ; ... else jump if on

    incf    inhAcc,W        ; Increment signal inhibit accumulator
    btfss   STATUS,Z        ; Skip if not rolled over to zero ...
    movwf   inhAcc          ; ... else update the signal inhibit accumulator

    btfsc   inhAcc,INPACTV  ; Skip if below on threshold ...
    bsf     lclCntlr,INHFLG ; ... else set signal inhibit state to on
    goto    InhibitEnd   

DecInhibitAcc
    decf    inhAcc,W        ; Decrement inhibit input accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   inhAcc          ; ... else update the accumulator

    btfsc   STATUS,Z        ; Skip if above on threshold (not reached zero) ...
    bcf     lclCntlr,INHFLG ; ... else set signal inhibit state to off

InhibitEnd

NextLinkEnd

    ; Unless the local signal is inhibited this controller normally displays
    ; the signal aspect for the next block

    movlw   ~ASPSTATE
    andwf   lclCntlr,F      ; Clear signal aspect value bits

    movlw   ASPSTATE
    andwf   nxtCntlr,W      ; Get signal aspect from next block controller

    btfss   lclCntlr,INHFLG ; Skip if signal is line inhibited ...
    iorwf   lclCntlr,F      ; ... else use the signal aspect for display

    ; This block's signal aspect value (displayed by previous controller)
    ; depends on the aspect value of the local signal such that:
    ; 'Local'    ->    'This'
    ; Red              Yellow
    ; Yellow           Double Yellow
    ; Double Yellow    Green
    ; Green            Green

    movlw   ~ASPSTATE
    andwf   prvCntlr,F      ; Clear signal aspect value bits (= red aspect)

    movlw   ASPINCR
    addwf   lclCntlr,W      ; Increment local signal aspect value into W
    btfsc   STATUS,C        ; Skip if no overflow ...
    movlw   ASPGREEN        ; ... else set for green aspect
    andlw   ASPSTATE        ; Isolate new aspect value bits   

    btfss   nxtCntlr,REVFLG ; Skip if next block is line reversed ...
    iorwf   prvCntlr,F      ; ... else set new aspect value

    ; Run this occupation block state machine
    ;******************************************************************

    ; The signal aspect for this block is dependant on the aspect of the next
    ; signal but for the purpose of this block it doesn't matter if these have
    ; been received or simulated.

    movlw   high BlockTable ; Load jump table address high byte ...
    movwf   PCLATH          ; ... into PCLATH to make jump in same code block
    movf    lclCntlr,W      ; Use current state value ...
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

NewBlkState
    iorwf   lclCntlr,F      ; Set at least the desired state
    iorlw   ~BLKSTATE       ; Protect non state bits
    andwf   lclCntlr,F      ; Narrow to the desired state
    goto    BlockStateJump  ; Go directly to the new state


BlockClear      ; State 0 - Block clear

    bcf     prvCntlr,REVFLG ; Clear line reversed flag for this block

CheckNtrRev
    ; Check for train entering in reverse
    movlw   TRAINENTERINGR
    btfsc   lclCntlr,EXTFLG ; Skip if exit detection off ...
    goto    NewBlkState     ; ... else train entering in reverse, change state

CheckNtrFwd
    ; Check for train entering forwards
    btfss   prvCntlr,ENTFLG ; Skip if entry detection on ...
    goto    BlockEnd        ; ... else remain in current state

    ; Train at block entrance,
    ; next state = 1 - Train entering forward,
    incf    lclCntlr,F


TrainEnteringF  ; State 1 - Train entering forward

ChkSpnFwd
    ; Check if train now spans this block
    movlw   BLOCKSPANNED
    btfsc   lclCntlr,EXTFLG ; Skip if exit detection off ...
    goto    NewBlkState     ; ... else train now spans this block, change state

CheckOccFwd
    ; Check if train now occupies this block
    btfsc   prvCntlr,ENTFLG ; Skip if entry detection off ...
    goto    BlockOccupied   ; ... else remain in current state

    ; Train no longer at block entrance,
    ; next state = 2 - Train in block
    incf    lclCntlr,F


TrainInBlock   ; State 2 - Train in block

CheckExtRev
    ; Check for train exiting in reverse
    movlw   TRAINLEAVINGR
    btfsc   prvCntlr,ENTFLG ; Skip if entry detection off ...
    goto    NewBlkState     ; ... else train exiting in reverse, change state

CheckExtFwd
    btfss   lclCntlr,EXTFLG ; Skip if exit detection on ...
    goto    BlockOccupied   ; ... else remain in current state

    ; Train detected at block exit,
    ; next state = 3 - Train leaving forward
    incf    lclCntlr,F


TrainLeavingF   ; State 3 - Train leaving forward

    ; Check if train has left block
    btfsc   lclCntlr,EXTFLG ; Skip if exit detection off ...
    goto    ChkTrnRvd       ; ... else check if train now spans this block

    ; In case simulating next controller set next signal aspect value to red
    ; and reset the aspect timer to simulate train traversing next block
    movlw   ~ASPSTATE
    andwf   lclCntlr,F      ; Ensure local signal continues to display red
    andwf   nxtCntlr,F

    movf    aspectTime,W
    movwf   nxtTimer

    ; Train no longer at block exit,
    ; next state = 0 - Block clear
    movlw   BLOCKCLEAR
    goto    NewBlkState     ; Change state

ChkTrnRvd
    ; Check if train has changed direction and now spans this block
    btfss   prvCntlr,ENTFLG ; Skip if entry detection on ...
    goto    BothOccupied    ; ... else remain in current state

    bsf     prvCntlr,REVFLG ; Set line reversed flag for this block

    ; Train detected at block entrance,
    ; next state = 4 - Train spanning block
    incf    lclCntlr,F


TrainSpansBlock    ; State 4 - Train spanning block

CheckTrvFwd
    ; Check for train traversal of block forwards
    movlw   TRAINLEAVINGF
    btfss   prvCntlr,ENTFLG ; Skip if entry detection on ...
    goto    NewBlkState     ; ... else train is leaving forwards, change state

CheckTrvRev
    ; Check for train traversal of block in reverse
    btfsc   lclCntlr,EXTFLG ; Skip if exit detection off ...
    goto    BothOccupied    ; ... else remain in current state

    ; Train no longer at block exit,
    ; next state = 6 - Train leaving reverse
    movlw   TRAINLEAVINGR
    goto    NewBlkState


TrainEnteringR  ; State 5 - Train entering reverse

    bsf     prvCntlr,REVFLG ; Set line reversed flag for this block

ChkSpnRev
    ; Check if train now spans this block
    movlw   BLOCKSPANNED
    btfsc   prvCntlr,ENTFLG ; Skip if entry detection off ...
    goto    NewBlkState     ; ... else train at block entrance, change state

CheckOccRev
    ; Check if train now occupies this block
    btfsc   lclCntlr,EXTFLG ; Skip if exit detection off ...
    goto    BothOccupied    ; ... else remain in current state

    ; Train no longer at block exit,
    ; next state = 2 - Train in block
    movlw   BLOCKOCCUPIED
    goto    NewBlkState


TrainLeavingR   ; State 6 - Train leaving reverse

    bsf     prvCntlr,REVFLG ; Set line reversed flag for this block

    ; Check if train has changed direction and now spans this block
    movlw   BLOCKSPANNED
    btfsc   lclCntlr,EXTFLG ; Skip if exit detection off ...
    goto    NewBlkState     ; ... else train at block exit, change state

    ; Check if train has left block
    btfsc   prvCntlr,ENTFLG ; Skip if entry detection off ...
    goto    BlockOccupied   ; ... else remain in current state

    ; Train no longer at block entrance,
    ; next state = 0 - Block clear
    movlw   BLOCKCLEAR
    goto    NewBlkState     ; Change State

BothOccupied ; End of block state machine, next & this blocks occupied
    movlw   ~ASPSTATE
    andwf   lclCntlr,F      ; Clear next block's signal aspect value (= red)

BlockOccupied ; End of block state machine, this block occupied
    movlw   ~ASPSTATE
    andwf   prvCntlr,F      ; Clear this block's signal aspect value (= red)

BlockEnd    ; End of signal block state machine

    ; Set aspect display output
    ;******************************************************************

    ; Set appropriate carry in STATUS for yellow PWM, picked up later on
    movf    ylwDuty,W
    addwf   pwmAcc,F

    movf    lclCntlr,W      ; Aspect state is run by next controller
    andlw   ASPSTATE        ; Test for red aspect required (isolates aspect)
    btfss   STATUS,Z        ; Skip if zero (= red) ...
    goto    NotStopAspect   ; ... else check for other aspects

StopAspect
    ; Display stop - red over red
    movlw   (REDMSKU | REDMSKL)
    iorwf   ASPPORT,F
    goto    AspectDone

NotStopAspect
    xorlw   ASPGREEN        ; Test for green aspect required
    andlw   ASPDOUBLE       ; Test for yellow aspect required (inverted by xor)
    btfsc   STATUS,Z        ; Skip if not zero (yellow) ...
    goto    ClearAspect     ; ... else display clear aspect

WarnAspect
    ; Display warning

    btfsc   prvCntlr,SPDFLG   ; Skip if signal at normal speed ...
    goto    MediumWarn        ; ... else display medium speed yellow aspect

NormalWarn
    ; Display normal speed warning - yellow over red

    ; Lower head displays red
    bsf     ASPPORT,REDOUTL

UpperYellow
    ; Upper head displays yellow, carry already appropriate for yellow PWM
    btfss   STATUS,C
    bsf     ASPPORT,REDOUTU
    btfsc   STATUS,C
    bcf     ASPPORT,REDOUTU
    goto    AspectDone

MediumWarn
    ; Display medium speed warning - red over yellow

    ; Upper head displays red
    bsf     ASPPORT,REDOUTU

LowerYellow
    ; Lower head displays yellow, carry already appropriate for yellow PWM
    btfss   STATUS,C
    bsf     ASPPORT,REDOUTL
    btfsc   STATUS,C
    bcf     ASPPORT,REDOUTL
    goto    AspectDone

ClearAspect
    ; Display clear

    btfsc   prvCntlr,SPDFLG   ; Skip if signal at normal speed ...
    goto    MediumGreen       ; ... else display medium speed green aspect
    btfss   nxtCntlr,SPDFLG   ; ... else skip if next signal medium speed ...
    goto    NormalGreen       ; ... else display aspect as usual

ReduceGreen
    ; Signal at normal speed, next at medium
    ; DIsplay display reduce to medium speed - yellow over green

    ; Upper head displays green
    bcf     ASPPORT,REDOUTU

    ; Lower head displays yellow
    goto    LowerYellow

NormalGreen
    ; Display normal speed clear - green over red

    ; Upper head displays green
    bcf     ASPPORT,REDOUTU

    ; Lower head displays red
    bsf     ASPPORT,REDOUTL
    goto    AspectDone

MediumGreen
    ; Display medium speed clear - red over green

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
