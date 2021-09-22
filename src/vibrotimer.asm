; *******************************************************
; Автор:            Тимофей Лукашевич                   *
; Дата:             2010.09.21                          *
; Версия:           2.0                                 *
; Имя файла:        vibrotimer.asm                      *
; Для AVR:          ATTiny13                            *
; Тактовая частота: 128 kHz                             *
; *******************************************************

; Выполняемые функции: таймер для включения вибросигнала каждые n минут 
; период подачи вибросигнала настраивается: 5, 10, 20, 30, 40, 60 минут
; на время между прерываниями контроллер переходит в idle mode для 
; экономии батареек. Между включениями устройства период запоминается в EEPROM


.include "tn13Adef.inc"   ; Используем Tiny13a

;= Definitions ===============================================
.def		temp		=	r16 ; Временный регистр для различных целей
.def		kbdTimer	=	r17	; счетчик для использования для отсчета таймаутов кнопки.
.def		indTimer	=	r18	; счетчик для отмерения интервалов вибры и светодиода
.def		eepromTimer	=	r19	; таймер отложенной записи в eeprom (чтобы при многократных переключениях
								; периода за короткий промежуток времени не записывать их все в eeprom)
.def		delayL		=	r17 ; младший байт времени задержки для процедуры Delay2
.def		delayH		=	r18 ; старший байт времени задержки для процедуры Delay2
.def		flashCount	=	r20	; для хранения числа оставшихся вспышек светодиода
.def		vibroCountL	=	r21 ; содержит число 1/16-секундных периодов, 
.def		vibroCountM =	r22 ; прошедших с последнего
.def		vibroCountH	=	r23 ; срабатывания.
.def		period		=	r24	/* запрограмминованный период срабатывания:
										0 - 1  минута
								 		1 - 5  минут 
										2 - 10 минут
										3 - 15 минут
										4 - 20 минут
										5 - 30 минут
										6 - 40 минут
										7 - 60 минут	*/

.equ		DEFAULT_PERIOD	=	6
.equ		MAX_PERIOD		=	7
.def		flags		=	r25 ; Бит для различных флагов и сообщений
.def		FSMKBD		=	r26	; регистр для хранения состояния конечного автомата опроса кнопаря
.def		FSMInd		=	r27	; регистр для хранения состояния конечного автомата вибратора/индикатора
;.def		FSMLogic	=	r28 ; регистр для хранения состояния конечного автомата логики переключения


.equ		PIN_LED		=	PB2
.equ		PIN_BUTTON 	=	PB1
.equ		PIN_VIBRO	=	PB0

.equ		MC_FREQ	=	128000
.equ		DELAY_1s =	(MC_FREQ/4 - 1)
.equ		DELAY_200ms =	(DELAY_1s * 200 / 1000)

.equ		INTS_PER_MINUTE	=	60 * 16		; количество прерываний таймера в минуту
.equ		TIMEOUT_01MIN	=	01 * INTS_PER_MINUTE
.equ		TIMEOUT_05MIN	=	05 * INTS_PER_MINUTE
.equ		TIMEOUT_10MIN	=	10 * INTS_PER_MINUTE
.equ		TIMEOUT_15MIN	=	15 * INTS_PER_MINUTE
.equ		TIMEOUT_20MIN	=	20 * INTS_PER_MINUTE
.equ		TIMEOUT_30MIN	=	30 * INTS_PER_MINUTE
.equ		TIMEOUT_40MIN	=	40 * INTS_PER_MINUTE
.equ		TIMEOUT_60MIN	=	60 * INTS_PER_MINUTE
.equ		MSG_VIBRO_BIT	=	1	; бит в регистре FLAGS, означает наличие сообщения "ВКЛЮЧИТЬ ВИБРУ"
.equ		MSG_INDICATE_BIT=	2	; бит в регистре FLAGS, означает наличие сообщения "ПОМИГАТЬ СВЕТОДИОДОМ, ПОКАЗАТЬ ТЕКУЩИЙ ПЕРИОД"

