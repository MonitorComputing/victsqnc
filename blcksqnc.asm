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
; Include and configuration directives                                *
;**********************************************************************

    list      p=16C84

#include <p16C84.inc>

; Configuration word
;  - Code Protection Off
;  - Watchdog timer disabled
;  - Power up timer enabled
;  - Crystal (resonator) oscillator

    __CONFIG   _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC

; '__CONFIG' directive is used to embed configuration data within .asm file.
; The lables following the directive are located in the respective .inc file.
; See respective data sheet for additional information on configuration word.

; Include serial interface macros
#include <\dev\projects\utility\pic\asyn_srl.inc>
#include <\dev\projects\utility\pic\link_hd.inc>


;**********************************************************************
; Macro definitions                                                   *
;**********************************************************************
MaxIns      macro   arg1, arg2, instr

#if (arg1 > arg2)
    instr   arg1
#else
    instr   arg2
#endif

    endm

;**********************************************************************
; Constant definitions                                                *
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

; Next signal serial interface constants (see 'asyn_srl.inc')
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

; Previous signal serial interface constants (see 'asyn_srl.inc')
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

INPHIGHWTR  EQU     B'11111000' ; Input debounce on threshold mask

; Signalling status constants

; State values, 'this' block
BLOCKCLEAR     EQU  0           ; Block clear state value
TRAINENTERINGF EQU  1           ; Train entering forward state value
BLOCKOCCUPIED  EQU  2           ; Block occupied state value
TRAINLEAVINGF  EQU  3           ; Train leaving forward state value
BLOCKSPANNED   EQU  4           ; Block spanned state value
TRAINENTERINGR EQU  5           ; Train entering reverse state value
TRAINLEAVINGR  EQU  6           ; Train leaving reverse state value
BLKSTATE       EQU  B'00000111' ; Mask to isolate signal block state bits

ASPGREEN    EQU     B'11000000' ; Green aspect value
ASPDOUBLE   EQU     B'10000000' ; Double yellow aspect value mask
ASPINCR     EQU     B'01000000' ; Aspect value increment
ASPSTATE    EQU     B'11000000' ; Aspect value mask

REDDUTY     EQU     0xFF        ; PWM duty cycle for red aspect
GRNDUTY     EQU     0           ; PWM duty cycle for green aspect

REVFLG      EQU     3           ; Line reversed bit in status byte
REVSTATE    EQU     B'00001000' ; Line reversed state bit mask

SPDFLG      EQU     4           ; Special speed bit in status byte
SPDSTATE    EQU     B'00010000' ; Special speed state bit mask

DETFLG      EQU     5           ; Train detection bit in status byte
DETSTATE    EQU     B'00100000' ; Train detection state bit mask

NRVFLG      EQU     DETFLG      ; Line reversed bit in status from next signal
NRVSTATE    EQU     DETSTATE    ; Line reversed state from next bit mask

; Aspect output constants
ASPPORT         EQU     PORTB       ; Aspect output port
REDOUTN         EQU     7           ; Normal speed red aspect output bit
GREENOUTN       EQU     6           ; Normal speed green aspect output bit
REDOUTM         EQU     5           ; Medium speed red aspect output bit
GREENOUTM       EQU     4           ; Medium speed green aspect output bit


;**********************************************************************
; Variable registers                                                  *
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

; Next signal interface
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

; Previous signal interface
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

lclState        ; Local signalling status
                ;   bits 0,2 - Signal block state
                ;     0 - Block clear
                ;     1 - Train entering forward
                ;     2 - Block occupied
                ;     3 - Train leaving forward
                ;     4 - Block spanned
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

nxtState        ; Remote signalling status from next signal
                ;   bits 0,3 - Unused
                ;   bit 4 - Special speed
                ;   bit 5 - Line reversed
                ;   bits 6,7 - Aspect value
                ;     0 - Red
                ;     1 - Yellow
                ;     2 - Double Yellow
                ;     3 - Green

prvState        ; Remote signalling status from previous signal
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
telemPrv        ; Data last received from previous signal
telemNxt        ; Data last received from next signal

