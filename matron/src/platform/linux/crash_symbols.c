/*
 * crash_symbols.c: see crash_symbols.h
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "crash_symbols.h"

#include <elf.h>
#include <fcntl.h>
#include <link.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
    uintptr_t addr, size;
    const char *name;
} sym_t;

static sym_t *table = NULL;
static size_t table_n = 0;

static int by_addr(const void *a, const void *b) {
    uintptr_t x = ((const sym_t *)a)->addr, y = ((const sym_t *)b)->addr;
    return x < y ? -1 : x > y;
}

static int first_object(struct dl_phdr_info *info, size_t size, void *data) {
    (void)size;
    *(uintptr_t *)data = (uintptr_t)info->dlpi_addr; // the first object is the main program
    return 1;
}

uintptr_t crash_symbols_bias(void) {
    uintptr_t b = 0;
    dl_iterate_phdr(first_object, &b);
    return b;
}

int crash_symbols_load(const char *exe) {
    // a second call replaces the table (the old mapping stays: a handler may be reading it)
    sym_t *old = table;
    (void)old;
    table = NULL;
    table_n = 0;
    if (exe == NULL) {
        return 0;
    }
    int fd = open(exe, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return 0;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < (off_t)sizeof(Elf64_Ehdr)) {
        close(fd);
        return 0;
    }
    unsigned char *map = (unsigned char *)mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED) {
        return 0;
    }
    size_t size = (size_t)st.st_size;
    const Elf64_Ehdr *eh = (const Elf64_Ehdr *)map;
    if (memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 || eh->e_ident[EI_CLASS] != ELFCLASS64 || eh->e_shoff == 0 || eh->e_shentsize != sizeof(Elf64_Shdr) || eh->e_shnum == 0 ||
        eh->e_shoff > size || (size - eh->e_shoff) / sizeof(Elf64_Shdr) < eh->e_shnum) {
        munmap(map, size);
        return 0;
    }
    const Elf64_Shdr *sh = (const Elf64_Shdr *)(map + eh->e_shoff);
    int found = 0;
    for (int i = 0; i < eh->e_shnum; i++) {
        if (sh[i].sh_type != SHT_SYMTAB || sh[i].sh_link >= eh->e_shnum) {
            continue;
        }
        const Elf64_Shdr *strs = &sh[sh[i].sh_link];
        if (sh[i].sh_offset > size || sh[i].sh_size > size - sh[i].sh_offset || strs->sh_offset > size || strs->sh_size > size - strs->sh_offset || sh[i].sh_entsize != sizeof(Elf64_Sym)) {
            continue;
        }
        size_t n = sh[i].sh_size / sizeof(Elf64_Sym);
        const Elf64_Sym *syms = (const Elf64_Sym *)(map + sh[i].sh_offset);
        const char *str = (const char *)(map + strs->sh_offset);
        sym_t *t = (sym_t *)malloc((n + 1) * sizeof(sym_t));
        if (t == NULL) {
            break;
        }
        size_t k = 0;
        for (size_t j = 0; j < n; j++) {
            if (ELF64_ST_TYPE(syms[j].st_info) != STT_FUNC || syms[j].st_value == 0 || syms[j].st_name >= strs->sh_size) {
                continue;
            }
            // a name that does not end inside the string table is not used
            if (memchr(str + syms[j].st_name, 0, strs->sh_size - syms[j].st_name) == NULL) {
                continue;
            }
            t[k].addr = (uintptr_t)syms[j].st_value;
            t[k].size = (uintptr_t)syms[j].st_size;
            t[k].name = str + syms[j].st_name;
            k++;
        }
        qsort(t, k, sizeof(sym_t), by_addr);
        table = t;
        table_n = k;
        found = (int)k;
        break;
    }
    if (found == 0) {
        munmap(map, size); // nothing in it is kept
    }
    return found;
}

const char *crash_symbols_find(uintptr_t addr, uintptr_t *off) {
    size_t lo = 0, hi = table_n;
    if (table == NULL || table_n == 0) {
        return NULL;
    }
    // the last symbol whose address is not above addr
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (table[mid].addr <= addr) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo == 0) {
        return NULL;
    }
    const sym_t *s = &table[lo - 1];
    uintptr_t d = addr - s->addr;
    if (d >= (s->size > 0 ? s->size : 4096)) {
        return NULL; // past the end of it: not in any function we know
    }
    if (off != NULL) {
        *off = d;
    }
    return s->name;
}
