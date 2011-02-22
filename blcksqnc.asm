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


;**********************************************************************
; Constant definitions                                                *
;**********************************************************************

; I/O port direction it masks
PORTASTATUS EQU     B'00001000'
PORTBSTATUS EQU     B'00001011'

; Interrupt & timing constants
RTCCINT     EQU     158         ; 10KHz = (1MHz / 100) - RTCC write inhibit (2)

INT5KBIT    EQU     2           ; Interrupts per serial bit @ 5K baud
INT5KINI    EQU     3           ; Interrupts per initial Rx serial bit @ 5K
INT2K5BIT   EQU     4           ; Interrupts per serial bit @ 2K5 baud
INT2K5INI   EQU     6           ; Interrupts per initial Rx serial bit @ 2K5

; Next signal interface constants
RXNFLAG     EQU     0           ; Receive byte buffer 'loaded' status bit
RXNERR      EQU     1           ; Receive error status bit
RXNBREAK    EQU     2           ; Received 'break' status bit
RXNTRIS     EQU     TRISB       ; Rx port direction register
RXNPORT     EQU     PORTB       ; Rx port data register
RXNBIT      EQU     1           ; Rx input bit

; Previous signal interface constants
TXPFLAG     EQU     3           ; Transmit byte buffer 'clear' status bit
TXPTRIS     EQU     TRISB       ; Tx port direction register
TXPPORT     EQU     PORTB       ; Tx port data register
TXPBIT      EQU     2           ; Tx output bit

; Timing constants
INTMILLI        EQU     10 + 1  ; Interrupts per millisecond

SECMILLI        EQU     1000 + 1    ; Milliseconds per second low byte

NEXTTIMEOUT     EQU     100 + 1     ; Next signal link timeout (milliseconds)

; Detector I/O constants
EMTPORT         EQU     PORTA       ; Emitter drive port
EMTBIT          EQU     2           ; Emmitter drive bit (active low)
SNSPORT         EQU     PORTA       ; Sensor input port
SNSBIT          EQU     3           ; Sensor input bit (active high)
INDPORT         EQU     PORTA       ; Detection indicator port
INDBIT          EQU     4           ; Detection indicator bit (active low)

; Detection input constants
DETPORT         EQU     PORTB       ; Detection input port
DETBIT          EQU     0           ; Detection input bit (active low)

; Inhibit (force display of red aspect) input constants
INHPORT         EQU     PORTB       ; Inhibit input port
INHBIT          EQU     1           ; Inhibit input bit (active low)

; Speed input constants
SPDPORT         EQU     PORTB   ; Speed input port
SPDBIT          EQU     3       ; Speed input bit

INPHIGHWTR      EQU     200     ; Input debounce "On" threshold
INPLOWWTR       EQU     55      ; Input debounce "Off" threshold

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

SPDFLG          EQU     4           ; Speed bit in status byte
SPDSTATE        EQU     B'00010000' ; Speed state bit mask

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
serNRxTmr       ; Interrupt counter for serial bit timing
serNRxReg       ; Data shift register
serNRxByt       ; Data byte buffer
serNRxBitCnt    ; Bit down counter

; Previous signal interface
serPTxTmr       ; Interrupt counter for serial bit timing
serPTxReg       ; Data shift register
serPTxByt       ; Data byte buffer
serPTxBitCnt    ; Bit down counter

milliCount      ; Interrupt counter for millisecond timing

secCountLow     ; Millisecond counter (low byte) for second timing
secCountHigh    ; Millisecond counter (high byte) for second timing

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
                ;   bit 4 - Normal speed
                ;   bit 5 - Detection state
                ;   bits 6,7 - Aspect value
                ;     3 - Green
                ;     2 - Double Yellow
                ;     1 - Yellow
                ;     0 - Red

nxtState        ; Signalling status received from next signal
                ;   bits 0,3 - Unused
                ;   bit 4 - Normal speed
                ;   bit 5 - Detection state
                ;   bits 6,7 - Aspect value
                ;     3 - Green
                ;     2 - Double Yellow
                ;     1 - Yellow
                ;     0 - Red

aspectTime      ; Aspect interval for simulating next signal
nxtTimer        ; Second counter for simulating next signal
nxtLnkTmr       ; Millisecond counter for timing out next signal link
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

    call    SrvcNRx         ; Perform next signal interface Rx service
    call    SrvcPTx         ; Perform previous signal interface Tx service

    ; Run interrupt counter for millisecond timing
    decfsz  milliCount,W    ; Decrement millisecond Interrupt counter into W
    movwf   milliCount      ; If result is not zero update the counter

    ; Run detection logic

    btfsc   EMTPORT,EMTBIT  ; Test current state of emitter ...
    goto    EmitterIsOff    ; ... jump if off, else ...

