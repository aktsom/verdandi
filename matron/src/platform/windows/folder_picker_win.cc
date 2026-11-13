/*
 * folder_picker_win.cc: the folder picker of the Windows build (docs/port/phase-m8.md): the Explorer-style window of Windows (IFileOpenDialog with the pick-folders option).
 * it runs on its own thread with its own COM apartment, so neither the audio nor the clock threads wait for it, and it hangs on the window of this program that is in front when it opens
 * (the norns window, or the screen's own window; any other window is not used as an owner).
 * "cancelled" is only the user's own Cancel (HRESULT_FROM_WIN32(ERROR_CANCELLED)). every other failure is a failure: its step and its HRESULT go to norns.log ("windows: folder picker: ...") and, in words,
 * to the screen (the callback gets n = -1 and the text in paths[0]). if the in-process window cannot be made, a small PowerShell helper shows the (older, tree style) folder window instead; that is logged too.
 * the ids come from the headers (__uuidof), not from libuuid (it defines a GUID the program already has) and not typed by hand (a wrong byte there made CoCreateInstance fail: E_NOINTERFACE).
 * files (PICK_FILE, PICK_FILES) are not in this build: -1 and the caller says so.
 */
#ifdef _WIN32
#include "platform/linux/file_picker.h"
#include <windows.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <atomic>
#include <string>
#include <thread>
#include <vector>

namespace {
std::atomic<int> open_now{0};
std::atomic<int> cancelled{0};

struct job {
    std::wstring start, title;
    HWND owner;
    picker_done_fn done;
    void *ctx;
};

enum { R_OK_PATH = 0, R_CANCEL = 1, R_FAIL = -1 };

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

std::string narrow(const wchar_t *w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (n <= 1) {
        return "";
    }
    std::string s((size_t)n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, NULL, NULL);
    s.resize((size_t)n - 1);
    return s;
}

// one line in norns.log (stderr) for a step that did not work
void log_step(const char *step, HRESULT hr) {
    fprintf(stderr, "windows: folder picker: %s failed, HRESULT 0x%08lX\n", step, (unsigned long)hr);
    fflush(stderr);
}

std::string fail_text(const char *step, HRESULT hr) {
    char b[200];
    snprintf(b, sizeof b, "the folder window could not open (%s, error 0x%08lX)", step, (unsigned long)hr);
    return b;
}

#define STEP(call, name)                                                                                                                                       \
    do {                                                                                                                                                       \
        hr = (call);                                                                                                                                           \
        if (FAILED(hr)) {                                                                                                                                      \
            log_step(name, hr);                                                                                                                                \
            err = fail_text(name, hr);                                                                                                                         \
            goto done;                                                                                                                                         \
        }                                                                                                                                                      \
    } while (0)

// the Explorer-style window. R_OK_PATH (path set), R_CANCEL (the user pressed Cancel or closed it), R_FAIL (err says which step)
int show_dialog(const job *j, std::string *path, std::string *err_out) {
    std::string err;
    int result = R_FAIL;
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    bool com = SUCCEEDED(hr);
    IFileOpenDialog *dlg = NULL;
    IShellItem *item = NULL;
    PWSTR name = NULL;
    DWORD opts = 0;
    if (FAILED(hr)) {
        log_step("CoInitializeEx", hr);
        err = fail_text("CoInitializeEx", hr);
        goto done;
    }
    STEP(CoCreateInstance(__uuidof(FileOpenDialog), NULL, CLSCTX_INPROC_SERVER, __uuidof(IFileOpenDialog), (void **)&dlg), "CoCreateInstance(FileOpenDialog)");
    STEP(dlg->GetOptions(&opts), "GetOptions");
    STEP(dlg->SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR), "SetOptions(PICKFOLDERS)");
    if (!j->title.empty()) {
        hr = dlg->SetTitle(j->title.c_str());
        if (FAILED(hr)) {
            log_step("SetTitle (goes on)", hr);
        }
    }
    if (!j->start.empty()) {
        IShellItem *si = NULL;
        hr = SHCreateItemFromParsingName(j->start.c_str(), NULL, __uuidof(IShellItem), (void **)&si);
        if (SUCCEEDED(hr) && si) {
            dlg->SetFolder(si);
            si->Release();
        } else {
            log_step("SHCreateItemFromParsingName for the start folder (goes on)", hr);
        }
    }
    hr = dlg->Show(j->owner);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        result = R_CANCEL;
        goto done;
    }
    if (FAILED(hr)) {
        log_step("Show", hr);
        err = fail_text("Show", hr);
        goto done;
    }
    STEP(dlg->GetResult(&item), "GetResult");
    STEP(item->GetDisplayName(SIGDN_FILESYSPATH, &name), "GetDisplayName(FILESYSPATH)");
    *path = narrow(name);
    if (path->empty()) {
        fprintf(stderr, "windows: folder picker: the answer was an empty path\n");
        err = "the folder window gave no path";
        goto done;
    }
    result = R_OK_PATH;