; СОСТОЯния конечного автомата обработки кнопки:
.equ		KBD_INIT			=	0
.equ		KBD_PRESS_DREBEZG	=	1
.equ		KBD_PRESSED			=	2
.equ		KBD_WAITRELEASE		=	3
.equ		KBD_RELEASE_DREBEZG	=	4

; СОСТОЯния конечного автомата индикации:
.equ		IND_INIT			=	0
.equ		IND_VIBRATING		=	1
.equ		IND_LEDON			=	2
.equ		IND_LEDOFF			=	3

; Состояния когечного автомата логики
;.equ		LOGIC_INIT			=	0
;.equ		LOGIC_STATE2		=	1

; СОСТОЯния конечного автомата Вибрации/индикации

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
			in		temp,		MCUCR	; запретить спящие режимы (рекомендуется делать сразу по просыпанию)
			andi	temp,		~(1<<SE)
			out		MCUCR,		temp

			ldi		temp,	131		; записываем в счетный регистр 131 (чтобы отсчитывать 
			out		TCNT0,		temp ; интерывалы ровно по 1/16 секунды)
			wdr								; кинем кость сторожевой собачке :)
			subi	vibroCountL,	1		; декрементируем счетчик 1/16 секундных периодов
			sbci	vibroCountM,	0
			sbci	vibroCountH,	0
			mov		temp,	vibroCountL
			or		temp,	vibroCountM
			or		temp,	vibroCountH
			brne	process_eeprom_timer
			ori		flags,	1<<MSG_VIBRO_BIT	; послать сообщение "включи вибросигнал"
			rcall	reset_timer			; проинициализировать таймер вибросигнала

process_eeprom_timer:
			tst		eepromTimer
			breq	process_kbd_timer
			dec		eepromTimer
			brne	process_kbd_timer

			;write EEPROM:
			sbic	EECR,	EEPE		; ждем завершения предыдущей операции записи в EEPROM
			rjmp	eepromRetryLater	; писалка eeprom еще занята - попробуем еще раз позднее
			; Включить режим програмирования (Erase&Write): 
			ldi		temp,	(0<<EEPM1) | (0<<EEPM0)
			out		EECR,	temp
			; Записать адрес в р-р адреса (адрес = 0 в нашем случае):
			clr		temp
			out		EEARL,	temp
			; Записать данные в регистр данных:
			out		EEDR,	period
			sbi		EECR,	EEMPE
			sbi		EECR,	EEPE		; инициировать запись в EEPROM
			rjmp	process_kbd_timer
eepromRetryLater:
			ldi		eepromTimer,	1

process_kbd_timer:
			tst		kbdTimer
			breq	process_vib_timer
			dec		kbdTimer


process_vib_timer:
			tst		indTimer
			breq	process_kbdfsm
			dec		indTimer

process_kbdfsm:			// обработка автомата нажатия кнопки:
			cpi		FSMKBD,	KBD_INIT		// начальное состояние
			brne	check_kbd_press_drebezg
			sbic	PINB,	PIN_BUTTON
			rjmp	process_indfsm
			ldi		FSMKBD,	KBD_PRESS_DREBEZG
			ldi		kbdTimer,	1
			rjmp	process_indfsm
check_kbd_press_drebezg:
			cpi		FSMKBD,	KBD_PRESS_DREBEZG // состояние ожидания окончания дребезга
			brne	check_kbd_pressed
			tst		kbdTimer
			brne	process_indfsm
			sbis	PINB,	PIN_BUTTON
			rjmp	goto_kbd_pressed
			ldi		FSMKBD,	KBD_INIT
			rjmp	process_indfsm
goto_kbd_pressed:
			ldi		FSMKBD,	KBD_PRESSED
			ldi		kbdTimer,	8
			rjmp	process_indfsm

