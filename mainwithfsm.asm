$NOLIST
$MOD9351
$LIST
;-------------------;
;    Const Define   ;
;-------------------; 
XTAL EQU 7373000
BAUD EQU 115200
BRVAL EQU ((XTAL/BAUD)-16)

CCU_RATE      EQU 100      ; 100Hz, for an overflow rate of 10ms
CCU_RELOAD    EQU ((65536-(XTAL/(2*CCU_RATE))))

TIMER0_RATE   EQU 4096
TIMER0_RELOAD EQU ((65536-(XTAL/(2*TIMER0_RATE))))

;-------------------;
;    Ports Define   ;
;-------------------; 
BUTTON equ P0.1

;------------------------;
;    Interrupt Vectors   ;
;------------------------; 
; Reset vector
org 0x0000
    ljmp MainProgram
    ; External interrupt 0 vector
org 0x0003
	reti
    ; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR
    ; External interrupt 1 vector
org 0x0013
	reti
    ; Timer/Counter 1 overflow interrupt vector
org 0x001B
	reti
    ; Serial port receive/transmit interrupt vector
org 0x0023 
	reti
    ; CCU interrupt vector
org 0x005b 
	ljmp CCU_ISR

;-----------------------;
;    Variables Define   ;
;-----------------------; 
;Variable_name: ds n
dseg at 0x30

    FSM0_State: ds 1
    FSM1_State: ds 1

    Profile_Num: ds 1

    TEMP_SOAK:  ds 4
    TIME_SOAK:  ds 4
    TEMP_RFLW:  ds 4
    TIME_RFLW:  ds 4
    TEMP_SAFE:  ds 4
    Current_Room_Temp: ds 4
	Current_Oven_Temp: ds 4
    
    Cursor:     ds 1
    NEW_BCD:    ds 3    ; 3 digit BCD used to store current entered number
    NEW_HEX:    ds 4    ; 32 bit number of new entered number
    
;-------------------;
;    Flags Define   ;
;-------------------; 
;Flag_name: dbit 1
bseg
    FSM0_State_Changed:  dbit 1
    Main_State:          dbit 1; 0 for setting, 1 for reflowing

    PB0: dbit 1 ; Variable to store the state of pushbutton 0 after calling ADC_to_PB below
    PB1: dbit 1 ; Variable to store the state of pushbutton 1 after calling ADC_to_PB below
    PB2: dbit 1 ; Variable to store the state of pushbutton 2 after calling ADC_to_PB below
    PB3: dbit 1 ; Variable to store the state of pushbutton 3 after calling ADC_to_PB below
    PB4: dbit 1 ; Variable to store the state of pushbutton 4 after calling ADC_to_PB below
    PB5: dbit 1 ; Variable to store the state of pushbutton 5 after calling ADC_to_PB below
    PB6: dbit 1 ; Variable to store the state of pushbutton 6 after calling ADC_to_PB below

    PB13: dbit 1 ; Variable to store the state of pushbutton 0 after calling ADC_to_PB below
    PB12: dbit 1 ; Variable to store the state of pushbutton 1 after calling ADC_to_PB below
    PB11: dbit 1 ; Variable to store the state of pushbutton 2 after calling ADC_to_PB below
    PB10: dbit 1 ; Variable to store the state of pushbutton 3 after calling ADC_to_PB below
    PB9: dbit 1 ; Variable to store the state of pushbutton 4 after calling ADC_to_PB below
    PB8: dbit 1 ; Variable to store the state of pushbutton 5 after calling ADC_to_PB below 
    PB7: dbit 1 ; Variable to store the state of pushbutton 6 after calling ADC_to_PB below
;-----------------------;
;     Include Files     ;
;-----------------------; 
$NOLIST
    ;$include(lcd_4bit.inc) 
    $include(math32.inc)
    ;$include(DAC.inc)
    $include(LPC9351.inc)
    $include(serial.inc)
    ;$include(SPI.inc)
    ;$include(keys.inc)
    ;$include(temperature.inc)
$LIST


;-----------------------;
;    Program Segment    ;
;-----------------------; 
cseg at 0x0000

HexAscii: db '0123456789ABCDEF'

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    clr TR0   ; not start timer 0, wait until used
	ret
;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;
Timer0_ISR:
    mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
    ;codes here
    reti

;---------------------------------;
; Routine to initialize the CCU   ;
; We are using the CCU timer in a ;
; manner similar to timer 2       ;
;---------------------------------;
CCU_Init:
	mov TH2, #high(CCU_RELOAD)
	mov TL2, #low(CCU_RELOAD)
	mov TOR2H, #high(CCU_RELOAD)
	mov TOR2L, #low(CCU_RELOAD)
	mov TCR21, #10000000b ; Latch the reload value
	mov TICR2, #10000000b ; Enable CCU Timer Overflow Interrupt
	setb ECCU ; Enable CCU interrupt
	clr TMOD20 ; not start CCU timer yet, wait until used
	ret

;---------------------------------;
; ISR for CCU                     ;
;---------------------------------;
CCU_ISR:
	mov TIFR2, #0 ; Clear CCU Timer Overflow Interrupt Flag bit.
    ;codes here
	reti



;-------------------;
;       Macros      ;
;-------------------; 


MainProgram:
    Ports_Initialize()
    LCD_Initailize()
    Clock_Double()
    SPI_Initialize()

    mov FSM0_State, #0
    mov FSM1_State, #0
    mov Profile_Num, #0
    LCD_INTERFACE_WELCOME()
    lcall WaitHalfSec

;start fsm
MainLoop:
    jnb Main_State, FSM0    ;if 0, go to FSM0 to setting interface
    ;ljmp FSM1               ;if 1, go to FSM1 to reflow process