EmitterIsOn

    btfss   SNSPORT,SNSBIT  ; Test if sensor is also on ...
    goto    SensorNotOn     ; ... else sensor not in correspondance

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
    goto    SensorNotOff    ; ... else sensor not in correspondance

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

    ; Debounce train detection input

    btfss   DETPORT,DETBIT  ; Skip if train detection input is set ...
    goto    DecDetAcc       ; ... otherwise jump if not set

    incfsz  detAcc,W        ; Increment train detection accumulator into W
    movwf   detAcc          ; If result is not zero update the accumulator
    goto    DetDbncEnd   

DecDetAcc
    decfsz  detAcc,W        ; Decrement train detection accumulator into W
    movwf   detAcc          ; If result is not zero update the accumulator

DetDbncEnd

    ; Debounce inhibit input

    btfss   INHPORT,INHBIT  ; Skip if inhibit input is set ...
    goto    DecInhAcc       ; ... otherwise jump if not set

    incfsz  inhAcc,W        ; Increment inhibit input accumulator into W
    movwf   inhAcc          ; If result is not zero update the accumulator
    goto    InhDbncEnd   

DecInhAcc
    decfsz  inhAcc,W        ; Decrement inhibit input accumulator into W
    movwf   inhAcc          ; If result is not zero update the accumulator

InhDbncEnd

    ; Debounce speed input

    btfss   SPDPORT,SPDBIT  ; Skip if speed input is set ...
    goto    DecSpdAcc       ; ... otherwise jump if not set

    incfsz  spdAcc,W        ; Increment speed input accumulator into W
    movwf   spdAcc          ; If result is not zero update the accumulator
    goto    SpdDbncEnd   

DecSpdAcc
    decfsz  spdAcc,W        ; Decrement speed input accumulator into W
    movwf   spdAcc          ; If result is not zero update the accumulator

SpdDbncEnd

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

EnableNRx   EnableRx  RXNTRIS, RXNPORT, RXNBIT
    return


InitNRx     InitRx  serNRxTmr, srlIfStat, RXNFLAG, RXNERR, RXNBREAK
    return


SrvcNRx     ServiceRx serNRxTmr, RXNPORT, RXNBIT, serNRxBitCnt, INT2K5INI, srlIfStat, RXNERR, RXNBREAK, serNRxReg, serNRxByt, RXNFLAG, INT2K5BIT


LinkNRx
SerNRx      SerialRx srlIfStat, RXNFLAG, serNRxByt


;**********************************************************************
; Instance previous signal interface routine macros                   *
;**********************************************************************

EnablePTx   EnableTx  TXPTRIS, TXPPORT, TXPBIT
    return


InitPTx     InitTx  serPTxTmr, srlIfStat, TXPFLAG
    return


SrvcPTx     ServiceTx serPTxTmr, srlIfStat, serPTxByt, serPTxReg, TXPFLAG, serPTxBitCnt, INT2K5BIT, TXPPORT, TXPBIT, 0, 0


