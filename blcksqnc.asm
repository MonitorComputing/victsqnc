; $Id$

;**********************************************************************
;                                                                     *
;    Description:   Controller for Victoria Railways multi aspect     *
;                   colour light speed signal with associated         *
;                   positional train detector after  signal.          *
;                   Continuosly transmits displayed aspect and        *
;                   detector state to 'previous' signal whilst        *
;                   listening for same from 'next' signal.            *
;                   If data received from 'next' signal this is used  *
;                   to determine section occupation and aspect to     *
;                   display.  Otherwise aspect to display is set by   *
;                   a fixed period timer once train has passed.       *
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

    list      p=16F84

#include <p16F84.inc>

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
; Constant definitions                                                *
;**********************************************************************

; I/O port direction it masks
PORTASTATUS EQU     B'00001000'
PORTBSTATUS EQU     B'00001011'

; Interrupt & timing constants
RTCCINT     EQU     158         ; 10KHz = (1MHz / 100) - RTCC write inhibit (2)

INTSERBIT   EQU     4           ; Interrupts per serial bit @ 2K5 baud
INTSERINI   EQU     6           ; Interrupts per initial Rx serial bit @ 2K5
INTLINKDEL  EQU     0           ; Interrupt cycles for link turnaround delays

; Next signal interface constants
RXNFLAG     EQU     0           ; Receive byte buffer 'loaded' status bit
RXNERR      EQU     1           ; Receive error status bit
RXNBREAK    EQU     2           ; Received 'break' status bit
RXNTRIS     EQU     TRISB       ; Rx port direction register
RXNPORT     EQU     PORTB       ; Rx port data register
RXNBIT      EQU     1           ; Rx input bit
TXNFLAG     EQU     0           ; Transmit byte buffer 'clear' status bit
TXNTRIS     EQU     TRISA       ; Tx port direction register
TXNPORT     EQU     PORTA       ; Tx port data register
TXNBIT      EQU     1           ; Tx output bit

; Previous signal interface constants
RXPFLAG     EQU     3           ; Receive byte buffer 'loaded' status bit
RXPERR      EQU     4           ; Receive error status bit
RXPBREAK    EQU     5           ; Received 'break' status bit
RXPTRIS     EQU     TRISB       ; Rx port direction register
RXPPORT     EQU     PORTB       ; Rx port data register
RXPBIT      EQU     2           ; Rx input bit
TXPFLAG     EQU     3           ; Transmit byte buffer 'clear' status bit
TXPTRIS     EQU     TRISB       ; Tx port direction register
TXPPORT     EQU     PORTB       ; Tx port data register
TXPBIT      EQU     2           ; Tx output bit

; Timing constants
INTSCLNG    EQU     80 + 1      ; Interrupts scaling for seconds
SECSCLNG    EQU     125         ; Scaled interrupts per second
HALFSEC     EQU     B'11000000' ; Roughly half second scaled interrupts mask

NEXTTIMEOUT EQU     13 + 1      ; Next signal link timeout (scaled interrupts)

; Detector I/O constants
EMTPORT         EQU     PORTA   ; Emitter drive port
EMTBIT          EQU     2       ; Emmitter drive bit (active low)
SNSPORT         EQU     PORTA   ; Sensor input port
SNSBIT          EQU     3       ; Sensor input bit (active high)
DETPORT         EQU     PORTA   ; Detection indicator port
DETBIT          EQU     4       ; Detection indicator bit (active low)

; Inhibit (force display of red aspect) input constants
INHPORT         EQU     PORTB   ; Inhibit input port
INHBIT          EQU     1       ; Inhibit input bit (active low)

; Special speed input constants
SPDPORT         EQU     PORTB   ; Special speed input port
SPDBIT          EQU     3       ; Special speed input bit (active low)

INPHIGHWTR      EQU     B'11111000' ; Input debounce on threshold mask

; Signalling status constants
BLKSTATE        EQU     B'00000011' ; Mask to isolate signal block state bits

; State values, 'this' block
BLOCKCLEAR      EQU     0           ; Block clear state value
TRAINENTERING   EQU     1           ; Train entering block state value
BLOCKOCCUPIED   EQU     2           ; Block occupied state value
TRAINLEAVING    EQU     3           ; Train leaving block state value