FSM0:
    ;-------------------;
    ;    Setting FSM    ;
    ;-------------------;

    ;Checking Keyboard
    ;Key_Scan()
    FSM0_Start:
        mov a, FSM0_State
        FSM0_State0:
            cjne a, #0, FSM0_State1
            mov FSM0_State, #0x01
        bitleft_state0:
            ;scan number button
            jnb PB0,bridge0_state0_bitleft
            jnb PB1,bridge1_state0_bitleft
            jnb PB2,bridge2_state0_bitleft
            jnb PB3,bridge3_state0_bitleft
            jnb PB4,bridge4_state0_bitleft
            jnb PB5,bridge5_state0_bitleft
            jnb PB6,bridge6_state0_bitleft
            jnb PB7,bridge7_state0_bitleft
            jnb PB8,bridge8_state0_bitleft
            jnb PB9,bridge9_state0_bitleft
            ;scan state button
            jnb PB10,bridge10_state0_bitleft
            jnb PB11,bridge11_state0_bitleft
            jnb PB12,bridge12_state0_bitleft
            jnb PB13,bridge13_state0_bitleft
            ljmp bitleft_state0
        bridge0_state0_bitleft: ljmp BCD0_state0_bitleft
        bridge1_state0_bitleft: ljmp BCD1_state0_bitleft
        bridge2_state0_bitleft: ljmp BCD2_state0_bitleft
        bridge3_state0_bitleft: ljmp BCD3_state0_bitleft
        bridge4_state0_bitleft: ljmp BCD4_state0_bitleft
        bridge5_state0_bitleft: ljmp BCD5_state0_bitleft
        bridge6_state0_bitleft: ljmp BCD6_state0_bitleft
        bridge7_state0_bitleft: ljmp BCD7_state0_bitleft
        bridge8_state0_bitleft: ljmp BCD8_state0_bitleft
        bridge9_state0_bitleft: ljmp BCD9_state0_bitleft
        bridge10_state0_bitleft: ljmp enter_button_state0_bitleft
        bridge11_state0_bitleft: ljmp upward_button_state0_bitleft
        bridge12_state0_bitleft: ljmp downward_button_state0_bitleft
        bridge13_state0_bitleft: ljmp clear_button_state0_bitleft

        BCD0_state0_bitleft:
	        mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
	         
            jb PB0, $
            ljmp bitmiddle_state0
        BCD1_state0_bitleft:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB1, $
            ljmp bitmiddle_state0
        BCD2_state0_bitleft:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
            
            jb PB2, $
            ljmp bitmiddle_state0
        BCD3_state0_bitleft:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB3, $
            ljmp bitmiddle_state0
        BCD4_state0_bitleft:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB4, $
            ljmp bitmiddle_state0
        BCD5_state0_bitleft:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB5, $
            ljmp bitmiddle_state0
        BCD6_state0_bitleft:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
        
            jb PB6, $ 
            ljmp bitmiddle_state0
        BCD7_state0_bitleft:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB7, $
            ljmp bitmiddle_state0   
        
        
        
        BCD8_state0_bitleft:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB8, $
            ljmp bitmiddle_state0
        BCD9_state0_bitleft:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB9, $
            ljmp bitmiddle_state0




        bitmiddle_state0:
            ;scan number button
            jnb PB0,bridge0_state0_bitmiddle
            jnb PB1,bridge1_state0_bitmiddle
            jnb PB2,bridge2_state0_bitmiddle
            jnb PB3,bridge3_state0_bitmiddle
            jnb PB4,bridge4_state0_bitmiddle
            jnb PB5,bridge5_state0_bitmiddle
            jnb PB6,bridge6_state0_bitmiddle
            jnb PB7,bridge7_state0_bitmiddle
            jnb PB8,bridge8_state0_bitmiddle
            jnb PB9,bridge9_state0_bitmiddle
            ;scan state button
            jnb PB10,bridge10_state0_bitmiddle
            jnb PB11,bridge11_state0_bitmiddle
            jnb PB12,bridge12_state0_bitmiddle
            jnb PB13,bridge13_state0_bitmiddle
            ljmp bitleft_state0
        bridge0_state0_bitmiddle: ljmp BCD0_state0_bitmiddle
        bridge1_state0_bitmiddle: ljmp BCD1_state0_bitmiddle
        bridge2_state0_bitmiddle: ljmp BCD2_state0_bitmiddle
        bridge3_state0_bitmiddle: ljmp BCD3_state0_bitmiddle
        bridge4_state0_bitmiddle: ljmp BCD4_state0_bitmiddle
        bridge5_state0_bitmiddle: ljmp BCD5_state0_bitmiddle
        bridge6_state0_bitmiddle: ljmp BCD6_state0_bitmiddle
        bridge7_state0_bitmiddle: ljmp BCD7_state0_bitmiddle
        bridge8_state0_bitmiddle: ljmp BCD8_state0_bitmiddle
        bridge9_state0_bitmiddle: ljmp BCD9_state0_bitmiddle
        bridge10_state0_bitmiddle: ljmp enter_button_state0_bitmiddle
        bridge11_state0_bitmiddle: ljmp upward_button_state0_bitmiddle
        bridge12_state0_bitmiddle: ljmp downward_button_state0_bitmiddle
        bridge13_state0_bitmiddle: ljmp clear_button_state0_bitmiddle

        BCD0_state0_bitmiddle:
            mov a, #0x0
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitright_state0
        BCD1_state0_bitmiddle:
            mov a, #0x1
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB1, $
            ljmp bitright_state0
        BCD2_state0_bitmiddle:
            mov a, #0x2
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitright_state0
        BCD3_state0_bitmiddle:
            mov a, #0x3
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitright_state0
        BCD4_state0_bitmiddle:
            mov a, #0x4
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitright_state0
        BCD5_state0_bitmiddle:
            mov a, #0x5
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB5, $
            ljmp bitright_state0
        BCD6_state0_bitmiddle:
            mov a, #0x6
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitright_state0
        BCD7_state0_bitmiddle:
            mov a, #0x7
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitright_state0
        BCD8_state0_bitmiddle:
            mov a, #0x8
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB8, $
            ljmp bitright_state0
        BCD9_state0_bitmiddle:
            mov a, #0x9
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitright_state0
        ;enter??

        bitright_state0:
            ;scan number button
            jnb PB0,bridge0_state0_bitright
            jnb PB1,bridge1_state0_bitright
            jnb PB2,bridge2_state0_bitright
            jnb PB3,bridge3_state0_bitright
            jnb PB4,bridge4_state0_bitright
            jnb PB5,bridge5_state0_bitright
            jnb PB6,bridge6_state0_bitright
            jnb PB7,bridge7_state0_bitright
            jnb PB8,bridge8_state0_bitright
            jnb PB9,bridge9_state0_bitright
            ;scan state button
            jnb PB10,bridge10_state0_bitright
            jnb PB11,bridge11_state0_bitright
            jnb PB12,bridge12_state0_bitright
            jnb PB13,bridge13_state0_bitright
            ljmp bitleft_state0
        bridge0_state0_bitright: ljmp BCD0_state0_bitright
        bridge1_state0_bitright: ljmp BCD1_state0_bitright
        bridge2_state0_bitright: ljmp BCD2_state0_bitright
        bridge3_state0_bitright: ljmp BCD3_state0_bitright
        bridge4_state0_bitright: ljmp BCD4_state0_bitright
        bridge5_state0_bitright: ljmp BCD5_state0_bitright
        bridge6_state0_bitright: ljmp BCD6_state0_bitright
        bridge7_state0_bitright: ljmp BCD7_state0_bitright
        bridge8_state0_bitright: ljmp BCD8_state0_bitright
        bridge9_state0_bitright: ljmp BCD9_state0_bitright
        bridge10_state0_bitright: ljmp enter_button_state0_bitright
        bridge11_state0_bitright: ljmp upward_button_state0_bitright
        bridge12_state0_bitright: ljmp downward_button_state0_bitright
        bridge13_state0_bitright: ljmp clear_button_state0_bitright

        BCD0_state0_bitright:
            mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitleft_state0
        BCD1_state0_bitright:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB1, $
            ljmp bitleft_state0
        BCD2_state0_bitright:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitleft_state0
        BCD3_state0_bitright:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitleft_state0
        BCD4_state0_bitright:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitleft_state0
        BCD5_state0_bitright:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB5, $
            ljmp bitleft_state0
        BCD6_state0_bitright:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitleft_state0
        BCD7_state0_bitright:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitleft_state0
        BCD8_state0_bitright:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
        
            jb PB8, $
            ljmp bitleft_state0
        BCD9_state0_bitright:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitleft_state0
        
        enter_button_state0_bitright:
            mov a, New_BCD
            mov New_HEX,a
            mov a, New_BCD+1
            mov New_BCD,a

            jb PB10, $
            ljmp FSM0_State0_Done

        upward_button_state0_bitright:
            jb PB11, $
            ljmp FSM0_State1

        downward_button_state0_bitright:
            jb PB12, $
            ljmp FSM0_State4

        clear_button_state0_bitright:
            mov a,#0x0
            mov New_BCD+1,a
            mov a,#0x0
            mov New_BCD,a

            jb PB13, $
            ljmp bitleft_state0

        FSM0_State0_Done:
            ljmp MainLoop

        FSM0_state1:
            cjne a, #0, FSM0_State1
            mov FSM0_State, #0x02
        bitleft_state1:
            ;scan number button
            jnb PB0,bridge0_state1_bitleft
            jnb PB1,bridge1_state1_bitleft
            jnb PB2,bridge2_state1_bitleft
            jnb PB3,bridge3_state1_bitleft
            jnb PB4,bridge4_state1_bitleft
            jnb PB5,bridge5_state1_bitleft
            jnb PB6,bridge6_state1_bitleft
            jnb PB7,bridge7_state1_bitleft
            jnb PB8,bridge8_state1_bitleft
            jnb PB9,bridge9_state1_bitleft
            ;scan state button
            jnb PB10,bridge10_state1_bitleft
            jnb PB11,bridge11_state1_bitleft
            jnb PB12,bridge12_state1_bitleft
            jnb PB13,bridge13_state1_bitleft
            ljmp bitleft_state1
        bridge0_state1_bitleft: ljmp BCD0_state1_bitleft
        bridge1_state1_bitleft: ljmp BCD1_state1_bitleft
        bridge2_state1_bitleft: ljmp BCD2_state1_bitleft
        bridge3_state1_bitleft: ljmp BCD3_state1_bitleft
        bridge4_state1_bitleft: ljmp BCD4_state1_bitleft
        bridge5_state1_bitleft: ljmp BCD5_state1_bitleft
        bridge6_state1_bitleft: ljmp BCD6_state1_bitleft
        bridge7_state1_bitleft: ljmp BCD7_state1_bitleft
        bridge8_state1_bitleft: ljmp BCD8_state1_bitleft
        bridge9_state1_bitleft: ljmp BCD9_state1_bitleft
        bridge10_state1_bitleft: ljmp enter_button_state1_bitleft
        bridge11_state1_bitleft: ljmp upward_button_state1_bitleft
        bridge12_state1_bitleft: ljmp downward_button_state1_bitleft
        bridge13_state1_bitleft: ljmp clear_button_state1_bitleft

        BCD0_state1_bitleft:
	        mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
	         
            jb PB0, $
            ljmp bitmiddle_state1
        BCD1_state1_bitleft:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB1, $
            ljmp bitmiddle_state1
        BCD2_state1_bitleft:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
            
            jb PB2, $
            ljmp bitmiddle_state1
        BCD3_state1_bitleft:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB3, $
            ljmp bitmiddle_state1
        BCD4_state1_bitleft:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB4, $
            ljmp bitmiddle_state1
        BCD5_state1_bitleft:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB5, $
            ljmp bitmiddle_state1
        BCD6_state1_bitleft:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
        
            jb PB6, $ 
            ljmp bitmiddle_state1
        BCD7_state1_bitleft:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB7, $
            ljmp bitmiddle_state1   
        
        
        
        BCD8_state1_bitleft:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB8, $
            ljmp bitmiddle_state1
        BCD9_state1_bitleft:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB9, $
            ljmp bitmiddle_state1




        bitmiddle_state1:
            ;scan number button
            jnb PB0,bridge0_state1_bitmiddle
            jnb PB1,bridge1_state1_bitmiddle
            jnb PB2,bridge2_state1_bitmiddle
            jnb PB3,bridge3_state1_bitmiddle
            jnb PB4,bridge4_state1_bitmiddle
            jnb PB5,bridge5_state1_bitmiddle
            jnb PB6,bridge6_state1_bitmiddle
            jnb PB7,bridge7_state1_bitmiddle
            jnb PB8,bridge8_state1_bitmiddle
            jnb PB9,bridge9_state1_bitmiddle
            ;scan state button
            jnb PB10,bridge10_state1_bitmiddle
            jnb PB11,bridge11_state1_bitmiddle
            jnb PB12,bridge12_state1_bitmiddle
            jnb PB13,bridge13_state1_bitmiddle
            ljmp bitleft_state1
        bridge0_state1_bitmiddle: ljmp BCD0_state1_bitmiddle
        bridge1_state1_bitmiddle: ljmp BCD1_state1_bitmiddle
        bridge2_state1_bitmiddle: ljmp BCD2_state1_bitmiddle
        bridge3_state1_bitmiddle: ljmp BCD3_state1_bitmiddle
        bridge4_state1_bitmiddle: ljmp BCD4_state1_bitmiddle
        bridge5_state1_bitmiddle: ljmp BCD5_state1_bitmiddle
        bridge6_state1_bitmiddle: ljmp BCD6_state1_bitmiddle
        bridge7_state1_bitmiddle: ljmp BCD7_state1_bitmiddle
        bridge8_state1_bitmiddle: ljmp BCD8_state1_bitmiddle
        bridge9_state1_bitmiddle: ljmp BCD9_state1_bitmiddle
        bridge10_state1_bitmiddle: ljmp enter_button_state1_bitmiddle
        bridge11_state1_bitmiddle: ljmp upward_button_state1_bitmiddle
        bridge12_state1_bitmiddle: ljmp downward_button_state1_bitmiddle
        bridge13_state1_bitmiddle: ljmp clear_button_state1_bitmiddle

        BCD0_state1_bitmiddle:
            mov a, #0x0
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitright_state1
        BCD1_state1_bitmiddle:
            mov a, #0x1
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB1, $
            ljmp bitright_state1
        BCD2_state1_bitmiddle:
            mov a, #0x2
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitright_state1
        BCD3_state1_bitmiddle:
            mov a, #0x3
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitright_state1
        BCD4_state1_bitmiddle:
            mov a, #0x4
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitright_state1
        BCD5_state1_bitmiddle:
            mov a, #0x5
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB5, $
            ljmp bitright_state1
        BCD6_state1_bitmiddle:
            mov a, #0x6
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitright_state1
        BCD7_state1_bitmiddle:
            mov a, #0x7
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitright_state1
        BCD8_state1_bitmiddle:
            mov a, #0x8
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB8, $
            ljmp bitright_state1
        BCD9_state1_bitmiddle:
            mov a, #0x9
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitright_state1
        ;enter??

        bitright_state1:
            ;scan number button
            jnb PB0,bridge0_state1_bitright
            jnb PB1,bridge1_state1_bitright
            jnb PB2,bridge2_state1_bitright
            jnb PB3,bridge3_state1_bitright
            jnb PB4,bridge4_state1_bitright
            jnb PB5,bridge5_state1_bitright
            jnb PB6,bridge6_state1_bitright
            jnb PB7,bridge7_state1_bitright
            jnb PB8,bridge8_state1_bitright
            jnb PB9,bridge9_state1_bitright
            ;scan state button
            jnb PB10,bridge10_state1_bitright
            jnb PB11,bridge11_state1_bitright
            jnb PB12,bridge12_state1_bitright
            jnb PB13,bridge13_state1_bitright
            ljmp bitleft_state1
        bridge0_state1_bitright: ljmp BCD0_state1_bitright
        bridge1_state1_bitright: ljmp BCD1_state1_bitright
        bridge2_state1_bitright: ljmp BCD2_state1_bitright
        bridge3_state1_bitright: ljmp BCD3_state1_bitright
        bridge4_state1_bitright: ljmp BCD4_state1_bitright
        bridge5_state1_bitright: ljmp BCD5_state1_bitright
        bridge6_state1_bitright: ljmp BCD6_state1_bitright
        bridge7_state1_bitright: ljmp BCD7_state1_bitright
        bridge8_state1_bitright: ljmp BCD8_state1_bitright
        bridge9_state1_bitright: ljmp BCD9_state1_bitright
        bridge10_state1_bitright: ljmp enter_button_state1_bitright
        bridge11_state1_bitright: ljmp upward_button_state1_bitright
        bridge12_state1_bitright: ljmp downward_button_state1_bitright
        bridge13_state1_bitright: ljmp clear_button_state1_bitright

        BCD0_state1_bitright:
            mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitleft_state1
        BCD1_state1_bitright:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB1, $
            ljmp bitleft_state1
        BCD2_state1_bitright:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitleft_state1
        BCD3_state1_bitright:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitleft_state1
        BCD4_state1_bitright:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitleft_state1
        BCD5_state1_bitright:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB5, $
            ljmp bitleft_state1
        BCD6_state1_bitright:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitleft_state1
        BCD7_state1_bitright:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitleft_state1
        BCD8_state1_bitright:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
        
            jb PB8, $
            ljmp bitleft_state1
        BCD9_state1_bitright:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitleft_state1
        
        enter_button_state1_bitright:
            mov a, New_BCD
            mov New_HEX,a
            mov a, New_BCD+1
            mov New_BCD,a

            jb PB10, $
            ljmp FSM0_state1_Done

        upward_button_state1_bitright:
            jb PB11, $
            ljmp FSM0_State2

        downward_button_state1_bitright:
            jb PB12, $
            ljmp FSM0_State0

        clear_button_state1_bitright:
            mov a,#0x0
            mov New_BCD+1,a
            mov a,#0x0
            mov New_BCD,a

            jb PB13, $
            ljmp bitleft_state1

        FSM0_state1_Done:
            ljmp MainLoop

        FSM0_State2:
            cjne a, #0, FSM0_State2
            mov FSM0_State, #0x03
        bitleft_State2:
            ;scan number button
            jnb PB0,bridge0_State2_bitleft
            jnb PB1,bridge1_State2_bitleft
            jnb PB2,bridge2_State2_bitleft
            jnb PB3,bridge3_State2_bitleft
            jnb PB4,bridge4_State2_bitleft
            jnb PB5,bridge5_State2_bitleft
            jnb PB6,bridge6_State2_bitleft
            jnb PB7,bridge7_State2_bitleft
            jnb PB8,bridge8_State2_bitleft
            jnb PB9,bridge9_State2_bitleft
            ;scan state button
            jnb PB10,bridge10_State2_bitleft
            jnb PB11,bridge11_State2_bitleft
            jnb PB12,bridge12_State2_bitleft
            jnb PB13,bridge13_State2_bitleft
            ljmp bitleft_State2
        bridge0_State2_bitleft: ljmp BCD0_State2_bitleft
        bridge1_State2_bitleft: ljmp BCD1_State2_bitleft
        bridge2_State2_bitleft: ljmp BCD2_State2_bitleft
        bridge3_State2_bitleft: ljmp BCD3_State2_bitleft
        bridge4_State2_bitleft: ljmp BCD4_State2_bitleft
        bridge5_State2_bitleft: ljmp BCD5_State2_bitleft
        bridge6_State2_bitleft: ljmp BCD6_State2_bitleft
        bridge7_State2_bitleft: ljmp BCD7_State2_bitleft
        bridge8_State2_bitleft: ljmp BCD8_State2_bitleft
        bridge9_State2_bitleft: ljmp BCD9_State2_bitleft
        bridge10_State2_bitleft: ljmp enter_button_State2_bitleft
        bridge11_State2_bitleft: ljmp upward_button_State2_bitleft
        bridge12_State2_bitleft: ljmp downward_button_State2_bitleft
        bridge13_State2_bitleft: ljmp clear_button_State2_bitleft

        BCD0_State2_bitleft:
	        mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
	         
            jb PB0, $
            ljmp bitmiddle_State2
        BCD1_State2_bitleft:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB1, $
            ljmp bitmiddle_State2
        BCD2_State2_bitleft:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
            
            jb PB2, $
            ljmp bitmiddle_State2
        BCD3_State2_bitleft:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB3, $
            ljmp bitmiddle_State2
        BCD4_State2_bitleft:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB4, $
            ljmp bitmiddle_State2
        BCD5_State2_bitleft:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB5, $
            ljmp bitmiddle_State2
        BCD6_State2_bitleft:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
        
            jb PB6, $ 
            ljmp bitmiddle_State2
        BCD7_State2_bitleft:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB7, $
            ljmp bitmiddle_State2   
        
        
        
        BCD8_State2_bitleft:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB8, $
            ljmp bitmiddle_State2
        BCD9_State2_bitleft:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB9, $
            ljmp bitmiddle_State2




        bitmiddle_State2:
            ;scan number button
            jnb PB0,bridge0_State2_bitmiddle
            jnb PB1,bridge1_State2_bitmiddle
            jnb PB2,bridge2_State2_bitmiddle
            jnb PB3,bridge3_State2_bitmiddle
            jnb PB4,bridge4_State2_bitmiddle
            jnb PB5,bridge5_State2_bitmiddle
            jnb PB6,bridge6_State2_bitmiddle
            jnb PB7,bridge7_State2_bitmiddle
            jnb PB8,bridge8_State2_bitmiddle
            jnb PB9,bridge9_State2_bitmiddle
            ;scan state button
            jnb PB10,bridge10_State2_bitmiddle
            jnb PB11,bridge11_State2_bitmiddle
            jnb PB12,bridge12_State2_bitmiddle
            jnb PB13,bridge13_State2_bitmiddle
            ljmp bitleft_State2
        bridge0_State2_bitmiddle: ljmp BCD0_State2_bitmiddle
        bridge1_State2_bitmiddle: ljmp BCD1_State2_bitmiddle
        bridge2_State2_bitmiddle: ljmp BCD2_State2_bitmiddle
        bridge3_State2_bitmiddle: ljmp BCD3_State2_bitmiddle
        bridge4_State2_bitmiddle: ljmp BCD4_State2_bitmiddle
        bridge5_State2_bitmiddle: ljmp BCD5_State2_bitmiddle
        bridge6_State2_bitmiddle: ljmp BCD6_State2_bitmiddle
        bridge7_State2_bitmiddle: ljmp BCD7_State2_bitmiddle
        bridge8_State2_bitmiddle: ljmp BCD8_State2_bitmiddle
        bridge9_State2_bitmiddle: ljmp BCD9_State2_bitmiddle
        bridge10_State2_bitmiddle: ljmp enter_button_State2_bitmiddle
        bridge11_State2_bitmiddle: ljmp upward_button_State2_bitmiddle
        bridge12_State2_bitmiddle: ljmp downward_button_State2_bitmiddle
        bridge13_State2_bitmiddle: ljmp clear_button_State2_bitmiddle

        BCD0_State2_bitmiddle:
            mov a, #0x0
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitright_State2
        BCD1_State2_bitmiddle:
            mov a, #0x1
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB1, $
            ljmp bitright_State2
        BCD2_State2_bitmiddle:
            mov a, #0x2
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitright_State2
        BCD3_State2_bitmiddle:
            mov a, #0x3
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitright_State2
        BCD4_State2_bitmiddle:
            mov a, #0x4
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitright_State2
        BCD5_State2_bitmiddle:
            mov a, #0x5
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB5, $
            ljmp bitright_State2
        BCD6_State2_bitmiddle:
            mov a, #0x6
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitright_State2
        BCD7_State2_bitmiddle:
            mov a, #0x7
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitright_State2
        BCD8_State2_bitmiddle:
            mov a, #0x8
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB8, $
            ljmp bitright_State2
        BCD9_State2_bitmiddle:
            mov a, #0x9
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitright_State2
        ;enter??

        bitright_State2:
            ;scan number button
            jnb PB0,bridge0_State2_bitright
            jnb PB1,bridge1_State2_bitright
            jnb PB2,bridge2_State2_bitright
            jnb PB3,bridge3_State2_bitright
            jnb PB4,bridge4_State2_bitright
            jnb PB5,bridge5_State2_bitright
            jnb PB6,bridge6_State2_bitright
            jnb PB7,bridge7_State2_bitright
            jnb PB8,bridge8_State2_bitright
            jnb PB9,bridge9_State2_bitright
            ;scan state button
            jnb PB10,bridge10_State2_bitright
            jnb PB11,bridge11_State2_bitright
            jnb PB12,bridge12_State2_bitright
            jnb PB13,bridge13_State2_bitright
            ljmp bitleft_State2
        bridge0_State2_bitright: ljmp BCD0_State2_bitright
        bridge1_State2_bitright: ljmp BCD1_State2_bitright
        bridge2_State2_bitright: ljmp BCD2_State2_bitright
        bridge3_State2_bitright: ljmp BCD3_State2_bitright
        bridge4_State2_bitright: ljmp BCD4_State2_bitright
        bridge5_State2_bitright: ljmp BCD5_State2_bitright
        bridge6_State2_bitright: ljmp BCD6_State2_bitright
        bridge7_State2_bitright: ljmp BCD7_State2_bitright
        bridge8_State2_bitright: ljmp BCD8_State2_bitright
        bridge9_State2_bitright: ljmp BCD9_State2_bitright
        bridge10_State2_bitright: ljmp enter_button_State2_bitright
        bridge11_State2_bitright: ljmp upward_button_State2_bitright
        bridge12_State2_bitright: ljmp downward_button_State2_bitright
        bridge13_State2_bitright: ljmp clear_button_State2_bitright

        BCD0_State2_bitright:
            mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitleft_State2
        BCD1_State2_bitright:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB1, $
            ljmp bitleft_State2
        BCD2_State2_bitright:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitleft_State2
        BCD3_State2_bitright:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitleft_State2
        BCD4_State2_bitright:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitleft_State2
        BCD5_State2_bitright:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB5, $
            ljmp bitleft_State2
        BCD6_State2_bitright:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitleft_State2
        BCD7_State2_bitright:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitleft_State2
        BCD8_State2_bitright:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
        
            jb PB8, $
            ljmp bitleft_State2
        BCD9_State2_bitright:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitleft_State2
        
        enter_button_State2_bitright:
            mov a, New_BCD
            mov New_HEX,a
            mov a, New_BCD+1
            mov New_BCD,a

            jb PB10, $
            ljmp FSM0_State2_Done

        upward_button_State2_bitright:
            jb PB11, $
            ljmp FSM0_State3

        downward_button_State2_bitright:
            jb PB12, $
            ljmp FSM0_State1

        clear_button_State2_bitright:
            mov a,#0x0
            mov New_BCD+1,a
            mov a,#0x0
            mov New_BCD,a

            jb PB13, $
            ljmp bitleft_State2

        FSM0_State2_Done:
            ljmp MainLoop
