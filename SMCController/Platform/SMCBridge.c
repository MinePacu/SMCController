//
//  SMCBridge.c
//  SMCController
//

#include "SMCBridge.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOReturn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_error.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>  // for geteuid()

// Debug logging (set to 0 to disable)
#define SMC_DEBUG 1
#define SMC_DEBUG_READ 0  // Disable read operation logs
#define SMC_DEBUG_WRITE 1 // Keep write operation logs

#if SMC_DEBUG && SMC_DEBUG_READ
#define SMC_LOG_READ(fmt, ...) fprintf(stderr, "[SMC] " fmt "\n", ##__VA_ARGS__)
#else
#define SMC_LOG_READ(fmt, ...)
#endif

#if SMC_DEBUG && SMC_DEBUG_WRITE
#define SMC_LOG_WRITE(fmt, ...) fprintf(stderr, "[SMC] " fmt "\n", ##__VA_ARGS__)
#else
#define SMC_LOG_WRITE(fmt, ...)
#endif

#if SMC_DEBUG
#define SMC_LOG(fmt, ...) fprintf(stderr, "[SMC] " fmt "\n", ##__VA_ARGS__)
#else
#define SMC_LOG(fmt, ...)
#endif

// Convert kern_return_t to human-readable string
static const char* kern_return_name(kern_return_t kr) {
    switch (kr) {
        case KERN_SUCCESS: return "KERN_SUCCESS";
        case KERN_INVALID_ADDRESS: return "KERN_INVALID_ADDRESS";
        case KERN_PROTECTION_FAILURE: return "KERN_PROTECTION_FAILURE";
        case KERN_NO_SPACE: return "KERN_NO_SPACE";
        case KERN_INVALID_ARGUMENT: return "KERN_INVALID_ARGUMENT";
        case KERN_FAILURE: return "KERN_FAILURE";
        case kIOReturnError: return "kIOReturnError";
        case kIOReturnNoMemory: return "kIOReturnNoMemory";
        case kIOReturnNoResources: return "kIOReturnNoResources";
        case kIOReturnIPCError: return "kIOReturnIPCError";
        case kIOReturnNoDevice: return "kIOReturnNoDevice";
        case kIOReturnNotPrivileged: return "kIOReturnNotPrivileged";
        case kIOReturnBadArgument: return "kIOReturnBadArgument";
        case kIOReturnLockedRead: return "kIOReturnLockedRead";
        case kIOReturnLockedWrite: return "kIOReturnLockedWrite";
        case kIOReturnExclusiveAccess: return "kIOReturnExclusiveAccess";
        case kIOReturnBadMessageID: return "kIOReturnBadMessageID";
        case kIOReturnUnsupported: return "kIOReturnUnsupported";
        case kIOReturnVMError: return "kIOReturnVMError";
        case kIOReturnInternalError: return "kIOReturnInternalError";
        case kIOReturnIOError: return "kIOReturnIOError";
        case kIOReturnCannotLock: return "kIOReturnCannotLock";
        case kIOReturnNotOpen: return "kIOReturnNotOpen";
        case kIOReturnNotReadable: return "kIOReturnNotReadable";
        case kIOReturnNotWritable: return "kIOReturnNotWritable";
        case kIOReturnNotAligned: return "kIOReturnNotAligned";
        case kIOReturnBadMedia: return "kIOReturnBadMedia";
        case kIOReturnStillOpen: return "kIOReturnStillOpen";
        case kIOReturnRLDError: return "kIOReturnRLDError";
        case kIOReturnDMAError: return "kIOReturnDMAError";
        case kIOReturnBusy: return "kIOReturnBusy";
        case kIOReturnTimeout: return "kIOReturnTimeout";
        case kIOReturnOffline: return "kIOReturnOffline";
        case kIOReturnNotReady: return "kIOReturnNotReady";
        case kIOReturnNotAttached: return "kIOReturnNotAttached";
        case kIOReturnNoChannels: return "kIOReturnNoChannels";
        case kIOReturnNoSpace: return "kIOReturnNoSpace";
        case kIOReturnPortExists: return "kIOReturnPortExists";
        case kIOReturnCannotWire: return "kIOReturnCannotWire";
        case kIOReturnNoInterrupt: return "kIOReturnNoInterrupt";
        case kIOReturnNoFrames: return "kIOReturnNoFrames";
        case kIOReturnMessageTooLarge: return "kIOReturnMessageTooLarge";
        case kIOReturnNotPermitted: return "kIOReturnNotPermitted";
        case kIOReturnNoPower: return "kIOReturnNoPower";
        case kIOReturnNoMedia: return "kIOReturnNoMedia";
        case kIOReturnUnformattedMedia: return "kIOReturnUnformattedMedia";
        case kIOReturnUnsupportedMode: return "kIOReturnUnsupportedMode";
        case kIOReturnUnderrun: return "kIOReturnUnderrun";
        case kIOReturnOverrun: return "kIOReturnOverrun";
        case kIOReturnDeviceError: return "kIOReturnDeviceError";
        case kIOReturnNoCompletion: return "kIOReturnNoCompletion";
        case kIOReturnAborted: return "kIOReturnAborted";
        case kIOReturnNoBandwidth: return "kIOReturnNoBandwidth";
        case kIOReturnNotResponding: return "kIOReturnNotResponding";
        case kIOReturnIsoTooOld: return "kIOReturnIsoTooOld";
        case kIOReturnIsoTooNew: return "kIOReturnIsoTooNew";
        case kIOReturnNotFound: return "kIOReturnNotFound";
        case kIOReturnInvalid: return "kIOReturnInvalid";
        default: return "UNKNOWN";
    }
}