check_kbd_pressed:		
			cpi		FSMKBD,	KBD_PRESSED			// состояние "кнопка нажата"
			brne	check_kbd_waitrelease
			sbis	PINB,	PIN_BUTTON
			rjmp	goto_checklongpress
			; сюда попадаем, если кнопка отпускается после недолгого нажатия. Сменим период
			inc		period
			cpi		period,	(MAX_PERIOD + 1)
			brbs	SREG_C,	PC+2
			clr		period
			ldi		eepromTimer, 160	; запись нового значения периода в eeprom произойдет через 160/16 = 10 секунд
			ori		flags,	1<<MSG_INDICATE_BIT
			ldi		FSMKBD,	KBD_WAITRELEASE
			rcall	reset_timer
			rjmp	process_indfsm
goto_checklongpress:
			; сюда попадаем, если юзер держит кнопку нажатой. проверим, что натикало нужное время нажатия
			tst		kbdTimer
			brne	process_indfsm
			ori		flags,	1<<MSG_INDICATE_BIT
			ldi		FSMKBD,	KBD_WAITRELEASE
			rjmp	process_indfsm

check_kbd_waitrelease:
			cpi		FSMKBD,	KBD_WAITRELEASE		// состояние "ожидание отпускания кнопки"
			brne	check_kbd_release_drebezg
			sbis	PINB,	PIN_BUTTON
			rjmp	process_indfsm
			ldi		FSMKBD,	KBD_RELEASE_DREBEZG
			ldi		kbdTimer,	1
			rjmp	process_indfsm

check_kbd_release_drebezg: // состояние ожидания окончания дребезга при отпускании
			tst		kbdTimer
			brne	process_indfsm
			ldi		FSMKBD,	KBD_INIT
			sbis	PINB,	PIN_BUTTON
			ldi		FSMKBD,	KBD_WAITRELEASE
			rjmp	process_indfsm



process_indfsm:			// обработка автомата индикации
			cpi		FSMIND,	IND_INIT
			brne	check_ind_vibrating
			sbrs	flags,	MSG_VIBRO_BIT
			rjmp	check_indicate_msg
			andi	flags,	~(1<<MSG_VIBRO_BIT)
			ldi		indTimer,	64		; включить вибру на 64/16 долей секунды
			ldi		FSMInd,		IND_VIBRATING
			sbi		PORTB,		PIN_VIBRO
			rjmp	check_fsm_next
check_indicate_msg:
			sbrs	flags,	MSG_INDICATE_BIT
			rjmp	check_fsm_next
			andi	flags,	~(1<<MSG_INDICATE_BIT)
			ldi		FSMInd,	IND_LEDON
			ldi		indTimer,	4	; включить диод на 4/16 секунды
			sbi		PORTB,	PIN_LED
			mov		flashCount,	period
			inc		flashCount
			rjmp	check_fsm_next

check_ind_vibrating:
			cpi		FSMIND,	IND_VIBRATING
			brne	check_ind_ledon
			tst		indTimer
			brne	check_fsm_next
			cbi		PORTB,		PIN_VIBRO
			ldi		FSMIND,		IND_INIT
			rjmp	check_fsm_next

check_ind_ledon:
			cpi		FSMIND,	IND_LEDON
			brne	check_ind_ledoff
			tst		indTimer
			brne	check_fsm_next
			dec		flashCount
			ldi		indTimer,	4
			ldi		FSMIND,		IND_LEDOFF
			cbi		PORTB,		PIN_LED
			tst 	flashCount		; если проморгали нужное число раз, то...
;			sbic	SREG,	SREG_Z
			brbc	SREG_Z,	PC+2
			ldi		FSMIND,		IND_INIT ; ...возвращаемся в исходное состояние.
			rjmp	check_fsm_next
check_ind_ledoff:
			tst		indTimer
			brne	check_fsm_next
			sbi		PORTB,	PIN_LED
			ldi		FSMIND,	IND_LEDON
			ldi		indTimer,	4
			rjmp	check_fsm_next

check_fsm_next:
exit_timer_overflow:
			in		temp,	MCUCR		; разрешить спящие режимы
			andi	temp,	1<<SE
			out		MCUCR,	temp

			sleep						; заснуть
			reti

