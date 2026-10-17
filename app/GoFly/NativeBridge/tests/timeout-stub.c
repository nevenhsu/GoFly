// The lifetime harness never links the native archive or opens a device.
#include <stdint.h>
void idevice_set_global_timeout(uint64_t seconds) { (void)seconds; }