FSM0_State3:
            cjne a, #0, FSM0_State3
            mov FSM0_State, #0x04
        bitleft_State3:
            ;scan number button
            jnb PB0,bridge0_State3_bitleft
            jnb PB1,bridge1_State3_bitleft
            jnb PB2,bridge2_State3_bitleft
            jnb PB3,bridge3_State3_bitleft
            jnb PB4,bridge4_State3_bitleft
            jnb PB5,bridge5_State3_bitleft
            jnb PB6,bridge6_State3_bitleft
            jnb PB7,bridge7_State3_bitleft
            jnb PB8,bridge8_State3_bitleft
            jnb PB9,bridge9_State3_bitleft
            ;scan state button
            jnb PB10,bridge10_State3_bitleft
            jnb PB11,bridge11_State3_bitleft
            jnb PB12,bridge12_State3_bitleft
            jnb PB13,bridge13_State3_bitleft
            ljmp bitleft_State3
        bridge0_State3_bitleft: ljmp BCD0_State3_bitleft
        bridge1_State3_bitleft: ljmp BCD1_State3_bitleft
        bridge2_State3_bitleft: ljmp BCD2_State3_bitleft
        bridge3_State3_bitleft: ljmp BCD3_State3_bitleft
        bridge4_State3_bitleft: ljmp BCD4_State3_bitleft
        bridge5_State3_bitleft: ljmp BCD5_State3_bitleft
        bridge6_State3_bitleft: ljmp BCD6_State3_bitleft
        bridge7_State3_bitleft: ljmp BCD7_State3_bitleft
        bridge8_State3_bitleft: ljmp BCD8_State3_bitleft
        bridge9_State3_bitleft: ljmp BCD9_State3_bitleft
        bridge10_State3_bitleft: ljmp enter_button_State3_bitleft
        bridge11_State3_bitleft: ljmp upward_button_State3_bitleft
        bridge12_State3_bitleft: ljmp downward_button_State3_bitleft
        bridge13_State3_bitleft: ljmp clear_button_State3_bitleft

        BCD0_State3_bitleft:
	        mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
	         
            jb PB0, $
            ljmp bitmiddle_State3
        BCD1_State3_bitleft:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB1, $
            ljmp bitmiddle_State3
        BCD2_State3_bitleft:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
            
            jb PB2, $
            ljmp bitmiddle_State3
        BCD3_State3_bitleft:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB3, $
            ljmp bitmiddle_State3
        BCD4_State3_bitleft:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB4, $
            ljmp bitmiddle_State3
        BCD5_State3_bitleft:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB5, $
            ljmp bitmiddle_State3
        BCD6_State3_bitleft:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
        
            jb PB6, $ 
            ljmp bitmiddle_State3
        BCD7_State3_bitleft:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB7, $
            ljmp bitmiddle_State3   
        
        
        
        BCD8_State3_bitleft:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB8, $
            ljmp bitmiddle_State3
        BCD9_State3_bitleft:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB9, $
            ljmp bitmiddle_State3




        bitmiddle_State3:
            ;scan number button
            jnb PB0,bridge0_State3_bitmiddle
            jnb PB1,bridge1_State3_bitmiddle
            jnb PB2,bridge2_State3_bitmiddle
            jnb PB3,bridge3_State3_bitmiddle
            jnb PB4,bridge4_State3_bitmiddle
            jnb PB5,bridge5_State3_bitmiddle
            jnb PB6,bridge6_State3_bitmiddle
            jnb PB7,bridge7_State3_bitmiddle
            jnb PB8,bridge8_State3_bitmiddle
            jnb PB9,bridge9_State3_bitmiddle
            ;scan state button
            jnb PB10,bridge10_State3_bitmiddle
            jnb PB11,bridge11_State3_bitmiddle
            jnb PB12,bridge12_State3_bitmiddle
            jnb PB13,bridge13_State3_bitmiddle
            ljmp bitleft_State3
        bridge0_State3_bitmiddle: ljmp BCD0_State3_bitmiddle
        bridge1_State3_bitmiddle: ljmp BCD1_State3_bitmiddle
        bridge2_State3_bitmiddle: ljmp BCD2_State3_bitmiddle
        bridge3_State3_bitmiddle: ljmp BCD3_State3_bitmiddle
        bridge4_State3_bitmiddle: ljmp BCD4_State3_bitmiddle
        bridge5_State3_bitmiddle: ljmp BCD5_State3_bitmiddle
        bridge6_State3_bitmiddle: ljmp BCD6_State3_bitmiddle
        bridge7_State3_bitmiddle: ljmp BCD7_State3_bitmiddle
        bridge8_State3_bitmiddle: ljmp BCD8_State3_bitmiddle
        bridge9_State3_bitmiddle: ljmp BCD9_State3_bitmiddle
        bridge10_State3_bitmiddle: ljmp enter_button_State3_bitmiddle
        bridge11_State3_bitmiddle: ljmp upward_button_State3_bitmiddle
        bridge12_State3_bitmiddle: ljmp downward_button_State3_bitmiddle
        bridge13_State3_bitmiddle: ljmp clear_button_State3_bitmiddle

        BCD0_State3_bitmiddle:
            mov a, #0x0
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitright_State3
        BCD1_State3_bitmiddle:
            mov a, #0x1
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB1, $
            ljmp bitright_State3
        BCD2_State3_bitmiddle:
            mov a, #0x2
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitright_State3
        BCD3_State3_bitmiddle:
            mov a, #0x3
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitright_State3
        BCD4_State3_bitmiddle:
            mov a, #0x4
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitright_State3
        BCD5_State3_bitmiddle:
            mov a, #0x5
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB5, $
            ljmp bitright_State3
        BCD6_State3_bitmiddle:
            mov a, #0x6
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitright_State3
        BCD7_State3_bitmiddle:
            mov a, #0x7
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitright_State3
        BCD8_State3_bitmiddle:
            mov a, #0x8
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB8, $
            ljmp bitright_State3
        BCD9_State3_bitmiddle:
            mov a, #0x9
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitright_State3
        ;enter??

        bitright_State3:
            ;scan number button
            jnb PB0,bridge0_State3_bitright
            jnb PB1,bridge1_State3_bitright
            jnb PB2,bridge2_State3_bitright
            jnb PB3,bridge3_State3_bitright
            jnb PB4,bridge4_State3_bitright
            jnb PB5,bridge5_State3_bitright
            jnb PB6,bridge6_State3_bitright
            jnb PB7,bridge7_State3_bitright
            jnb PB8,bridge8_State3_bitright
            jnb PB9,bridge9_State3_bitright
            ;scan state button
            jnb PB10,bridge10_State3_bitright
            jnb PB11,bridge11_State3_bitright
            jnb PB12,bridge12_State3_bitright
            jnb PB13,bridge13_State3_bitright
            ljmp bitleft_State3
        bridge0_State3_bitright: ljmp BCD0_State3_bitright
        bridge1_State3_bitright: ljmp BCD1_State3_bitright
        bridge2_State3_bitright: ljmp BCD2_State3_bitright
        bridge3_State3_bitright: ljmp BCD3_State3_bitright
        bridge4_State3_bitright: ljmp BCD4_State3_bitright
        bridge5_State3_bitright: ljmp BCD5_State3_bitright
        bridge6_State3_bitright: ljmp BCD6_State3_bitright
        bridge7_State3_bitright: ljmp BCD7_State3_bitright
        bridge8_State3_bitright: ljmp BCD8_State3_bitright
        bridge9_State3_bitright: ljmp BCD9_State3_bitright
        bridge10_State3_bitright: ljmp enter_button_State3_bitright
        bridge11_State3_bitright: ljmp upward_button_State3_bitright
        bridge12_State3_bitright: ljmp downward_button_State3_bitright
        bridge13_State3_bitright: ljmp clear_button_State3_bitright

        BCD0_State3_bitright:
            mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitleft_State3
        BCD1_State3_bitright:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB1, $
            ljmp bitleft_State3
        BCD2_State3_bitright:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitleft_State3
        BCD3_State3_bitright:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitleft_State3
        BCD4_State3_bitright:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitleft_State3
        BCD5_State3_bitright:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB5, $
            ljmp bitleft_State3
        BCD6_State3_bitright:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitleft_State3
        BCD7_State3_bitright:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitleft_State3
        BCD8_State3_bitright:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
        
            jb PB8, $
            ljmp bitleft_State3
        BCD9_State3_bitright:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitleft_State3
        
        enter_button_State3_bitright:
            mov a, New_BCD
            mov New_HEX,a
            mov a, New_BCD+1
            mov New_BCD,a

            jb PB10, $
            ljmp FSM0_State3_Done

        upward_button_State3_bitright:
            jb PB11, $
            ljmp FSM0_State4

        downward_button_State3_bitright:
            jb PB12, $
            ljmp FSM0_State2

        clear_button_State3_bitright:
            mov a,#0x0
            mov New_BCD+1,a
            mov a,#0x0
            mov New_BCD,a

            jb PB13, $
            ljmp bitleft_State3

        FSM0_State3_Done:
            ljmp MainLoop


