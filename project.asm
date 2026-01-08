    list p=16f877
    include "p16f877.inc"

; -----------------------
; RAM VARIABLES
; -----------------------
ADC_result      EQU 0x70    ; Raw ADC result (8-bit)
unite           EQU 0x71    ; Integer part of voltage (V)
reste           EQU 0x72    ; Remainder for conversion
diz             EQU 0x73    ; Decimal part (tenths of V)

save_W          EQU 0x74    ; Context save: W register
save_STATUS     EQU 0x75    ; Context save: STATUS register

extrus_TIMER    EQU 0x76    ; Software counter for 1-second timing
second_passe    EQU 0x77    ; bit0 = 1 => one second elapsed flag

rx_char         EQU 0x78    ; Last received character ('a' / 'r' / 'd')
rx_flag         EQU 0x79    ; bit0 = 1 => new RX command received
mode            EQU 0x7A    ; 0 = Automatic mode / 1 = On-demand mode

; -----------------------
; CONFIGURATION BITS
; -----------------------
 __CONFIG _FOSC_HS & _WDTE_OFF & _PWRTE_OFF & _CP_OFF & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _WRT_ON

; -----------------------
; INTERRUPT VECTORS
; -----------------------
    org 0x000
    goto INIT                ; Reset vector

    org 0x004
    goto ISRs                ; Interrupt vector

; -----------------------
; INITIALIZATION
; -----------------------
INIT
    ; Default operating mode = Automatic
    clrf mode
    clrf rx_flag

    ; Clear 1-second flag
    clrf second_passe

    ; 1-second counter: 20 x 50 ms = 1 s
    movlw .20
    movwf extrus_TIMER

; ---- USART configuration: 9600 baud @ 8 MHz ----
    banksel SPBRG
    movlw .51
    movwf SPBRG

    banksel TXSTA
    movlw b'00100100'        ; BRGH=1, TXEN=1, asynchronous mode
    movwf TXSTA

    banksel RCSTA
    movlw b'10000000'        ; SPEN=1 (enable serial port)
    movwf RCSTA
    bsf  RCSTA, CREN         ; Enable receiver (RX)

    banksel TRISC
    bcf TRISC,6              ; TX pin as output
    bsf TRISC,7              ; RX pin as input

; ---- ADC configuration ----
    banksel ADCON1
    movlw b'00001110'        ; AN0 analog input, Vref = Vdd/Vss
    movwf ADCON1

    banksel ADCON0
    movlw b'01000001'        ; Fosc/8, ADC enabled, channel AN0
    movwf ADCON0

; ---- TIMER1 + INTERRUPTS (50 ms time base) ----
    banksel T1CON
    movlw b'00110001'        ; Timer1 ON, prescaler 1:8, clock = Fosc/4
    movwf T1CON

    ; Timer1 preload for 50 ms: 0xCF2C (8 MHz + prescaler 1:8)
    banksel TMR1H
    movlw 0xCF
    movwf TMR1H
    movlw 0x2C
    movwf TMR1L

    banksel PIR1
    bcf PIR1, TMR1IF
    bcf PIR1, RCIF           ; Clear RX flag (RCREG read clears it anyway)

    banksel PIE1
    bsf PIE1, TMR1IE         ; Enable Timer1 interrupt
    bsf PIE1, RCIE           ; Enable USART RX interrupt

    banksel INTCON
    bsf INTCON, PEIE         ; Enable peripheral interrupts
    bsf INTCON, GIE          ; Enable global interrupts

    goto MainLoop

; -----------------------
; MAIN LOOP
; - Automatic mode: send voltage every second
; - On-demand mode: send voltage only on 'd' command
; - Remote echo: send back received characters
; -----------------------

MainLoop

; ---- Check if a RX command has been received ----
    banksel rx_flag
    btfss rx_flag,0
    goto DO_MODE

    bcf rx_flag,0            ; Consume RX event
    movf rx_char,W           ; W = received character

    ; Remote echo (send received character back)
    call USART_SEND

    ; Commands:
    ; 'a' => automatic mode
    ; 'r' => on-demand mode
    ; 'd' => request measurement
    xorlw 'a'
    btfsc STATUS,Z
    goto SET_AUTO

    movf rx_char,W
    xorlw 'r'
    btfsc STATUS,Z
    goto SET_REQ

    movf rx_char,W
    xorlw 'd'
    btfsc STATUS,Z
    goto DEMANDE

    goto DO_MODE             ; Other characters are ignored

SET_AUTO
    banksel mode
    clrf mode                ; Automatic mode
    goto DO_MODE

