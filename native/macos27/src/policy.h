/* SPDX-License-Identifier: MIT
 * Constant native ceiling: NEVER lower the target as observed charge falls.
 * Independent lower restart thresholds are deliberately not emulated.
 */
#ifndef BATTERY27_POLICY_H
#define BATTERY27_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <limits.h>

static inline bool b27_parse_percent(const char *s, int *out) {
    if (!s || !*s || !out) return false;
    unsigned n = 0; size_t len = 0;
    for (; *s; ++s) {
        if (++len > 3 || *s < '0' || *s > '9') return false;
        n = n * 10u + (unsigned)(*s - '0');
    }
    if (n < 1 || n > 100) return false;
    *out = (int)n; return true;
}
/* Reader accepts the old schema to allow rollback or an EXPLICIT replacement.
 * Applying a range is never allowed: see b27_fixed_target. */
static inline bool b27_valid_saved_range(int lower, int upper) {
    return lower >= 1 && upper <= 100 && lower <= upper &&
           (lower == upper || lower >= 10);
}
static inline bool b27_fixed_target(int lower, int upper, int *target) {
    if (!target || lower < 1 || upper > 100 || lower != upper) return false;
    *target = upper; return true;
}
/* IORegistry may expose negative signed currents as unsigned 32/64-bit data.
 * Convert without signed overflow, then reject implausibly large readings.
 * This sanity bound is a parser guard, not a battery health threshold. */
static inline bool b27_decode_current(uint64_t raw, int64_t *out) {
    if (!out) return false;
    int64_t value;
    if (raw <= INT32_MAX) value = (int64_t)raw;
    else if (raw <= UINT32_MAX) value = -(int64_t)(UINT32_MAX - raw) - 1;
    else if (raw > INT64_MAX) value = -(int64_t)(UINT64_MAX - raw) - 1;
    else return false;
    if (value < -100000 || value > 100000) return false;
    *out = value; return true;
}
#endif
