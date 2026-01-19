//
//  main_daemon.c
//  SMCHelper
//
//  Privileged helper daemon for SMC operations
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <errno.h>
#include <time.h>
#include <ctype.h>
#include <pthread.h>
#include <CoreFoundation/CoreFoundation.h>
#include "../SMCController/SMCBridge.h"

#define SOCKET_PATH "/tmp/com.minepacu.SMCHelper.socket"
#define POWER_CACHE_TTL 3.0  // seconds

static SMCConnection* g_conn = NULL;
static double g_cpu_power = -1.0;
static double g_gpu_power = -1.0;
static double g_dc_power = -1.0;
static double g_power_timestamp = 0.0;

static void type_code_to_str(uint32_t code, char out[5]) {
    out[0] = (char)((code >> 24) & 0xFF);
    out[1] = (char)((code >> 16) & 0xFF);
    out[2] = (char)((code >> 8) & 0xFF);
    out[3] = (char)(code & 0xFF);
    out[4] = '\0';
}

static double decode_numeric(uint8_t* buffer, uint32_t size, uint32_t dataType) {
    char typeStr[5];
    type_code_to_str(dataType, typeStr);

    if (strcmp(typeStr, "fpe2") == 0 && size >= 2) {
        uint16_t v = ((uint16_t)buffer[0] << 8) | buffer[1];
        return ((double)(int16_t)v) / 4.0;
    } else if ((strcmp(typeStr, "sp78") == 0 || strcmp(typeStr, "sp87") == 0) && size >= 2) {
        uint16_t v = ((uint16_t)buffer[0] << 8) | buffer[1];
        return ((double)(int16_t)v) / 256.0;
    } else if (strcmp(typeStr, "ui16") == 0 && size >= 2) {
        uint16_t v = ((uint16_t)buffer[0] << 8) | buffer[1];
        return (double)v;
    } else if (strcmp(typeStr, "ui32") == 0 && size >= 4) {
        uint32_t v = ((uint32_t)buffer[0] << 24) | ((uint32_t)buffer[1] << 16) | ((uint32_t)buffer[2] << 8) | buffer[3];
        return (double)v;
    } else if (strcmp(typeStr, "ui8 ") == 0 && size >= 1) {
        return (double)buffer[0];
    } else if (strcmp(typeStr, "flt ") == 0 && size >= 4) {
        uint32_t v = ((uint32_t)buffer[0]) | ((uint32_t)buffer[1] << 8) | ((uint32_t)buffer[2] << 16) | ((uint32_t)buffer[3] << 24);
        float f;
        memcpy(&f, &v, sizeof(float));
        return (double)f;
    }

    return NAN;
}

static bool read_smc_key_value(const char* key, char* outBuf, size_t outLen) {
    if (!g_conn) return false;

    uint32_t dataSize = 0;
    uint32_t dataType = 0;
    if (smc_read_key_info(g_conn, key, &dataSize, &dataType) != 0) {
        return false;
    }

    uint8_t buffer[64] = {0};
    uint32_t actualSize = 0;
    uint32_t actualType = 0;
    int result = smc_read_key(g_conn, key, buffer, dataSize, &actualSize, &actualType);
    if (result <= 0) {
        return false;
    }

    // For simplicity, format as hex bytes and best-effort decoded value
    size_t pos = 0;
    char typeStr[5];
    type_code_to_str(actualType, typeStr);

    int n = snprintf(outBuf + pos, outLen - pos, "KEY=%s SIZE=%u TYPE=%s (0x%08X) DATA=", key, actualSize, typeStr, actualType);
    if (n < 0 || (size_t)n >= outLen) return false;
    pos += (size_t)n;

    for (uint32_t i = 0; i < actualSize && pos + 3 < outLen; i++) {
        n = snprintf(outBuf + pos, outLen - pos, "%02X", buffer[i]);
        if (n < 0 || (size_t)n >= outLen) break;
        pos += (size_t)n;
        if (i + 1 < actualSize && pos + 1 < outLen) {
            outBuf[pos++] = ' ';
        }
    }
    double decoded = decode_numeric(buffer, actualSize, actualType);
    if (!isnan(decoded)) {
        n = snprintf(outBuf + pos, outLen - pos, " VALUE=%.3f", decoded);
        if (n > 0) {
            pos += (size_t)n;
        }
    }
    if (pos < outLen) outBuf[pos] = '\0';
    return true;
}