ylwDuty         ; PWM duty cycle for yellow aspect
pwmAccN         ; PWM accumulator for 'normal speed' aspects
pwmDutyN        ; Current PWM duty cycle for 'normal speed' aspects
pwmAccM         ; PWM accumulator for 'medium speed' aspects
pwmDutyM        ; Current PWM duty cycle for 'medium speed' aspects

            ENDC


;**********************************************************************
; EEPROM initialisation                                               *
;**********************************************************************

            ORG     0x2100  ; EEPROM data area

EEaspectTime    DE  6       ; Seconds to delay between aspect changes
EEylwDuty       DE  0x50    ; PWM duty cycle value for yellow aspect


;**********************************************************************
; Reset vector                                                        *
;**********************************************************************

            ORG     0x000   ; Processor reset vector

BootVector
    clrf    INTCON          ; Disable interrupts
    clrf    INTCON          ; Ensure interrupts are disabled
    goto    Boot            ; Jump to beginning of program


;**********************************************************************
; Interrupt vector                                                    *
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

    ; Service next signal link

    decfsz  serNTimer,W     ; Decrement serial timing counter, skip if zero ...
    movwf   serNTimer       ; ... else update the counter

    btfss   lnkNState,LNKRXFLG
    goto    linkNNotRx

    decfsz  lnkNTimer,W     ; Decrement Rx timeout counter, skip if zero ...
    movwf   lnkNTimer       ; ... else update the counter

    call    SrvcRxN         ; Service link serial reception
    xorlw   RX_BUSY         ; Test if receiving data
    movlw   (INTLINKTMON + 1)
    btfsc   STATUS,Z        ; Skip if not receiving data ...
    movwf   lnkNTimer       ; ... else reload the Rx timeout counter

linkNNotRx
    btfsc   lnkNState,LNKTXFLG
    call    SrvcTxN         ; Service link serial transmission

    ; Service previous signal link

    decfsz  serPTimer,W     ; Decrement serial timing counter, skip if zero ...
    movwf   serPTimer       ; ... else update the counter

    btfss   lnkPState,LNKRXFLG
    goto    linkPNotRx

    decfsz  lnkPTimer,W     ; Decrement Rx timeout counter, skip if zero ...
    movwf   lnkPTimer       ; ... else update the counter

    call    SrvcRxP         ; Service link serial reception
    xorlw   RX_BUSY         ; Test if receiving data
    movlw   (INTLINKTMOP + 1)
    btfsc   STATUS,Z        ; Skip if not receiving data ...
    movwf   lnkPTimer       ; ... else reload the Rx timeout counter

linkPNotRx
    btfsc   lnkPState,LNKTXFLG
    call    SrvcTxP         ; Service link serial transmission

    ; Run interrupt scaling counter for second timing
    decfsz  intScCount,W    ; Decrement interrupt scaling counter into W
    movwf   intScCount      ; If result is not zero update the counter

    ; Run detection logic

    btfsc   EMTPORT,EMTBIT  ; Test current state of emitter ...
    goto    EmitterIsOff    ; ... jump if off, else ...

EmitterIsOn

    btfss   SNSPORT,SNSBIT  ; Test if sensor is also on ...
    goto    SensorNotOn     ; ... else sensor not in correspondence

    incfsz  snsAcc,W        ; Increment sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator
    goto    EmitterOnEnd   

SensorNotOn

    decfsz  snsAcc,W        ; Decrement sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator
    decfsz  snsAcc,W        ; Decrement sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator

EmitterOnEnd
    bsf     EMTPORT,EMTBIT  ; Turn emitter off
    goto    SnsChkEnd

EmitterIsOff

    btfsc   SNSPORT,SNSBIT  ; Test if sensor is also off ...
    goto    SensorNotOff    ; ... else sensor not in correspondence

    incfsz  snsAcc,W        ; Increment sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator
    goto    EmitterOffEnd   

SensorNotOff

    decfsz  snsAcc,W        ; Decrement sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator
    decfsz  snsAcc,W        ; Decrement sensor match accumulator into W
    movwf   snsAcc          ; If result is not zero update the accumulator

EmitterOffEnd
    bcf     EMTPORT,EMTBIT  ; Turn emitter on

