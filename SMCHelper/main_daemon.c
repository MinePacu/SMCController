//
//  main_daemon.c
//  SMCHelper
//
//  Root launchd helper. Requests are accepted only over the declared XPC Mach
//  service after launchd/XPC has checked the installed application's signing
//  requirement.
//

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <xpc/xpc.h>

#include "RequestValidation.h"
#include "SMCBridge.h"

#define HELPER_MACH_SERVICE "com.minepacu.SMCHelper"
#define HELPER_PROTOCOL_VERSION 2
#define HELPER_VERSION "2.0"
#define CLIENT_CONFIG_PATH "/Library/PrivilegedHelperTools/com.minepacu.SMCHelper.client-requirement.plist"
#define CLIENT_IDENTIFIER "com.minepacu.SMCController"
#define MAX_CONFIG_SIZE (64 * 1024)
#define POWER_CACHE_TTL 3.0
#define ERROR_INVALID_REQUEST "invalidRequest"
#define ERROR_OUT_OF_RANGE "outOfRange"
#define ERROR_HARDWARE_UNAVAILABLE "hardwareUnavailable"
#define ERROR_SMC_FAILURE "smcFailure"
#define ERROR_INCOMPATIBLE_VERSION "incompatibleVersion"
#define WATCHDOG_RETRY_SECONDS 5
#define NANOSECONDS_PER_SECOND UINT64_C(1000000000)

static SMCConnection *g_connection = NULL;
static dispatch_queue_t g_smc_queue = NULL;
static dispatch_source_t g_watchdog_timer = NULL;
static smc_helper_lease g_manual_lease = {0};
static double g_cpu_power = -1.0;
static double g_gpu_power = -1.0;
static double g_dc_power = -1.0;
static double g_power_timestamp = 0.0;

static void disable_watchdog_timer(void) {
    if (g_watchdog_timer != NULL) {
        dispatch_source_set_timer(g_watchdog_timer,
                                  DISPATCH_TIME_FOREVER,
                                  DISPATCH_TIME_FOREVER,
                                  0);
    }
}

static uint64_t monotonic_nanoseconds(void) {
    struct timespec timestamp = {0};
    if (clock_gettime(CLOCK_MONOTONIC, &timestamp) != 0 || timestamp.tv_sec < 0 ||
        timestamp.tv_nsec < 0) {
        return 0;
    }

    uint64_t seconds = (uint64_t)timestamp.tv_sec;
    if (seconds > UINT64_MAX / NANOSECONDS_PER_SECOND) {
        return UINT64_MAX;
    }
    uint64_t base = seconds * NANOSECONDS_PER_SECOND;
    uint64_t nanoseconds = (uint64_t)timestamp.tv_nsec;
    return UINT64_MAX - base < nanoseconds ? UINT64_MAX : base + nanoseconds;
}

static void cleanup(void) {
    if (g_watchdog_timer != NULL) {
        dispatch_source_cancel(g_watchdog_timer);
        g_watchdog_timer = NULL;
    }
    if (g_connection != NULL) {
        // The normal launchd teardown path gets one final best-effort return
        // to automatic control. A crash is covered by the active lease timer.
        (void)smc_set_fan_manual(g_connection, false);
        smc_close(g_connection);
        g_connection = NULL;
    }
}

static bool read_all(int fd, void *buffer, size_t length) {
    uint8_t *cursor = buffer;
    while (length > 0) {
        ssize_t count = read(fd, cursor, length);
        if (count == 0) {
            return false;
        }
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        cursor += count;
        length -= (size_t)count;
    }
    return true;
}

