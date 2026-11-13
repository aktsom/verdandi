/* win_paths.c: see win_paths.h */
#ifdef _WIN32
#include "win_paths.h"
#include <shlobj.h>
#include <windows.h>
#include <string.h>

/* FOLDERID_Pictures {33E28130-4E1E-4676-835A-98395C3BC3BB} written out: no libuuid needed */
static const GUID k_folder_pictures = {0x33E28130, 0x4E1E, 0x4676, {0x83, 0x5A, 0x98, 0x39, 0x5C, 0x3B, 0xC3, 0xBB}};

static int to_wide(const char *u, wchar_t *w, int n) {
    if (!u || MultiByteToWideChar(CP_UTF8, 0, u, -1, w, n) <= 0) {
        return -1;
    }
    for (wchar_t *q = w; *q; q++) {
        if (*q == L'/') {
            *q = L'\\';
        }
    }
    return 0;
}

int win_known_pictures(char *out, size_t n) {
    PWSTR w = NULL;
    out[0] = 0;
    if (FAILED(SHGetKnownFolderPath(&k_folder_pictures, 0, NULL, &w)) || !w) {
        return -1;
    }
    int r = WideCharToMultiByte(CP_UTF8, 0, w, -1, out, (int)n, NULL, NULL);
    CoTaskMemFree(w);
    if (r <= 0) {
        out[0] = 0;
        return -1;
    }
    for (char *q = out; *q; q++) {
        if (*q == '\\') {
            *q = '/';
        }
    }
    return 0;
}

FILE *win_fopen_utf8(const char *path, const char *mode) {
    wchar_t w[32768 / 4], m[16];
    int i = 0;
    if (to_wide(path, w, (int)(sizeof w / sizeof w[0])) != 0 || !mode) {
        return NULL;
    }
    for (; mode[i] && i < 15; i++) {
        m[i] = (wchar_t)(unsigned char)mode[i];
    }
    m[i] = 0;
    return _wfopen(w, m);
}

int win_exists_utf8(const char *path) {
    wchar_t w[32768 / 4];
    return to_wide(path, w, (int)(sizeof w / sizeof w[0])) == 0 && GetFileAttributesW(w) != INVALID_FILE_ATTRIBUTES;
}

int win_unlink_utf8(const char *path) {
    wchar_t w[32768 / 4];
    return to_wide(path, w, (int)(sizeof w / sizeof w[0])) == 0 && DeleteFileW(w) ? 0 : -1;
}

int win_mkdirs_utf8(const char *path) {
    wchar_t w[32768 / 4];
    if (to_wide(path, w, (int)(sizeof w / sizeof w[0])) != 0) {
        return -1;
    }
    for (wchar_t *q = w + 1; *q; q++) {
        if (*q == L'\\') {
            *q = 0;
            if (wcslen(w) > 2) {
                CreateDirectoryW(w, NULL);
            }
            *q = L'\\';
        }
    }
    CreateDirectoryW(w, NULL);
    DWORD a = GetFileAttributesW(w);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY) ? 0 : -1;
}
#endif