LinkPTx
SerPTx      SerialTx srlIfStat, TXPFLAG, serPTxByt


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
    bsf     INDPORT,INDBIT  ; Ensure detector indicator is off

    ; Initialise next and previous signal serial link
    SerInit    srlIfStat, serPTxTmr, serPTxReg, serPTxByt, serPTxBitCnt, serNRxTmr, serNRxReg, serNRxByt, serNRxBitCnt

    call    EnableNRx       ; Enable receive from next signal
    call    InitNRx         ; Initialise receiver for next signal

    call    EnablePTx       ; Enable transmit to previous signal
    call    InitPTx         ; Initialise transmitter to previous signal

    ; Initialise input debounce accumulators
    clrf    snsAcc          ; Initialise sensor for clear
    incf    snsAcc,F        ; Prevent rollover down through zero
    clrf    detAcc          ; Initialise detection input for no train detected
    decf    detAcc,F        ; Rollover through zero to 'full house'
    clrf    inhAcc          ; Initialise inhibit input for 'free run'
    decf    inhAcc,F        ; Rollover through zero to 'full house'
    clrf    spdAcc          ; Initialise speed input for 'normal speed'
    decf    spdAcc,F        ; Rollover through zero to 'full house'

    movlw   ASPGREEN
    movwf   sigState        ; Initialise this signal to green aspect

    clrf    nxtState        ; Initialise next signal to cycle to green aspect
    bsf     nxtState,SPDFLG ; Assume next signal speed is 'Normal'

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

    movlw   INTMILLI
    movwf   milliCount      ; Initialise millisecond Interrupts counter

    movlw   low SECMILLI
    movwf   secCountLow     ; Initialise one second milliseconds counter low
    movlw   high SECMILLI
    movwf   secCountHigh    ; Initialise one second milliseconds counter high

    movlw   low EEaspectTime
    call    GetEEPROM
    movwf   aspectTime      ; Initialise aspect interval for next signal
    movwf   nxtTimer        ; Initialise timer used to simulate next signal

    clrf    nxtLnkTmr       ; Initialise next signal link  as timedout
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
    ; it reaches 1 indicating that a millisecond has passed.  Here in the main
    ; program loop (i.e. outside the interrupt service routine) the count
    ; is tested and if found to be 1 it is reset and the various timing
    ; operations are performed.

    decfsz  milliCount,W    ; Test millisecond Interrupts counter
    goto    TimingEnd       ; Skip timing if a millisecond has not elapsed

    movlw   INTMILLI        ; Reload millisecond Interrupts counter
    movwf   milliCount

    decfsz  nxtLnkTmr,W     ; Decrement next signal link timeout timer into W
    movwf   nxtLnkTmr       ; If result is not zero update the timer

    incf    pwmDutyN,W      ; Test current 'normal speed' PWM duty cycle ...
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

    incf    pwmDutyM,W      ; Test current 'medium speed' PWM duty cycle ...
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

    decfsz  secCountLow,F   ; Decrement seconds counter low byte ...
    goto    TimingEnd       ; ... skipping this jump if it has reached zero
    decfsz  secCountHigh,F  ; Decrement second counter high byte ...
    goto    TimingEnd       ; ... skipping this jump if it has reached zero

    movlw   low SECMILLI    ; Reload one second ...
    movwf   secCountLow     ; ... milliseconds counter low byte
    movlw   high SECMILLI   ; Reload one second ...
    movwf   secCountHigh    ; ... milliseconds counter high byte

    decfsz  nxtTimer,W      ; Decrement next signal simulation timer into W
    movwf   nxtTimer        ; If result is not zero update the timer

TimingEnd

    ; Check status of detector indicator

    btfsc   INDPORT,INDBIT  ; Test state of detector indicator ...
    goto    IndicatorIsOff  ; ... jump if off, else ...

    ; Detector indicator is currently on
    movf    snsAcc,W        ; Test if detector correspondance accumulator ...
    sublw   INPLOWWTR       ; ... is above "Off" threshold
    btfss   STATUS,C        ; Skip if at or below threshold ...
    goto    EndDetector     ; ... else do nothing

    ; Detector correspondance has fallen to or below threshold
    bsf     INDPORT,INDBIT  ; Turn detector indicator off
    goto    EndDetector

IndicatorIsOff
    ; Detector indicator is currently off
    movf    snsAcc,W        ; Test if detector correspondance accumulator ...
    sublw   INPHIGHWTR      ; ... is above "On" threshold
    btfsc   STATUS,C        ; Skip if above threshold ...
    goto    EndDetector     ; ... else do nothing

    ; Detector correspondance has risen above threshold
    bcf     INDPORT,INDBIT  ; Turn detector indicator on

EndDetector

    ; Check status of train detection input

Detect
    btfsc   sigState,DETFLG ; Skip if detection state is "Off" ...
    goto    DetectOn        ; ... otherwise jump if state is "On"

    ; Train detection state is currently 'Off'
    movf    detAcc,W        ; Test if detection debounce accumulator ...
    sublw   INPLOWWTR       ; ... is above "On" threshold
    btfss   STATUS,C        ; Skip if at or below threshold ...
    goto    DetectEnd       ; ... otherwise jump if above threshold

    ; Train detection input has turned "On"
    bsf     sigState,DETFLG ; Set train detection state to "On"
    goto    DetectEnd

DetectOn
    ; Train detection state is currently 'On'
    movf    detAcc,W        ; Test if detection debounce accumulator ...
    sublw   INPHIGHWTR      ; ... is above "On" threshold
    btfsc   STATUS,C        ; Skip if above threshold ...
    goto    DetectEnd       ; ... otherwise jump if at or below threshold

    ; Train detection input has turned "Off"
    bcf     sigState,DETFLG ; Set detection state to "Off"

DetectEnd

    ; Check status of 'Normal Speed' input

