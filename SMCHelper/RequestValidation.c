//
//  RequestValidation.c
//  SMCHelper
//

#include "RequestValidation.h"

#include <ctype.h>
#include <limits.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

#define SMC_HELPER_MIN_WATCHDOG_SECONDS 15
#define SMC_HELPER_MAX_WATCHDOG_SECONDS 60
#define NANOSECONDS_PER_SECOND UINT64_C(1000000000)

bool smc_helper_is_valid_key(const char *key) {
    if (key == NULL || strlen(key) != 4) {
        return false;
    }

    for (size_t i = 0; i < 4; ++i) {
        unsigned char c = (unsigned char)key[i];
        if (c < 0x20 || c > 0x7e) {
            return false;
        }
    }
    return true;
}

bool smc_helper_is_valid_fan_request(int64_t fan_index,
                                     int64_t rpm,
                                     int fan_count,
                                     double minimum_rpm,
                                     double maximum_rpm) {
    if (fan_count < 1 || fan_count > 10 || fan_index < 0 || fan_index > 9 ||
        fan_index >= fan_count || rpm < 0 || rpm > INT_MAX || !isfinite(minimum_rpm) ||
        !isfinite(maximum_rpm) || minimum_rpm < 0 || maximum_rpm < minimum_rpm) {
        return false;
    }

    return (double)rpm >= minimum_rpm && (double)rpm <= maximum_rpm;
}

bool smc_helper_execute_fan_request(
    int64_t fan_index,
    int64_t rpm,
    const smc_helper_fan_request_callbacks *callbacks,
    void *context) {
    if (callbacks == NULL || callbacks->read_fan_count == NULL ||
        callbacks->read_minimum_rpm == NULL || callbacks->read_maximum_rpm == NULL ||
        callbacks->write_fan_rpm == NULL || fan_index < 0 || fan_index > 9 ||
        rpm < 0 || rpm > INT_MAX) {
        return false;
    }

    int fan_count = 0;
    double minimum_rpm = 0;
    double maximum_rpm = 0;
    uint32_t safe_fan_index = (uint32_t)fan_index;

    if (!callbacks->read_fan_count(context, &fan_count) ||
        !callbacks->read_minimum_rpm(context, safe_fan_index, &minimum_rpm) ||
        !callbacks->read_maximum_rpm(context, safe_fan_index, &maximum_rpm) ||
        !smc_helper_is_valid_fan_request(
            fan_index, rpm, fan_count, minimum_rpm, maximum_rpm)) {
        return false;
    }

    return callbacks->write_fan_rpm(context, safe_fan_index, (int)rpm);
}

bool smc_helper_is_valid_watchdog_seconds(int64_t watchdog_seconds) {
    return watchdog_seconds >= SMC_HELPER_MIN_WATCHDOG_SECONDS &&
           watchdog_seconds <= SMC_HELPER_MAX_WATCHDOG_SECONDS;
}

void smc_helper_lease_init(smc_helper_lease *lease) {
    if (lease == NULL) {
        return;
    }
    lease->phase = SMC_HELPER_LEASE_INACTIVE;
    lease->watchdog_seconds = 0;
    lease->deadline_nanoseconds = 0;
}

static bool smc_helper_lease_set_deadline(smc_helper_lease *lease,
                                          uint64_t now_nanoseconds) {
    if (lease == NULL || !smc_helper_is_valid_watchdog_seconds(lease->watchdog_seconds)) {
        return false;
    }

    uint64_t duration = (uint64_t)lease->watchdog_seconds * NANOSECONDS_PER_SECOND;
    if (UINT64_MAX - now_nanoseconds < duration) {
        return false;
    }
    lease->deadline_nanoseconds = now_nanoseconds + duration;
    return true;
}

bool smc_helper_lease_start(smc_helper_lease *lease,
                            int64_t watchdog_seconds,
                            uint64_t now_nanoseconds) {
    if (lease == NULL || !smc_helper_is_valid_watchdog_seconds(watchdog_seconds)) {
        return false;
    }

    smc_helper_lease candidate = {
        .phase = SMC_HELPER_LEASE_ACTIVE,
        .watchdog_seconds = watchdog_seconds,
        .deadline_nanoseconds = 0,
    };
    if (!smc_helper_lease_set_deadline(&candidate, now_nanoseconds)) {
        return false;
    }
    *lease = candidate;
    return true;
}

bool smc_helper_lease_allows_fan_write(const smc_helper_lease *lease) {
    return lease != NULL && lease->phase == SMC_HELPER_LEASE_ACTIVE;
}

bool smc_helper_lease_refresh(smc_helper_lease *lease, uint64_t now_nanoseconds) {
    return smc_helper_lease_allows_fan_write(lease) &&
           smc_helper_lease_set_deadline(lease, now_nanoseconds);
}

bool smc_helper_lease_is_expired(const smc_helper_lease *lease,
                                 uint64_t now_nanoseconds) {
    return smc_helper_lease_allows_fan_write(lease) &&
           now_nanoseconds >= lease->deadline_nanoseconds;
}

void smc_helper_lease_begin_restoration(smc_helper_lease *lease) {
    if (lease == NULL) {
        return;
    }
    lease->phase = SMC_HELPER_LEASE_RESTORING;
}

void smc_helper_lease_finish_restoration(smc_helper_lease *lease, bool succeeded) {
    if (lease == NULL) {
        return;
    }
    if (succeeded) {
        smc_helper_lease_init(lease);
    } else {
        lease->phase = SMC_HELPER_LEASE_RESTORING;
    }
}

bool smc_helper_restore_automatic_mode(
    smc_helper_lease *lease,
    smc_helper_write_manual_mode_callback write_manual_mode,
    void *context) {
    if (lease == NULL || write_manual_mode == NULL) {
        return false;
    }

    smc_helper_lease_begin_restoration(lease);
    bool restored = write_manual_mode(context, false);
    smc_helper_lease_finish_restoration(lease, restored);
    return restored;
}
