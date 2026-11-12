/* plugin_heal.h: what kind of file is this SuperCollider plug-in? (Windows launcher; pure, linux/tests/plugin_heal_test.c). A script that installs a plug-in for the Raspberry Pi (an ELF file) or the Mac (Mach-O) must never
 * be loaded by the Windows sclang: SuperCollider stops at the first plug-in it cannot load. only a PE file for x86-64 is the right kind. the launcher moves the others aside before sclang starts. */
#ifndef VERDANDI_PLUGIN_HEAL_H
#define VERDANDI_PLUGIN_HEAL_H
#include <stddef.h>

typedef enum { PH_PE_X64, PH_PE_OTHER, PH_ELF, PH_MACHO, PH_UNKNOWN } ph_kind;

static inline ph_kind ph_classify(const unsigned char *b, size_t n) {
    if (n >= 4 && b[0] == 0x7f && b[1] == 'E' && b[2] == 'L' && b[3] == 'F') return PH_ELF;
    if (n >= 4 && ((b[0] == 0xcf && b[1] == 0xfa && b[2] == 0xed && b[3] == 0xfe) || (b[0] == 0xce && b[1] == 0xfa && b[2] == 0xed && b[3] == 0xfe) ||
                   (b[0] == 0xca && b[1] == 0xfe && b[2] == 0xba && b[3] == 0xbe) || (b[0] == 0xfe && b[1] == 0xed && b[2] == 0xfa && (b[3] == 0xce || b[3] == 0xcf)))) return PH_MACHO;
    if (n >= 0x40 && b[0] == 'M' && b[1] == 'Z') {
        size_t pe = (size_t)b[0x3c] | ((size_t)b[0x3d] << 8) | ((size_t)b[0x3e] << 16) | ((size_t)b[0x3f] << 24);
        if (pe + 6 <= n && b[pe] == 'P' && b[pe + 1] == 'E' && b[pe + 2] == 0 && b[pe + 3] == 0) {
            unsigned machine = (unsigned)b[pe + 4] | ((unsigned)b[pe + 5] << 8);
            return machine == 0x8664 ? PH_PE_X64 : PH_PE_OTHER;
        }
    }
    return PH_UNKNOWN;
}

static inline const char *ph_words(ph_kind k) {
    switch (k) {
    case PH_ELF: return "a Linux / Raspberry Pi plug-in";
    case PH_MACHO: return "a Mac plug-in";
    case PH_PE_OTHER: return "a Windows plug-in for another processor (ARM or 32 bit)";
    case PH_UNKNOWN: return "not a plug-in this Windows can load";
    default: return "a Windows x86-64 plug-in";
    }
}
#endif