// SMC structures - based on iSMC (https://github.com/dkorunic/iSMC)
// GPL v3 License - structure definitions for Apple SMC interoperabilityb
typedef struct {
    uint8_t  major;
    uint8_t  minor;
    uint8_t  build;
    uint8_t  reserved[1];
    uint16_t release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;
    
typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyData_keyInfo_t;

typedef uint8_t SMCBytes_t[32];

typedef struct {
    uint32_t                key;
    SMCKeyData_vers_t       vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t    keyInfo;
    uint8_t                 result;
    uint8_t                 status;
    uint8_t                 data8;
    uint32_t                data32;
    SMCBytes_t              bytes;
} SMCKeyData_t;

enum {
    kSMCUserClientOpen  = 0,
    kSMCUserClientClose = 1,
    kSMCHandleYPCEvent  = 2,
};

enum {
    kSMCCommandReadBytes     = 5,
    kSMCCommandWriteBytes    = 6,
    kSMCCommandReadIndex     = 8,
    kSMCCommandReadKeyInfo   = 9,
    kSMCCommandReadPLimit    = 11,
    kSMCCommandReadVersion   = 12
};

static kern_return_t call_smc(struct SMCConnection* c, SMCKeyData_t* in, SMCKeyData_t* out) {
    size_t inSize = sizeof(SMCKeyData_t);
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(c->conn, kSMCHandleYPCEvent, in, inSize, out, &outSize);
}

static uint32_t str_to_key(const char key[4]) {
    return ((uint32_t)key[0] << 24) | ((uint32_t)key[1] << 16) | ((uint32_t)key[2] << 8) | ((uint32_t)key[3]);
}

static int smc_get_key_info(struct SMCConnection* c, uint32_t key, SMCKeyData_keyInfo_t* outInfo) {
    if (!c) {
        SMC_LOG_READ("ERROR: smc_get_key_info called with NULL connection");
        return -1;
    }
    SMCKeyData_t in = {0}, out = {0};
    in.key = key;
    in.data8 = kSMCCommandReadKeyInfo;
    
    char keyStr[5];
    keyStr[0] = (key >> 24) & 0xFF;
    keyStr[1] = (key >> 16) & 0xFF;
    keyStr[2] = (key >> 8) & 0xFF;
    keyStr[3] = key & 0xFF;
    keyStr[4] = '\0';
    
    kern_return_t kr = call_smc(c, &in, &out);
    if (kr != KERN_SUCCESS) {
        SMC_LOG_READ("ERROR: smc_get_key_info('%s') failed: 0x%08x (%s) - %s, result=%u, status=%u", 
                keyStr, kr, kern_return_name(kr), mach_error_string(kr), out.result, out.status);
        return -1;
    }
    SMC_LOG_READ("smc_get_key_info('%s') succeeded: dataSize=%u, dataType=0x%08x, result=%u, status=%u", 
            keyStr, out.keyInfo.dataSize, out.keyInfo.dataType, out.result, out.status);
    *outInfo = out.keyInfo;
    return 0;
}

SMCConnection* smc_open(void) {
    SMC_LOG_READ("Attempting to open SMC connection...");
    SMC_LOG_READ("SMCKeyData_t structure size: %zu bytes (should be 80 on Apple Silicon)", sizeof(SMCKeyData_t));
    SMC_LOG_READ("Key offsets: key=%zu, data8=%zu, bytes=%zu", 
            offsetof(SMCKeyData_t, key), offsetof(SMCKeyData_t, data8), offsetof(SMCKeyData_t, bytes));
    
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) {
        SMC_LOG_READ("ERROR: IOServiceGetMatchingService failed - AppleSMC service not found");
        return NULL;
    }
    SMC_LOG_READ("AppleSMC service found: 0x%x", service);
    
    io_connect_t connect = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connect);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) {
        SMC_LOG_READ("ERROR: IOServiceOpen failed: 0x%08x (%s) - %s", 
                result, kern_return_name(result), mach_error_string(result));
        return NULL;
    }
    SMC_LOG_READ("IOServiceOpen succeeded, connection: 0x%x", connect);

    struct SMCConnection* c = (struct SMCConnection*)calloc(1, sizeof(struct SMCConnection));
    if (!c) {
        SMC_LOG_READ("ERROR: calloc failed for SMCConnection");
        IOServiceClose(connect);
        return NULL;
    }
    c->conn = connect;
    SMC_LOG_READ("SMC connection opened successfully");
    return c;
}