FSM0_State4:
            cjne a, #0, FSM0_State4
            mov FSM0_State, #0x00
        bitleft_State4:
            ;scan number button
            jnb PB0,bridge0_State4_bitleft
            jnb PB1,bridge1_State4_bitleft
            jnb PB2,bridge2_State4_bitleft
            jnb PB3,bridge3_State4_bitleft
            jnb PB4,bridge4_State4_bitleft
            jnb PB5,bridge5_State4_bitleft
            jnb PB6,bridge6_State4_bitleft
            jnb PB7,bridge7_State4_bitleft
            jnb PB8,bridge8_State4_bitleft
            jnb PB9,bridge9_State4_bitleft
            ;scan state button
            jnb PB10,bridge10_State4_bitleft
            jnb PB11,bridge11_State4_bitleft
            jnb PB12,bridge12_State4_bitleft
            jnb PB13,bridge13_State4_bitleft
            ljmp bitleft_State4
        bridge0_State4_bitleft: ljmp BCD0_State4_bitleft
        bridge1_State4_bitleft: ljmp BCD1_State4_bitleft
        bridge2_State4_bitleft: ljmp BCD2_State4_bitleft
        bridge3_State4_bitleft: ljmp BCD3_State4_bitleft
        bridge4_State4_bitleft: ljmp BCD4_State4_bitleft
        bridge5_State4_bitleft: ljmp BCD5_State4_bitleft
        bridge6_State4_bitleft: ljmp BCD6_State4_bitleft
        bridge7_State4_bitleft: ljmp BCD7_State4_bitleft
        bridge8_State4_bitleft: ljmp BCD8_State4_bitleft
        bridge9_State4_bitleft: ljmp BCD9_State4_bitleft
        bridge10_State4_bitleft: ljmp enter_button_State4_bitleft
        bridge11_State4_bitleft: ljmp upward_button_State4_bitleft
        bridge12_State4_bitleft: ljmp downward_button_State4_bitleft
        bridge13_State4_bitleft: ljmp clear_button_State4_bitleft

        BCD0_State4_bitleft:
	        mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
	         
            jb PB0, $
            ljmp bitmiddle_State4
        BCD1_State4_bitleft:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB1, $
            ljmp bitmiddle_State4
        BCD2_State4_bitleft:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
            
            jb PB2, $
            ljmp bitmiddle_State4
        BCD3_State4_bitleft:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB3, $
            ljmp bitmiddle_State4
        BCD4_State4_bitleft:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB4, $
            ljmp bitmiddle_State4
        BCD5_State4_bitleft:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB5, $
            ljmp bitmiddle_State4
        BCD6_State4_bitleft:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a
        
            jb PB6, $ 
            ljmp bitmiddle_State4
        BCD7_State4_bitleft:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB7, $
            ljmp bitmiddle_State4   
        
        
        
        BCD8_State4_bitleft:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB8, $
            ljmp bitmiddle_State4
        BCD9_State4_bitleft:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD+1
	        mov New_BCD+1,a

            jb PB9, $
            ljmp bitmiddle_State4




        bitmiddle_State4:
            ;scan number button
            jnb PB0,bridge0_State4_bitmiddle
            jnb PB1,bridge1_State4_bitmiddle
            jnb PB2,bridge2_State4_bitmiddle
            jnb PB3,bridge3_State4_bitmiddle
            jnb PB4,bridge4_State4_bitmiddle
            jnb PB5,bridge5_State4_bitmiddle
            jnb PB6,bridge6_State4_bitmiddle
            jnb PB7,bridge7_State4_bitmiddle
            jnb PB8,bridge8_State4_bitmiddle
            jnb PB9,bridge9_State4_bitmiddle
            ;scan state button
            jnb PB10,bridge10_State4_bitmiddle
            jnb PB11,bridge11_State4_bitmiddle
            jnb PB12,bridge12_State4_bitmiddle
            jnb PB13,bridge13_State4_bitmiddle
            ljmp bitleft_State4
        bridge0_State4_bitmiddle: ljmp BCD0_State4_bitmiddle
        bridge1_State4_bitmiddle: ljmp BCD1_State4_bitmiddle
        bridge2_State4_bitmiddle: ljmp BCD2_State4_bitmiddle
        bridge3_State4_bitmiddle: ljmp BCD3_State4_bitmiddle
        bridge4_State4_bitmiddle: ljmp BCD4_State4_bitmiddle
        bridge5_State4_bitmiddle: ljmp BCD5_State4_bitmiddle
        bridge6_State4_bitmiddle: ljmp BCD6_State4_bitmiddle
        bridge7_State4_bitmiddle: ljmp BCD7_State4_bitmiddle
        bridge8_State4_bitmiddle: ljmp BCD8_State4_bitmiddle
        bridge9_State4_bitmiddle: ljmp BCD9_State4_bitmiddle
        bridge10_State4_bitmiddle: ljmp enter_button_State4_bitmiddle
        bridge11_State4_bitmiddle: ljmp upward_button_State4_bitmiddle
        bridge12_State4_bitmiddle: ljmp downward_button_State4_bitmiddle
        bridge13_State4_bitmiddle: ljmp clear_button_State4_bitmiddle

        BCD0_State4_bitmiddle:
            mov a, #0x0
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitright_State4
        BCD1_State4_bitmiddle:
            mov a, #0x1
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB1, $
            ljmp bitright_State4
        BCD2_State4_bitmiddle:
            mov a, #0x2
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitright_State4
        BCD3_State4_bitmiddle:
            mov a, #0x3
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitright_State4
        BCD4_State4_bitmiddle:
            mov a, #0x4
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitright_State4
        BCD5_State4_bitmiddle:
            mov a, #0x5
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB5, $
            ljmp bitright_State4
        BCD6_State4_bitmiddle:
            mov a, #0x6
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitright_State4
        BCD7_State4_bitmiddle:
            mov a, #0x7
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitright_State4
        BCD8_State4_bitmiddle:
            mov a, #0x8
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB8, $
            ljmp bitright_State4
        BCD9_State4_bitmiddle:
            mov a, #0x9
            anl a, #0x0f
            swap a
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitright_State4
        ;enter??

        bitright_State4:
            ;scan number button
            jnb PB0,bridge0_State4_bitright
            jnb PB1,bridge1_State4_bitright
            jnb PB2,bridge2_State4_bitright
            jnb PB3,bridge3_State4_bitright
            jnb PB4,bridge4_State4_bitright
            jnb PB5,bridge5_State4_bitright
            jnb PB6,bridge6_State4_bitright
            jnb PB7,bridge7_State4_bitright
            jnb PB8,bridge8_State4_bitright
            jnb PB9,bridge9_State4_bitright
            ;scan state button
            jnb PB10,bridge10_State4_bitright
            jnb PB11,bridge11_State4_bitright
            jnb PB12,bridge12_State4_bitright
            jnb PB13,bridge13_State4_bitright
            ljmp bitleft_State4
        bridge0_State4_bitright: ljmp BCD0_State4_bitright
        bridge1_State4_bitright: ljmp BCD1_State4_bitright
        bridge2_State4_bitright: ljmp BCD2_State4_bitright
        bridge3_State4_bitright: ljmp BCD3_State4_bitright
        bridge4_State4_bitright: ljmp BCD4_State4_bitright
        bridge5_State4_bitright: ljmp BCD5_State4_bitright
        bridge6_State4_bitright: ljmp BCD6_State4_bitright
        bridge7_State4_bitright: ljmp BCD7_State4_bitright
        bridge8_State4_bitright: ljmp BCD8_State4_bitright
        bridge9_State4_bitright: ljmp BCD9_State4_bitright
        bridge10_State4_bitright: ljmp enter_button_State4_bitright
        bridge11_State4_bitright: ljmp upward_button_State4_bitright
        bridge12_State4_bitright: ljmp downward_button_State4_bitright
        bridge13_State4_bitright: ljmp clear_button_State4_bitright

        BCD0_State4_bitright:
            mov a, #0x0
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB0, $
            ljmp bitleft_State4
        BCD1_State4_bitright:
            mov a, #0x1
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB1, $
            ljmp bitleft_State4
        BCD2_State4_bitright:
            mov a, #0x2
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB2, $
            ljmp bitleft_State4
        BCD3_State4_bitright:
            mov a, #0x3
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB3, $
            ljmp bitleft_State4
        BCD4_State4_bitright:
            mov a, #0x4
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB4, $
            ljmp bitleft_State4
        BCD5_State4_bitright:
            mov a, #0x5
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
            
            jb PB5, $
            ljmp bitleft_State4
        BCD6_State4_bitright:
            mov a, #0x6
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB6, $
            ljmp bitleft_State4
        BCD7_State4_bitright:
            mov a, #0x7
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB7, $
            ljmp bitleft_State4
        BCD8_State4_bitright:
            mov a, #0x8
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a
        
            jb PB8, $
            ljmp bitleft_State4
        BCD9_State4_bitright:
            mov a, #0x9
            anl a, #0x0f
	        orl a, New_BCD
	        mov New_BCD,a

            jb PB9, $
            ljmp bitleft_State4
        
        enter_button_State4_bitright:
            mov a, New_BCD
            mov New_HEX,a
            mov a, New_BCD+1
            mov New_BCD,a

            jb PB10, $
            ljmp FSM0_State4_Done

        upward_button_State4_bitright:
            jb PB11, $
            ljmp FSM0_State0

        downward_button_State4_bitright:
            jb PB12, $
            ljmp FSM0_State3

        clear_button_State4_bitright:
            mov a,#0x0
            mov New_BCD+1,a
            mov a,#0x0
            mov New_BCD,a

            jb PB13, $
            ljmp bitleft_State4

        FSM0_State4_Done:
            ljmp MainLoop


            

        ;FSM0_State5:
        ;    cjne a, #5, FSM0_Done
        ;    LCD_INTERFACE_MODIFY5()


END