// Loads only a root-owned, private, regular file. The lstat/fstat comparison
// prevents an attacker from replacing the file between inspection and open.
static char *copy_installed_client_requirement(void) {
    struct stat before = {0};
    if (lstat(CLIENT_CONFIG_PATH, &before) != 0 || !S_ISREG(before.st_mode) ||
        before.st_uid != 0 || before.st_nlink != 1 || (before.st_mode & 0077) != 0 ||
        before.st_size <= 0 || before.st_size > MAX_CONFIG_SIZE) {
        return NULL;
    }

    int fd = open(CLIENT_CONFIG_PATH, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        return NULL;
    }

    struct stat after = {0};
    bool valid_file = fstat(fd, &after) == 0 && S_ISREG(after.st_mode) &&
                      after.st_uid == 0 && after.st_nlink == 1 &&
                      (after.st_mode & 0077) == 0 && after.st_dev == before.st_dev &&
                      after.st_ino == before.st_ino && after.st_size == before.st_size;
    if (!valid_file) {
        close(fd);
        return NULL;
    }

    CFIndex length = (CFIndex)after.st_size;
    UInt8 *bytes = calloc((size_t)length, sizeof(*bytes));
    if (bytes == NULL || !read_all(fd, bytes, (size_t)length)) {
        free(bytes);
        close(fd);
        return NULL;
    }
    close(fd);

    CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, length);
    free(bytes);
    if (data == NULL) {
        return NULL;
    }

    CFErrorRef error = NULL;
    CFPropertyListRef plist = CFPropertyListCreateWithData(kCFAllocatorDefault,
                                                             data,
                                                             kCFPropertyListImmutable,
                                                             NULL,
                                                             &error);
    CFRelease(data);
    if (error != NULL) {
        CFRelease(error);
    }
    if (plist == NULL || CFGetTypeID(plist) != CFDictionaryGetTypeID()) {
        if (plist != NULL) {
            CFRelease(plist);
        }
        return NULL;
    }

    CFDictionaryRef dictionary = (CFDictionaryRef)plist;
    CFTypeRef format_version = CFDictionaryGetValue(dictionary, CFSTR("FormatVersion"));
    CFTypeRef identifier = CFDictionaryGetValue(dictionary, CFSTR("Identifier"));
    CFTypeRef requirement = CFDictionaryGetValue(dictionary, CFSTR("Requirement"));
    char identifier_buffer[sizeof(CLIENT_IDENTIFIER)] = {0};
    char *result = NULL;
    int version = 0;

    if (format_version != NULL && identifier != NULL && requirement != NULL &&
        CFGetTypeID(format_version) == CFNumberGetTypeID() &&
        CFGetTypeID(identifier) == CFStringGetTypeID() &&
        CFGetTypeID(requirement) == CFStringGetTypeID() &&
        CFNumberGetValue((CFNumberRef)format_version, kCFNumberIntType, &version) && version == 2 &&
        CFStringGetCString((CFStringRef)identifier,
                           identifier_buffer,
                           sizeof(identifier_buffer),
                           kCFStringEncodingUTF8) &&
        strcmp(identifier_buffer, CLIENT_IDENTIFIER) == 0) {
        CFIndex maximum_length = CFStringGetMaximumSizeForEncoding(
            CFStringGetLength((CFStringRef)requirement), kCFStringEncodingUTF8);
        if (maximum_length > 0 && maximum_length < MAX_CONFIG_SIZE) {
            result = calloc((size_t)maximum_length + 1, sizeof(*result));
            if (result != NULL && !CFStringGetCString((CFStringRef)requirement,
                                                       result,
                                                       (CFIndex)maximum_length + 1,
                                                       kCFStringEncodingUTF8)) {
                free(result);
                result = NULL;
            }
        }
    }

    CFRelease(plist);
    return result;
}

static bool ensure_smc_connection(void) {
    if (g_connection == NULL) {
        g_connection = smc_open();
    }
    return g_connection != NULL;
}

