; *******************************************************
; Автор:            Тимофей Лукашевич                   *
; Дата:             2010.09.20                          *
; Версия:           1.0                                 *
; Имя файла:        vibrotimer.asm                      *
; Для AVR:          ATTiny13                            *
; Тактовая частота: 128 kHz                             *
; *******************************************************

; Выполняемые функции: таймер для включения вибросигнала каждые n минут 
; период подачи вибросигнала настраивается: 5, 10, 20, 30, 40, 60 минут


.include "tn13Adef.inc"   ; Используем Tiny13a

;= Definitions ===============================================
.def		temp		=	r16 ; Временный регистр для различных целей (не использовать в прерываниях!!!!)
.def		delayL		=	r18 ; младший байт времени задержки для процедуры Delay2
.def		delayH		=	r19 ; старший байт времени задержки для процедуры Delay2
;.def		reg_zero	=	r20 ; содержит константу = 0
;.def		reg_one		=	r21 ; содержит константу = 1
.def		timeL		=	r22 ; содержит число 0.5-секундных периодов, прошедших с последнего
.def		timeH		=	r23 ; срабатывания.
.def		period		=	r24	/* запрограмминованный период срабатывания:
								 		0 - 5  минут 
										1 - 10 минут
										2 - 20 минут
										3 - 30 минут
										4 - 40 минут
										5 - 60 минут	*/
.def		temp_int	=	r25 ; Временный регистр для различных целей (для использования в прерываниях!!!!)
.def		flags		=	r20 ; Бит для различных флагов

.equ		PIN_LED		=	PB2
.equ		PIN_BUTTON 	=	PB1
.equ		PIN_VIBRO	=	PB0

.equ		MC_FREQ	=	128000
.equ		DELAY_1s =	(MC_FREQ/4 - 1)
.equ		DELAY_31ms =	(DELAY_1s * 031 / 1000)
.equ		DELAY_50ms =	(DELAY_1s * 020 / 1000)
.equ		DELAY_100ms =	(DELAY_1s * 100 / 1000)
.equ		DELAY_150ms =	(DELAY_1s * 160 / 1000)
.equ		DELAY_200ms =	(DELAY_1s * 200 / 1000)

.equ		TICKS_PER_5Min = (MC_FREQ * 60 * 5)
.equ		TICKS_PER_10Min = (MC_FREQ * 60 * 10)
.equ		TICKS_PER_20Min = (MC_FREQ * 60 * 20)
.equ		TICKS_PER_30Min = (MC_FREQ * 60 * 30)
.equ		TICKS_PER_40Min = (MC_FREQ * 60 * 40)
.equ		TICKS_PER_60Min = (MC_FREQ * 60 * 60)
.equ		FLAG_VIBRO		=	0	; бит в регистре FLAGS, установка которого в 1 означает включение вибры в основном цикле
;= End definitions ===========================================

;= Start 	macro.inc ========================================
.macro    OUTI
			ldi    R16,@1
.if @0 < 0x40
			out    @0,R16
.else
			sts      @0,R16
.endif
.endm

.macro    UOUT        
.if	@0 < 0x40
			out	@0,@1         
.else
			sts	@0,@1
.endif
.endm
;= End 		macro.inc ========================================



; RAM ========================================================
			.DSEG


; FLASH ======================================================
			.CSEG
			.ORG $000        ; (RESET) 
			RJMP   Reset
			.ORG $001
			RETI             ; (INT0) External Interrupt Request 0
			.ORG $002
			RETI             ; (PCINT0) Pin Change Interrupt Request 0
			.ORG $003
			rjmp	timer_overflow     ; (TIM0_OVF) Timer/Counter Overflow
			.ORG $004
			RETI             ; (EE_RDY) EEPROM Ready
			.ORG $005
			RETI			; (ANA_COMP) Analog Comparator
			.ORG $006 
			RETI             ; (TIM0_COMPA) Timer/Counter Compare Match A
			.ORG $007
			RETI             ; (TIM0_COMPB) Timer/Counter Compare Match B
			.ORG $008
			RETI             ; (WDT) Watchdog Time-out
			.ORG	$009
			RETI             ; (ADC) ADC Conversion Complete
			.ORG   INT_VECTORS_SIZE      	; Конец таблицы прерываний
; Interrupts ==============================================
timer_overflow:
			in			temp_int,	SREG
			push		temp_int
			ldi			temp_int,	6		; записываем в счетный регистр 6 (чтобы отсчитывать 
			out			TCNT0,		temp_int ; интерывалы ровно по 0.5 секунды)
			subi		timeL,	1		; декрементируем счетчик 0.5 секундных периодов
			sbci		timeH,	0
			mov			temp_int,	timeL
			or			temp_int,	timeH
			brne		exit_timer_overflow
			ori			flags,	1<<FLAG_VIBRO
			rcall		reset_timer

