/* SPDX-License-Identifier: MIT */
#include "../src/policy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    int n = -1;
    assert(b27_parse_percent("55", &n) && n == 55);
    assert(b27_parse_percent("001", &n) && n == 1);
    assert(b27_parse_percent("100", &n) && n == 100);
    const char *bad[] = {"", "0", "101", "-1", "+55", "45-55", "5.5", "55 ", "55;id", "0001"};
    for (size_t i=0; i<sizeof bad/sizeof *bad; ++i) assert(!b27_parse_percent(bad[i], &n));
    assert(!b27_parse_percent(NULL, &n));
    assert(!b27_parse_percent("55", NULL));
    for (int p=1; p<=100; ++p) {
        assert(b27_fixed_target(p,p,&n) && n==p);
        /* The current percentage isn't an input: it cannot ratchet the ceiling. */
        for (int observed=0; observed<=100; ++observed) {
            (void)observed;
            assert(b27_fixed_target(p,p,&n) && n==p);
        }
    }
    for (int lo=0; lo<=101; ++lo) for (int hi=0; hi<=101; ++hi)
        assert(b27_fixed_target(lo,hi,&n) == (lo==hi && lo>=1 && hi<=100));
    assert(!b27_fixed_target(55,55,NULL));
    assert(b27_valid_saved_range(45,55)); /* Read old state for explicit recovery only. */
    assert(!b27_fixed_target(45,55,&n));
    int64_t a;
    assert(b27_decode_current(0,&a) && a==0);
    assert(b27_decode_current(3911,&a) && a==3911);
    assert(b27_decode_current(UINT64_MAX-1199,&a) && a==-1200);
    assert(b27_decode_current(UINT32_MAX-1199,&a) && a==-1200);
    assert(!b27_decode_current(INT64_MAX,&a));
    assert(!b27_decode_current(UINT32_MAX/2+1,&a));
    assert(!b27_decode_current(100001,&a));
    assert(!b27_decode_current(0,NULL));
    /* Reproduce the live failure: registered 55%, AC, charging at 62%.
     * Override detection must win even below the ceiling or at zero current. */
    assert(b27_charge_warning(55,62,true,true,true,3501,true,3501,true) == B27_CHARGE_WARNING_FULL_CHARGE_OVERRIDE);
    assert(b27_charge_warning(55,27,true,true,true,3501,true,3501,true) == B27_CHARGE_WARNING_FULL_CHARGE_OVERRIDE);
    assert(b27_charge_warning(55,55,true,false,true,0,true,0,true) == B27_CHARGE_WARNING_FULL_CHARGE_OVERRIDE);
    assert(b27_charge_warning(55,62,true,true,true,3501,true,3501,false) == B27_CHARGE_WARNING_ABOVE_CEILING);
    assert(b27_charge_warning(55,55,true,true,false,0,false,0,false) == B27_CHARGE_WARNING_ABOVE_CEILING);
    /* Positive current is evidence even when the charging flag is stale. */
    assert(b27_charge_warning(55,62,true,false,true,3000,false,0,false) == B27_CHARGE_WARNING_ABOVE_CEILING);
    assert(b27_charge_warning(55,62,true,false,false,0,true,3000,false) == B27_CHARGE_WARNING_ABOVE_CEILING);
    assert(b27_charge_warning(55,54,true,true,true,3501,true,3501,false) == B27_CHARGE_WARNING_NONE);
    assert(b27_charge_warning(55,62,false,false,true,-1000,true,-1000,false) == B27_CHARGE_WARNING_NONE);
    assert(b27_charge_warning(55,55,true,false,true,0,true,0,false) == B27_CHARGE_WARNING_NONE);
    assert(b27_charge_warning(55,62,true,false,false,3000,false,3000,false) == B27_CHARGE_WARNING_NONE);
    assert(b27_charge_warning(100,100,true,true,true,100,true,100,true) == B27_CHARGE_WARNING_NONE);
    assert(b27_charge_warning(0,62,true,true,true,3000,true,3000,true) == B27_CHARGE_WARNING_NONE);
    puts("PASS: fixed ceilings, validation, signed current, override and overrun detection.");
    return 0;
}
