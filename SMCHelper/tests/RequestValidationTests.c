#include "../RequestValidation.h"

#include <assert.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    bool fan_count_succeeds;
    bool minimum_succeeds;
    bool maximum_succeeds;
    bool writer_succeeds;
    int fan_count;
    double minimum_rpm;
    double maximum_rpm;
    int fan_count_reads;
    int minimum_reads;
    int maximum_reads;
    int writer_calls;
    uint32_t written_fan_index;
    int written_rpm;
    int manual_mode_writer_calls;
    bool manual_mode_writer_succeeds;
    bool last_manual_mode;
} fake_smc;

static bool read_fan_count(void *context, int *fan_count) {
    fake_smc *smc = context;
    smc->fan_count_reads += 1;
    if (!smc->fan_count_succeeds) {
        return false;
    }
    *fan_count = smc->fan_count;
    return true;
}

static bool read_minimum_rpm(void *context, uint32_t fan_index, double *rpm) {
    fake_smc *smc = context;
    (void)fan_index;
    smc->minimum_reads += 1;
    if (!smc->minimum_succeeds) {
        return false;
    }
    *rpm = smc->minimum_rpm;
    return true;
}

static bool read_maximum_rpm(void *context, uint32_t fan_index, double *rpm) {
    fake_smc *smc = context;
    (void)fan_index;
    smc->maximum_reads += 1;
    if (!smc->maximum_succeeds) {
        return false;
    }
    *rpm = smc->maximum_rpm;
    return true;
}

static bool write_fan_rpm(void *context, uint32_t fan_index, int rpm) {
    fake_smc *smc = context;
    smc->writer_calls += 1;
    smc->written_fan_index = fan_index;
    smc->written_rpm = rpm;
    return smc->writer_succeeds;
}

static bool write_manual_mode(void *context, bool enabled) {
    fake_smc *smc = context;
    smc->manual_mode_writer_calls += 1;
    smc->last_manual_mode = enabled;
    return smc->manual_mode_writer_succeeds;
}

static smc_helper_fan_request_callbacks callbacks = {
    .read_fan_count = read_fan_count,
    .read_minimum_rpm = read_minimum_rpm,
    .read_maximum_rpm = read_maximum_rpm,
    .write_fan_rpm = write_fan_rpm,
};

static fake_smc valid_fake_smc(void) {
    return (fake_smc){
        .fan_count_succeeds = true,
        .minimum_succeeds = true,
        .maximum_succeeds = true,
        .writer_succeeds = true,
        .fan_count = 2,
        .minimum_rpm = 1100,
        .maximum_rpm = 6200,
        .manual_mode_writer_succeeds = true,
    };
}

static void assert_no_writer_for_read_failure(void) {
    fake_smc smc = valid_fake_smc();
    smc.fan_count_succeeds = false;
    assert(!smc_helper_execute_fan_request(0, 1200, &callbacks, &smc));
    assert(smc.writer_calls == 0);
    assert(smc.minimum_reads == 0);
    assert(smc.maximum_reads == 0);

    smc = valid_fake_smc();
    smc.minimum_succeeds = false;
    assert(!smc_helper_execute_fan_request(0, 1200, &callbacks, &smc));
    assert(smc.writer_calls == 0);
    assert(smc.maximum_reads == 0);

    smc = valid_fake_smc();
    smc.maximum_succeeds = false;
    assert(!smc_helper_execute_fan_request(0, 1200, &callbacks, &smc));
    assert(smc.writer_calls == 0);
}

static void assert_boundary_writes(void) {
    fake_smc smc = valid_fake_smc();
    assert(smc_helper_execute_fan_request(1, 1100, &callbacks, &smc));
    assert(smc.writer_calls == 1);
    assert(smc.written_fan_index == 1);
    assert(smc.written_rpm == 1100);

    smc = valid_fake_smc();
    assert(smc_helper_execute_fan_request(1, 6200, &callbacks, &smc));
    assert(smc.writer_calls == 1);
    assert(smc.written_fan_index == 1);
    assert(smc.written_rpm == 6200);
}

static void assert_invalid_requests_do_not_write(void) {
    const int64_t invalid_fan_indices[] = { -1, 2, 10, INT64_MAX };
    const int64_t invalid_rpms[] = { -1, 1099, 6201, (int64_t)INT_MAX + 1, INT64_MAX };

    for (size_t i = 0; i < sizeof(invalid_fan_indices) / sizeof(invalid_fan_indices[0]); ++i) {
        fake_smc smc = valid_fake_smc();
        assert(!smc_helper_execute_fan_request(invalid_fan_indices[i], 1200, &callbacks, &smc));
        assert(smc.writer_calls == 0);
    }

    for (size_t i = 0; i < sizeof(invalid_rpms) / sizeof(invalid_rpms[0]); ++i) {
        fake_smc smc = valid_fake_smc();
        assert(!smc_helper_execute_fan_request(0, invalid_rpms[i], &callbacks, &smc));
        assert(smc.writer_calls == 0);
    }

    fake_smc smc = valid_fake_smc();
    smc.fan_count = 0;
    assert(!smc_helper_execute_fan_request(0, 1200, &callbacks, &smc));
    assert(smc.writer_calls == 0);

    smc = valid_fake_smc();
    smc.minimum_rpm = 6200;
    smc.maximum_rpm = 1100;
    assert(!smc_helper_execute_fan_request(0, 1200, &callbacks, &smc));
    assert(smc.writer_calls == 0);
}