void smc_close(SMCConnection* c) {
    if (!c) return;
    if (c->conn != IO_OBJECT_NULL) {
        IOServiceClose(c->conn);
    }
    free(c);
}

int smc_read_key(SMCConnection* c, const char keyStr[4], uint8_t* outBuf, uint32_t outBufSize, uint32_t* outDataSize, uint32_t* outDataType) {
    if (!c || !outBuf) {
        SMC_LOG_READ("ERROR: smc_read_key called with NULL pointer");
        return -1;
    }
    
    char keyStrSafe[5] = {keyStr[0], keyStr[1], keyStr[2], keyStr[3], '\0'};
    (void)keyStrSafe;
    SMC_LOG_READ("Reading key '%s'...", keyStrSafe);
    
    uint32_t key = str_to_key(keyStr);
    SMCKeyData_keyInfo_t info;
    if (smc_get_key_info(c, key, &info) != 0) {
        SMC_LOG_READ("ERROR: Failed to get key info for '%s'", keyStrSafe);
        return -1;
    }

    SMCKeyData_t in = {0}, out = {0};
    in.key = key;
    in.keyInfo = info;
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = kSMCCommandReadBytes;
    kern_return_t kr = call_smc(c, &in, &out);
    if (kr != KERN_SUCCESS) {
        SMC_LOG_READ("ERROR: kSMCCommandReadBytes for '%s' failed: 0x%08x (%s) - %s, result=%u, status=%u", 
                keyStrSafe, kr, kern_return_name(kr), mach_error_string(kr), out.result, out.status);
        return -1;
    }

    // Use the input keyInfo size/type, not output (output keyInfo is not populated)
    uint32_t size = info.dataSize;
    if (outDataSize) *outDataSize = size;
    uint32_t dtype = info.dataType;
    if (outDataType) *outDataType = dtype;

    if (size > outBufSize) size = outBufSize;
    memcpy(outBuf, out.bytes, size);
    
    SMC_LOG_READ("Successfully read key '%s': size=%u, type=0x%08x, data[0-3]=0x%02x%02x%02x%02x", 
            keyStrSafe, size, dtype, 
            size > 0 ? out.bytes[0] : 0, 
            size > 1 ? out.bytes[1] : 0,
            size > 2 ? out.bytes[2] : 0,
            size > 3 ? out.bytes[3] : 0);
    
    return (int)size;
}