ASPSTATE        EQU     B'11000000' ; Aspect value mask
ASPSTSWP        EQU     B'00001100' ; Swapped nibbles aspect value mask
ASPINCR         EQU     B'01000000' ; Aspect value increment
ASPGREEN        EQU     B'11000000' ; Green aspect value
ASPDOUBLE       EQU     B'10000000' ; Double yellow aspect value mask

INHFLG          EQU     3           ; Inhibit bit in status byte
INHSTATE        EQU     B'00001000' ; Inhibit state bit mask

SPDFLG          EQU     4           ; Special speed bit in status byte
SPDSTATE        EQU     B'00010000' ; Special speed state bit mask

DETFLG          EQU     5           ; Train detection bit in status byte
DETSTATE        EQU     B'00100000' ; Train detection state bit mask

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
srlIfStat       ; Serial I/F status flags

; Next signal interface
serNTmr         ; Interrupt counter for serial bit timing
serNReg         ; Data shift register
serNByt         ; Data byte buffer
serNBitCnt      ; Bit down counter
lnkNState       ; Link state register

; Previous signal interface
serPTmr         ; Interrupt counter for serial bit timing
serPReg         ; Data shift register
serPByt         ; Data byte buffer
serPBitCnt      ; Bit down counter
lnkPState       ; Link state register

intScCount       ; Interrupt scaling counter for second timing
secCount        ; Scaled interrupts counter for second timing

snsAcc          ; Detector sensor match (emitter state) accumulator

detAcc          ; Detection input debounce accumulator
inhAcc          ; Inhibit input debounce accumulator
spdAcc          ; Speed input debounce accumulator

sigState        ; Signalling status (for this signal)
                ;   bits 0,1 - Signal block state
                ;     3 - Train leaving block
                ;     2 - Block occupied
                ;     1 - Train entering Block
                ;     0 - Block Clear
                ;   bit 2 - Unused
                ;   bit 3 - Inhibit state
                ;   bit 4 - Special speed
                ;   bit 5 - Detection state
                ;   bits 6,7 - Aspect value
                ;     3 - Green
                ;     2 - Double Yellow
                ;     1 - Yellow
                ;     0 - Red

nxtState        ; Signalling status received from next signal
                ;   bits 0,3 - Unused
                ;   bit 4 - Special speed
                ;   bit 5 - Detection state
                ;   bits 6,7 - Aspect value
                ;     3 - Green
                ;     2 - Double Yellow
                ;     1 - Yellow
                ;     0 - Red

aspectTime      ; Aspect interval for simulating next signal
nxtTimer        ; Second counter for simulating next signal
nxtLnkTmr       ; Scaled interrupts counter for timing out next signal link
telemData       ; Data received from next or sent to previous signal

redDuty         ; PWM duty cycle for red aspect
ylwDuty         ; PWM duty cycle for yellow aspect
grnDuty         ; PWM duty cycle for green aspect
pwmAccN         ; PWM accumulator for 'normal speed' aspects
pwmDutyN        ; Current PWM duty cycle for 'normal speed' aspects
pwmAccM         ; PWM accumulator for 'medium speed' aspects
pwmDutyM        ; Current PWM duty cycle for 'medium speed' aspects

            ENDC


;**********************************************************************
; EEPROM initialisation                                               *
;**********************************************************************

            ORG     0x2100  ; EEPROM data area

EEaspectTime    DE  6 + 1   ; Seconds to delay between aspect changes
EEredDuty       DE  0xFF    ; PWM duty cycle value for red aspect
EEylwDuty       DE  0x50    ; PWM duty cycle value for yellow aspect
EEgrnDuty       DE  0x00    ; PWM duty cycle value for green aspect


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
    movlw   RTCCINT
    addwf   TMR0,F          ; Reload RTCC

	call    SrvcLinkN       ; Service next signal link
	call    SrvcLinkP       ; Service previous signal link

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
; Instance next signal interface routine macros                       *
;**********************************************************************