static void schedule_watchdog_at(uint64_t deadline_nanoseconds) {
    if (g_watchdog_timer == NULL) {
        return;
    }

    uint64_t now = monotonic_nanoseconds();
    uint64_t delay = deadline_nanoseconds > now ? deadline_nanoseconds - now : 0;
    // All valid leases and retries are at most 60 seconds. Saturate anyway so
    // a malformed clock value cannot produce a negative dispatch interval.
    int64_t dispatch_delay = delay > (uint64_t)INT64_MAX ? INT64_MAX : (int64_t)delay;
    dispatch_source_set_timer(g_watchdog_timer,
                              dispatch_time(DISPATCH_TIME_NOW, dispatch_delay),
                              DISPATCH_TIME_FOREVER,
                              0);
}

static void schedule_watchdog_retry(void) {
    uint64_t now = monotonic_nanoseconds();
    uint64_t retry_delay = (uint64_t)WATCHDOG_RETRY_SECONDS * NANOSECONDS_PER_SECOND;
    uint64_t retry_deadline = UINT64_MAX - now < retry_delay ? UINT64_MAX : now + retry_delay;
    schedule_watchdog_at(retry_deadline);
}

// This function and the watchdog event handler always run on g_smc_queue.
// Once restoration is pending, no RPM write can pass the lease gate.
static bool write_manual_mode_for_restore(void *context, bool enabled) {
    (void)context;
    return ensure_smc_connection() && smc_set_fan_manual(g_connection, enabled) == 0;
}

static bool restore_automatic_mode(void) {
    bool restored = smc_helper_restore_automatic_mode(
        &g_manual_lease, write_manual_mode_for_restore, NULL);
    if (restored) {
        disable_watchdog_timer();
    } else {
        schedule_watchdog_retry();
    }
    return restored;
}

static void handle_watchdog_timer(void) {
    if (g_manual_lease.phase == SMC_HELPER_LEASE_ACTIVE) {
        uint64_t now = monotonic_nanoseconds();
        if (!smc_helper_lease_is_expired(&g_manual_lease, now)) {
            // A setFan request may have refreshed the lease after this timer
            // event was queued. Honour the refreshed monotonic deadline.
            schedule_watchdog_at(g_manual_lease.deadline_nanoseconds);
            return;
        }
        smc_helper_lease_begin_restoration(&g_manual_lease);
    }

    if (g_manual_lease.phase == SMC_HELPER_LEASE_RESTORING) {
        (void)restore_automatic_mode();
    } else {
        disable_watchdog_timer();
    }
}

static void type_code_to_string(uint32_t code, char output[5]) {
    output[0] = (char)((code >> 24) & 0xff);
    output[1] = (char)((code >> 16) & 0xff);
    output[2] = (char)((code >> 8) & 0xff);
    output[3] = (char)(code & 0xff);
    output[4] = '\0';
}

static bool decode_smc_number(const uint8_t *buffer,
                              uint32_t size,
                              uint32_t data_type,
                              double *result) {
    char type[5] = {0};
    type_code_to_string(data_type, type);

    if (strcmp(type, "fpe2") == 0 && size >= 2) {
        uint16_t value = ((uint16_t)buffer[0] << 8) | buffer[1];
        *result = (double)value / 4.0;
    } else if ((strcmp(type, "sp78") == 0 || strcmp(type, "sp87") == 0) && size >= 2) {
        int16_t value = (int16_t)(((uint16_t)buffer[0] << 8) | buffer[1]);
        *result = (double)value / 256.0;
    } else if (strcmp(type, "ui16") == 0 && size >= 2) {
        *result = (double)(((uint16_t)buffer[0] << 8) | buffer[1]);
    } else if (strcmp(type, "ui32") == 0 && size >= 4) {
        uint32_t value = ((uint32_t)buffer[0] << 24) | ((uint32_t)buffer[1] << 16) |
                         ((uint32_t)buffer[2] << 8) | buffer[3];
        *result = (double)value;
    } else if (strcmp(type, "ui8 ") == 0 && size >= 1) {
        *result = (double)buffer[0];
    } else if (strcmp(type, "flt ") == 0 && size >= 4) {
        float value = 0;
        memcpy(&value, buffer, sizeof(value));
        *result = (double)value;
    } else {
        return false;
    }

    return isfinite(*result);
}

