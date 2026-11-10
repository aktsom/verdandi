/*
 * crash_report_win.cc: crash_report.h for Windows. a crash of norns.exe leaves
 *   <dir>\crash-<time>-<pid>.txt   what happened, in the order of how likely it is to survive a dying process:
 *                                   1. the exception (code, address, module + offset, read/write/execute and the address touched), the thread (id and name), the registers   [written and flushed first]
 *                                   2. the call stack of the FAULTING context (unwound with the .pdata tables: modules + offsets), each flushed as it is found
 *                                   3. function names for the frames in norns.exe (the symbol table of the .exe that is running, read from disk: names are the mangled ones, c++filt shows them)
 *                                   4. the modules loaded
 *   <dir>\crash-<time>-<pid>.dmp   a minidump (DbgHelp), last: it may be slow or fail
 * and one line in the log (stderr). The first parts use only Win32 calls on buffers that exist already (no C library, no allocation, no locks that the crashed thread could hold): the first M2 crash reports
 * were empty files because the process ended while the C library's file functions were still working, or the reporter itself ran into a lock. Every part is written and flushed (FlushFileBuffers) before the next
 * is tried. While a report is being made verdandi_crash_in_progress() is 1: the normal exit path (exit_win.c) waits for it instead of ending the process under it.
 * the folder is the one the launcher names (<Verdandi folder>\logs\crash). dir NULL: no files, the log line only.
 */
#ifdef _WIN32

#include <windows.h>

#include <dbghelp.h>
#include <psapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../linux/crash_report.h"

static char g_dir[MAX_PATH * 2];
static void (*g_hook)(void);
static LONG volatile g_in_crash;
static DWORD g_start_tick;

extern "C" void crash_report_set_hook(void (*fn)(void)) { g_hook = fn; }
extern "C" int verdandi_crash_in_progress(void) { return g_in_crash != 0; }

// ---- a small output buffer: text is formatted by hand into it and written with WriteFile ----
struct Out {
    HANDLE file;
    char buf[8192];
    size_t len;
};

static void out_flush(Out *o) {
    if (o->file != INVALID_HANDLE_VALUE && o->len) {
        DWORD done;
        WriteFile(o->file, o->buf, (DWORD)o->len, &done, NULL);
        FlushFileBuffers(o->file);
    }
    o->len = 0;
}
static void out_s(Out *o, const char *s) {
    while (*s) {
        if (o->len >= sizeof o->buf - 1) {
            out_flush(o);
        }
        o->buf[o->len++] = *s++;
    }
}
static void out_hex(Out *o, uint64_t v, int digits) {
    char t[20];
    int n = 0;
    do {
        t[n++] = "0123456789abcdef"[v & 15];
        v >>= 4;
    } while (v && n < 16);
    while (n < digits && n < 16) {
        t[n++] = '0';
    }
    char s[24];
    int k = 0;
    s[k++] = '0';
    s[k++] = 'x';
    while (n) {
        s[k++] = t[--n];
    }
    s[k] = 0;
    out_s(o, s);
}
static void out_dec(Out *o, uint64_t v) {
    char t[24];
    int n = 0;
    do {
        t[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    char s[24];
    int k = 0;
    while (n) {
        s[k++] = t[--n];
    }
    s[k] = 0;
    out_s(o, s);
}

static const char *exception_name(DWORD code) {
    switch (code) {
    case EXCEPTION_ACCESS_VIOLATION: return "access violation";
    case EXCEPTION_STACK_OVERFLOW: return "stack overflow";
    case EXCEPTION_ILLEGAL_INSTRUCTION: return "illegal instruction";
    case EXCEPTION_INT_DIVIDE_BY_ZERO: return "integer divide by zero";
    case EXCEPTION_FLT_DIVIDE_BY_ZERO: return "float divide by zero";
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "array bounds exceeded";
    case EXCEPTION_IN_PAGE_ERROR: return "in page error";
    case EXCEPTION_PRIV_INSTRUCTION: return "privileged instruction";
    default: return "exception";
    }
}

// ---- where an address is: module name and offset (the module list of the process, by VirtualQuery + the module that owns the memory) ----
static void out_where(Out *o, uint64_t addr) {
    HMODULE mod = NULL;
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)(uintptr_t)addr, &mod) && mod) {
        char name[MAX_PATH];
        DWORD n = GetModuleFileNameA(mod, name, sizeof name);
        const char *base = name;
        for (DWORD i = 0; i < n; i++) {
            if (name[i] == '\\' || name[i] == '/') {
                base = name + i + 1;
            }
        }
        out_s(o, n ? base : "?");
        out_s(o, "+");
        out_hex(o, addr - (uint64_t)(uintptr_t)mod, 1);
    } else {
        out_s(o, "(no module)");
    }
}