; End Interrupts ==========================================


Reset:		
	 
; Start coreinit.inc
			LDI 	R16,Low(RAMEND)	; Инициализация стека
			OUT 	SPL,R16			; Обязательно!!!
;			clr		reg_zero
;			ldi		reg_one,	1
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
			ldi		temp,	0b00000011
			out		TCCR0B,	temp		; set prescaler to 1/64
			

			ldi		temp,	(1<<PIN_LED) | (1<<PIN_VIBRO) ; PB0 and PB2 is outputs, PB1 is input
			out		DDRB,	temp
			ldi		temp, 	0b00000010	; Enable pull-up on PB1
			out		portb,	temp
			sbi		ACSR,	ACD			; отключить аналоговый компаратор
			in		temp,	MCUCR
			andi	temp,	~((1<<SM1) | (1<<SM0))	; выбрать idle mode (а не power down mode)
			out		MCUCR,	temp
; End Internal Hardware Init ===================================



; External Hardware Init  ======================================

; End Internal Hardware Init ===================================



; Run ==========================================================
			clr		flags
			rcall	readEEPROM
			rcall	hello

			; конечные автоматы - в исходное состояние:
			clr		FSMInd
			clr		FSMKBD
			; таймеры - в исх. состояние
			clr		indTimer	
			clr		kbdTimer
			clr		eepromTimer
			ldi		temp,	131
			out		TCNT0,	temp
			rcall	reset_timer			; установим новый счетчик в зависимости от переменной period
			ldi		temp,	0xff
			out		TIFR0,	temp		; очистим флаги прерываний
			sei							; разрешить прерывания

; End Run ======================================================



; Main =========================================================
Main:
			in		temp,	MCUCR		; разрешить спящие режимы
			andi	temp,	1<<SE
			out		MCUCR,	temp

			sleep						; заснуть

			in		temp,		MCUCR	; запретить спящие режимы (рекомендуется делать сразу по просыпанию)
			andi	temp,		~(1<<SE)
			out		MCUCR,		temp
			rjmp	Main



; End Main =====================================================


; Procedure ====================================================

; процедура readEEPROM читает из ПЗУ ранее сохраненный период и помещает в переменную period
readEEPROM:
			sbic	EECR,	EEPE		; ждем завершения предыдущей операции записи в EEPROM
			rjmp	readEEPROM
			clr		temp
			out		EEARL,	temp		; читать будем по адресу 0
			sbi		EECR,	EERE		; инициировать чтение установкой бита EERE в регистре EECR
			in		period,	EEDR
			cpi		period,	(MAX_PERIOD + 1) ; если прочтенное значение > MAX_PERIOD, то ставим умолчальное значение
			brcs	exitReadEEPROM
			ldi		period,	DEFAULT_PERIOD
exitReadEEPROM:
			ret


/*; процедура writeEEPROM записывает в ПЗУ текущий период (из переменной period)
writeEEPROM:
			sbic	EECR,	EEPE		; ждем завершения предыдущей операции записи в EEPROM
			rjmp	writeEEPROM
			; Включить режим програмирования (Erase&Write): 
			ldi		temp,	(0<<EEPM1) | (0<<EEPM0)
			out		EECR,	temp
			; Записать адрес в р-р адреса (адрес = 0 в нашем случае):
			clr		temp
			out		EEARL,	temp
			; Записать данные в регистр данных:
			out		EEDR,	period
			sbi		EECR,	EEMPE
			sbi		EECR,	EEPE		; инициировать запись в EEPROM
			ret
*/
; Процедура Hello приветствует пользователя несколькими миганиями светодиода при 
; включенном вибросигнале (число миганий = период, см. комменты в начале файла)
Hello:		
			sbi		PORTB,  PIN_VIBRO
			rcall	indicate
			cbi		PORTB,  PIN_VIBRO
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
			cpi		period,	0
			brne	reset_period1
			ldi		vibroCountL,	low  (TIMEOUT_01MIN)
			ldi		vibroCountM,	BYTE2(TIMEOUT_01MIN)
			ldi		vibroCountH,	BYTE3(TIMEOUT_01MIN)
			rjmp	reset_exit