static bool read_fan_limit(uint32_t fan_index, const char suffix[2], double *limit) {
    char key[4] = {'F', (char)('0' + fan_index), suffix[0], suffix[1]};
    uint8_t buffer[32] = {0};
    uint32_t size = 0;
    uint32_t type = 0;
    int read_result = smc_read_key(g_connection, key, buffer, sizeof(buffer), &size, &type);
    return read_result > 0 && decode_smc_number(buffer, size, type, limit);
}

static double now_seconds(void) {
    struct timespec timestamp = {0};
    clock_gettime(CLOCK_REALTIME, &timestamp);
    return (double)timestamp.tv_sec + (double)timestamp.tv_nsec / 1000000000.0;
}

static double parse_power_line(const char *line) {
    char *end = NULL;
    while (*line != '\0' && !((*line >= '0' && *line <= '9') || *line == '-' || *line == '.')) {
        ++line;
    }
    if (*line == '\0') {
        return -1.0;
    }

    double value = strtod(line, &end);
    if (end == line || !isfinite(value) || value < 0) {
        return -1.0;
    }
    return strstr(end, "mW") != NULL ? value / 1000.0 : value;
}

static void refresh_power_cache_if_needed(void) {
    double now = now_seconds();
    if (now - g_power_timestamp < POWER_CACHE_TTL) {
        return;
    }

    FILE *process = popen("/usr/bin/powermetrics -n 1 -i 500 --samplers cpu_power,gpu_power 2>/dev/null", "r");
    if (process == NULL) {
        return;
    }

    double cpu = -1.0;
    double gpu = -1.0;
    double dc = -1.0;
    char line[512] = {0};
    while (fgets(line, sizeof(line), process) != NULL) {
        if (strstr(line, "CPU Power") != NULL) {
            cpu = parse_power_line(line);
        } else if (strstr(line, "GPU Power") != NULL) {
            gpu = parse_power_line(line);
        } else if (strstr(line, "Combined System Power") != NULL ||
                   strstr(line, "System Total") != NULL || strstr(line, "Total Power") != NULL) {
            dc = parse_power_line(line);
        }
    }
    pclose(process);

    if (cpu >= 0 || gpu >= 0 || dc >= 0) {
        g_cpu_power = cpu;
        g_gpu_power = gpu;
        g_dc_power = dc;
        g_power_timestamp = now;
    }
}

static xpc_object_t make_reply(xpc_object_t request) {
    xpc_object_t reply = xpc_dictionary_create_reply(request);
    if (reply != NULL) {
        xpc_dictionary_set_int64(reply, "protocolVersion", HELPER_PROTOCOL_VERSION);
    }
    return reply;
}

static void set_error(xpc_object_t reply, const char *error_code, const char *message) {
    xpc_dictionary_set_bool(reply, "ok", false);
    xpc_dictionary_set_string(reply, "errorCode", error_code);
    xpc_dictionary_set_string(reply, "message", message);
}

static bool request_has_protocol(xpc_object_t request) {
    xpc_object_t protocol = xpc_dictionary_get_value(request, "protocolVersion");
    return protocol != NULL && xpc_get_type(protocol) == XPC_TYPE_INT64 &&
           xpc_int64_get_value(protocol) == HELPER_PROTOCOL_VERSION;
}

static bool request_int64(xpc_object_t request, const char *name, int64_t *result) {
    xpc_object_t value = xpc_dictionary_get_value(request, name);
    if (value == NULL || xpc_get_type(value) != XPC_TYPE_INT64) {
        return false;
    }
    *result = xpc_int64_get_value(value);
    return true;
}

static void handle_check(xpc_object_t reply) {
    xpc_dictionary_set_bool(reply, "ok", true);
    xpc_dictionary_set_string(reply, "helperVersion", HELPER_VERSION);
}

typedef struct {
    bool writer_was_called;
} fan_request_context;