// ---- the thread's name (Windows 10 and later; the metro, device and clock threads set one) ----
static void out_thread_name(Out *o) {
    typedef HRESULT(WINAPI * GetThreadDescription_t)(HANDLE, PWSTR *);
    HMODULE k = GetModuleHandleA("kernel32.dll");
    GetThreadDescription_t gtd = k ? (GetThreadDescription_t)(void *)GetProcAddress(k, "GetThreadDescription") : NULL;
    if (!gtd) {
        k = GetModuleHandleA("kernelbase.dll");
        gtd = k ? (GetThreadDescription_t)(void *)GetProcAddress(k, "GetThreadDescription") : NULL;
    }
    PWSTR w = NULL;
    if (gtd && SUCCEEDED(gtd(GetCurrentThread(), &w)) && w) {
        char a[80];
        int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, a, sizeof a - 1, NULL, NULL);
        a[n > 0 ? n : 0] = 0;
        LocalFree(w);
        if (a[0]) {
            out_s(o, " \"");
            out_s(o, a);
            out_s(o, "\"");
            return;
        }
    }
    out_s(o, " (no name)");
}

// ---- function names from the COFF symbol table of the running .exe ----
struct Sym {
    uint32_t rva;
    uint32_t name_off; // into g_names
};
static Sym *g_syms;
static size_t g_nsyms;
static char *g_names;
static uint32_t g_image_size;

static int sym_cmp(const void *a, const void *b) {
    uint32_t x = ((const Sym *)a)->rva, y = ((const Sym *)b)->rva;
    return x < y ? -1 : (x > y ? 1 : 0);
}

// reads the symbol table of the main module's file. true when some symbols were read. allocates: only used after the first parts of the report are on disk
static bool load_symbols(void) {
    char path[MAX_PATH * 2];
    if (!GetModuleFileNameA(NULL, path, sizeof path)) {
        return false;
    }
    HANDLE f = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) {
        return false;
    }
    bool ok = false;
    HANDLE map = CreateFileMappingA(f, NULL, PAGE_READONLY, 0, 0, NULL);
    const unsigned char *p = map ? (const unsigned char *)MapViewOfFile(map, FILE_MAP_READ, 0, 0, 0) : NULL;
    LARGE_INTEGER size;
    if (p && GetFileSizeEx(f, &size) && size.QuadPart > 0x400) {
        const IMAGE_DOS_HEADER *dos = (const IMAGE_DOS_HEADER *)p;
        const IMAGE_NT_HEADERS64 *nt = (const IMAGE_NT_HEADERS64 *)(p + dos->e_lfanew);
        const IMAGE_FILE_HEADER *fh = &nt->FileHeader;
        const IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
        uint32_t symoff = fh->PointerToSymbolTable, nsym = fh->NumberOfSymbols;
        if (dos->e_magic == IMAGE_DOS_SIGNATURE && symoff && nsym && (uint64_t)symoff + (uint64_t)nsym * 18 + 4 <= (uint64_t)size.QuadPart) {
            g_image_size = nt->OptionalHeader.SizeOfImage;
            const unsigned char *symtab = p + symoff;
            const char *strtab = (const char *)(symtab + (size_t)nsym * 18);
            uint32_t strsize = *(const uint32_t *)strtab;
            g_syms = (Sym *)malloc(sizeof(Sym) * nsym);
            g_names = (char *)malloc(strsize + (size_t)nsym * 9 + 16); // (room for the short names: 8 characters + a zero each)
            if (g_syms && g_names && (uint64_t)symoff + (uint64_t)nsym * 18 + strsize <= (uint64_t)size.QuadPart) {
                memcpy(g_names, strtab, strsize);
                g_names[strsize] = 0;
                size_t k = 0;
                uint32_t extra = strsize + 1; // where the next short name goes
                for (uint32_t i = 0; i < nsym; i++) {
                    const unsigned char *e = symtab + (size_t)i * 18;
                    uint32_t value = *(const uint32_t *)(e + 8);
                    int16_t secno = *(const int16_t *)(e + 12);
                    uint16_t type = *(const uint16_t *)(e + 14);
                    unsigned char cls = e[16], aux = e[17];
                    i += aux;
                    // a function (type 0x20) in a section, external or static; (C++ names: the compiler marks them as functions)
                    if (secno > 0 && secno <= fh->NumberOfSections && (cls == 2 || cls == 3) && (type & 0xF0) == 0x20) {
                        uint32_t nameoff;
                        if (*(const uint32_t *)e == 0) {
                            nameoff = *(const uint32_t *)(e + 4);
                        } else {
                            memcpy(g_names + extra, e, 8); // a name of up to 8 characters is in the entry itself
                            g_names[extra + 8] = 0;
                            nameoff = extra;
                            extra += 9;
                        }
                        if (nameoff >= extra) {
                            continue;
                        }
                        g_syms[k].rva = sec[secno - 1].VirtualAddress + value;
                        g_syms[k].name_off = nameoff;
                        k++;
                    }
                }
                g_nsyms = k;
                qsort(g_syms, g_nsyms, sizeof(Sym), sym_cmp);
                ok = g_nsyms > 0;
            }
        }
    }
    if (p) {
        UnmapViewOfFile(p);
    }
    if (map) {
        CloseHandle(map);
    }
    CloseHandle(f);
    return ok;
}

