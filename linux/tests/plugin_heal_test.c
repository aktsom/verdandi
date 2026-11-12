/* the plug-in kinds of the Windows launcher (windows/launcher/plugin_heal.h): only a PE file for x86-64 is loaded.
 *   cc -std=gnu11 -Wall -I windows/launcher linux/tests/plugin_heal_test.c -o /tmp/pht && /tmp/pht */
#include <stdio.h>
#include <string.h>
#include "plugin_heal.h"
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)
static void pe(unsigned char *b, unsigned machine) { memset(b, 0, 512); b[0] = 'M'; b[1] = 'Z'; b[0x3c] = 0x80; b[0x80] = 'P'; b[0x81] = 'E'; b[0x84] = machine & 0xff; b[0x85] = machine >> 8; }
int main(void) {
    unsigned char b[512];
    pe(b, 0x8664); CHECK(ph_classify(b, sizeof b) == PH_PE_X64, "x86-64 PE is the right kind");
    pe(b, 0xAA64); CHECK(ph_classify(b, sizeof b) == PH_PE_OTHER, "ARM64 PE is not");
    pe(b, 0x14c); CHECK(ph_classify(b, sizeof b) == PH_PE_OTHER, "32 bit PE is not");
    memset(b, 0, sizeof b); memcpy(b, "\x7f""ELF\x02\x01\x01", 7); CHECK(ph_classify(b, sizeof b) == PH_ELF, "ELF (a Raspberry Pi plug-in)");
    memset(b, 0, sizeof b); memcpy(b, "\xcf\xfa\xed\xfe", 4); CHECK(ph_classify(b, sizeof b) == PH_MACHO, "Mach-O");
    memset(b, 0, sizeof b); memcpy(b, "\xca\xfe\xba\xbe", 4); CHECK(ph_classify(b, sizeof b) == PH_MACHO, "a universal Mach-O");
    memset(b, 0, sizeof b); CHECK(ph_classify(b, sizeof b) == PH_UNKNOWN, "zeros are nothing");
    memset(b, 0, sizeof b); b[0] = 'M'; b[1] = 'Z'; b[0x3c] = 0xff; b[0x3d] = 0xff; CHECK(ph_classify(b, sizeof b) == PH_UNKNOWN, "a broken header does not run off the buffer");
    CHECK(ph_classify(b, 2) == PH_UNKNOWN, "a tiny file");
    CHECK(strstr(ph_words(PH_ELF), "Raspberry Pi"), "words");
    printf(fails == 0 ? "plugin_heal: all checks pass\n" : "plugin_heal: %d failures\n", fails);
    return fails != 0;
}
