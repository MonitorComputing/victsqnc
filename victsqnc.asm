;**********************************************************************
;                                                                     *
;    Description:   Controller for multiple aspect colour light       *
;                   signal and occupation block with positional train *
;                   detector at block exit.                           *
;                                                                     *
;                   This is a specialisation for Australian Victoria  *
;                   Railways 3 aspect MAS searchlight signals.        *
;                                                                     *
;    Author:        Chris White                                       *
;    Company:       Monitor Computing Services Ltd.                   *
;                                                                     * 
;                                                                     *
;**********************************************************************
;                                                                     *
;    Copyright (C) 2018  Monitor Computing Services Ltd.              *
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
;                                                                     *
;                            +---+ +---+                              *
;           Lower red  <- RA2|1  |_| 18|RA1 -> Upper green            *
;         Lower green  <- RA3|2      17|RA0 -> Upper red              *
;          !Detecting <-> RA4|3      16|                              *
;                            |4      15|                              *
;                            |5      14|                              *
;     !Latch Signal On -> RB0|6      13|RB7 <-> Next / <- !Inhibit    *
;       !Line reversed -> RB1|7      12|RB6 <-> Previous              *
;   Line bidirectional -> RB2|8      11|RB5 ->  !Emitter              *
;         Normal speed -> RB3|9      10|RB4 <-  Sensor                *
;                            +---------+                              *
;                                                                     *
;**********************************************************************


;**********************************************************************
; Configuration directives and constant definitions
;**********************************************************************
#include "blcksqnc/blcksqnc_def.inc"

; Aspect output constants
REDMSKU     EQU     B'00000001' ; Mask for upper head red aspect
GRNMSKU     EQU     B'00000010' ; Mask for upper head speed green aspect
REDMSKL     EQU     B'00000100' ; Mask for lower head red aspect
GRNMSKL     EQU     B'00001000' ; Mask for lower head green aspect


;**********************************************************************
; Variable registers
;**********************************************************************
#include "blcksqnc/blcksqnc_ram.inc"

ylwDuty         ; PWM duty cycle for yellow aspect
pwmAcc          ; PWM accumulator for yellow aspect

afterRAM
            endc
endRAM      EQU afterRAM - 1
#if RAM_End < endRAM
    error "This program ran out of RAM!"
#endif


;**********************************************************************
; EEPROM initialisation
;**********************************************************************
#include "blcksqnc/blcksqnc_rom.inc"

EEylwDuty       DE  0x50    ; PWM duty cycle value for yellow aspect


;**********************************************************************
; Code
;**********************************************************************
UserInit    macro

    movlw   low EEylwDuty
    call    ReadEEPROM
    movwf   ylwDuty         ; Initialise yellow aspect PWM duty cycle

    endm

; Include serial link interface macros
;  - Serial link bit timing is performed by link service routines
#define CLKD_SERIAL
#include "blcksqnc/utility/asyn_srl.inc"
#include "blcksqnc/utility/link_hd.inc"
#include "blcksqnc/blcksqnc_cod.inc"


;**********************************************************************
; Subroutine to return aspect output mask in accumulator
;  Stop                         - Red over Red
;  Warning at medium speed      - Red over Yellow
;  Warning at normal speed      - Yellow over Red
;  Clear at medium speed        - Red over Green
;  Clear reduce to medium speed - Yellow over Green
;  Clear at normal speed        - Green over Red
;**********************************************************************
GetAspectOutput
    ; Set appropriate carry in STATUS for yellow PWM, picked up later on
    movf    ylwDuty,W
    addwf   pwmAcc,F

    movf    aspVal,W            ; Get aspect display value
    btfsc   STATUS,Z            ; Skip if not zero ...
    retlw   (REDMSKU | REDMSKL) ; ... else display stop, red over red

    btfss   aspVal,ASPW2FLG ; Skip if clear aspects required ...
    goto    WarnAspect      ; ... else warning aspects required

    ; Display clear:
    ;  - normal speed = green over red,
    ;  - medium speed = red over green
    ;  - reduce to medium speed = yellow over green
    btfss   inputs,SPDBIT       ; Skip if at normal speed ...
    retlw   (REDMSKU | GRNMSKL) ; ... else display medium clear, red over green
    btfsc   nxtCntlr,SPDFLG     ; ... else skip if next signal medium speed ...
    retlw   (GRNMSKU | REDMSKL) ; ... else display normal clear, green over red

    ; Signal at normal speed, next at medium
    ; Display reduce to medium speed, yellow over green
    movlw   GRNMSKL         ; Lower head displays green
    goto    UpperYellow     ; Upper head displays yellow

WarnAspect
    ; Display warning

    btfss   inputs,SPDBIT   ; Skip if at normal speed ...
    goto    MediumWarn      ; ... else display medium speed yellow aspect

NormalWarn
    ; Display normal speed warning, yellow over red
    movlw   REDMSKL         ; Lower head displays red

UpperYellow
    ; Upper head displays yellow, carry already appropriate for yellow PWM
    btfss   STATUS,C
    iorlw   REDMSKU
    btfsc   STATUS,C
    iorlw   GRNMSKU
    return

MediumWarn
    ; Display medium speed warning, red over yellow
    movlw   REDMSKU         ; Upper head displays red

    ; Lower head displays yellow, carry already appropriate for yellow PWM
    btfss   STATUS,C
    iorlw   REDMSKL
    btfsc   STATUS,C
    iorlw   GRNMSKL
    return


;**********************************************************************
; End of source code
;**********************************************************************

#if CodeEnd < $
    error "This program is just too big!"
#endif

    end     ; directive 'end of program'