EnableRxN   EnableRx  RXNTRIS, RXNPORT, RXNBIT
    return

InitRxN     InitRx  serNTmr, srlIfStat, RXNFLAG, RXNERR, RXNBREAK
    return

SrvcRxN     ServiceRx serNTmr, RXNPORT, RXNBIT, serNBitCnt, INTSERINI, srlIfStat, RXNERR, RXNBREAK, serNReg, serNByt, RXNFLAG, INTSERBIT

SerRxN      SerialRx srlIfStat, RXNFLAG, serNByt

EnableTxN   EnableTx  TXNTRIS, TXNPORT, TXNBIT
    return

InitTxN     InitTx  serNTmr, srlIfStat, TXNFLAG
    return

SrvcTxN     ServiceTx serNTmr, srlIfStat, serNByt, serNReg, TXNFLAG, serNBitCnt, INTSERBIT, TXPPORT, TXPBIT, RXNPORT, RXNBIT

SerTxN      SerialTx srlIfStat, TXNFLAG, serNByt

LinkRxN		LinkRx lnkNState, SerRxN

LinkTxN		LinkTx lnkNState, SerTxN

SrvcLinkN	SrvcLink   SrvcRxN, SrvcTxN, lnkNState, INTLINKDEL, serNTmr, EnableTxN, InitTxN, EnableRxN, InitRxN


;**********************************************************************
; Instance previous signal interface routine macros                   *
;**********************************************************************

EnableRxP   EnableRx  RXPTRIS, RXPPORT, RXPBIT
    return

InitRxP     InitRx  serPTmr, srlIfStat, RXPFLAG, RXPERR, RXPBREAK
    return

SrvcRxP     ServiceRx serPTmr, RXPPORT, RXPBIT, serPBitCnt, INTSERINI, srlIfStat, RXPERR, RXPBREAK, serPReg, serPByt, RXPFLAG, INTSERBIT

SerRxP      SerialRx srlIfStat, RXPFLAG, serPByt

EnableTxP   EnableTx  TXPTRIS, TXPPORT, TXPBIT
    return

InitTxP     InitTx  serPTmr, srlIfStat, TXPFLAG
    return

SrvcTxP     ServiceTx serPTmr, srlIfStat, serPByt, serPReg, TXPFLAG, serPBitCnt, INTSERBIT, TXPPORT, TXPBIT, RXPPORT, RXPBIT

SerTxP      SerialTx srlIfStat, TXPFLAG, serPByt

LinkRxP		LinkRx lnkPState, SerRxP

LinkTxP		LinkTx lnkPState, SerTxP

SrvcLinkP	SrvcLink   SrvcRxP, SrvcTxP, lnkPState, INTLINKDEL, serPTmr, EnableTxP, InitTxP, EnableRxP, InitRxP


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

    ; Initialise next signal serial interface
    SerInit    srlIfStat, serNTmr, serNReg, serNByt, serNBitCnt, serNTmr, serNReg, serNByt, serNBitCnt

    ; Initialise next signal link to receive
    movlw   SWITCH2RXSTATE
    movwf   lnkNState
    call    SrvcLinkN

    ; Initialise previous signal serial interface
    SerInit    srlIfStat, serPTmr, serPReg, serPByt, serPBitCnt, serPTmr, serPReg, serPByt, serPBitCnt

    ; Initialise previous signal link to transmit
    movlw   SWITCH2TXSTATE
    movwf   lnkPState
    call    SrvcLinkP

    ; Initialise input debounce accumulators
    clrf    snsAcc          ; Initialise sensor for clear
    incf    snsAcc,F        ; Prevent rollover down through zero
    clrf    detAcc          ; Initialise detection input for no train detected
    decf    detAcc,F        ; Rollover through zero to 'full house'
    clrf    inhAcc          ; Initialise inhibit input for automatic free run
    decf    inhAcc,F        ; Rollover through zero to 'full house'
    clrf    spdAcc          ; Initialise special speed input for normal
    decf    spdAcc,F        ; Rollover through zero to 'full house'

    movlw   ASPGREEN
    movwf   sigState        ; Initialise this signal to green aspect

    clrf    nxtState        ; Initialise next signal to cycle to green aspect

    ; Initialise aspect output PWM
    movlw   low EEredDuty
    call    GetEEPROM
    movwf   redDuty

    movlw   low EEylwDuty
    call    GetEEPROM
    movwf   ylwDuty

    movlw   low EEgrnDuty
    call    GetEEPROM
    movwf   grnDuty

    clrf    pwmAccN
    clrf    pwmDutyN
    clrf    pwmAccM
    clrf    pwmDutyM

    ; Initialise timers

    movlw   INTSCLNG
    movwf   intScCount      ; Initialise interrupts scaling counter

    movlw   SECSCLNG
    movwf   secCount        ; Initialise one second scaled interrupts counter

    movlw   low EEaspectTime
    call    GetEEPROM
    movwf   aspectTime      ; Initialise aspect interval for next signal
    movwf   nxtTimer        ; Initialise timer used to simulate next signal

    clrf    nxtLnkTmr       ; Initialise next signal link as timedout
    incf    nxtLnkTmr,F     ; Prevent rollover down through zero

    clrf    telemData       ; Clear serial link data store

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

    decfsz  nxtLnkTmr,W     ; Decrement next signal link timeout timer into W
    movwf   nxtLnkTmr       ; If result is not zero update the timer

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
    bcf     sigState,DETFLG ; ... else set detection state to off
    goto    DetectEnd    