static bool callback_read_fan_count(void *context, int *fan_count) {
    (void)context;
    int result = smc_read_fan_count(g_connection);
    if (result < 0) {
        return false;
    }
    *fan_count = result;
    return true;
}

static bool callback_read_minimum_rpm(void *context, uint32_t fan_index, double *rpm) {
    (void)context;
    return read_fan_limit(fan_index, "Mn", rpm);
}

static bool callback_read_maximum_rpm(void *context, uint32_t fan_index, double *rpm) {
    (void)context;
    return read_fan_limit(fan_index, "Mx", rpm);
}

static bool callback_write_fan_rpm(void *context, uint32_t fan_index, int rpm) {
    fan_request_context *request_context = context;
    request_context->writer_was_called = true;
    return smc_write_fan_target_rpm(g_connection, fan_index, rpm) == 0;
}

static const smc_helper_fan_request_callbacks k_fan_request_callbacks = {
    .read_fan_count = callback_read_fan_count,
    .read_minimum_rpm = callback_read_minimum_rpm,
    .read_maximum_rpm = callback_read_maximum_rpm,
    .write_fan_rpm = callback_write_fan_rpm,
};

static void handle_set_fan(xpc_object_t request, xpc_object_t reply) {
    int64_t fan_index = -1;
    int64_t rpm = -1;
    if (!request_int64(request, "fan", &fan_index) || !request_int64(request, "rpm", &rpm) ||
        fan_index < 0 || fan_index > 9 || rpm < 0 || rpm > INT_MAX) {
        set_error(reply, ERROR_INVALID_REQUEST, "fan and rpm must be signed 64-bit integers in range");
        return;
    }
    if (!smc_helper_lease_allows_fan_write(&g_manual_lease)) {
        set_error(reply,
                  ERROR_INVALID_REQUEST,
                  "setFan requires an active manual mode lease without pending restoration");
        return;
    }
    if (!ensure_smc_connection()) {
        set_error(reply, ERROR_HARDWARE_UNAVAILABLE, "AppleSMC is unavailable");
        return;
    }

    fan_request_context context = {0};
    if (!smc_helper_execute_fan_request(
            fan_index, rpm, &k_fan_request_callbacks, &context)) {
        if (context.writer_was_called) {
            set_error(reply, ERROR_SMC_FAILURE, "unable to write the fan target");
            return;
        }
        set_error(reply, ERROR_OUT_OF_RANGE, "fan target is outside the hardware limits");
        return;
    }

    // A lease is refreshed only after every input, hardware limit and writer
    // check succeeds. Should monotonic expiry bookkeeping fail, restore
    // automatic mode immediately rather than leave a manual write unguarded.
    if (!smc_helper_lease_refresh(&g_manual_lease, monotonic_nanoseconds())) {
        smc_helper_lease_begin_restoration(&g_manual_lease);
        (void)restore_automatic_mode();
        set_error(reply, ERROR_SMC_FAILURE, "unable to refresh the manual mode lease");
        return;
    }
    schedule_watchdog_at(g_manual_lease.deadline_nanoseconds);
    xpc_dictionary_set_bool(reply, "ok", true);
}

