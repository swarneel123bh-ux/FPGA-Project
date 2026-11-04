#include "uart_rx.h"
#include <stdint.h>
#include <stddef.h>

#include "xparameters.h"
#include "xplatform_info.h"
#include "xuartps.h"
#include "xil_exception.h"
#include "xil_printf.h"

#ifdef XPAR_INTC_0_DEVICE_ID
	#include "xintc.h"
#else
	#include "xscugic.h"
#endif

#define INTC             XScuGic
#define UART_DEVICE_ID   XPAR_XUARTPS_0_DEVICE_ID
#define INTC_DEVICE_ID   XPAR_SCUGIC_SINGLE_DEVICE_ID
#define UART_INT_IRQ_ID  XPAR_XUARTPS_1_INTR


static volatile u32 TotalReceivedCount;
static volatile u32 TotalErrorCount;

static void Handler(void *CallBackRef, u32 Event, u32 EventData);

static XUartPs uart;
static XScuGic gic;
static INTC *IntcInstancePtr = &gic;
static XUartPs *UartInstancePtr = &uart;
static XScuGic_Config *IntcConfig;
u16 DeviceId = UART_DEVICE_ID;
u16 UartIntrId = UART_INT_IRQ_ID;

int uart_rx_init(void) {
	int Status;
	XUartPs_Config *Config;
	u32 IntrMask;

	/*
	 * Initialize the UART driver so that it's ready to use
	 * Look up the configuration in the config table, then initialize it.
	 */
	Config = XUartPs_LookupConfig(DeviceId);
	if (NULL == Config) { return XST_FAILURE; }

	Status = XUartPs_CfgInitialize(UartInstancePtr, Config, Config->BaseAddress);
	if (Status != XST_SUCCESS) { return XST_FAILURE; }

	// Set Baud Rate and Fifo Thresholds
	if (XUartPs_SetBaudRate(UartInstancePtr, 230400) != XST_SUCCESS) { return XST_FAILURE; }
  XUartPs_SetFifoThreshold(UartInstancePtr, 32);

  XUartPs_SetRecvTimeout(UartInstancePtr, 8);

  XUartPs_SetHandler(UartInstancePtr, (XUartPs_Handler)Handler, UartInstancePtr);

  IntrMask =
		XUARTPS_IXR_TOUT | XUARTPS_IXR_PARITY | XUARTPS_IXR_FRAMING |
		XUARTPS_IXR_OVER | XUARTPS_IXR_RXFULL |
		XUARTPS_IXR_RXOVR;
  XUartPs_SetInterruptMask(UartInstancePtr, IntrMask);


	/* Initialize the interrupt controller driver */
	IntcConfig = XScuGic_LookupConfig(INTC_DEVICE_ID);
	if (NULL == IntcConfig) { return XST_FAILURE; }

	Status =  XScuGic_CfgInitialize(
		IntcInstancePtr, IntcConfig,
		IntcConfig->CpuBaseAddress
	); if (Status != XST_SUCCESS) { return XST_FAILURE; }

	Xil_ExceptionRegisterHandler(
		XIL_EXCEPTION_ID_INT,
		(Xil_ExceptionHandler) XScuGic_InterruptHandler,
		IntcInstancePtr
	);

	Status = XScuGic_Connect(
		IntcInstancePtr, UartIntrId,
		(Xil_ExceptionHandler) XUartPs_InterruptHandler,
		(void *) UartInstancePtr
	); if (Status != XST_SUCCESS) { return XST_FAILURE; }

	XScuGic_Enable(IntcInstancePtr, UartIntrId);
	Xil_ExceptionEnable();

	return XST_SUCCESS;
}

static volatile int rx_done = 0;
static void Handler(void *CallBackRef, u32 Event, u32 EventData) {

	/* All of the data has been received */
	if (Event == XUARTPS_EVENT_RECV_DATA) {
		TotalReceivedCount = EventData;
		rx_done = 1;
	}

	/* Data was received, but not the expected number of bytes,
	 * a timeout just indicates the data stopped for 8 character times */
	if (Event == XUARTPS_EVENT_RECV_TOUT) {
		TotalReceivedCount = EventData;
	}

	/* Data was received with an error, keep the data but determine what kind of errors occurred */
	if (Event == XUARTPS_EVENT_RECV_ERROR) {
		TotalReceivedCount = EventData;
		TotalErrorCount++;
	}
}


void uart_rx_start(u8 *buf, u32 n) {
	rx_done = 0;
	TotalErrorCount = 0;
	TotalReceivedCount = 0;
	XUartPs_Recv(UartInstancePtr, buf, n);
}

int uart_rx_done(void) { return rx_done; }
