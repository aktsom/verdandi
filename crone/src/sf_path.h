// sf_path.h: opening a sound file by a UTF-8 path. Linux and macOS: sf_open and SndfileHandle as they are. Windows: libsndfile's narrow sf_open takes the ANSI code page and the old 260 character limit (a name with an accent
// or a long path under an [ext] folder fails with "cannot open sndfile"); here the path becomes a wide path, made absolute, with the \\?\ prefix when it is long, and goes to sf_wchar_open / SndfileHandle(LPCWSTR).
#pragma once
#include <sndfile.h>
#include <string>

#ifdef _WIN32
#include <windows.h>

// the wide, absolute form of a UTF-8 path ('/' becomes '\'); \\?\ in front when it is 240 characters or more and a drive or UNC path
inline std::wstring sf_wide_path(const char *path) {
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
    std::wstring w(n > 0 ? (size_t)n - 1 : 0, L'\0');
    if (n > 1) {
        MultiByteToWideChar(CP_UTF8, 0, path, -1, &w[0], n);
    }
    for (auto &c : w) {
        if (c == L'/') {
            c = L'\\';
        }
    }
    if (w.compare(0, 4, L"\\\\?\\") == 0 || w.compare(0, 4, L"\\\\.\\") == 0) {
        return w;
    }
    DWORD need = GetFullPathNameW(w.c_str(), 0, nullptr, nullptr);
    if (need == 0) {
        return w;
    }
    std::wstring full((size_t)need, L'\0');
    DWORD got = GetFullPathNameW(w.c_str(), need, &full[0], nullptr);
    if (got == 0 || got >= need) {
        return w;
    }
    full.resize(got);
    if (full.size() >= 240) {
        if (full.compare(0, 2, L"\\\\") == 0) {
            full = L"\\\\?\\UNC\\" + full.substr(2);
        } else if (full.size() > 2 && full[1] == L':') {
            full = L"\\\\?\\" + full;
        }
    }
    return full;
}

inline SNDFILE *sf_open_path(const char *path, int mode, SF_INFO *info) {
    return sf_wchar_open(sf_wide_path(path).c_str(), mode, info);
}
// SndfileHandle takes a wide path on Windows: SndfileHandle file(SF_HANDLE_PATH(path), ...)  (the temporary lives until the end of the statement)
#define SF_HANDLE_PATH(p) (sf_wide_path((p).c_str()).c_str())
#else
inline SNDFILE *sf_open_path(const char *path, int mode, SF_INFO *info) {
    return sf_open(path, mode, info);
}
#define SF_HANDLE_PATH(p) (p)
#endif