exit_timer_overflow:
			pop			temp_int
			out			SREG,	temp_int
			reti

; End Interrupts ==========================================


Reset:		
	 
; Start coreinit.inc
			LDI 	R16,Low(RAMEND)	; Инициализация стека
			OUT 	SPL,R16			; Обязательно!!!
;			clr		reg_zero
;			ldi		reg_one,	1
			clr		flags
			clr		period
/* We don't need to zero memory and registers, so code is commented:
RAM_Flush:	LDI		ZL,Low(SRAM_START)	; Адрес начала ОЗУ в индекс
			LDI		ZH,High(SRAM_START)
			CLR		R16					; Очищаем R16
Flush:		ST 		Z+,R16				; Сохраняем 0 в ячейку памяти
			CPI		ZH,High(RAMEND)		; Достигли конца оперативки?
			BRNE	Flush				; Нет? Крутимся дальше!
 
			CPI		ZL,Low(RAMEND)		; А младший байт достиг конца?
			BRNE	Flush
 
			CLR		ZL					; Очищаем индекс
			CLR		ZH
			CLR		R0
			CLR		R1
			CLR		R2
			CLR		R3
			CLR		R4
			CLR		R5
			CLR		R6
			CLR		R7
			CLR		R8
			CLR		R9
			CLR		R10
			CLR		R11
			CLR		R12
			CLR		R13
			CLR		R14
			CLR		R15
			CLR		R16
			CLR		R17
			CLR		R18
			CLR		R19
			CLR		R20
			CLR		R21
			CLR		R22
			CLR		R23
			CLR		R24
			CLR		R25
			CLR		R26
			CLR		R27
			CLR		R28
			CLR		R29 */
; End coreinit.inc



; Internal Hardware Init  ======================================
			ldi		temp,	(1 << TOIE0) ; разрешить прерывание по переполнению TMR0
			out		TIMSK0,	temp
			ldi		temp,	0b00000100
			out		TCCR0B,	temp		; set prescaler to 1/256
			

			ldi		temp,	(1<<PIN_LED) | (1<<PIN_VIBRO) ; PB0 and PB2 is outputs, PB1 is input
			out		DDRB,	temp
			ldi		temp, 	0b00000010	; Enable pull-up on PB1
			out		portb,	temp
			sbi		ACSR,	ACD			; отключить аналоговый компаратор
			rcall	reset_timer
;			sei							; разрешить прерывания
; End Internal Hardware Init ===================================



; External Hardware Init  ======================================

; End Internal Hardware Init ===================================



; Run ==========================================================

; End Run ======================================================



; Main =========================================================
			rcall	hello
			sei							; разрешить прерывания
Main:
			sbrc	flags,	FLAG_VIBRO 	; если просят, повибрируем :)
			rcall	vibrate
			sbic	PINB, PIN_BUTTON
			rjmp	Main
			clr		temp
delay_drebezg1:
			ldi		delayH,	high(DELAY_31ms)	; кнопарь нажат. ждем устаканивания дребезга
			ldi		delayL,	low(DELAY_31ms)
			rcall	Delay2
			sbic	PINB, PIN_BUTTON			; кнопарь еще нажат -> не дребезг
			rjmp	Main

long_press:
			ldi		delayH,	high(DELAY_31ms)	; кнопарь нажат. ждем устаканивания дребезга
			ldi		delayL,	low(DELAY_31ms)
			rcall	Delay2
			inc		temp
			cpi		temp,	20
			brcc	indicate_current_period
			sbis	PINB, PIN_BUTTON			; кнопарь еще нажат -> не дребезг
			rjmp	long_press


			cli
			inc		period						; переключимся на следующий период (0->1, ... 5->0)
			cpi		period,	6
			brcs	main_ok
			clr		period
main_ok:	andi	flags,	~(1<<FLAG_VIBRO)
			rcall	wait_release
			rcall	reset_timer
			sei	
			rcall	indicate
			
			RJMP	Main

indicate_current_period:
			cli
			sbi		PORTB,	PIN_VIBRO
			rcall	indicate
			cbi		PORTB,	PIN_VIBRO
			sei
			rcall	wait_release
			RJMP	Main

; End Main =====================================================


