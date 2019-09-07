CC=avr-gcc
CCP=avr-g++
AS=$(CC)
LD=$(CC)

OBJS=main.o gcn64txrx0.o gcn64txrx1.o gcn64txrx2.o gcn64txrx3.o 

PROGNAME=gcn64usb
OBJDIR=objs-$(PROGNAME)
CPU=atmega32u4
CFLAGS=-Wall -std=c11 -mmcu=$(CPU) -DF_CPU=16000000L -Os -DUART1_STDOUT
CPPFLAGS=-Wall -std=c++17 -mmcu=$(CPU) -DF_CPU=16000000L -Os -DUART1_STDOUT
LDFLAGS=-mmcu=$(CPU) -Wl,-Map=$(PROGNAME).map

HEXFILE=$(PROGNAME).hex

all: $(HEXFILE)

gcn64txrx0.o: gcn64txrx.S
	$(CC) $(CFLAGS) -c $< -o $@ -DSUFFIX=0 -DGCN64_DATA_BIT=0

gcn64txrx1.o: gcn64txrx.S
	$(CC) $(CFLAGS) -c $< -o $@ -DSUFFIX=1 -DGCN64_DATA_BIT=2

gcn64txrx2.o: gcn64txrx.S
	$(CC) $(CFLAGS) -c $< -o $@ -DSUFFIX=2 -DGCN64_DATA_BIT=1

gcn64txrx3.o: gcn64txrx.S
	$(CC) $(CFLAGS) -c $< -o $@ -DSUFFIX=3 -DGCN64_DATA_BIT=3

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.c %.h
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.cpp
	$(CCP) $(CPPFLAGS) -c $< -o $@

$(PROGNAME).elf: $(OBJS)
	$(LD) $(OBJS) $(LDFLAGS) -o $(PROGNAME).elf

$(PROGNAME).hex: $(PROGNAME).elf
	avr-objcopy -j .data -j .text -O ihex $(PROGNAME).elf $(PROGNAME).hex