done:
    if (name) {
        CoTaskMemFree(name);
    }
    if (item) {
        item->Release();
    }
    if (dlg) {
        dlg->Release();
    }
    if (com) {
        CoUninitialize();
    }
    *err_out = err;
    return result;
}

// the helper: powershell shows the standard folder window (tree style). its answer is the path on stdout (UTF-8). exit code 0 = a folder, 3 = cancelled
int show_helper(std::string *path, std::string *err_out) {
    wchar_t sysdir[MAX_PATH];
    if (!GetSystemDirectoryW(sysdir, MAX_PATH)) {
        *err_out = "the helper window could not be started (no system folder)";
        return R_FAIL;
    }
    std::wstring ps = std::wstring(sysdir) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
    std::wstring cmd = L"\"" + ps +
                       L"\" -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -Command \"Add-Type -AssemblyName System.Windows.Forms; "
                       L"$f = New-Object System.Windows.Forms.Form; $f.TopMost = $true; $d = New-Object System.Windows.Forms.FolderBrowserDialog; "
                       L"$d.Description = 'Choose a folder with samples'; $d.ShowNewFolderButton = $false; "
                       L"if ($d.ShowDialog($f) -eq 'OK') { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; [Console]::Out.Write($d.SelectedPath); exit 0 } else { exit 3 }\"";
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    HANDLE rd = NULL, wr = NULL;
    if (!CreatePipe(&rd, &wr, &sa, 0)) {
        *err_out = "the helper window could not be started (pipe)";
        return R_FAIL;
    }
    SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);
    STARTUPINFOW si = {};
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = wr;
    si.hStdError = wr;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    PROCESS_INFORMATION pi = {};
    std::vector<wchar_t> mut(cmd.begin(), cmd.end());
    mut.push_back(0);
    BOOL ok = CreateProcessW(ps.c_str(), mut.data(), NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
    DWORD le = GetLastError();
    CloseHandle(wr);
    if (!ok) {
        CloseHandle(rd);
        fprintf(stderr, "windows: folder picker: the PowerShell helper did not start, error %lu\n", (unsigned long)le);
        char b[160];
        snprintf(b, sizeof b, "the helper window could not be started (error %lu)", (unsigned long)le);
        *err_out = b;
        return R_FAIL;
    }
    std::string out;
    char buf[1024];
    DWORD got;
    while (ReadFile(rd, buf, sizeof buf, &got, NULL) && got > 0) {
        out.append(buf, got);
    }
    CloseHandle(rd);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    if (code == 3) {
        return R_CANCEL;
    }
    while (!out.empty() && (out.back() == '\r' || out.back() == '\n')) {
        out.pop_back();
    }
    if (code == 0 && !out.empty()) {
        *path = out;
        return R_OK_PATH;
    }
    fprintf(stderr, "windows: folder picker: the PowerShell helper ended with code %lu\n", (unsigned long)code);
    char b[160];
    snprintf(b, sizeof b, "the helper window failed (code %lu)", (unsigned long)code);
    *err_out = b;
    return R_FAIL;
}

void run(job *j) {
    std::string path, err;
    int r = show_dialog(j, &path, &err);
    if (r == R_FAIL) {
        fprintf(stderr, "windows: folder picker: the in-process window did not work, trying the PowerShell helper\n");
        std::string err2;
        r = show_helper(&path, &err2);
        if (r == R_FAIL) {
            err += "; " + err2;
        }
    }
    open_now = 0;
    if (!cancelled.load() && j->done) {
        if (r == R_OK_PATH) {
            const char *one[1] = {path.c_str()};
            j->done(one, 1, j->ctx);
        } else if (r == R_CANCEL) {
            j->done(NULL, 0, j->ctx);
        } else {
            const char *one[1] = {err.c_str()};
            j->done(one, -1, j->ctx); // -1: it failed, paths[0] says how (a cancel is 0)
        }
    }
    delete j;
}

// a window of this program that can be an owner, else none
HWND usable_owner(void) {
    HWND w = GetForegroundWindow();
    if (!w || !IsWindow(w)) {
        return NULL;
    }
    DWORD pid = 0;
    GetWindowThreadProcessId(w, &pid);
    return pid == GetCurrentProcessId() ? w : NULL;
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
    job *j = new job{widen(start_dir), widen(title), usable_owner(), done, ctx};
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