SET_REQ
    banksel mode
    movlw 0x01
    movwf mode               ; On-demand mode
    goto DO_MODE

DEMANDE
    banksel mode
    movf mode,W
    btfss STATUS,Z           ; If mode != 0 (on-demand)
    goto SEND_VALUE
    goto DO_MODE             ; 'd' ignored in automatic mode

SEND_VALUE
    call ReadADC
    call ConvertUniteAndSend
    goto DO_MODE

; ---- Behavior depending on mode ----
DO_MODE
    banksel mode
    movf mode,W
    btfss STATUS,Z           ; Automatic mode?
    goto MainLoop            ; On-demand mode: idle

; ---- Automatic mode: once per second ----
    banksel second_passe
    btfss second_passe,0
    goto MainLoop
    bcf second_passe,0

    call ReadADC
    call ConvertUniteAndSend
    goto MainLoop

; -----------------------
; ADC READ ROUTINE (ADRESH only)
; -----------------------
ReadADC
    banksel ADCON0
    bsf ADCON0, GO           ; Start ADC conversion
WaitADC
    btfsc ADCON0, GO
    goto WaitADC             ; Wait until conversion complete

    movf ADRESH, W
    banksel ADC_result
    movwf ADC_result
    return

; -----------------------
; ADC TO ASCII CONVERSION + USART SEND
; Format: "U,D V\r\n"
; -----------------------
ConvertUniteAndSend
    banksel ADC_result
    movf ADC_result,W
    banksel reste
    movwf reste
    clrf unite

; ---- Integer volts (subtract 51 ? 1 V) ----
BoucleUnite
    movlw .51
    subwf reste,F
    btfss STATUS,C
    goto FinUnite
    incf unite,F
    goto BoucleUnite

FinUnite
    movlw .51
    addwf reste,F

; ---- Decimal part (subtract 5 ? 0.1 V) ----
    clrf diz
BoucleDec
    movlw .5
    subwf reste,F
    btfss STATUS,C
    goto FinDec
    incf diz,F
    goto BoucleDec

FinDec
    ; Correction if decimal reaches 10
    movf diz,W
    xorlw .10
    btfss STATUS,Z
    goto Affiche
    clrf diz
    incf unite,F

Affiche
    ; Integer part (ASCII)
    movf unite,W
    addlw 0x30
    call USART_SEND

    ; Decimal separator
    movlw ','
    call USART_SEND

    ; Decimal digit (ASCII)
    movf diz,W
    addlw 0x30
    call USART_SEND

    ; Space + 'V'
    movlw ' '
    call USART_SEND
    movlw 'V'
    call USART_SEND

    ; Carriage return + line feed
    movlw 0x0D
    call USART_SEND
    movlw 0x0A
    call USART_SEND
    return

; -----------------------
; USART_SEND: send W to TXREG (blocking)
; -----------------------
USART_SEND
    banksel PIR1
WaitTX
    btfss PIR1, TXIF
    goto WaitTX              ; Wait until TXREG is free
    banksel TXREG
    movwf TXREG
    return

; -----------------------
; INTERRUPT SERVICE ROUTINE
; Handles Timer1 and USART RX
; -----------------------
ISRs
    ; Save context
    movwf save_W
    movf STATUS,W
    movwf save_STATUS

    ; ---- USART RX interrupt ----
    banksel PIR1
    btfsc PIR1, RCIF
    goto ISR_RX

    ; ---- Timer1 interrupt ----
    btfsc PIR1, TMR1IF
    goto ISR_TMR1

    goto ISR_EXIT

ISR_RX
    ; Overrun error handling
    banksel RCSTA
    btfss RCSTA, OERR
    goto RX_READ
    bcf RCSTA, CREN
    bsf RCSTA, CREN

RX_READ
    banksel RCREG
    movf RCREG,W
    banksel rx_char
    movwf rx_char
    banksel rx_flag
    bsf rx_flag,0
    goto ISR_EXIT

ISR_TMR1
    ; Reload Timer1 for 50 ms
    banksel TMR1H
    movlw 0xCF
    movwf TMR1H
    movlw 0x2C
    movwf TMR1L

    ; Clear Timer1 interrupt flag
    banksel PIR1
    bcf PIR1, TMR1IF

    ; 1-second software counter (20 x 50 ms)
    banksel extrus_TIMER
    decfsz extrus_TIMER,F
    goto ISR_EXIT

    movlw .20
    movwf extrus_TIMER
    banksel second_passe
    bsf second_passe,0
    goto ISR_EXIT

ISR_EXIT
    ; Restore context
    movf save_STATUS,W
    movwf STATUS
    movf save_W,W
    retfie

    END