int smc_write_key(SMCConnection* c, const char keyStr[4], const uint8_t* inBuf, uint32_t inSize, uint32_t dataType) {
    if (!c || !inBuf) return -1;
    uint32_t key = str_to_key(keyStr);

    char keyStrPrint[5] = {keyStr[0], keyStr[1], keyStr[2], keyStr[3], '\0'};
    SMC_LOG_WRITE("Writing key '%s': size=%d, type=0x%08x, data[0-1]=0x%02x%02x", 
            keyStrPrint, inSize, dataType, 
            inSize >= 1 ? inBuf[0] : 0, 
            inSize >= 2 ? inBuf[1] : 0);

    SMCKeyData_t in = {0}, out = {0};
    in.key = key;
    in.data8 = kSMCCommandWriteBytes;
    in.keyInfo.dataSize = inSize;
    in.keyInfo.dataType = dataType;
    uint32_t size = inSize > sizeof(in.bytes) ? sizeof(in.bytes) : inSize;
    memcpy(in.bytes, inBuf, size);
    kern_return_t kr = call_smc(c, &in, &out);
    
    if (kr != KERN_SUCCESS) {
        SMC_LOG_WRITE("Write failed for key '%s': %s (0x%x)", keyStrPrint, kern_return_name(kr), kr);
        return -1;
    }
    
    SMC_LOG_WRITE("Successfully wrote key '%s'", keyStrPrint);
    return 0;
}

static uint16_t __attribute__((unused)) encode_fpe2_from_double(double v) {
    if (v < 0) v = 0;
    if (v > 16383.75) v = 16383.75;
    return (uint16_t)llround(v * 4.0);
}

int smc_read_fan_count(SMCConnection* c) {
    SMC_LOG_READ("Reading fan count (FNum)...");
    uint8_t buf[32] = {0};
    uint32_t size=0, dtype=0;
    if (smc_read_key(c, "FNum", buf, sizeof(buf), &size, &dtype) < 0) {
        SMC_LOG_READ("ERROR: Failed to read FNum key");
        return -1;
    }
    if (size < 1) {
        SMC_LOG_READ("ERROR: FNum returned size < 1 (size=%u)", size);
        return -1;
    }
    SMC_LOG_READ("Fan count: %u", buf[0]);
    return buf[0];
}

