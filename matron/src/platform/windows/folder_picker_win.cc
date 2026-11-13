/*
 * folder_picker_win.cc: the folder picker of the Windows build (docs/port/phase-m8.md): the Explorer-style window of Windows (IFileOpenDialog with the pick-folders option).
 * it runs on its own thread with its own COM apartment, so neither the audio nor the clock threads wait for it, and it hangs on the window that is in front when it opens (the norns window, or the screen's own window).
 * the answer is a UTF-8 path from the wide API (any letters, long paths). picker_open keeps the name and the shape of platform/linux/file_picker.h, so the shared code links unchanged.
 * files (PICK_FILE, PICK_FILES) are not in this build: -1 and the caller says so.
 */
#ifdef _WIN32
#include "platform/linux/file_picker.h"
#include <windows.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <stdlib.h>
#include <string.h>
#include <atomic>
#include <string>
#include <thread>

namespace {
std::atomic<int> open_now{0};
std::atomic<int> cancelled{0};

struct job {
    int mode;
    std::wstring start, title;
    HWND owner;
    picker_done_fn done;
    void *ctx;
};

std::wstring widen(const char *s) {
    if (!s || !*s) {
        return L"";
    }
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (n <= 0) {
        return L"";
    }
    std::wstring w((size_t)n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
    w.resize((size_t)n - 1);
    return w;
}

void run(job *j) {
    char *utf8 = NULL;
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    bool com = SUCCEEDED(hr);
    IFileOpenDialog *dlg = NULL;
    if (SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dlg))) && dlg) {
        DWORD opts = 0;
        dlg->GetOptions(&opts);
        dlg->SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR);
        if (!j->title.empty()) {
            dlg->SetTitle(j->title.c_str());
        }
        if (!j->start.empty()) {
            IShellItem *si = NULL;
            if (SUCCEEDED(SHCreateItemFromParsingName(j->start.c_str(), NULL, IID_PPV_ARGS(&si))) && si) {
                dlg->SetFolder(si);
                si->Release();
            }
        }
        if (SUCCEEDED(dlg->Show(j->owner))) {
            IShellItem *item = NULL;
            if (SUCCEEDED(dlg->GetResult(&item)) && item) {
                PWSTR path = NULL;
                if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
                    int n = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
                    if (n > 0) {
                        utf8 = (char *)malloc((size_t)n);
                        if (utf8) {
                            WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8, n, NULL, NULL);
                        }
                    }
                    CoTaskMemFree(path);
                }
                item->Release();
            }
        }
        dlg->Release();
    }
    if (com) {
        CoUninitialize();
    }
    open_now = 0;
    if (!cancelled.load() && j->done) {
        const char *one[1] = {utf8};
        j->done(one, utf8 ? 1 : 0, j->ctx);
    }
    free(utf8);
    delete j;
}
} // namespace

extern "C" {
int picker_open(int mode, const char *start_dir, const char *title, picker_done_fn done, void *ctx) {
    if (mode != PICK_FOLDER) {
        return -1; // files: not in this build yet
    }
    int expected = 0;
    if (!open_now.compare_exchange_strong(expected, 1)) {
        return 0; // already open: nothing changes
    }
    cancelled = 0;
    job *j = new job{mode, widen(start_dir), widen(title), GetForegroundWindow(), done, ctx};
    try {
        std::thread(run, j).detach();
    } catch (...) {
        open_now = 0;
        delete j;
        return -1;
    }
    return 0;
}
void picker_close(void) {
    cancelled = 1; // the window stays until it is closed; its answer is dropped
}
const char *picker_backend(void) {
    return "windows";
}
} // extern "C"
#endif
