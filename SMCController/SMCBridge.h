//
//  SMCBridge.h
//  SMCController
//

#ifndef SMCBridge_h
#define SMCBridge_h

#include <stdint.h>
#include <stdbool.h>
#include <IOKit/IOKitLib.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque connection handle used by the C bridge
typedef struct SMCConnection {
    io_connect_t conn;
} SMCConnection;

SMCConnection* smc_open(void);
void smc_close(SMCConnection* conn);

int smc_read_key(SMCConnection* conn, const char key[4], uint8_t* outBuf, uint32_t outBufSize, uint32_t* outDataSize, uint32_t* outDataType);
int smc_write_key(SMCConnection* conn, const char key[4], const uint8_t* inBuf, uint32_t inSize, uint32_t dataType);

int smc_write_fan_target_rpm(SMCConnection* conn, uint32_t fanIndex, int rpm);

int smc_read_fan_count(SMCConnection* conn);
int smc_set_fan_manual(SMCConnection* conn, bool enabled);

// Check if we have write access to SMC
int smc_check_write_access(SMCConnection* conn);

// Debug functions for SMC sensor enumeration
int smc_read_key_info(SMCConnection* conn, const char key[4], uint32_t* outDataSize, uint32_t* outDataType);

#ifdef __cplusplus
}
#endif

#endif /* SMCBridge_h */