SnsChkEnd

EndISR
    movf    pclath_isr,W    ; Retrieve copy of PCLATH register
    movwf   PCLATH          ; Restore pre-isr PCLATH register contents
    swapf   status_isr,W    ; Swap copy of STATUS register into W register
    movwf   STATUS          ; Restore pre-isr STATUS register contents
    swapf   w_isr,F         ; Swap pre-isr W register value nibbles
    swapf   w_isr,W         ; Swap pre-isr W register into W register

    retfie                  ; return from Interrupt


;**********************************************************************
; Main program initialisation code                                    *
;**********************************************************************

#include <\dev\projects\utility\pic\eeprom.inc>

Boot
    ; Clear I/O ports
    clrf    PORTA
    clrf    PORTB

    BANKSEL OPTION_REG

    ; Program I/O port bit directions
    movlw   PORTASTATUS
    movwf   TRISA
    movlw   PORTBSTATUS
    movwf   TRISB

    ; Set option register:
    ;   Prescaler assignment - watchdog timer
    clrf    OPTION_REG
    bsf     OPTION_REG,PSA

    BANKSEL TMR0

    movlw   PORTASTATUS     ; For Port A need to write one to each bit ...
    movwf   PORTA           ; ... being used for input

    bsf     EMTPORT,EMTBIT  ; Ensure detector emmitter is off
    bsf     DETPORT,DETBIT  ; Ensure detector indicator is off

    ; Initialise input debounce accumulators
    clrf    snsAcc          ; Initialise sensor for clear
    incf    snsAcc,F        ; Prevent rollover down through zero
    clrf    detAcc          ; Initialise detection input for no train detected
    decf    detAcc,F        ; Rollover through zero to 'full house'
    clrf    inhAcc          ; Initialise inhibit input for automatic free run
    decf    inhAcc,F        ; Rollover through zero to 'full house'
    clrf    spdAcc          ; Initialise special speed input for normal
    decf    spdAcc,F        ; Rollover through zero to 'full house'

    ; Clear all signal states (default to red)
    clrf    nxtState
    clrf    lclState
    clrf    prvState

    ; Initialise aspect output PWM
    movlw   low EEylwDuty
    call    GetEEPROM
    movwf   ylwDuty

    clrf    pwmAccN
    clrf    pwmDutyN
    clrf    pwmAccM
    clrf    pwmDutyM

    ; Initialise timing

    movlw   INTSCLNG
    movwf   intScCount      ; Initialise interrupts scaling counter

    movlw   SECSCLNG
    movwf   secCount        ; Initialise one second scaled interrupts counter

    movlw   low EEaspectTime
    call    GetEEPROM
    movwf   aspectTime      ; Initialise aspect interval for next signal
    movwf   nxtTimer        ; Initialise timer used to simulate next signal

    ; Initialise next signal link to receive
    call    InitRxN

    ; Initialise previous signal link to transmit
    call    InitTxP

    ; Initialise interrupts
    movlw   RTCCINT
    movwf   TMR0            ; Initialise RTCC for timer interrupts
    clrf    INTCON          ; Disable all interrupt sources
    bsf     INTCON,T0IE     ; Enable RTCC interrupts
    bsf     INTCON,GIE      ; Enable interrupts

Main        ; Top of main processing loop

Timing
    ; Perform timing operations

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

    incf    pwmDutyN,W      ; Test normal speed PWM duty cycle ...
    btfsc   STATUS,Z        ; ... for 'full scale' value (overflow to zero) ...
    goto    RedAspN         ; ... if so display red aspect (avoids flickering)

    movf    pwmDutyN,W
    addwf   pwmAccN,F
    btfsc   STATUS,C
    goto    RedAspN

    bcf     ASPPORT,REDOUTN
    bsf     ASPPORT,GREENOUTN
    goto    EndAspN

RedAspN
    bsf     ASPPORT,REDOUTN
    bcf     ASPPORT,GREENOUTN