static void handle_set_mode(xpc_object_t request, xpc_object_t reply) {
    xpc_object_t enabled = xpc_dictionary_get_value(request, "enabled");
    if (enabled == NULL || xpc_get_type(enabled) != XPC_TYPE_BOOL) {
        set_error(reply, ERROR_INVALID_REQUEST, "enabled must be a boolean");
        return;
    }

    bool wants_manual_mode = xpc_bool_get_value(enabled);
    int64_t watchdog_seconds = 0;
    if (wants_manual_mode) {
        if (!request_int64(request, "watchdogSeconds", &watchdog_seconds)) {
            set_error(reply,
                      ERROR_INVALID_REQUEST,
                      "watchdogSeconds must be a signed 64-bit integer when enabling manual mode");
            return;
        }
        if (!smc_helper_is_valid_watchdog_seconds(watchdog_seconds)) {
            set_error(reply, ERROR_OUT_OF_RANGE, "watchdogSeconds must be between 15 and 60");
            return;
        }
        if (g_manual_lease.phase == SMC_HELPER_LEASE_RESTORING) {
            set_error(reply,
                      ERROR_INVALID_REQUEST,
                      "automatic mode restoration is pending; manual mode cannot be re-enabled");
            return;
        }
    }

    if (!wants_manual_mode) {
        // Even an already-inactive lease requests automatic mode again: this
        // is an explicit safety operation, not merely local state cleanup.
        smc_helper_lease_begin_restoration(&g_manual_lease);
        if (!restore_automatic_mode()) {
            set_error(reply, ERROR_SMC_FAILURE, "unable to restore automatic fan mode; watchdog will retry");
            return;
        }
        xpc_dictionary_set_bool(reply, "ok", true);
        return;
    }

    if (!ensure_smc_connection()) {
        set_error(reply, ERROR_HARDWARE_UNAVAILABLE, "AppleSMC is unavailable");
        return;
    }

    if (smc_set_fan_manual(g_connection, true) != 0) {
        set_error(reply, ERROR_SMC_FAILURE, "unable to change fan mode");
        return;
    }

    if (!smc_helper_lease_start(&g_manual_lease, watchdog_seconds, monotonic_nanoseconds())) {
        smc_helper_lease_begin_restoration(&g_manual_lease);
        (void)restore_automatic_mode();
        set_error(reply, ERROR_SMC_FAILURE, "unable to establish the manual mode lease");
        return;
    }

    schedule_watchdog_at(g_manual_lease.deadline_nanoseconds);

    xpc_dictionary_set_bool(reply, "ok", true);
}

static void handle_power(xpc_object_t reply) {
    refresh_power_cache_if_needed();
    xpc_dictionary_set_bool(reply, "ok", true);
    xpc_dictionary_set_double(reply, "cpu", g_cpu_power);
    xpc_dictionary_set_double(reply, "gpu", g_gpu_power);
    xpc_dictionary_set_double(reply, "dc", g_dc_power);
    xpc_dictionary_set_double(reply, "timestamp", g_power_timestamp);
}

static void handle_read_key(xpc_object_t request, xpc_object_t reply) {
    xpc_object_t key_value = xpc_dictionary_get_value(request, "key");
    if (key_value == NULL || xpc_get_type(key_value) != XPC_TYPE_STRING) {
        set_error(reply, ERROR_INVALID_REQUEST, "key must be a four-character string");
        return;
    }
    if (!ensure_smc_connection()) {
        set_error(reply, ERROR_HARDWARE_UNAVAILABLE, "AppleSMC is unavailable");
        return;
    }

    const char *key_string = xpc_string_get_string_ptr(key_value);
    if (!smc_helper_is_valid_key(key_string)) {
        set_error(reply, ERROR_INVALID_REQUEST, "key must contain exactly four printable ASCII characters");
        return;
    }

    char key[4] = {key_string[0], key_string[1], key_string[2], key_string[3]};
    uint8_t bytes[32] = {0};
    uint32_t size = 0;
    uint32_t type = 0;
    int read_result = smc_read_key(g_connection, key, bytes, sizeof(bytes), &size, &type);
    if (read_result < 0 || size > sizeof(bytes)) {
        set_error(reply, ERROR_SMC_FAILURE, "unable to read the SMC key");
        return;
    }

    xpc_dictionary_set_bool(reply, "ok", true);
    xpc_dictionary_set_string(reply, "key", key_string);
    xpc_dictionary_set_data(reply, "data", bytes, size);
    xpc_dictionary_set_int64(reply, "dataSize", size);
    xpc_dictionary_set_int64(reply, "dataType", type);
}

