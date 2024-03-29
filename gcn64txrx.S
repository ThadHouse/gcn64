#include <avr/io.h>

; When compiling, you must define the following.
;
; SUFFIX         : The suffix for exported function (eg: Set to 0 to generate gcn64_sendBytes0)
; GCN64_DATA_BIT : The bit number in the port.
;
; Port and Pin IOs are defined below.
;

#define CONCAT(a,b)	a##b
#define EXPORT_SYMBOL(a, b)	.global CONCAT(a,b)
#define FUNCTION(a, b)		CONCAT(a,b)

.text
EXPORT_SYMBOL(gcn64_sendBytes, SUFFIX)
EXPORT_SYMBOL(gcn64_receiveBytes, SUFFIX)

#define xl  r26
#define xh  r27
#define yl  r28
#define yh  r29
#define zl  r30
#define zh  r31
#define __zero_reg__	r1

/* the value of the gpio is pre-configured to low. We simulate
	an open drain output by toggling the direction */

#ifdef STK525
	#define GCN64_DATA_PORT _SFR_IO_ADDR(PORTA)
	#define GCN64_DATA_DDR  _SFR_IO_ADDR(DDRA)
	#define GCN64_DATA_PIN  _SFR_IO_ADDR(PINA)
#else
	#define GCN64_DATA_PORT _SFR_IO_ADDR(PORTD)
	#define GCN64_DATA_DDR  _SFR_IO_ADDR(DDRD)
	#define GCN64_DATA_PIN  _SFR_IO_ADDR(PIND)
#endif
;#define GCN64_DATA_BIT	0

#if F_CPU != 16000000L
#error Only 16MHz clock supported
#endif

	/************************************************
	* Function gcn64_receiveBits
    *
    * Works by timing the low and high periods of each bit and
	* then comparing them to know if a 1 or a 0 was on the wire.
	*
	* Example timed values:
	* 54 4e 53 4d 53 4d 53 4e 53 4d 4d 53 53 4e 4c 54 53 4d 54 4d 53 4d 53 4d ...
	*   0     0     0     0     0     1     0     1     0     0     0     0  ....
	*/

	; The bit timeout is a counter to 127. This is the
	; start value. Counting from 0 takes hundreads of
	; microseconds. Because of this, the reception function
	; "hangs in there" much longer than necessary..
#define TIMING_OFFSET	75
	; unsigned int gcn64_receiveBytes(unsigned char *dstbuf, unsigned char max_bytes);
	; r24,r25 : dstbuf
	; r22 : max bytes (for fututre use)
	; return: count in r24,r25 (0xff: Error, 0xfe: Overflow [max_bytes too low])
FUNCTION(gcn64_receiveBytes, SUFFIX):
	clr xl
	clr xh
	mov zl, r24
	mov zh, r25
	clr r18
	ldi r20, 1
	clr r24
initial_wait_low:
	inc r18
	breq timeout	; overflow to 0
	sbic GCN64_DATA_PIN, GCN64_DATA_BIT
	rjmp initial_wait_low

	; the next transition is to a high bit
	rjmp waithigh

waitlow:
	mov r21, r18 ; Save the last value
	ldi r18, TIMING_OFFSET
waitlow_lp:
	inc r18
	brmi rxdone		; > 127 (approx 50uS timeout)
	sbic GCN64_DATA_PIN, GCN64_DATA_BIT
	rjmp waitlow_lp

	; Compare the low period and the high period.
	sub r19, r18 ; Carry is set when 1
	rol r20
	brcs store_byte
	rjmp waithigh

store_byte:
	cp r22, r24 ; Check max_bytes
	breq overflow
	inc r24 ; Count byte
	st z+,r20
	ldi r20, 1

waithigh:
	ldi r19, TIMING_OFFSET
waithigh_lp:
	inc r19
	brmi frame_error ; This means the line is stuck in a low state...
	sbis GCN64_DATA_PIN, GCN64_DATA_BIT
	rjmp waithigh_lp
	rjmp waitlow

overflow:
	ser r24 ; 0xff
	dec r24 ; 0xfe
	ret

timeout:
	tst r24
	breq rxdone ; If r24 is still zero, we did not receive anything. Return 0.
	; Otherwise, it is a frame error (i.e. A partial byte was received)
frame_error:
	ser r24
rxdone:
	; Return the number if received bits in r24
	ret


; These are for a slower 4us/1.5us timing.
; The MadCatz Microcon does not work with 3us/1us timing...
#define LOOPS_SEND0_LOW		20
#define DELAY_SEND0_HIGH	2
#define LOOPS_SEND1_LOW		4
#define LOOPS_SEND1_HIGH	13

/*
; These are for the perfect 3us/1us timing described below
#define LOOPS_SEND0_LOW		15
#define LOOPS_SEND1_LOW		4
#define LOOPS_SEND1_HIGH	10
*/
	/************************************************
	* Send data using the N64/GC serial protocol which
	* is as follows:
	*   0          1
	*     __        _____
	* ____|       __|
	* ^   ^ ^     ^ ^   ^
	*  3us 1us    1us 3us
	*
	* To send a 1, the pin direction is set to input.
	* To send a 0, the pin direction is set to output.
	*	(of course, it's value is preset to zero)
	*
	* At 16 mhz, a 1us period is 16 cycles. Thus a 3us period
	* is 48 cycles.
	*
	* Pointer to data is passed in r24, r25
	* Number of bytes to send is passed in r22
	*
	* A stop bit is added at thy end of the packet.
	*
	************************************************/
FUNCTION(gcn64_sendBytes, SUFFIX):
	; Move r23,r24 pointer to z
	mov zl, r24
	mov zh, r25

	tst r22
	breq done_send

send_next_byte:
	; Check if this is the last byte.
	tst r22
	breq send_stop
	dec r22
	ld r21, z+
	ldi r27, 0x80 ; mask

send_next_bit:
	mov r19, r21
	and r19, r27
	brne send1
	nop

send0:
	sbi GCN64_DATA_DDR, GCN64_DATA_BIT   ; Pull bus to 0

	ldi r20, LOOPS_SEND0_LOW
lp_send0_3us:
	dec r20
	brne lp_send0_3us
	nop

	cbi GCN64_DATA_DDR, GCN64_DATA_BIT	; Release bus to 1

#ifdef DELAY_SEND0_HIGH
	ldi r20, DELAY_SEND0_HIGH
lp_send0_1us:
	dec r20
	brne lp_send0_1us
#endif

	lsr r27
	breq send_next_byte
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp send_next_bit

send1:
	sbi GCN64_DATA_DDR, GCN64_DATA_BIT	; Pull bus to 0

	ldi r20, LOOPS_SEND1_LOW
lp_send1_1us:
	dec r20
	brne lp_send1_1us
	nop
	nop

	cbi GCN64_DATA_DDR, GCN64_DATA_BIT	; Release bus to 1

	ldi r20, LOOPS_SEND1_HIGH
lp_send1_3us:
	dec r20
	brne lp_send1_3us
	nop
	nop

	lsr r27
	breq send_next_byte
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp send_next_bit

send_stop:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	; STOP BIT
	sbi GCN64_DATA_DDR, GCN64_DATA_BIT ; Pull low for stop bit
	ldi r20, LOOPS_SEND1_LOW
stbdly0:
	dec r20
	brne stbdly0
	nop
	cbi GCN64_DATA_DDR, GCN64_DATA_BIT ;	Release

done_send:
	ret