static void assert_watchdog_lease(void) {
    smc_helper_lease lease;
    smc_helper_lease_init(&lease);
    assert(lease.phase == SMC_HELPER_LEASE_INACTIVE);
    assert(!smc_helper_lease_allows_fan_write(&lease));

    assert(!smc_helper_is_valid_watchdog_seconds(14));
    assert(smc_helper_is_valid_watchdog_seconds(15));
    assert(smc_helper_is_valid_watchdog_seconds(60));
    assert(!smc_helper_is_valid_watchdog_seconds(61));
    assert(!smc_helper_lease_start(&lease, 14, 100));
    assert(!smc_helper_lease_start(&lease, 61, 100));
    assert(!smc_helper_lease_start(&lease, 15, UINT64_MAX - 1));

    const uint64_t start = UINT64_C(1000000000);
    assert(smc_helper_lease_start(&lease, 15, start));
    assert(lease.phase == SMC_HELPER_LEASE_ACTIVE);
    assert(smc_helper_lease_allows_fan_write(&lease));
    assert(lease.deadline_nanoseconds == start + UINT64_C(15000000000));
    assert(!smc_helper_lease_is_expired(&lease, lease.deadline_nanoseconds - 1));
    assert(smc_helper_lease_is_expired(&lease, lease.deadline_nanoseconds));

    const uint64_t refreshed_at = UINT64_C(4000000000);
    assert(smc_helper_lease_refresh(&lease, refreshed_at));
    assert(lease.deadline_nanoseconds == refreshed_at + UINT64_C(15000000000));

    // A restoration request gates every subsequent RPM write. Failed auto
    // restoration remains gated so the timer can safely retry later.
    fake_smc smc = valid_fake_smc();
    smc.manual_mode_writer_succeeds = false;
    assert(!smc_helper_restore_automatic_mode(&lease, write_manual_mode, &smc));
    assert(lease.phase == SMC_HELPER_LEASE_RESTORING);
    assert(!smc_helper_lease_allows_fan_write(&lease));
    assert(smc.manual_mode_writer_calls == 1);
    assert(!smc.last_manual_mode);
    assert(!smc_helper_lease_refresh(&lease, refreshed_at));

    // The timer's next event performs the same restore operation. The fake
    // writer observes both the failed first attempt and successful retry.
    smc.manual_mode_writer_succeeds = true;
    assert(smc_helper_restore_automatic_mode(&lease, write_manual_mode, &smc));
    assert(smc.manual_mode_writer_calls == 2);
    assert(lease.phase == SMC_HELPER_LEASE_INACTIVE);
    assert(!smc_helper_lease_allows_fan_write(&lease));

    // Startup and an explicit setMode(false) both use automatic restoration
    // even if no manual lease had been established locally.
    smc_helper_lease_init(&lease);
    assert(smc_helper_restore_automatic_mode(&lease, write_manual_mode, &smc));
    assert(smc.manual_mode_writer_calls == 3);
    assert(lease.phase == SMC_HELPER_LEASE_INACTIVE);
}

int main(void) {
    assert(smc_helper_is_valid_key("F0Ac"));
    assert(smc_helper_is_valid_key("FS! "));
    assert(!smc_helper_is_valid_key("F0A"));
    assert(!smc_helper_is_valid_key("F0Acc"));
    assert(!smc_helper_is_valid_key("F0\nC"));

    assert(smc_helper_is_valid_fan_request(0, 1200, 1, 1100, 6200));
    assert(smc_helper_is_valid_fan_request(9, 6200, 10, 1100, 6200));
    assert(!smc_helper_is_valid_fan_request(1, 1200, 1, 1100, 6200));
    assert(!smc_helper_is_valid_fan_request(10, 1200, 10, 1100, 6200));
    assert(!smc_helper_is_valid_fan_request(0, 1099, 1, 1100, 6200));
    assert(!smc_helper_is_valid_fan_request(0, 6201, 1, 1100, 6200));
    assert(!smc_helper_is_valid_fan_request(0, 1200, 0, 1100, 6200));
    assert(!smc_helper_is_valid_fan_request(0, 1200, 1, 6200, 1100));
    assert(!smc_helper_is_valid_fan_request(0, (int64_t)INT_MAX + 1, 1, 0, (double)INT64_MAX));

    assert_no_writer_for_read_failure();
    assert_boundary_writes();
    assert_invalid_requests_do_not_write();
    assert_watchdog_lease();
    return 0;
}