EndAspN

    incf    pwmDutyM,W      ; Test medium speed PWM duty cycle ...
    btfsc   STATUS,Z        ; ... for 'full scale' value (overflow to zero) ...
    goto    RedAspM         ; ... if so display red aspect (avoids flickering)

    movf    pwmDutyM,W
    addwf   pwmAccM,F
    btfsc   STATUS,C
    goto    RedAspM

    bcf     ASPPORT,REDOUTM
    bsf     ASPPORT,GREENOUTM
    goto    EndAspM

RedAspM
    bsf     ASPPORT,REDOUTM
    bcf     ASPPORT,GREENOUTM

EndAspM

    ; Check status of detector indicator

    btfsc   DETPORT,DETBIT  ; Skip if detector indicator is on ...
    goto    IndicatorIsOff  ; ... else jump if detector indicator is off

    ; Detector indicator is on
    decf    snsAcc,W        ; Test detector correspondence accumulator
    btfsc   STATUS,Z        ; Skip if above off threshold ...

    ; Detector correspondence has fallen to or below off threshold
    bsf     DETPORT,DETBIT  ; ... else turn detector indicator off
    goto    EndDetector

IndicatorIsOff
    ; Detector indicator is off
    movf    snsAcc,W        ; Test if detector correspondence accumulator ...
    andlw   INPHIGHWTR      ; ... is above on threshold
    btfsc   STATUS,Z        ; Skip if above on threshold ...
    goto    EndDetector     ; ... else do nothing

    ; Detector correspondence has risen above on threshold
    bcf     DETPORT,DETBIT  ; Turn detector indicator on

    clrf    detAcc          ; Set detection accumulator for train detected
    incf    detAcc,F        ; Prevent rollover down through zero

EndDetector

    ; Check status of train detection input (active low)

    btfss   DETPORT,DETBIT  ; Skip if train detection input is set ...
    goto    DecDetAcc       ; ... else jump if not set

    incf    detAcc,W        ; Increment train detection accumulator
    btfsc   STATUS,Z        ; Skip if not rolled over to zero ...
    goto    DetectEnd       ; ... else do nothing
    
    movwf   detAcc          ; Update the train detection accumulator

    andlw   INPHIGHWTR      ; Test if above off threshold
    btfss   STATUS,Z        ; Skip if not above off threshold ...
    bcf     lclState,DETFLG ; ... else set detection state to off
    goto    DetectEnd    

DecDetAcc
    decf    detAcc,W        ; Decrement train detection accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   detAcc          ; ... else update the accumulator

    btfsc   STATUS,Z        ; Skip if above on threshold (not reached zero) ...
    bsf     lclState,DETFLG ; ... else set train detection state to on

DetectEnd

    ; Check status of special speed input (active low)

    btfss   SPDPORT,SPDBIT  ; Skip if special speed input is set ...
    goto    DecSpdAcc       ; ... else jump if not set

    incf    spdAcc,W        ; Increment special speed input accumulator
    btfsc   STATUS,Z        ; Skip if not rolled over to zero ...
    goto    SpeedEnd        ; ... else do nothing
    
    movwf   spdAcc          ; Update special speed input accumulator

    andlw   INPHIGHWTR      ; Test if above off threshold
    btfss   STATUS,Z        ; Skip if not above off threshold ...
    bcf     lclState,SPDFLG ; ... else set speed state to normal
    goto    SpeedEnd   

DecSpdAcc
    decf    spdAcc,W        ; Decrement speed input accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   spdAcc          ; ... else update the accumulator

    btfsc   STATUS,Z        ; Skip if above on threshold (not reached zero) ...
    bsf     lclState,SPDFLG ; ... else set speed state to special

SpeedEnd

    ; Look for status reply from previous signal

    btfsc   lnkPState,LNKDIRFLG ; Skip if waiting for reply from previous ...
    goto    PrevRxEnd           ; ... else skip over previous signal receive

    call    LinkRxToP           ; Check link reception timeout
    btfsc   STATUS,Z            ; Skip if link not timedout ...
    bsf     lnkPState,LNKDIRFLG ; ... else resume sending to previous signal

    call    LinkRxP         ; Check for data from previous signal
    btfss   STATUS,Z        ; Skip if data received ...
    goto    PrevRxEnd       ; ... else skip over received data decoding