Speed
    btfss   sigState,SPDFLG ; Skip if speed state is 'Normal' ...
    goto    SpeedMedium     ; ... otherwise jump if state is 'Medium'

    ; Speed state is currently 'Normal'
    movf    spdAcc,W        ; Test if speed debounce accumulator ...
    sublw   INPLOWWTR       ; ... is above 'Medium' threshold
    btfss   STATUS,C        ; Skip if at or below threshold ...
    goto    SpeedEnd        ; ... otherwise jump if above threshold

    ; Speed input has turned 'Medium'
    bcf     sigState,SPDFLG ; Set train speed state to 'Medium'
    goto    SpeedEnd

SpeedMedium
    ; Speed state is currently 'Medium'
    movf    spdAcc,W        ; Test if speed debounce accumulator ...
    sublw   INPHIGHWTR      ; ... is above 'Normal' threshold
    btfsc   STATUS,C        ; Skip if above threshold ...
    goto    SpeedEnd        ; ... otherwise jump if at or below threshold

    ; Speed input has turned 'Normal'
    bsf     sigState,SPDFLG ; Set speed state to 'Normal'

SpeedEnd

    ; Look for status received from next signal

    call    LinkNRx         ; Check for data from next signal
    btfss   STATUS,Z        ; Skip if data received ...
    goto    TimeoutNext     ; ... otherwise check for link timedout

    ; New data received, decode it
    movwf   telemData       ; Store the received data
    swapf   telemData,W     ; Copy received data but with nibbles swapped
    comf    telemData,F     ; One's complement the received data
    xorwf   telemData,W     ; Exclusive or complemented and swapped data
    btfss   STATUS,Z        ; Skip if result is zero, i.e. data is ok ...
    goto    NxtBlkEnd       ; ... otherwise ignore received data

    comf    telemData,W     ; Store (original) received data ...
    movwf   nxtState        ; ... as next signal status

    movlw   NEXTTIMEOUT     ; Reset next signal ...
    movwf   nxtLnkTmr       ; ... link timeout

    ; If next signal link is not timed out then ignore inhibit input
    bcf     sigState,INHFLG ; Set inhibit state to "Off"

    goto    NxtBlkEnd

    ; Test if next signal link has timedout, i.e. there is no next signal

TimeoutNext
    decfsz  nxtLnkTmr,W     ; Skip if link timeout elapsed ...
    goto    NxtBlkEnd       ; ... otherwise keep waiting for data

    ; Link to next signal timedout so check status of inhibit input

Inhibit
    btfsc   sigState,INHFLG ; Skip if inhibit state is "Off"
    goto    InhibitOn       ; Jump if state is "On"

    ; Inhibit state is currently "Off"
    movf    inhAcc,W        ; Test if inhibit debounce accumulator ...
    sublw   INPLOWWTR       ; ... is above "On" threshold
    btfss   STATUS,C        ; Skip if at or below threshold ...
    goto    InhibitEnd      ; ... otherwise jump if above threshold

    ; Inhibit input has turned "On"
    bsf     sigState,INHFLG ; Set inhibit state to "On"
    goto    InhibitEnd

InhibitOn
    ; Inhibit state is currently "On"
    movf    inhAcc,W        ; Test if inhibit debounce accumulator ...
    sublw   INPHIGHWTR      ; ... is above "Off" threshold
    btfsc   STATUS,C        ; Skip if above threshold ...
    goto    InhibitEnd      ; ... otherwise jump if at or below threshold

    ; Inhibit input has turned "Off"
    bcf     sigState,INHFLG ; Set inhibit state to "Off"

InhibitEnd

    ; Link to next signal timedout so simulate next signal

    decfsz  nxtTimer,W      ; Test if signalling timer elapsed ...
    goto    NxtBlkEnd       ; ... otherwise skip next signal sequencing

    btfss   nxtState,DETFLG ; Skip if next detection "On" ...
    goto    SequenceNxtBlk  ; ... sequence next signal aspect

    bcf     nxtState,DETFLG ; Set simulated next signal train detection "Off"
    goto    DelayNxtBlk

SequenceNxtBlk
    ; Time to simulate next signal changing aspect
    movlw   ASPINCR
    addwf   nxtState,W      ; Increment to next aspect value
    btfss   STATUS,C        ; Skip if overflow, already showing 'green' ...
    movwf   nxtState        ; ... otherwise store new aspect value

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
    movlw   ASPGREEN        ; ... otherwise set for green aspect
    andlw   ASPSTATE        ; Isolate new aspect value bits   
    iorwf   sigState,F      ; Set new aspect value

