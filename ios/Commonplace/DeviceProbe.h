#ifndef COMMONPLACE_DEVICE_PROBE_H
#define COMMONPLACE_DEVICE_PROBE_H
#include <stdint.h>
uint64_t CPAvailableMemory(void);
uint64_t CPPhysicalFootprint(void);
uint64_t CPResidentMemory(void);
#endif