// the name of the function that contains rva: the last symbol at or below it, within 1 MiB (a symbol that is further is a gap, not this function)
static const char *name_for(uint32_t rva, uint32_t *offset) {
    size_t lo = 0, hi = g_nsyms;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (g_syms[mid].rva <= rva) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo == 0) {
        return NULL;
    }
    const Sym *s = &g_syms[lo - 1];
    if (rva - s->rva > 0x100000) {
        return NULL;
    }
    *offset = rva - s->rva;
    return g_names + s->name_off;
}

static void make_names(char *dst, size_t n, const char *prefix, const char *ext) {
    SYSTEMTIME t;
    GetLocalTime(&t);
    char *p = dst;
    size_t room = n - 1;
    const char *parts[] = {g_dir, "\\crash-"};
    for (int i = 0; i < 2; i++) {
        for (const char *s = parts[i]; *s && room; s++, room--) {
            *p++ = *s;
        }
    }
    char num[40];
    unsigned vals[6] = {t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond};
    int k = 0;
    for (int i = 0; i < 6; i++) {
        if (i == 3) {
            num[k++] = '-';
        }
        int w = i == 0 ? 4 : 2;
        for (int d = w - 1; d >= 0; d--) {
            unsigned div = 1;
            for (int j = 0; j < d; j++) {
                div *= 10;
            }
            num[k++] = (char)('0' + (vals[i] / div) % 10);
        }
    }
    num[k++] = '-';
    DWORD pid = GetCurrentProcessId();
    char pd[12];
    int pn = 0;
    do {
        pd[pn++] = (char)('0' + pid % 10);
        pid /= 10;
    } while (pid);
    while (pn) {
        num[k++] = pd[--pn];
    }
    num[k] = 0;
    for (const char *s = num; *s && room; s++, room--) {
        *p++ = *s;
    }
    (void)prefix;
    for (const char *s = ext; *s && room; s++, room--) {
        *p++ = *s;
    }
    *p = 0;
}