// All dispatches into this function run on g_smc_queue. This is the sole
// location that calls the root-only SMC bridge or updates its cached state.
static void handle_request(xpc_connection_t peer, xpc_object_t request) {
    xpc_object_t reply = make_reply(request);
    if (reply == NULL) {
        return;
    }

    if (!request_has_protocol(request)) {
        set_error(reply, ERROR_INCOMPATIBLE_VERSION, "protocolVersion must be 2");
    } else {
        xpc_object_t op_value = xpc_dictionary_get_value(request, "operation");
        const char *operation = op_value != NULL && xpc_get_type(op_value) == XPC_TYPE_STRING
                                    ? xpc_string_get_string_ptr(op_value)
                                    : NULL;
        if (operation == NULL) {
            set_error(reply, ERROR_INVALID_REQUEST, "operation must be a string");
        } else if (strcmp(operation, "check") == 0) {
            handle_check(reply);
        } else if (strcmp(operation, "setFan") == 0) {
            handle_set_fan(request, reply);
        } else if (strcmp(operation, "setMode") == 0) {
            handle_set_mode(request, reply);
        } else if (strcmp(operation, "power") == 0) {
            handle_power(reply);
        } else if (strcmp(operation, "readKey") == 0) {
            handle_read_key(request, reply);
        } else {
            set_error(reply, ERROR_INVALID_REQUEST, "operation is not supported");
        }
    }

    xpc_connection_send_message(peer, reply);
    xpc_release(reply);
}

static void accept_peer(xpc_connection_t peer) {
    xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
        if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) {
            return;
        }

        xpc_connection_t retained_peer = xpc_retain(peer);
        xpc_object_t retained_request = xpc_retain(event);
        dispatch_async(g_smc_queue, ^{
            handle_request(retained_peer, retained_request);
            xpc_release(retained_request);
            xpc_release(retained_peer);
        });
    });
    xpc_connection_activate(peer);
}

static void run_service(const char *client_requirement) {
    g_smc_queue = dispatch_queue_create("com.minepacu.SMCHelper.smc", DISPATCH_QUEUE_SERIAL);
    smc_helper_lease_init(&g_manual_lease);
    g_watchdog_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, g_smc_queue);
    if (g_watchdog_timer == NULL) {
        fprintf(stderr, "Unable to create manual mode watchdog\n");
        exit(2);
    }
    dispatch_source_set_event_handler(g_watchdog_timer, ^{
        handle_watchdog_timer();
    });
    disable_watchdog_timer();
    dispatch_resume(g_watchdog_timer);

    // A previous process might have been killed while fan control was manual.
    // Restore before accepting a new peer; failure remains protected by the
    // retrying watchdog and does not prevent authenticated diagnostics.
    smc_helper_lease_begin_restoration(&g_manual_lease);
    (void)restore_automatic_mode();

    xpc_connection_t listener = xpc_connection_create_mach_service(
        HELPER_MACH_SERVICE, NULL, XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (listener == NULL) {
        fprintf(stderr, "Unable to create XPC Mach service listener\n");
        exit(3);
    }

    if (xpc_connection_set_peer_code_signing_requirement(listener, client_requirement) != 0) {
        fprintf(stderr, "Unable to apply the installed client signing requirement\n");
        exit(4);
    }

    xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_CONNECTION) {
            accept_peer((xpc_connection_t)event);
        }
    });
    xpc_connection_activate(listener);
    dispatch_main();
}

int main(int argc, const char *argv[]) {
    (void)argv;
    if (geteuid() != 0) {
        fprintf(stderr, "SMCHelper must run as root\n");
        return 1;
    }
    if (argc != 1) {
        fprintf(stderr, "SMCHelper is launchd-managed and accepts no command-line arguments\n");
        return 1;
    }

    char *client_requirement = copy_installed_client_requirement();
    if (client_requirement == NULL) {
        fprintf(stderr, "Missing or unsafe client signing requirement configuration\n");
        return 1;
    }

    atexit(cleanup);
    run_service(client_requirement);
    free(client_requirement);
    return 0;
}