DecodePrev

    bsf     lnkPState,LNKDIRFLG ; Resume sending to previous signal

    movwf   FSR             ; Store the received data

    ; As a simple error check received data is ignored unless same value
    ; received twice in succession

    xorwf   telemPrv,F      ; Test against last data received
    movwf   telemPrv        ; Replace last data received
    btfss   STATUS,Z        ; Skip if last and just received data match ...
    goto    PrevRxEnd       ; ... else ignore received data

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check these are in low nibble with their ones complement in high nibble

    swapf   FSR,W           ; Get received data but with nibbles swapped
    comf    FSR,F           ; Ones complement the received data
    xorwf   FSR,F           ; Exclusive or complemented and swapped data
    btfss   STATUS,Z        ; Skip if result is zero, i.e. data is ok ...
    goto    PrevRxEnd       ; ... else ignore received data

    movwf   prvState        ; Save received data as previous signal status

PrevRxEnd

    ; Look for status received from next signal

    btfsc   lnkNState,LNKDIRFLG ; Skip if not replying to next ...
    goto    NextRxEnd           ; ... else skip over next signal receive

    call    LinkRxN         ; Check for data from next signal
    btfss   STATUS,Z        ; Skip if data received ...
    goto    NextRxEnd       ; ... else skip over next signal receive

    movwf   FSR             ; Store the received data

    ; As a simple error check received data is ignored unless same value
    ; received twice in succession

    xorwf   telemNxt,F      ; Test against last data received
    movwf   telemNxt        ; Replace last data received
    btfss   STATUS,Z        ; Skip if last and just received data match ...
    goto    NextRxEnd       ; ... else ignore received data

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check these are in low nibble with their ones complement in high nibble

    swapf   FSR,W           ; Get received data but with nibbles swapped
    comf    FSR,F           ; Ones complement the received data
    xorwf   FSR,F           ; Exclusive or complemented and swapped data
    btfss   STATUS,Z        ; Skip if result is zero, i.e. data is ok ...
    goto    NextRxEnd       ; ... else ignore received data

    movwf   nxtState        ; Save received data as next signal status

    bsf     lnkNState,LNKDIRFLG ; Reply to next signal

    ; If next signal link is not timed out then ignore inhibit input
    clrf    inhAcc          ; Reset inhibit input for automatic free run
    decf    inhAcc,F        ; Rollover through zero to 'full house'

NextRxEnd

    ; Test if next signal link has timedout, i.e. there is no next signal

    call    LinkRxToN       ; Check link reception timeout
    btfss   STATUS,Z        ; Skip if link timedout ...
    goto    NextNotTimedOut ; ... else keep waiting for data

    ; Next signal link timed out, simulate next signal

    decfsz  nxtTimer,W      ; Test if signalling timer elapsed ...
    goto    NxtBlkEnd       ; ... else skip next signal sequencing

SequenceNxtBlk
    ; Time to simulate next signal changing aspect
    movlw   ASPINCR
    addwf   nxtState,W      ; Increment to next aspect value
    btfss   STATUS,C        ; Skip if overflow, already showing 'green' ...
    movwf   nxtState        ; ... else store new aspect value

DelayNxtBlk
    ; Load signalling timer for the duration of the new aspect
    movf    aspectTime,W
    movwf   nxtTimer

NxtBlkEnd   ; End of simulation of next signal.

    ; Next signal link timed out, check status of inhibit input (active low)

    btfss   INHPORT,INHBIT  ; Skip if inhibit input is set ...
    goto    DecInhAcc       ; ... else jump if not set

    decfsz  inhAcc,W        ; Skip if inhibit accumulator reached zero ...
    movwf   inhAcc          ; ... else update inhibit input accumulator
    goto    InhibitEnd   

DecInhAcc
    decf    inhAcc,W        ; Decrement inhibit input accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   inhAcc          ; ... else  update the accumulator

    btfss   STATUS,Z        ; Skip if not above on threshold (reached zero) ...
    goto    InhibitEnd      ; ... else leave inhibit state to on

    movlw   ~ASPSTATE
    andwf   nxtState,F      ; Clear next signal aspect value bits (= red)

    ; Load signalling timer to simulate time taken by train to traverse the
    ; simulated next signal block
    movf    aspectTime,W
    movwf   nxtTimer