DecDetAcc
    decf    detAcc,W        ; Decrement train detection accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   detAcc          ; ... else update the accumulator

    btfsc   STATUS,Z        ; Skip if above on threshold ...
    bsf     sigState,DETFLG ; ... else set train detection state to on

DetectEnd

    ; Check status of special speed input (active low)

    btfss   SPDPORT,SPDBIT  ; Skip if special speed input is set ...
    goto    DecSpdAcc       ; ... else jump if not set

    incf  spdAcc,W          ; Increment special speed input accumulator
    btfsc   STATUS,Z        ; Skip if not rolled over to zero ...
    goto    SpeedEnd        ; ... else do nothing
    
    movwf   spdAcc          ; Update special speed input accumulator

    andlw   INPHIGHWTR      ; Test if above off threshold
    btfss   STATUS,Z        ; Skip if not above off threshold ...
    bcf     sigState,SPDFLG ; ... else set speed state to normal
    goto    SpeedEnd   

DecSpdAcc
    decf  spdAcc,W          ; Decrement speed input accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   spdAcc          ; ... else update the accumulator

    btfsc   STATUS,Z        ; Skip if above on threshold ...
    bsf     sigState,SPDFLG ; ... else set speed state to special

SpeedEnd

    ; Look for status received from next signal

    call    LinkRxN         ; Check for data from next signal
    btfss   STATUS,Z        ; Skip if data received ...
    goto    TimeoutNext     ; ... else check for link timedout

    ; New data received, decode it
    movwf   telemData       ; Store the received data
    swapf   telemData,W     ; Copy received data but with nibbles swapped
    comf    telemData,F     ; One's complement the received data
    xorwf   telemData,W     ; Exclusive or complemented and swapped data
    btfss   STATUS,Z        ; Skip if result is zero, i.e. data is ok ...
    goto    NxtBlkEnd       ; ... else ignore received data

    comf    telemData,W     ; Store (original) received data ...
    movwf   nxtState        ; ... as next signal status

    movlw   NEXTTIMEOUT     ; Reset next signal ...
    movwf   nxtLnkTmr       ; ... link timeout

    ; If next signal link is not timed out then ignore inhibit input
    bcf     sigState,INHFLG ; Set inhibit state to off
    movlw   0xFF
    movwf   inhAcc          ; Reset inhibit input debounce

    goto    NxtBlkEnd

    ; Test if next signal link has timedout, i.e. there is no next signal

