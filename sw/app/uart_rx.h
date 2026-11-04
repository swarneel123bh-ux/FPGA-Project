#ifndef UART_RX_H
#define UART_RX_H
#include "xil_types.h"
int  uart_rx_init(void);
void uart_rx_start(u8 *buf, u32 n);
int  uart_rx_done(void);
#endif