InhibitEnd

NextNotTimedOut

    ; Run this signal block state machine
    ; The signal aspect to display and exit of a train from the signal block
    ; are dependant on the aspect, and train detection state, of the next
    ; signal but for the purpose of this signal it doesn't matter if these have
    ; been received or simulated.

    movlw   high BlockTable ; Load jump table address high byte ...
    movwf   PCLATH          ; ... into PCLATH to make jump in same code block
    movf    lclState,W      ; Use current state value ...
    andlw   BLKSTATE        ; ... (after removing flag and aspect bits) ...
    addwf   PCL,F           ; ... as offset into state jump table

BlockTable
    goto    BlockClear      ; State 0 - Block clear
    goto    TrainEnteringF  ; State 1 - Train entering forward
    goto    BlockOccupied   ; State 2 - Block occupied
    goto    TrainLeavingF   ; State 3 - Train leaving forward
    goto    BlockSpanned    ; State 4 - Block spanned
    goto    TrainEnteringR  ; State 5 - Train entering reverse
    goto    TrainLeavingR   ; State 6 - Train leaving reverse

#if (high BlockTable) != (high $)
    error "Signal block state jump table split across page boundary"
#endif


BlockClear      ; State 0 - Block clear

    ; Set signal aspect, this signals aspect value (if not Red) depends on the
    ; aspect value of the next signal such that:
    ; 'Next'     ->    'This'
    ; Red              Yellow
    ; Yellow           Double Yellow
    ; Double Yellow    Green
    ; Green            Green

    movlw   ~ASPSTATE
    andwf   lclState,F      ; Clear signal aspect value bits (= red)

    btfsc   nxtState,NRVFLG ; Skip if next block is not line reversed ...
    goto    CheckNtrRev     ; ... else leave signal aspect as red

    movlw   ASPINCR
    addwf   nxtState,W      ; Increment next signal aspect value into W
    btfsc   STATUS,C        ; Skip if no overflow ...
    movlw   ASPGREEN        ; ... else set for green aspect
    andlw   ASPSTATE        ; Isolate new aspect value bits   

    iorwf   lclState,F      ; Set new aspect value

CheckNtrRev
    ; Check for train entering in reverse
    btfss   lclState,DETFLG ; Skip if exit detection on ...
    goto    CheckNtrFwd     ; ... else check for train entering forwards

    ; Train at block exit,
    ; next state = 5 - Train entering reverse
    movlw   ~BLKSTATE
    andwf   lclState,W
    iorlw   TRAINENTERINGR
    movwf   lclState
    goto    TrainEnteringR

CheckNtrFwd
    ; Check for train entering forwards
    btfss   prvState,DETFLG ; Skip if entry detection on ...
    goto    BlockEnd        ; ... else remain in current state

    ; Train at block entrance,
    ; next state = 1 - Train entering forward,
    incf    lclState,F


TrainEnteringF  ; State 1 - Train entering forward

    bcf     lclState,REVFLG ; Clear line reversed flag for local block

ChkSpnFwd
    ; Check for train spanning forward
    btfss   lclState,DETFLG ; Skip if exit detection on ...
    goto    CheckOccFwd     ; ... else check for train occupying forwards

    ; Train at block exit,
    ; next state = 4 - Block spanned
    movlw   ~BLKSTATE
    andwf   lclState,W
    iorlw   BLOCKSPANNED
    movwf   lclState
    goto    BlockSpanned

CheckOccFwd
    btfsc   prvState,DETFLG ; Skip if entry detection off ...
    goto    TrainInBlock    ; ... else remain in current state

    ; Train no longer at block entrance,
    ; next state = 2 - Block occupied
    incf    lclState,F


BlockOccupied   ; State 2 - Block occupied