// the frames of the faulting context, newest first, found with the unwind tables of the modules (no DbgHelp, no allocation)
static int unwind(const CONTEXT *ctx, uint64_t *frames, int max) {
    CONTEXT c = *ctx;
    int n = 0;
    while (n < max) {
        uint64_t ip = c.Rip;
        if (!ip) {
            break;
        }
        frames[n++] = ip;
        DWORD64 base = 0;
        RUNTIME_FUNCTION *rf = RtlLookupFunctionEntry(ip, &base, NULL);
        if (!rf) {
            // a leaf function without unwind data: the return address is at the top of the stack
            if (!c.Rsp) {
                break;
            }
            c.Rip = *(uint64_t *)c.Rsp;
            c.Rsp += 8;
        } else {
            PVOID handler;
            DWORD64 frame;
            RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, ip, rf, &c, &handler, &frame, NULL);
        }
        if (c.Rip == ip && n > 1) {
            break; // no progress
        }
    }
    return n;
}

static void write_stderr_line(const char *a, uint64_t code, uint64_t addr, const char *path) {
    Out o;
    o.file = GetStdHandle(STD_ERROR_HANDLE);
    o.len = 0;
    if (o.file == NULL || o.file == INVALID_HANDLE_VALUE) {
        return;
    }
    out_s(&o, "\nnorns CRASHED: ");
    out_s(&o, a);
    out_s(&o, " (");
    out_hex(&o, code, 8);
    out_s(&o, ") at ");
    out_hex(&o, addr, 1);
    out_s(&o, " ");
    out_where(&o, addr);
    out_s(&o, "\n");
    if (path) {
        out_s(&o, "crash report: ");
        out_s(&o, path);
        out_s(&o, "\n");
    }
    out_flush(&o);
}

