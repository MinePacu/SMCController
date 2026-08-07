//
//  RequestValidation.h
//  SMCHelper
//
//  Hardware-independent validation for the privileged helper protocol.
//

#ifndef SMCHelperRequestValidation_h
#define SMCHelperRequestValidation_h

#include <stdbool.h>
#include <stdint.h>

// SMC keys are exactly four printable ASCII bytes. A terminating NUL is
// required so callers can safely pass an XPC string.
bool smc_helper_is_valid_key(const char *key);

// Validates a requested fan target against bounds read from the hardware.
// The caller must pass the current FNum value and the target fan's F?Mn/F?Mx
// values; invalid or unavailable hardware limits reject the request.
bool smc_helper_is_valid_fan_request(int64_t fan_index,
                                     int64_t rpm,
                                     int fan_count,
                                     double minimum_rpm,
                                     double maximum_rpm);

// Callbacks that keep hardware access outside of the validator.  A callback
// returns false when the requested SMC value could not be read or written.
// The writer is deliberately invoked only after every read and validation
// step succeeds.
typedef bool (*smc_helper_read_fan_count_callback)(void *context,
                                                   int *fan_count);
typedef bool (*smc_helper_read_fan_limit_callback)(void *context,
                                                   uint32_t fan_index,
                                                   double *rpm);
typedef bool (*smc_helper_write_fan_rpm_callback)(void *context,
                                                  uint32_t fan_index,
                                                  int rpm);

typedef struct {
    smc_helper_read_fan_count_callback read_fan_count;
    smc_helper_read_fan_limit_callback read_minimum_rpm;
    smc_helper_read_fan_limit_callback read_maximum_rpm;
    smc_helper_write_fan_rpm_callback write_fan_rpm;
} smc_helper_fan_request_callbacks;

// Reads the hardware bounds, validates the request, then writes the target
// RPM. Invalid arguments, incomplete callbacks, failed reads, and failed
// validation all return false without invoking write_fan_rpm.
bool smc_helper_execute_fan_request(
    int64_t fan_index,
    int64_t rpm,
    const smc_helper_fan_request_callbacks *callbacks,
    void *context);

// A manual fan-mode lease is deliberately represented without any dispatch or
// SMC dependencies so its safety rules can be exercised in unit tests. The
// helper owns scheduling; this state only records whether a write is allowed
// and the monotonic expiry it should schedule.
typedef enum {
    SMC_HELPER_LEASE_INACTIVE = 0,
    SMC_HELPER_LEASE_ACTIVE,
    SMC_HELPER_LEASE_RESTORING,
} smc_helper_lease_phase;

typedef struct {
    smc_helper_lease_phase phase;
    int64_t watchdog_seconds;
    uint64_t deadline_nanoseconds;
} smc_helper_lease;

// Watchdog values are constrained by the app's 5...20 second control period.
bool smc_helper_is_valid_watchdog_seconds(int64_t watchdog_seconds);

void smc_helper_lease_init(smc_helper_lease *lease);

// Starts a lease and calculates its monotonic expiry. Returns false for an
// invalid watchdog, a NULL lease, or an expiry calculation overflow.
bool smc_helper_lease_start(smc_helper_lease *lease,
                            int64_t watchdog_seconds,
                            uint64_t now_nanoseconds);

// Returns true only while manual writes are permitted.
bool smc_helper_lease_allows_fan_write(const smc_helper_lease *lease);

// Refreshes an active lease after a successful fan RPM write.
bool smc_helper_lease_refresh(smc_helper_lease *lease, uint64_t now_nanoseconds);

bool smc_helper_lease_is_expired(const smc_helper_lease *lease,
                                 uint64_t now_nanoseconds);

// Entering restoration blocks fan writes. A failed restoration remains in
// this state so the caller can retry; only success clears the lease.
void smc_helper_lease_begin_restoration(smc_helper_lease *lease);
void smc_helper_lease_finish_restoration(smc_helper_lease *lease, bool succeeded);

typedef bool (*smc_helper_write_manual_mode_callback)(void *context, bool enabled);

// Calls the supplied hardware writer with automatic mode (`false`). The lease
// remains in RESTORING on failure, which tells the daemon to retry it and to
// keep rejecting fan writes. Success is the only path that clears the lease.
bool smc_helper_restore_automatic_mode(
    smc_helper_lease *lease,
    smc_helper_write_manual_mode_callback write_manual_mode,
    void *context);

#endif /* SMCHelperRequestValidation_h */