int smc_write_fan_target_rpm(SMCConnection* c, uint32_t fanIndex, int rpm) {
    if (fanIndex > 9) return -1;
    char keyTg[4] = {'F', '0' + (char)fanIndex, 'T', 'g'};
    
    SMC_LOG_WRITE("========================================");
    SMC_LOG_WRITE("Writing Fan %d Target RPM: %d", fanIndex, rpm);
    SMC_LOG_WRITE("Method: Stats read-modify-write pattern");
    SMC_LOG_WRITE("========================================");
    
    // === Stats Method: Read current value first ===
    uint8_t currentBuf[32] = {0};
    uint32_t currentSize = 0, currentType = 0;
    
    int readResult = smc_read_key(c, keyTg, currentBuf, sizeof(currentBuf), &currentSize, &currentType);
    if (readResult <= 0) {
        SMC_LOG_WRITE("❌ Failed to read F%dTg (cannot determine type)", fanIndex);
        return -1;
    }
    
    // Log current value info
    char typeStr[5] = {
        (currentType >> 24) & 0xFF,
        (currentType >> 16) & 0xFF,
        (currentType >> 8) & 0xFF,
        currentType & 0xFF,
        0
    };
    
    // Decode current RPM
    int currentRPM = -1;
    if (currentType == ('f'<<24|'l'<<16|'t'<<8|' ') && currentSize >= 4) {
        float rpmFloat;
        memcpy(&rpmFloat, currentBuf, 4);
        currentRPM = (int)rpmFloat;
    } else if (currentType == ('f'<<24|'p'<<16|'e'<<8|'2') && currentSize >= 2) {
        uint16_t raw = (currentBuf[0] << 8) | currentBuf[1];
        currentRPM = (int)llround(raw / 4.0);
    } else if (currentType == ('u'<<24|'i'<<16|'1'<<8|'6') && currentSize >= 2) {
        currentRPM = (currentBuf[0] << 8) | currentBuf[1];
    }
    
    SMC_LOG_WRITE("📊 Before write:");
    SMC_LOG_WRITE("   F%dTg type='%s' (0x%08x), size=%u", fanIndex, typeStr, currentType, currentSize);
    SMC_LOG_WRITE("   Current target RPM: %d", currentRPM);
    
    // Prepare new bytes based on detected type
    uint8_t newBytes[32] = {0};
    memcpy(newBytes, currentBuf, currentSize); // Start with current data
    
    // Modify only the RPM bytes based on type
    if (currentType == ('f'<<24|'l'<<16|'t'<<8|' ')) {
        // flt (float) type
        float rpmFloat = (float)rpm;
        memcpy(newBytes, &rpmFloat, 4);
        SMC_LOG_WRITE("🔧 Encoding as flt: %f → bytes[0x%02x %02x %02x %02x]", 
                     rpmFloat, newBytes[0], newBytes[1], newBytes[2], newBytes[3]);
    } else if (currentType == ('f'<<24|'p'<<16|'e'<<8|'2')) {
        // fpe2 type (fixed point divide by 4)
        uint16_t encoded = (uint16_t)llround((double)rpm * 4.0);
        newBytes[0] = (encoded >> 8) & 0xFF;
        newBytes[1] = encoded & 0xFF;
        SMC_LOG_WRITE("🔧 Encoding as fpe2: %d * 4 = 0x%04x → bytes[0x%02x %02x]", 
                     rpm, encoded, newBytes[0], newBytes[1]);
    } else if (currentType == ('u'<<24|'i'<<16|'1'<<8|'6')) {
        // ui16 type (unsigned 16-bit)
        uint16_t encoded = (uint16_t)rpm;
        newBytes[0] = (encoded >> 8) & 0xFF;
        newBytes[1] = encoded & 0xFF;
        SMC_LOG_WRITE("🔧 Encoding as ui16: %d = 0x%04x → bytes[0x%02x %02x]", 
                     rpm, encoded, newBytes[0], newBytes[1]);
    } else {
        SMC_LOG_WRITE("⚠️ Unknown type '%s', trying fpe2 encoding anyway", typeStr);
        uint16_t encoded = (uint16_t)llround((double)rpm * 4.0);
        newBytes[0] = (encoded >> 8) & 0xFF;
        newBytes[1] = encoded & 0xFF;
    }
    
    // === Write with the SAME type and size as we read ===
    SMC_LOG_WRITE("📝 Writing to F%dTg...", fanIndex);
    int writeResult = smc_write_key(c, keyTg, newBytes, currentSize, currentType);
    if (writeResult != 0) {
        SMC_LOG_WRITE("❌ Write to F%dTg FAILED", fanIndex);
        return -1;
    }
    
    SMC_LOG_WRITE("✅ Write to F%dTg completed successfully", fanIndex);
    
    // === Wait for SMC to apply changes (100ms) ===
    SMC_LOG_WRITE("⏳ Waiting 100ms for SMC to apply changes...");
    usleep(100000); // 100 milliseconds
    
    // === Verify by reading back ===
    SMC_LOG_WRITE("🔍 Verifying write by reading back F%dTg...", fanIndex);
    uint8_t verifyBuf[32] = {0};
    uint32_t verifySize = 0, verifyType = 0;
    if (smc_read_key(c, keyTg, verifyBuf, sizeof(verifyBuf), &verifySize, &verifyType) > 0) {
        int verifiedRPM = -1;
        
        if (verifyType == ('f'<<24|'l'<<16|'t'<<8|' ') && verifySize >= 4) {
            float rpmFloat;
            memcpy(&rpmFloat, verifyBuf, 4);
            verifiedRPM = (int)rpmFloat;
        } else if (verifyType == ('f'<<24|'p'<<16|'e'<<8|'2') && verifySize >= 2) {
            uint16_t raw = (verifyBuf[0] << 8) | verifyBuf[1];
            verifiedRPM = (int)llround(raw / 4.0);
        } else if (verifyType == ('u'<<24|'i'<<16|'1'<<8|'6') && verifySize >= 2) {
            verifiedRPM = (verifyBuf[0] << 8) | verifyBuf[1];
        }
        
        SMC_LOG_WRITE("📊 After write:");
        SMC_LOG_WRITE("   F%dTg target RPM: %d (expected %d)", fanIndex, verifiedRPM, rpm);
        
        int diff = abs(verifiedRPM - rpm);
        if (diff <= 10) {
            SMC_LOG_WRITE("✅ VERIFICATION SUCCESSFUL! (diff: %d RPM)", diff);
            SMC_LOG_WRITE("========================================");
            return 0;
        } else {
            SMC_LOG_WRITE("⚠️ WARNING: Read-back differs by %d RPM!", diff);
            SMC_LOG_WRITE("   This may indicate SMC ignored the write");
            SMC_LOG_WRITE("========================================");
            return -1;
        }
    } else {
        SMC_LOG_WRITE("⚠️ Could not read back F%dTg for verification", fanIndex);
        SMC_LOG_WRITE("========================================");
    }
    
    return 0;
}