CheckExtRev
    ; Check for train exiting in reverse
    btfss   prvState,DETFLG ; Skip if entry detection on ...
    goto    CheckExtFwd     ; ... else check for train exiting forwards

    ; Train at block entrance,
    ; next state = 6 - Train leaving reverse
    movlw   ~BLKSTATE
    andwf   lclState,W
    iorlw   TRAINLEAVINGR
    movwf   lclState
    goto    TrainLeavingR

CheckExtFwd
    btfss   lclState,DETFLG ; Skip if exit detection on ...
    goto    TrainInBlock    ; ... else remain in current state

    ; Train detected at block exit,
    ; next state = 3 - Train leaving forward
    incf    lclState,F


TrainLeavingF   ; State 3 - Train leaving forward

    bcf     lclState,REVFLG ; Clear line reversed flag for local block

    call    LinkRxToN       ; Check link reception timeout
    btfss   STATUS,Z        ; Skip if link timedout ...
    goto    NextBlockLive   ; ... else skip simulation of next signal

    ; Link to next signal timedout so simulate train passing next signal

    movlw   ~ASPSTATE
    andwf   nxtState,F      ; Clear next signal aspect value bits (= red)

    ; Load signalling timer to simulate time taken by train to traverse the
    ; simulated next signal block
    movf    aspectTime,W
    movwf   nxtTimer

NextBlockLive
    btfsc   lclState,DETFLG ; Skip if exit detection off ...
    goto    TrainInBlock    ; ... else remain in current state

    ; Train no longer at block exit,
    ; next state = 0 - Block clear
    movlw   ~BLKSTATE
    andwf   lclState,F
    goto    BlockEnd


BlockSpanned    ; State 4 - Block spanned

CheckTrvRev
    ; Check for train traversal of block in reverse
    btfsc   lclState,DETFLG ; Skip if exit detection off ...
    goto    CheckTrvFwd     ; ... else check for train exiting forwards

    ; Train no longer at block exit,
    ; next state = 6 - Train leaving reverse
    movlw   ~BLKSTATE
    andwf   lclState,W
    iorlw   TRAINLEAVINGR
    movwf   lclState
    goto    TrainLeavingR

CheckTrvFwd
    ; Check for train traversal of block forwards
    btfsc   prvState,DETFLG ; Skip if entry detection off ...
    goto    TrainInBlock    ; ... else remain in current state

    ; Train no longer at block entrance,
    ; next state = 3 - Train leaving forward
    movlw   ~BLKSTATE
    andwf   lclState,W
    iorlw   TRAINLEAVINGF
    movwf   lclState
    goto    TrainLeavingF


TrainEnteringR  ; State 5 - Train entering reverse

    bsf     lclState,REVFLG ; Set line reversed flag for local block

ChkSpnRev
    ; Check for train spanning in reverse
    btfss   prvState,DETFLG ; Skip if entry detection on ...
    goto    CheckOccRev     ; ... else check for train occupying in reverse

    ; Train at block entrance,
    ; next state = 4 - Block spanned
    movlw   ~BLKSTATE
    andwf   lclState,W
    iorlw   BLOCKSPANNED
    movwf   lclState
    goto    BlockSpanned

CheckOccRev
    btfsc   lclState,DETFLG ; Skip if exit detection off ...
    goto    TrainInBlock    ; ... else remain in current state

    ; Train no longer at block exit,
    ; next state = 2 - Block occupied
    movlw   ~BLKSTATE
    andwf   lclState,W
    iorlw   BLOCKOCCUPIED
    movwf   lclState
    goto    BlockOccupied


TrainLeavingR   ; State 6 - Train leaving reverse

    bcf     lclState,REVFLG ; Clear line reversed flag for local block

    btfsc   prvState,DETFLG ; Skip if entry detection off ...
    goto    TrainInBlock    ; ... else remain in current state

    ; Train no longer at block entrance,
    ; next state = 0 - Block clear
    movlw   ~BLKSTATE
    andwf   lclState,F
    goto    BlockEnd


TrainInBlock ; End of signal block state machine, local block occupied
    movlw   ~ASPSTATE
    andwf   lclState,F      ; Clear signal aspect value bits (= red)

