;**********************************************************************
;                                                                     *
;    Description:   Controller for occupation block with positional   *
;                   train detector at exit.                           *
;                                                                     *
;                   Receives train detection state from previous (in  *
;                   rear) controller which it uses as entry detector  *
;                   for occupation block.                             *
;                   Sends value of signal aspect (increment of local  *
;                   value of signal aspect) along with special speed  *
;                   indication and block reversed to previous         *
;                   controller.                                       *
;                                                                     *
;                   Receives value of signal aspect to be displayed   *
;                   along with special speed indication and block     *
;                   reversed from next (in advance) controller.       *
;                   Sends train detection state to next controller.   *
;                                                                     *
;                   If no data is received from next controller link  *
;                   input is treated as a level input indicating      *
;                   to display a stop aspect or to cycle aspect from  *
;                   stop to clear at fixed intervals after the        *
;                   passing of a train.                               *
;                                                                     *
;                   Outputs aspect display for Australian Victoria    *
;                   Railways 3 aspect MAS searchlight signals.        *
;                                                                     *
;    Author:        Chris White                                       *
;    Company:       Monitor Computing Services Ltd.                   *
;                                                                     * 
;                                                                     *
;**********************************************************************
;                                                                     *
;    Copyright (C) 2017  Monitor Computing Services Ltd.              *
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
;             Emitter  <- RA2|1  |_| 18|RA1                           *
;              Sensor  -> RA3|2      17|RA0                           *
;          !Detecting  <- RA4|3      16|                              *
;                            |4      15|                              *
;                            |5      14|      Aspects:                *
;                         RB0|6      13|RB7 -> Upper red              *
; Next <-> / !Inhibit  -> RB1|7      12|RB6 -> Upper green            *
;            Previous <-> RB2|8      11|RB5 -> Lower red              *
;       Special speed  -> RB3|9      10|RB4 -> Lower green            *
;                            +---------+                              *
;                                                                     *
;**********************************************************************


;**********************************************************************
; Configuration directives and constant definitions
;**********************************************************************
#include "blcksqnc/blcksqnc_def.inc"

; Aspect output constants
REDOUTU     EQU     7           ; Upper head red aspect output bit
REDMSKU     EQU     B'10000000' ; Mask for upper head red aspect
GRNOUTU     EQU     6           ; Upper head green aspect output bit
GRNMSKU     EQU     B'01000000' ; Mask for upper head speed green aspect
REDOUTL     EQU     5           ; Lower head red aspect output bit
REDMSKL     EQU     B'00100000' ; Mask for lower head red aspect
GRNOUTL     EQU     4           ; Lower head green aspect output bit
GRNMSKL     EQU     B'00010000' ; Mask for lower head green aspect


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

#include "blcksqnc/blcksqnc_cod.inc"


;**********************************************************************
; Subroutine to return aspect output mask in accumulator
;**********************************************************************
GetAspectMask
    ; Set appropriate carry in STATUS for yellow PWM, picked up later on
    movf    ylwDuty,W
    addwf   pwmAcc,F

    movf    aspOut,W            ; Get aspect display value
    btfsc   STATUS,Z            ; Skip if not zero ...
    retlw   (REDMSKU | REDMSKL) ; ... else display stop, red over red

    btfss   aspOut,ASPCLFLG ; Skip if clear aspects required ...
    goto    WarnAspect      ; ... else warning aspects required

    ; Display clear:
    ;  - normal speed = green over red,
    ;  - medium speed = red over green
    ;  - reduce to medium speed = yellow over green
    btfsc   prvCntlr,SPDFLG     ; Skip if signal at normal speed ...
    retlw   (REDMSKU | GRNMSKL) ; ... else display medium clear, red over green
    btfss   nxtCntlr,SPDFLG     ; ... else skip if next signal medium speed ...
    retlw   (GRNMSKU | REDMSKL) ; ... else display normal clear, green over red

    ; Signal at normal speed, next at medium
    ; Display reduce to medium speed, yellow over green
    movlw   GRNMSKL         ; Lower head displays green
    goto    UpperYellow     ; Upper head displays yellow

WarnAspect
    ; Display warning

    btfsc   prvCntlr,SPDFLG ; Skip if signal at normal speed ...
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