int smc_set_fan_manual(SMCConnection* c, bool enabled) {
    SMC_LOG_WRITE("========================================");
    SMC_LOG_WRITE("Setting manual mode: %s", enabled ? "ENABLED" : "DISABLED");
    SMC_LOG_WRITE("Method: Stats read-modify-write pattern");
    SMC_LOG_WRITE("========================================");
    
    bool f0md_success = false;
    bool fs_success = false;
    
    // === Try method 1: F0Md (Fan 0 Mode) ===
    char keyFanMode[4] = {'F', '0', 'M', 'd'};
    
    SMC_LOG_WRITE("🔍 Attempting method 1: F0Md (per-fan mode)...");
    
    // Read current F0Md value first
    uint8_t currentBuf[32] = {0};
    uint32_t currentSize = 0, currentType = 0;
    
    int readResult = smc_read_key(c, keyFanMode, currentBuf, sizeof(currentBuf), &currentSize, &currentType);
    if (readResult > 0) {
        SMC_LOG_WRITE("   📊 Current F0Md: value=0x%02x, type=0x%08x, size=%u", 
                     currentBuf[0], currentType, currentSize);
        
        // Modify only the mode byte
        uint8_t oldValue = currentBuf[0];
        currentBuf[0] = enabled ? 1 : 0;
        
        SMC_LOG_WRITE("   🔧 Changing F0Md: 0x%02x → 0x%02x", oldValue, currentBuf[0]);
        
        // Write back with same type and size
        int writeResult = smc_write_key(c, keyFanMode, currentBuf, currentSize, currentType);
        if (writeResult == 0) {
            SMC_LOG_WRITE("   ✅ F0Md write successful");
            
            // Wait for SMC to apply
            SMC_LOG_WRITE("   ⏳ Waiting 50ms for SMC...");
            usleep(50000); // 50ms
            
            // Verify
            uint8_t verifyBuf[32] = {0};
            uint32_t verifySize = 0, verifyType = 0;
            if (smc_read_key(c, keyFanMode, verifyBuf, sizeof(verifyBuf), &verifySize, &verifyType) > 0 && verifySize >= 1) {
                SMC_LOG_WRITE("   📊 F0Md read-back: 0x%02x (expected 0x%02x)", verifyBuf[0], currentBuf[0]);
                if (verifyBuf[0] == currentBuf[0]) {
                    SMC_LOG_WRITE("   ✅✅ F0Md VERIFICATION SUCCESSFUL!");
                    f0md_success = true;
                } else {
                    SMC_LOG_WRITE("   ⚠️ F0Md verification failed (differs by %d)", 
                                 abs((int)verifyBuf[0] - (int)currentBuf[0]));
                }
            }
        } else {
            SMC_LOG_WRITE("   ❌ F0Md write failed");
        }
    } else {
        SMC_LOG_WRITE("   ⚠️ F0Md not readable on this system");
    }
    
    // === Try method 2: FS! (global fan manual mode) ===
    SMC_LOG_WRITE("🔍 Attempting method 2: FS! (global mode)...");
    
    char keyGlobal[4] = {'F','S','!',' '};
    
    readResult = smc_read_key(c, keyGlobal, currentBuf, sizeof(currentBuf), &currentSize, &currentType);
    if (readResult > 0) {
        SMC_LOG_WRITE("   📊 Current FS!: bytes[0x%02x 0x%02x], type=0x%08x, size=%u", 
                     currentBuf[0], currentBuf[1], currentType, currentSize);
        
        // Save old values
        uint8_t oldByte0 = currentBuf[0];
        uint8_t oldByte1 = currentSize >= 2 ? currentBuf[1] : 0;
        
        // Modify the mode byte
        // FS! uses byte[1] for mode (0=auto, 1=fan0 manual, 2=fan1 manual, 3=both manual)
        if (currentSize >= 2) {
            currentBuf[1] = enabled ? 1 : 0;  // Simplified: just fan 0 manual mode
            SMC_LOG_WRITE("   🔧 Changing FS![1]: 0x%02x → 0x%02x", oldByte1, currentBuf[1]);
        } else {
            currentBuf[0] = enabled ? 1 : 0;
            SMC_LOG_WRITE("   🔧 Changing FS![0]: 0x%02x → 0x%02x", oldByte0, currentBuf[0]);
        }
        
        // Write back with same type and size
        int writeResult = smc_write_key(c, keyGlobal, currentBuf, currentSize, currentType);
        if (writeResult == 0) {
            SMC_LOG_WRITE("   ✅ FS! write successful");
            
            // Wait for SMC to apply
            SMC_LOG_WRITE("   ⏳ Waiting 50ms for SMC...");
            usleep(50000); // 50ms
            
            // Verify
            uint8_t verifyBuf[32] = {0};
            uint32_t verifySize = 0, verifyType = 0;
            if (smc_read_key(c, keyGlobal, verifyBuf, sizeof(verifyBuf), &verifySize, &verifyType) > 0) {
                SMC_LOG_WRITE("   📊 FS! read-back: bytes[0x%02x 0x%02x] (expected [0x%02x 0x%02x])", 
                             verifyBuf[0], verifyBuf[1], currentBuf[0], currentBuf[1]);
                
                if (verifySize >= 2 && verifyBuf[1] == currentBuf[1]) {
                    SMC_LOG_WRITE("   ✅✅ FS! VERIFICATION SUCCESSFUL!");
                    fs_success = true;
                } else if (verifySize == 1 && verifyBuf[0] == currentBuf[0]) {
                    SMC_LOG_WRITE("   ✅✅ FS! VERIFICATION SUCCESSFUL!");
                    fs_success = true;
                } else {
                    SMC_LOG_WRITE("   ⚠️ FS! verification failed");
                }
            }
        } else {
            SMC_LOG_WRITE("   ❌ FS! write failed");
        }
    } else {
        SMC_LOG_WRITE("   ⚠️ FS! not readable on this system");
    }
    
    // === Summary ===
    SMC_LOG_WRITE("========================================");
    SMC_LOG_WRITE("📋 Manual Mode Setting Summary:");
    SMC_LOG_WRITE("   F0Md (per-fan): %s", f0md_success ? "✅ SUCCESS" : "❌ Failed");
    SMC_LOG_WRITE("   FS!  (global):  %s", fs_success ? "✅ SUCCESS" : "❌ Failed");
    
    if (f0md_success || fs_success) {
        SMC_LOG_WRITE("🎉 At least one method succeeded!");
        SMC_LOG_WRITE("========================================");
        return 0;
    } else {
        SMC_LOG_WRITE("❌ Both methods failed - manual mode may not be supported");
        SMC_LOG_WRITE("========================================");
        return -1;
    }
}