; Procedure ====================================================
/// Procedure Delay2 delays execution for a while
/// For example, to get delay of one second, you must issue those statements:
/// .equ		MC_FREQ	=	32768
/// .equ		DELAY_1s =	(MC_FREQ/4 - 1)
/// 			ldi		delayL,	low(DELAY_1s)
///				ldi		delayH, high(DELAY_1s)
///				call	Delay2


Delay2:
			subi	delayL,	1
			sbci	delayH,	0
			brne	Delay2
			ret


; The Hello procedure greets user with 5 flashes of LED during vibration
Hello:		push	period
			ldi		period, 	2
			sbi		PORTB,  PIN_VIBRO
			rcall	indicate
			cbi		PORTB,  PIN_VIBRO
			pop		period
			ret

; Функция indicate мигает светодиодом period + 1 раз для индикации текущего периода
indicate:	mov		temp, 	period
			inc		temp
indicate_inner:
			sbi		PORTB,	PIN_LED
			ldi		delayH,	high(DELAY_200ms)
			ldi		delayL, low(DELAY_200ms)
			rcall	Delay2
			cbi		PORTB,	PIN_LED
			dec		temp
			brne	indicate_next
			ret
indicate_next:	
			ldi		delayH,	high(DELAY_200ms)
			ldi		delayL, low(DELAY_200ms)
			rcall	Delay2
			rjmp	indicate_inner

; Функция reset_timer устанавливает таймер в зависимости от значения переменной period
reset_timer:
			cli 					; запретить прерывания

			cpi			period,	1
			brne		reset_period2
			ldi			timeH,	high(10 * 60 * 2) ; 10 минут = 1200 периодов по 0.5 сек
			ldi			timeL,	low (10 * 60 * 2) 
			rjmp		reset_exit
reset_period2:
			cpi			period,	2
			brne		reset_period3
			ldi			timeH,	high(20 * 60 * 2) ; 20 минут = 2400 периодов по 0.5 сек
			ldi			timeL,	low (20 * 60 * 2)
			rjmp		reset_exit
reset_period3:	
			cpi			period,	3
			brne		reset_period4
			ldi			timeH,	high(30 * 60 * 2) ; 30 минут = 3600 периодов по 0.5 сек
			ldi			timeL,	low (30 * 60 * 2)
			rjmp		reset_exit
reset_period4:
			cpi			period,	4
			brne		reset_period5
			ldi			timeH,	high(40 * 60 * 2) ; 40 минут = 4800 периодов по 0.5 сек
			ldi			timeL,	low (40 * 60 * 2)
			rjmp		reset_exit
reset_period5:
			cpi			period,	5
			brne		reset_period_default
			ldi			timeH,	high(60 * 60 * 2) ; 60 минут = 7200 периодов по 0.5 сек
			ldi			timeL,	low (60 * 60 * 2)
			rjmp		reset_exit
reset_period_default:
			clr			period
			ldi			timeH,	high(5 * 60 * 2) ; 5 минут = 600 периодов по 0.5 сек
			ldi			timeL,	low (5 * 60 * 2)

reset_exit:			
			clr		temp
			out		TCNT0,	temp
			ret						; вернуться

; функция vibrate включает вибро на 1 секунду и сбрасывает FLAG_VIBRO
vibrate:	sbi		PORTB,	PIN_VIBRO
			ldi		delayL,	low (DELAY_1s)
			ldi		delayH,	high(DELAY_1s)
			rcall	Delay2
			cbi		PORTB,	PIN_VIBRO
			andi	flags,	~(1<<FLAG_VIBRO)
;			rcall	reset_timer
;			sei
			ret


/*out_digit:	ldi		temp,	0b01010101
			cli
			ldi		temp_int,	8
out_digit_next_bit:
			sbi		PORTB,		PB2
			sbrs	temp,		0
			cbi		PORTB,		PB2
			sbi		PORTB,		PB0
			nop
			nop
			cbi		PORTB,		PB0
			lsr		temp
			dec		temp_int
			brne	out_digit_next_bit
			nop
			reti
*/

; Процедура wait_release ждет отпускания кнопки на выводе PIN_BUTTON
wait_release:
			sbis	PINB,	PIN_BUTTON			; ждем отпускания кнопачки
			rjmp	wait_release
			ldi		delayH,	high(DELAY_31ms)	; кнопарь отжат. ждем устаканивания дребезга
			ldi		delayL,	low(DELAY_31ms)
			rcall	Delay2
			sbis	PINB,	PIN_BUTTON			; кнопарь отжат -> не дребезг
			rjmp	wait_release

			ret
; End Procedure ================================================


; EEPROM =====================================================
			.ESEG				; Сегмент EEPROM