static LONG WINAPI on_crash(EXCEPTION_POINTERS *ep) {
    if (InterlockedExchange(&g_in_crash, 1)) {
        return EXCEPTION_CONTINUE_SEARCH; // a second crash while reporting the first
    }
    DWORD code = ep->ExceptionRecord->ExceptionCode;
    uint64_t addr = (uint64_t)(uintptr_t)ep->ExceptionRecord->ExceptionAddress;
    const char *what = exception_name(code);
    char txt[MAX_PATH * 2 + 80];
    txt[0] = 0;
    HANDLE file = INVALID_HANDLE_VALUE;
    if (g_dir[0]) {
        make_names(txt, sizeof txt, "crash", ".txt");
        file = CreateFileA(txt, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    }
    write_stderr_line(what, code, addr, file != INVALID_HANDLE_VALUE ? txt : NULL);

    static Out o; // static: no stack use in a handler for a stack overflow
    o.file = file;
    o.len = 0;
    // 1. the exception
    out_s(&o, "norns.exe crashed: ");
    out_s(&o, what);
    out_s(&o, " (");
    out_hex(&o, code, 8);
    out_s(&o, ") at ");
    out_hex(&o, addr, 1);
    out_s(&o, " = ");
    out_where(&o, addr);
    out_s(&o, "\n");
    if (code == EXCEPTION_ACCESS_VIOLATION && ep->ExceptionRecord->NumberParameters >= 2) {
        ULONG_PTR kind = ep->ExceptionRecord->ExceptionInformation[0];
        out_s(&o, kind == 0 ? "tried to read " : (kind == 1 ? "tried to write " : "tried to execute "));
        out_hex(&o, ep->ExceptionRecord->ExceptionInformation[1], 16);
        out_s(&o, "\n");
    }
    out_s(&o, "thread ");
    out_dec(&o, GetCurrentThreadId());
    out_thread_name(&o);
    out_s(&o, ", process ");
    out_dec(&o, GetCurrentProcessId());
    out_s(&o, ", running for ");
    out_dec(&o, (GetTickCount() - g_start_tick) / 1000);
    out_s(&o, " s\n");
    HMODULE exe = GetModuleHandleA(NULL);
    out_s(&o, "norns.exe base ");
    out_hex(&o, (uint64_t)(uintptr_t)exe, 1);
    out_s(&o, " (an offset below is relative to the module it names)\n");
    if (ep->ContextRecord) {
        const CONTEXT *c = ep->ContextRecord;
        out_s(&o, "rip ");
        out_hex(&o, c->Rip, 16);
        out_s(&o, " rsp ");
        out_hex(&o, c->Rsp, 16);
        out_s(&o, " rbp ");
        out_hex(&o, c->Rbp, 16);
        out_s(&o, "\nrax ");
        out_hex(&o, c->Rax, 16);
        out_s(&o, " rcx ");
        out_hex(&o, c->Rcx, 16);
        out_s(&o, " rdx ");
        out_hex(&o, c->Rdx, 16);
        out_s(&o, " r8 ");
        out_hex(&o, c->R8, 16);
        out_s(&o, "\n");
    }
    out_flush(&o);

    // 2. the stack of the faulting context
    static uint64_t frames[48];
    int n = ep->ContextRecord ? unwind(ep->ContextRecord, frames, 48) : 0;
    out_s(&o, "\nstack (the faulting thread, newest first):\n");
    for (int i = 0; i < n; i++) {
        out_s(&o, "  #");
        out_dec(&o, (uint64_t)i);
        out_s(&o, " ");
        out_hex(&o, frames[i], 1);
        out_s(&o, " ");
        out_where(&o, frames[i]);
        out_s(&o, "\n");
        if ((i & 7) == 7) {
            out_flush(&o);
        }
    }
    out_flush(&o);

    // 3. function names of the frames that are in norns.exe
    if (n > 0 && load_symbols()) {
        out_s(&o, "\nfunctions (norns.exe symbol table, mangled C++ names: c++filt):\n");
        for (int i = 0; i < n; i++) {
            uint64_t rva = frames[i] - (uint64_t)(uintptr_t)exe;
            if (frames[i] < (uint64_t)(uintptr_t)exe || rva >= g_image_size) {
                continue;
            }
            uint32_t off = 0;
            const char *nm = name_for((uint32_t)rva, &off);
            out_s(&o, "  #");
            out_dec(&o, (uint64_t)i);
            out_s(&o, " ");
            out_s(&o, nm ? nm : "(no symbol)");
            if (nm) {
                out_s(&o, "+");
                out_hex(&o, off, 1);
            }
            out_s(&o, "\n");
        }
        out_flush(&o);
    }

    // 4. the modules
    out_s(&o, "\nmodules:\n");
    HMODULE mods[512];
    DWORD need = 0;
    if (EnumProcessModules(GetCurrentProcess(), mods, sizeof mods, &need)) {
        for (DWORD i = 0; i < need / sizeof(HMODULE) && i < 512; i++) {
            char name[MAX_PATH];
            if (GetModuleFileNameA(mods[i], name, sizeof name)) {
                out_s(&o, "  ");
                out_hex(&o, (uint64_t)(uintptr_t)mods[i], 1);
                out_s(&o, " ");
                out_s(&o, name);
                out_s(&o, "\n");
            }
        }
    }
    out_flush(&o);
    if (file != INVALID_HANDLE_VALUE) {
        CloseHandle(file);
    }

    // the minidump, last
    if (g_dir[0]) {
        char dmp[MAX_PATH * 2 + 80];
        make_names(dmp, sizeof dmp, "crash", ".dmp");
        HANDLE h = CreateFileA(dmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h != INVALID_HANDLE_VALUE) {
            MINIDUMP_EXCEPTION_INFORMATION mei;
            mei.ThreadId = GetCurrentThreadId();
            mei.ExceptionPointers = ep;
            mei.ClientPointers = FALSE;
            MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), h, MiniDumpNormal, &mei, NULL, NULL);
            FlushFileBuffers(h);
            CloseHandle(h);
        }
    }
    if (g_hook) {
        g_hook(); // best effort: the LEDs of grids off (no grids yet)
    }
    return EXCEPTION_CONTINUE_SEARCH; // the system's own handling (and an error dialog) follows
}

extern "C" void crash_report_install(const char *dir) {
    g_dir[0] = 0;
    g_start_tick = GetTickCount();
    if (dir && *dir) {
        snprintf(g_dir, sizeof g_dir, "%s", dir);
        for (char *c = g_dir; *c; c++) {
            if (*c == '/') {
                *c = '\\';
            }
        }
        // the folder may not exist yet: create each level (the launcher normally has)
        for (char *c = g_dir + 3; *c; c++) {
            if (*c == '\\') {
                *c = 0;
                CreateDirectoryA(g_dir, NULL);
                *c = '\\';
            }
        }
        CreateDirectoryA(g_dir, NULL);
    }
    SetUnhandledExceptionFilter(on_crash);
}

#endif