// Debug function: Read SMC key info (dataSize and dataType)
int smc_read_key_info(SMCConnection* c, const char keyStr[4], uint32_t* outDataSize, uint32_t* outDataType) {
    if (!c) return -1;
    
    uint32_t key = str_to_key(keyStr);
    SMCKeyData_t in = {0}, out = {0};
    
    in.key = key;
    in.data8 = kSMCCommandReadKeyInfo;
    
    kern_return_t kr = call_smc(c, &in, &out);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    if (outDataSize) *outDataSize = out.keyInfo.dataSize;
    if (outDataType) *outDataType = out.keyInfo.dataType;
    
    return 0;
}

// Check if we have write access to SMC
// Returns 0 if we have write access, non-zero otherwise
int smc_check_write_access(SMCConnection* conn) {
    if (!conn || !conn->conn) {
        SMC_LOG_WRITE("❌ smc_check_write_access: invalid connection\n");
        return -1;
    }
    
    // Try to read a write-controlled key (F0Tg - Fan 0 Target RPM)
    // If we can read this, we likely have the necessary privileges
    const char* testKey = "F0Tg";
    uint32_t dataSize = 0, dataType = 0;
    
    int result = smc_read_key_info(conn, testKey, &dataSize, &dataType);
    
    if (result == 0 && dataSize > 0) {
        SMC_LOG_WRITE("✅ smc_check_write_access: Can read fan control key info\n");
        
        // Additional check: verify we're running with elevated privileges
        if (geteuid() == 0) {
            SMC_LOG_WRITE("✅ smc_check_write_access: Running as root (euid=0)\n");
            return 0;
        } else {
            SMC_LOG_WRITE("⚠️ smc_check_write_access: Not running as root (euid=%d)\n", geteuid());
            return -2;
        }
    } else {
        SMC_LOG_WRITE("❌ smc_check_write_access: Cannot read fan control key (result=%d)\n", result);
        return -3;
    }
}
