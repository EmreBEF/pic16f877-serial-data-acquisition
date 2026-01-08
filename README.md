# pic16f877-serial-data-acquisition

## Overview
This project implements an interrupt-driven serial data acquisition system on a PIC16F877 microcontroller, written in assembly language using MPLAB X.

The system acquires an analog voltage using the built-in ADC and transmits the measured value to a PC over a UART serial connection. Two operating modes are supported: automatic periodic transmission and on-demand measurement via serial commands.

---

## Features
- UART communication at 9600 baud (8N1)
- ADC sampling on AN0 (8-bit resolution, left-justified)
- Timer1 interrupt used as a 50 ms time base
- Software counter to generate a 1-second period
- Two operating modes:
  - **Automatic mode**: sends the measured voltage every second
  - **On-demand mode**: sends the measurement only when requested
- Remote echo of received serial characters
- Fully interrupt-driven design (Timer + USART RX)

---

## Hardware
- Microcontroller: **PIC16F877**
- Clock frequency: **8 MHz (HS oscillator)**
- Analog input: **AN0**
- Serial interface: UART via USB-to-Serial (e.g. MCP2221 / Explorer8 board)

---

## Software & Tools
- MPLAB X IDE
- MPASM assembler
- Terminal emulator (PuTTY or equivalent)
- PICkit (for programming/debugging)

---

## Serial Commands
| Command | Description |
|--------|------------|
| `a` | Switch to automatic mode |
| `r` | Switch to on-demand mode |
| `d` | Request a voltage measurement (on-demand mode only) |

The measured voltage is transmitted in ASCII format:

U,D V

Example:

2,3 V

---

## How It Works
- **Timer1 interrupt** generates a 50 ms tick; a software counter produces a 1-second event.
- **USART RX interrupt** captures incoming characters and sets a flag.
- **Main loop** processes events based on flags:
  - reads the ADC,
  - converts the result to a human-readable format,
  - sends data over UART.
- Interrupt Service Routines are kept short and only signal events using flags.

---

## ADC Conversion
- The ADC is configured with left justification.
- Only the `ADRESH` register is used (8-bit resolution).
- Voltage conversion is implemented using repeated subtraction (no division instruction).

---

## Build & Flash
1. Open MPLAB X
2. Create a new PIC16F877 assembly project
3. Add the `.asm` source file
4. Assemble and program the device using PICkit
5. Open a serial terminal at **9600 baud**

---

## Limitations
- Blocking UART transmission
- Approximate voltage conversion (no calibration)
- No checksum or error detection on serial data

---

## Possible Improvements
- Non-blocking UART transmission
- Higher ADC resolution using ADRESL
- Calibration and scaling improvements
- Additional serial commands
- Migration to C for portability

---

## Author
Developed by Emre Bekci as part of an embedded systems coursework.