BlockEnd    ; End of signal block state machine

    ; Set aspect display output

    ; Default is to display red aspect - stop
    movlw   REDDUTY
    movwf   pwmDutyN
    movwf   pwmDutyM

    movf    nxtState,W      ; Aspect state is run by next controller

    andlw   ASPSTATE        ; Test for red aspect required (isolates aspect)
    btfsc   STATUS,Z        ; Skip if not zero (not red) ...
    goto    AspectEnd       ; ... else display red aspect

    xorlw   ASPGREEN        ; Test for green aspect required
    btfsc   STATUS,Z        ; Skip if not zero (not green) ...
    goto    GreenAspect     ; ... else display green aspect

    andlw   ASPDOUBLE       ; Test for double yellow aspect required
    btfss   STATUS,Z        ; Skip if zero (not yellow) ...
    goto    YellowAspect    ; ... else display yellow

GreenAspect
    ; Display green aspect - clear
    movlw   GRNDUTY

    btfss   lclState,SPDFLG   ; Skip if signal at medium speed ...
    btfss   nxtState,SPDFLG   ; ... else skip if next signal medium speed ...
    goto    SetAspect         ; ... else display aspect as usual

    ; Signal at normal speed, next at medium, so display reduce to medium speed
    movwf   pwmDutyM
    movf    ylwDuty,W
    movwf   pwmDutyN
    goto    AspectEnd

YellowAspect
    ; Display yellow aspect - warning
    movf    ylwDuty,W

SetAspect
    btfss   lclState,SPDFLG   ; Skip if signal not at normal speed ...
    movwf   pwmDutyN          ; ... else set normal aspect
    btfsc   lclState,SPDFLG   ; Skip if signal not at medium speed...
    movwf   pwmDutyM          ; ... else set medium aspect

AspectEnd   ; End of aspect display output

    call    SrvcLinkN       ; Service next signal link
    call    SrvcLinkP       ; Service previous signal link

    btfss   lnkPState,LNKDIRFLG ; Skip if not waiting on reply from previous
    goto    PrevTxEnd           ; ... else skip over previous signal send

    ; Encode status for transmission

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check these are in low nibble with their ones complement in high nibble

    movf    lclState,W      ; Get local signalling status

    andlw   ~DETSTATE       ; Detector state not sent to previous signal
    btfsc   lclState,REVFLG ; Test if local block line reversed flag is set ...
    iorlw   NRVSTATE        ; ... if so propagate this to previous block
    btfsc   nxtState,NRVFLG ; Test if next block line reversed flag is set ...
    iorlw   NRVSTATE        ; ... if so propagate this to previous block

    iorlw   0x0F            ; Set up for ones complement nibble later

    movwf   FSR             ; Save local signalling status
    swapf   FSR,F           ; Swap signal status into low nibble and 0xF

    andlw   0xF0            ; Isolate signalling status to be sent
    xorwf   FSR,F           ; Combined with swapped ones complemnt

    call    LinkTxP             ; Send data to previous signal
    btfsc   STATUS,Z            ; Skip if data was not sent ...
    bcf     lnkPState,LNKDIRFLG ; ... else start waiting on reply from previous

PrevTxEnd

    btfss   lnkNState,LNKDIRFLG ; Skip if replying to next signal ...
    goto    NextTxEnd           ; ... else skip over next signal send

    ; Encode status for transmission

    ; Only four bits of signalling status need to be sent so as a simple error
    ; check these are in low nibble with their ones complement in high nibble

    movf    lclState,W      ; Get local signalling status

    iorlw   0x0F            ; Set up for ones complement nibble later

    movwf   FSR             ; Save local signalling status
    swapf   FSR,F           ; Swap signal status into low nibble and 0xF

    andlw   0xF0            ; Isolate signalling status to be sent
    xorwf   FSR,F           ; Combined with swapped ones complemnt

    call    LinkTxN             ; Send data to next signal
    btfsc   STATUS,Z            ; Skip if data was not sent ...
    bcf     lnkNState,LNKDIRFLG ; ... resume listening to next signal

NextTxEnd

    goto    Main            ; End of main processing loop


;**********************************************************************
; Instance next signal interface routine macros                       *
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
; Instance previous signal interface routine macros                   *
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

    end     ; directive 'end of program'