TimeoutNext
    decfsz  nxtLnkTmr,W     ; Skip if link timeout elapsed ...
    goto    NxtBlkEnd       ; ... else keep waiting for data

    ; Next signal link timed out, check status of inhibit input (active low)

    btfss   INHPORT,INHBIT  ; Skip if inhibit input is set ...
    goto    DecInhAcc       ; ... else jump if not set

    incf    inhAcc,W        ; Increment inhibit input accumulator
    btfsc   STATUS,Z        ; Skip if not rolled over to zero ...
    goto    InhibitEnd      ; ... else do nothing
    
    movwf   inhAcc          ; Update inhibit input accumulator

    andlw   INPHIGHWTR      ; Test if above off threshold
    btfss   STATUS,Z        ; Skip if not above off threshold ...
    bcf     sigState,INHFLG ; ... else set inhibit state to off
    goto    InhibitEnd   

DecInhAcc
    decf    inhAcc,W        ; Decrement inhibit input accumulator

    btfss   STATUS,Z        ; Skip if reached zero ...
    movwf   inhAcc          ; ... else  update the accumulator

    btfsc   STATUS,Z        ; Skip if above on threshold ...
    bsf     sigState,INHFLG ; ... else set inhibit state to on

InhibitEnd

    ; Link to next signal timedout so simulate next signal

    decfsz  nxtTimer,W      ; Test if signalling timer elapsed ...
    goto    NxtBlkEnd       ; ... else skip next signal sequencing

    btfss   nxtState,DETFLG ; Skip if next detection on ...
    goto    SequenceNxtBlk  ; ... sequence next signal aspect

    bcf     nxtState,DETFLG ; Set simulated next signal train detection off
    goto    DelayNxtBlk

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


    ; Run this signal block state machine
    ; The signal aspect to display and exit of a train from the signal block
    ; are dependant on the aspect, and train detection state, of the next
    ; signal but for the purpose of this signal it doesn't matter if these have
    ; been received or simulated.

    movlw   high BlockTable ; Load jump table address high byte ...
    movwf   PCLATH          ; ... into PCLATH to make jump in same code block
    movf    sigState,W      ; Use current state value ...
    andlw   BLKSTATE
    addwf   PCL,F           ; ... as offset into state jump table

BlockTable
    goto    BlockClear      ; State  0 - Block clear
    goto    TrainEntering   ; State  1 - Train entering Block
    goto    BlockOccupied   ; State  2 - Block occupied
    goto    TrainLeaving    ; State  3 - Train leaving block

#if (high BlockTable) != (high $)
    error "Signal block state jump table split across page boundary"
#endif


BlockClear
    ; State = "Block clear".

    ; Set signal aspect, this signals aspect value (if not Red) depends on the
    ; aspect value of the next signal such that:
    ; 'Next'     ->    'This'
    ; Red              Yellow
    ; Yellow           Double Yellow
    ; Double Yellow    Green
    ; Green            Green

    movlw   ~ASPSTATE
    andwf   sigState,F      ; Clear current aspect value bits
    movlw   ASPINCR
    addwf   nxtState,W      ; Increment next signal aspect value into W
    btfsc   STATUS,C        ; Skip if no overflow ...
    movlw   ASPGREEN        ; ... else set for green aspect
    andlw   ASPSTATE        ; Isolate new aspect value bits   
    iorwf   sigState,F      ; Set new aspect value

BlockDetect
    ; Test the state of the train detection for this signal.  If on set the
    ; state of this signal to "Train entering block" and the displayed signal
    ; aspect to "Red".

    btfss   sigState,DETFLG ; Skip if detection on ...
    goto    BlockEnd        ; ... else remain in current state

    ; Train detected at block entrance, set signal state to "Train entering
    ; block" and set signal aspect value to 'red'.
    movlw   ~(BLKSTATE | ASPSTATE)
    andwf   sigState,W
    iorlw   TRAINENTERING
    movwf   sigState


TrainEntering
    ; State = "Train entering block"

    btfsc   sigState,DETFLG ; Skip if detection off ...
    goto    BlockEnd        ; ... else remain in current state

    ; Train no longer detected at block entrance, set signal state to "Block
    ; occupied".
    movlw   ~BLKSTATE
    andwf   sigState,W
    iorlw   BLOCKOCCUPIED
    movwf   sigState

    decfsz  nxtLnkTmr,W     ; Skip if link timeout elapsed ...
    goto    BlockOccupied   ; ... else skip simulation of next signal

    ; Link to next signal timedout so simulate next signal

    movlw   ~ASPSTATE
    andwf   nxtState,F      ; Clear next signal aspect value bits (= red)
    bsf     nxtState,DETFLG ; Set simulated next signal train detection on

    ; Load signalling timer to simulate time taken by train to traverse the
    ; simulated next signal block
    movf    aspectTime,W
    movwf   nxtTimer