reset_period1:
			cpi		period,	1
			brne	reset_period2
			ldi		vibroCountL,	low  (TIMEOUT_05MIN)
			ldi		vibroCountM,	BYTE2(TIMEOUT_05MIN)
			ldi		vibroCountH,	BYTE3(TIMEOUT_05MIN)
			rjmp	reset_exit
reset_period2:	
			cpi		period,	2
			brne	reset_period3
			ldi		vibroCountL,	low  (TIMEOUT_10MIN)
			ldi		vibroCountM,	BYTE2(TIMEOUT_10MIN)
			ldi		vibroCountH,	BYTE3(TIMEOUT_10MIN)
			rjmp	reset_exit
reset_period3:
			cpi		period,	3
			brne	reset_period4
			ldi		vibroCountL,	low  (TIMEOUT_15MIN)
			ldi		vibroCountM,	BYTE2(TIMEOUT_15MIN)
			ldi		vibroCountH,	BYTE3(TIMEOUT_15MIN)
			rjmp	reset_exit
reset_period4:
			cpi		period,	4
			brne	reset_period5
			ldi		vibroCountL,	low  (TIMEOUT_20MIN)
			ldi		vibroCountM,	BYTE2(TIMEOUT_20MIN)
			ldi		vibroCountH,	BYTE3(TIMEOUT_20MIN)
			rjmp	reset_exit
reset_period5:
			cpi		period,	5
			brne	reset_period6
			ldi		vibroCountL,	low  (TIMEOUT_30MIN)
			ldi		vibroCountM,	BYTE2(TIMEOUT_30MIN)
			ldi		vibroCountH,	BYTE3(TIMEOUT_30MIN)
			rjmp	reset_exit
reset_period6:
			cpi		period,	6
			brne	reset_period7
			ldi		vibroCountL,	low  (TIMEOUT_40MIN)
			ldi		vibroCountM,	BYTE2(TIMEOUT_40MIN)
			ldi		vibroCountH,	BYTE3(TIMEOUT_40MIN)
			rjmp	reset_exit
reset_period7:
			cpi		period,	7
			brne	reset_period_default
			ldi		vibroCountL,	low  (TIMEOUT_60MIN)
			ldi		vibroCountM,	BYTE2(TIMEOUT_60MIN)
			ldi		vibroCountH,	BYTE3(TIMEOUT_60MIN)
			rjmp	reset_exit
reset_period_default:
			ldi		period,			DEFAULT_PERIOD		; сюда попадаем по умолчанию
			rjmp	reset_timer


reset_exit:			
;			clr		temp
;			out		TCNT0,	temp
			ret						; вернуться

; функция vibrate включает вибро на 1 секунду и сбрасывает FLAG_VIBRO
vibrate:	sbi		PORTB,	PIN_VIBRO
			ldi		delayL,	low (DELAY_1s)
			ldi		delayH,	high(DELAY_1s)
			rcall	Delay2
			cbi		PORTB,	PIN_VIBRO
;			andi	flags,	~(1<<FLAG_VIBRO)
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

/*; Процедура wait_release ждет отпускания кнопки на выводе PIN_BUTTON
wait_release:
			sbis	PINB,	PIN_BUTTON			; ждем отпускания кнопачки
			rjmp	wait_release
			ldi		delayH,	high(DELAY_31ms)	; кнопарь отжат. ждем устаканивания дребезга
			ldi		delayL,	low(DELAY_31ms)
			rcall	Delay2
			sbis	PINB,	PIN_BUTTON			; кнопарь отжат -> не дребезг
			rjmp	wait_release

			ret
*/

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
; End Procedure ================================================


; EEPROM =====================================================
			.ESEG				; Сегмент EEPROM