BlockDetect
    ; Test the state of the train detection for this signal.  If "On" set the
    ; state of this signal to "Train entering block" and the displayed signal
    ; aspect to "Red".

    btfss   sigState,DETFLG ; Skip if detection "On" ...
    goto    BlockEnd        ; ... otherwise remain in current state

    ; Train detected at block entrance, set signal state to "Train entering
    ; block" and set signal aspect value to 'red'.
    movlw   ~(BLKSTATE | ASPSTATE)
    andwf   sigState,W
    iorlw   TRAINENTERING
    movwf   sigState


TrainEntering
    ; State = "Train entering block"

    btfsc   sigState,DETFLG ; Skip if detection "Off" ...
    goto    BlockEnd        ; ... otherwise remain in current state

    ; Train no longer detected at block entrance, set signal state to "Block
    ; occupied".
    movlw   ~BLKSTATE
    andwf   sigState,W
    iorlw   BLOCKOCCUPIED
    movwf   sigState

    decfsz  nxtLnkTmr,W     ; Skip if link timeout elapsed ...
    goto    BlockOccupied   ; ... otherwise skip simulation of next signal

    ; Link to next signal timedout so simulate next signal

    movlw   ~ASPSTATE
    andwf   nxtState,F      ; Clear next signal aspect value bits (= red)
    bsf     nxtState,DETFLG ; Set simulated next signal train detection "On"

    ; Load signalling timer to simulate time taken by train to traverse the
    ; simulated next signal block
    movf    aspectTime,W
    movwf   nxtTimer


BlockOccupied
    ; State = "Block occupied".

    btfss   nxtState,DETFLG ; Skip if next detection "On" ...
    goto    BlockEnd        ; ... otherwise remain in current state

    ; Train detected at block exit, set signal state to "Train leaving block".
    movlw   ~BLKSTATE
    andwf   sigState,W
    iorlw   TRAINLEAVING
    movwf   sigState


TrainLeaving
    ; State ="Train leaving block".

    btfsc   nxtState,DETFLG   ; Skip if next detection "Off" ...
    goto    BlockEnd          ; ... otherwise remain in current state

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
    goto    AspectEnd       ; ... otherwise display red aspect

    movlw   ASPSTATE        ; Test for red aspect required
    andwf   sigState,W
    btfsc   STATUS,Z        ; Skip if not zero (not red) ...
    goto    AspectEnd       ; ... otherwise display red aspect

    xorlw   ASPGREEN        ; Test for green aspect required
    btfsc   STATUS,Z        ; Skip if not zero (not green) ...
    goto    GreenAspect     ; ... otherwise display green aspect

    andlw   ASPDOUBLE       ; Test for double yellow aspect required
    btfsc   STATUS,Z        ; Skip if not zero (not double yellow) ...
    goto    DblYllAspect    ; ... otherwise display double yellow

    ; Display yellow aspect - warning
    movf    ylwDuty,W
    goto    SetAspect

DblYllAspect
GreenAspect
    ; Display green aspect - clear
    movf    grnDuty,W

    btfsc   sigState,SPDFLG   ; Skip if signal at 'medium speed' ...
    btfsc   nxtState,SPDFLG   ; ... else skip if 'next' at 'medium speed' ...
    goto    SetAspect         ; ... else display aspect as usual

    ; Next signal at 'medium speed' so display 'reduce to medium speed'
    movwf   pwmDutyM
    movf    ylwDuty,W
    movwf   pwmDutyN
    goto    AspectEnd

SetAspect
    btfsc   sigState,SPDFLG   ; Skip if signal at 'medium speed' ...
    movwf   pwmDutyN          ; ... else set 'normal' aspect
    btfss   sigState,SPDFLG   ; Skip if signal at 'normal speed' ...
    movwf   pwmDutyM          ; ... else set 'medium' aspect

AspectEnd   ; End of aspect display output

    ; Send status to previous signal

    ; Encode status
    swapf   sigState,W      ; Copy status but with nibbles swapped

    btfsc   sigState,INHFLG ; Skip if not forced red aspect display ...
    andlw   ~ASPSTSWP       ; ... otherwise report aspect as red

    movwf   telemData
    comf    telemData,W     ; One's complement aspect and detector state
    andlw   0x0F            ; Isolate aspect, detection, and speed (swapped)
    movwf   telemData

    movf    sigState,W
    andlw   0xF0            ; Isolate aspect, detection, and speed (unswapped)

    btfsc   sigState,INHFLG ; Skip if not forced red aspect display ...
    andlw   ~ASPSTATE       ; ... otherwise report aspect as red

    iorwf   telemData,W     ; Combine complemented and uncomplemented data

    movwf   FSR
    call    LinkPTx         ; Send data to previous signal

    goto    Main            ; End of main processing loop


;**********************************************************************
; End of source code
;**********************************************************************

    end     ; directive 'end of program'
