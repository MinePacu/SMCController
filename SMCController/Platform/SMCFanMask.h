//
//  SMCFanMask.h
//  SMCController
//
//  Hardware-independent helpers for per-fan manual mode bits. Header-only so
//  both the app bridge and the helper unit tests can use it without IOKit.
//

#ifndef SMCFanMask_h
#define SMCFanMask_h

#include <stdint.h>

// SMC exposes at most ten fans (F0..F9).
#define SMC_MAX_FANS 10

// Bit mask with one bit per fan, used by the global "FS! " key.
// Non-positive counts yield 0; counts above SMC_MAX_FANS are clamped.
static inline uint16_t smc_fan_manual_mask(int fan_count) {
    if (fan_count <= 0) return 0;
    if (fan_count > SMC_MAX_FANS) fan_count = SMC_MAX_FANS;
    return (uint16_t)((1u << fan_count) - 1u);
}

// Number of fans to touch when the fan count cannot be read: fan 0 only,
// which matches the behaviour before multi-fan support.
static inline int smc_fan_count_or_default(int fan_count) {
    if (fan_count <= 0) return 1;
    return fan_count > SMC_MAX_FANS ? SMC_MAX_FANS : fan_count;
}

#endif /* SMCFanMask_h */