static void cleanup(void) {
    if (g_conn) {
        smc_close(g_conn);
        g_conn = NULL;
    }
    unlink(SOCKET_PATH);
}

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static double parse_power_line(const char* line) {
    // Extract first floating number
    double value = -1.0;
    const char* p = line;
    while (*p) {
        if (isdigit((unsigned char)*p) || ((*p == '.' || *p == '-') && isdigit((unsigned char)p[1]))) {
            value = strtod(p, NULL);
            break;
        }
        p++;
    }
    if (value < 0) return value;

    // If line mentions mW, convert to W
    if (strstr(line, "mW")) {
        value /= 1000.0;
    }
    return value;
}

static bool cfstring_contains(CFStringRef s, const char* needle) {
    if (!s || !needle) return false;
    CFStringRef needleStr = CFStringCreateWithCString(kCFAllocatorDefault, needle, kCFStringEncodingUTF8);
    if (!needleStr) return false;
    bool contains = CFStringFindWithOptions(s, needleStr, CFRangeMake(0, CFStringGetLength(s)), kCFCompareCaseInsensitive, NULL);
    CFRelease(needleStr);
    return contains;
}

static bool extract_power_from_cf(CFTypeRef obj, const char* needle, double* outValue) {
    if (!obj || !needle) return false;
    
    CFTypeID type = CFGetTypeID(obj);
    if (type == CFDictionaryGetTypeID()) {
        CFDictionaryRef dict = (CFDictionaryRef)obj;
        CFIndex count = CFDictionaryGetCount(dict);
        const void** keys = malloc(sizeof(void*) * count);
        const void** values = malloc(sizeof(void*) * count);
        CFDictionaryGetKeysAndValues(dict, keys, values);
        for (CFIndex i = 0; i < count; i++) {
            CFStringRef keyStr = (CFStringRef)keys[i];
            CFTypeRef val = values[i];
            if (cfstring_contains(keyStr, needle)) {
                if (CFGetTypeID(val) == CFNumberGetTypeID()) {
                    double v = 0;
                    if (CFNumberGetValue((CFNumberRef)val, kCFNumberDoubleType, &v)) {
                        *outValue = v;
                        free(keys); free(values);
                        return true;
                    }
                }
            }
            if (extract_power_from_cf(val, needle, outValue)) {
                free(keys); free(values);
                return true;
            }
        }
        free(keys);
        free(values);
    } else if (type == CFArrayGetTypeID()) {
        CFArrayRef arr = (CFArrayRef)obj;
        CFIndex count = CFArrayGetCount(arr);
        for (CFIndex i = 0; i < count; i++) {
            CFTypeRef val = CFArrayGetValueAtIndex(arr, i);
            if (extract_power_from_cf(val, needle, outValue)) {
                return true;
            }
        }
    }
    return false;
}

static int sample_powermetrics_text(double* cpu, double* gpu, double* dc) {
    FILE* fp = popen("/usr/bin/powermetrics -n 1 -i 500 --samplers cpu_power,gpu_power 2>/dev/null", "r");
    if (!fp) return -1;

    double cpuVal = -1.0, gpuVal = -1.0, dcVal = -1.0;

    char buf[512];
    while (fgets(buf, sizeof(buf), fp)) {
        if (strstr(buf, "CPU Power")) {
            double v = parse_power_line(buf);
            if (v >= 0) cpuVal = v;
        } else if (strstr(buf, "GPU Power")) {
            double v = parse_power_line(buf);
            if (v >= 0) gpuVal = v;
        } else if (strstr(buf, "Combined System Power") || strstr(buf, "System Total") || strstr(buf, "Total Power")) {
            double v = parse_power_line(buf);
            if (v >= 0) dcVal = v;
        }
    }
    pclose(fp);

    if (cpu) *cpu = cpuVal;
    if (gpu) *gpu = gpuVal;
    if (dc) *dc = dcVal;

    if (cpuVal < 0 && gpuVal < 0 && dcVal < 0) {
        return -1;
    }
    return 0;
}

