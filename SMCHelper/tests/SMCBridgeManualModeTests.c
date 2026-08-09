#include "../../SMCController/Platform/SMCBridge.h"

#include <assert.h>
#include <string.h>

int main(void) {
    char key[4] = {0};
    uint8_t mask[2] = {0x00, 0x01};

    assert(smc_prepare_fan_manual_values(1, true, key, mask, sizeof(mask)));
    assert(memcmp(key, "F1Md", sizeof(key)) == 0);
    assert(mask[0] == 0x00);
    assert(mask[1] == 0x03);

    assert(smc_prepare_fan_manual_values(1, false, key, mask, sizeof(mask)));
    assert(mask[1] == 0x01);
    return 0;
}
