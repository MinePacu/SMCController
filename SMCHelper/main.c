//
//  main.c
//  SMCHelper
//
//  Privileged helper for SMC operations
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include "../SMCController/SMCBridge.h"

static void print_usage(const char* prog) {
    fprintf(stderr, "Usage: %s <command> [args]\n", prog);
    fprintf(stderr, "Commands:\n");
    fprintf(stderr, "  set-fan <index> <rpm>     Set fan speed\n");
    fprintf(stderr, "  set-mode <enabled>        Set manual mode (1=on, 0=off)\n");
    fprintf(stderr, "  get-rpm <index>           Get current fan RPM\n");
    fprintf(stderr, "  check                     Check if helper is working\n");
}

int main(int argc, char* argv[]) {
    // Helper must run as root
    if (geteuid() != 0) {
        fprintf(stderr, "ERROR: Helper must run as root\n");
        return 1;
    }
    
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }
    
    const char* command = argv[1];
    
    // Open SMC connection
    SMCConnection* conn = smc_open();
    if (!conn) {
        fprintf(stderr, "ERROR: Failed to open SMC connection\n");
        return 2;
    }
    
    int result = 0;
    
    if (strcmp(command, "check") == 0) {
        // Simple check command
        printf("OK: Helper is working (euid=%d)\n", geteuid());
        result = 0;
        
    } else if (strcmp(command, "set-fan") == 0) {
        if (argc < 4) {
            fprintf(stderr, "ERROR: set-fan requires <index> <rpm>\n");
            result = 1;
        } else {
            int fan_index = atoi(argv[2]);
            int rpm = atoi(argv[3]);
            
            int ret = smc_write_fan_target_rpm(conn, fan_index, rpm);
            if (ret == 0) {
                printf("OK: Set fan %d to %d RPM\n", fan_index, rpm);
                result = 0;
            } else {
                fprintf(stderr, "ERROR: Failed to set fan speed (error=%d)\n", ret);
                result = 3;
            }
        }
        
    } else if (strcmp(command, "set-mode") == 0) {
        if (argc < 3) {
            fprintf(stderr, "ERROR: set-mode requires <enabled>\n");
            result = 1;
        } else {
            bool enabled = atoi(argv[2]) != 0;
            
            int ret = smc_set_fan_manual(conn, enabled);
            if (ret == 0) {
                printf("OK: Set manual mode to %s\n", enabled ? "ON" : "OFF");
                result = 0;
            } else {
                fprintf(stderr, "ERROR: Failed to set manual mode (error=%d)\n", ret);
                result = 3;
            }
        }
        
    } else if (strcmp(command, "get-rpm") == 0) {
        if (argc < 3) {
            fprintf(stderr, "ERROR: get-rpm requires <index>\n");
            result = 1;
        } else {
            int fan_index = atoi(argv[2]);
            
            // Read current RPM by calling smc_read_key directly
            char key[5];
            snprintf(key, sizeof(key), "F%dAc", fan_index);
            
            uint8_t buf[32];
            uint32_t dataSize = 0, dataType = 0;
            int ret = smc_read_key(conn, key, buf, sizeof(buf), &dataSize, &dataType);
            
            if (ret == 0) {
                // Decode based on type (simplified - assume fpe2 or flt)
                int rpm = 0;
                if (dataSize == 2) {
                    // fpe2 or ui16
                    rpm = (buf[0] << 8) | buf[1];
                    rpm /= 4; // fpe2 decode
                } else if (dataSize == 4) {
                    // float
                    float* f = (float*)buf;
                    rpm = (int)*f;
                }
                printf("OK: Fan %d current RPM: %d\n", fan_index, rpm);
                result = 0;
            } else {
                fprintf(stderr, "ERROR: Failed to read fan RPM (error=%d)\n", ret);
                result = 3;
            }
        }
        
    } else {
        fprintf(stderr, "ERROR: Unknown command '%s'\n", command);
        print_usage(argv[0]);
        result = 1;
    }
    
    smc_close(conn);
    return result;
}