static int sample_powermetrics(double* cpu, double* gpu, double* dc) {
    FILE* fp = popen("/usr/bin/powermetrics -n 1 -i 500 --samplers cpu_power,gpu_power --format plist 2>/dev/null", "r");
    if (!fp) return -1;

    // Read entire output
    size_t cap = 4096;
    size_t len = 0;
    char* data = malloc(cap);
    if (!data) {
        pclose(fp);
        return -1;
    }
    size_t nread;
    while ((nread = fread(data + len, 1, cap - len, fp)) > 0) {
        len += nread;
        if (cap - len < 1024) {
            cap *= 2;
            char* newData = realloc(data, cap);
            if (!newData) {
                free(data);
                pclose(fp);
                return -1;
            }
            data = newData;
        }
    }
    pclose(fp);

    double cpuVal = -1.0, gpuVal = -1.0, dcVal = -1.0;

    if (len > 0) {
        CFDataRef cfData = CFDataCreate(kCFAllocatorDefault, (const UInt8*)data, (CFIndex)len);
        if (cfData) {
            CFPropertyListRef plist = CFPropertyListCreateWithData(kCFAllocatorDefault, cfData, kCFPropertyListImmutable, NULL, NULL);
            if (plist) {
                extract_power_from_cf(plist, "cpu power", &cpuVal);
                extract_power_from_cf(plist, "gpu power", &gpuVal);
                extract_power_from_cf(plist, "combined system power", &dcVal);
                extract_power_from_cf(plist, "total power", &dcVal);
                CFRelease(plist);
            }
            CFRelease(cfData);
        }
    }

    free(data);

    // If plist parse failed, fall back to text sampler
    if (cpuVal < 0 && gpuVal < 0 && dcVal < 0) {
        return sample_powermetrics_text(cpu, gpu, dc);
    }

    if (cpu) *cpu = cpuVal;
    if (gpu) *gpu = gpuVal;
    if (dc) *dc = dcVal;

    if (cpuVal < 0 && gpuVal < 0 && dcVal < 0) {
        return -1;
    }
    return 0;
}

static void refresh_power_cache_if_needed(void) {
    double now = now_seconds();
    if (now - g_power_timestamp < POWER_CACHE_TTL) {
        return; // fresh enough
    }

    double cpu = -1, gpu = -1, dc = -1;
    if (sample_powermetrics(&cpu, &gpu, &dc) == 0) {
        g_cpu_power = cpu;
        g_gpu_power = gpu;
        g_dc_power = dc;
        g_power_timestamp = now;
    }
}