BlockOccupied
    ; State = "Block occupied".

    btfss   nxtState,DETFLG ; Skip if next detection on ...
    goto    BlockEnd        ; ... else remain in current state

    ; Train detected at block exit, set signal state to "Train leaving block".
    movlw   ~BLKSTATE
    andwf   sigState,W
    iorlw   TRAINLEAVING
    movwf   sigState


TrainLeaving
    ; State ="Train leaving block".

    btfsc   nxtState,DETFLG   ; Skip if next detection off ...
    goto    BlockEnd          ; ... else remain in current state

    ; Train no longer detected at block exit, set signal state to "Block
    ; clear".
    movlw   ~BLKSTATE
    andwf   sigState,W
    iorlw   BLOCKCLEAR
    movwf   sigState

BlockEnd    ; End of signal block state machine.

    ; Set aspect display output

    ; Default is to display red aspect - stop
    movf    redDuty,W
    movwf   pwmDutyN
    movwf   pwmDutyM

    btfsc   sigState,INHFLG ; Skip if not a forced red aspect display ...
    goto    AspectEnd       ; ... else display red aspect

    movlw   ASPSTATE        ; Test for red aspect required
    andwf   sigState,W
    btfsc   STATUS,Z        ; Skip if not zero (not red) ...
    goto    AspectEnd       ; ... else display red aspect

    xorlw   ASPGREEN        ; Test for green aspect required
    btfsc   STATUS,Z        ; Skip if not zero (not green) ...
    goto    GreenAspect     ; ... else display green aspect

    andlw   ASPDOUBLE       ; Test for double yellow aspect required
    btfsc   STATUS,Z        ; Skip if not zero (not double yellow) ...
    goto    DblYllAspect    ; ... else display double yellow

    ; Display yellow aspect - warning
    movf    ylwDuty,W
    goto    SetAspect

DblYllAspect
GreenAspect
    ; Display green aspect - clear
    movf    grnDuty,W

    btfss   sigState,SPDFLG   ; Skip if signal at medium speed ...
    btfss   nxtState,SPDFLG   ; ... else skip if 'next' at medium speed ...
    goto    SetAspect         ; ... else display aspect as usual

    ; Next signal at 'medium speed' so display 'reduce to medium speed'
    movwf   pwmDutyM
    movf    ylwDuty,W
    movwf   pwmDutyN
    goto    AspectEnd

SetAspect
    btfss   sigState,SPDFLG   ; Skip if signal at medium speed ...
    movwf   pwmDutyN          ; ... else set normal aspect
    btfsc   sigState,SPDFLG   ; Skip if signal at normal speed...
    movwf   pwmDutyM          ; ... else set medium aspect

AspectEnd   ; End of aspect display output

    ; Send status to previous signal

    ; Encode status
    swapf   sigState,W      ; Copy status but with nibbles swapped

    btfsc   sigState,INHFLG ; Skip if not forced red aspect display ...
    andlw   ~ASPSTSWP       ; ... else report aspect as red

    movwf   telemData
    comf    telemData,W     ; One's complement aspect and detector state
    andlw   0x0F            ; Isolate aspect, detection, and speed (swapped)
    movwf   telemData

    movf    sigState,W
    andlw   0xF0            ; Isolate aspect, detection, and speed (unswapped)

    btfsc   sigState,INHFLG ; Skip if not forced red aspect display ...
    andlw   ~ASPSTATE       ; ... else report aspect as red

    iorwf   telemData,W     ; Combine complemented and uncomplemented data

    movwf   FSR
    call    LinkTxP         ; Send data to previous signal

    goto    Main            ; End of main processing loop


;**********************************************************************
; End of source code
;**********************************************************************

    end     ; directive 'end of program'