static void handle_client(int client_fd) {
    char buffer[1024];
    ssize_t n = read(client_fd, buffer, sizeof(buffer) - 1);
    if (n <= 0) {
        close(client_fd);
        return;
    }
    buffer[n] = '\0';
    
    char response[1024] = "ERROR: Unknown command\n";
    
    // Parse command: "set-fan <index> <rpm>"
    char cmd[64], arg1[64], arg2[64];
    int argc = sscanf(buffer, "%63s %63s %63s", cmd, arg1, arg2);
    
    if (strcmp(cmd, "check") == 0) {
        snprintf(response, sizeof(response), "OK: Helper daemon running (euid=%d)\n", geteuid());
        
    } else if (strcmp(cmd, "set-fan") == 0 && argc >= 3) {
        int fan_index = atoi(arg1);
        int rpm = atoi(arg2);
        
        int ret = smc_write_fan_target_rpm(g_conn, fan_index, rpm);
        if (ret == 0) {
            snprintf(response, sizeof(response), "OK: Set fan %d to %d RPM\n", fan_index, rpm);
        } else {
            snprintf(response, sizeof(response), "ERROR: Failed to set fan speed (error=%d)\n", ret);
        }
        
    } else if (strcmp(cmd, "set-mode") == 0 && argc >= 2) {
        bool enabled = atoi(arg1) != 0;
        
        int ret = smc_set_fan_manual(g_conn, enabled);
        if (ret == 0) {
            snprintf(response, sizeof(response), "OK: Set manual mode to %s\n", enabled ? "ON" : "OFF");
        } else {
            snprintf(response, sizeof(response), "ERROR: Failed to set manual mode (error=%d)\n", ret);
        }
    } else if (strcmp(cmd, "power") == 0) {
        refresh_power_cache_if_needed();
        snprintf(response, sizeof(response),
                 "POWER CPU=%.3f GPU=%.3f DC=%.3f TS=%.0f\n",
                 g_cpu_power, g_gpu_power, g_dc_power, g_power_timestamp);
    } else if (strcmp(cmd, "power-stream") == 0) {
        // Stream cached power values until client disconnects
        while (1) {
            refresh_power_cache_if_needed();
            int written = snprintf(response, sizeof(response),
                     "POWER CPU=%.3f GPU=%.3f DC=%.3f TS=%.0f\n",
                     g_cpu_power, g_gpu_power, g_dc_power, g_power_timestamp);
            if (write(client_fd, response, written) <= 0) {
                break;
            }
            usleep(500000); // 0.5s interval
        }
        close(client_fd);
        return;
    } else if (strcmp(cmd, "read-key") == 0 && argc >= 2) {
        char key[5] = {0};
        strncpy(key, arg1, 4);
        char buf[256];
        if (read_smc_key_value(key, buf, sizeof(buf))) {
            snprintf(response, sizeof(response), "OK %s\n", buf);
        } else {
            snprintf(response, sizeof(response), "ERROR: Failed to read key %s\n", key);
        }
    }
    
    write(client_fd, response, strlen(response));
    close(client_fd);
}

static void* client_thread(void* arg) {
    int client_fd = *(int*)arg;
    free(arg);
    handle_client(client_fd);
    return NULL;
}

static void run_daemon(void) {
    int server_fd;
    struct sockaddr_un addr;
    
    // Open SMC connection once
    g_conn = smc_open();
    if (!g_conn) {
        fprintf(stderr, "ERROR: Failed to open SMC connection\n");
        exit(2);
    }
    
    // Create socket
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        exit(3);
    }
    
    // Remove existing socket
    unlink(SOCKET_PATH);
    
    // Bind socket
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);
    
    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind");
        exit(4);
    }
    
    // Make socket accessible to all users
    chmod(SOCKET_PATH, 0666);
    
    // Listen
    if (listen(server_fd, 5) < 0) {
        perror("listen");
        exit(5);
    }
    
    fprintf(stderr, "Daemon started, listening on %s\n", SOCKET_PATH);
    
    // Accept connections
    while (1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            break;
        }
        
        int* fdPtr = malloc(sizeof(int));
        if (!fdPtr) {
            close(client_fd);
            continue;
        }
        *fdPtr = client_fd;
        
        pthread_t tid;
        if (pthread_create(&tid, NULL, client_thread, fdPtr) == 0) {
            pthread_detach(tid);
        } else {
            free(fdPtr);
            handle_client(client_fd);
        }
    }
    
    close(server_fd);
}

int main(int argc, char* argv[]) {
    // Helper must run as root
    if (geteuid() != 0) {
        fprintf(stderr, "ERROR: Helper must run as root\n");
        return 1;
    }
    
    atexit(cleanup);
    run_daemon();
    
    return 0;
}
