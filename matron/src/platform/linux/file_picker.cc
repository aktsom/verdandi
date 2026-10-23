/*
 * file_picker.cc: see file_picker.h
 */

#include "file_picker.h"

#include <errno.h>
#include <fcntl.h>
#include <gio/gio.h>
#include <glib.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include <string>
#include <vector>

namespace {

enum backend_t { B_NONE, B_PORTAL, B_ZENITY, B_KDIALOG };

struct request {
    int mode;
    std::string start_dir;
    std::string title;
    picker_done_fn done;
    void *ctx;
    backend_t backend;
    // cancellation
    volatile bool cancelled;
    GMainLoop *loop;      // portal
    pid_t child;          // zenity, kdialog
    std::string handle;   // portal request object path
    GDBusConnection *conn;
    std::vector<std::string> result; // portal: what the dialog answered
};

pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
request *active = NULL;
unsigned counter = 0;

bool on_path(const char *prog) {
    gchar *p = g_find_program_in_path(prog);
    bool found = p != NULL;
    g_free(p);
    return found;
}

// the portal answers on the session bus
bool portal_there(void) {
    GError *err = NULL;
    GDBusConnection *conn = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &err);
    if (conn == NULL) {
        g_clear_error(&err);
        return false;
    }
    GVariant *r = g_dbus_connection_call_sync(conn, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                                              "org.freedesktop.DBus", "NameHasOwner",
                                              g_variant_new("(s)", "org.freedesktop.portal.Desktop"),
                                              G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 2000, NULL, &err);
    bool has = false;
    if (r != NULL) {
        g_variant_get(r, "(b)", &has);
        g_variant_unref(r);
    }
    if (!has) {
        // activatable on demand?
        GVariant *a = g_dbus_connection_call_sync(conn, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                                                  "org.freedesktop.DBus", "StartServiceByName",
                                                  g_variant_new("(su)", "org.freedesktop.portal.Desktop", 0),
                                                  NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, NULL);
        has = a != NULL;
        if (a != NULL) {
            g_variant_unref(a);
        }
    }
    g_clear_error(&err);
    g_object_unref(conn);
    return has;
}

backend_t detect(void) {
    const char *force = getenv("NORNS_PICKER");
    if (force != NULL && force[0] != '\0') {
        if (!strcmp(force, "portal")) {
            return B_PORTAL;
        }
        if (!strcmp(force, "zenity")) {
            return on_path("zenity") ? B_ZENITY : B_NONE;
        }
        if (!strcmp(force, "kdialog")) {
            return on_path("kdialog") ? B_KDIALOG : B_NONE;
        }
        return B_NONE;
    }
    if (portal_there()) {
        return B_PORTAL;
    }
    if (on_path("zenity")) {
        return B_ZENITY;
    }
    if (on_path("kdialog")) {
        return B_KDIALOG;
    }
    return B_NONE;
}

backend_t chosen = B_NONE;
bool detected = false;

void finish(request *r, const std::vector<std::string> &paths) {
    std::vector<const char *> list;
    for (const std::string &p : paths) {
        list.push_back(p.c_str());
    }
    bool cancelled = r->cancelled;
    picker_done_fn done = r->done;
    void *ctx = r->ctx;
    pthread_mutex_lock(&lock);
    if (active == r) {
        active = NULL;
    }
    pthread_mutex_unlock(&lock);
    delete r;
    if (!cancelled && done != NULL) {
        done(list.data(), (int)list.size(), ctx);
    }
}

//--- portal

void portal_response(GDBusConnection *conn, const gchar *sender, const gchar *path, const gchar *iface,
                     const gchar *signal, GVariant *params, gpointer data) {
    (void)conn;
    (void)sender;
    (void)path;
    (void)iface;
    (void)signal;
    request *r = (request *)data;
    guint32 code = 2;
    GVariant *results = NULL;
    g_variant_get(params, "(u@a{sv})", &code, &results);
    std::vector<std::string> &paths = r->result;
    if (code == 0 && results != NULL) {
        GVariant *uris = g_variant_lookup_value(results, "uris", G_VARIANT_TYPE("as"));
        if (uris != NULL) {
            GVariantIter it;
            gchar *uri;
            g_variant_iter_init(&it, uris);
            while (g_variant_iter_next(&it, "s", &uri)) {
                gchar *file = g_filename_from_uri(uri, NULL, NULL);
                if (file != NULL) {
                    paths.push_back(file);
                    g_free(file);
                }
                g_free(uri);
            }
            g_variant_unref(uris);
        }
    }
    if (results != NULL) {
        g_variant_unref(results);
    }
    // the thread that runs the loop hands the answer on
    g_main_loop_quit(r->loop);
}

void *portal_thread(void *arg) {
    request *r = (request *)arg;
    GMainContext *context = g_main_context_new();
    g_main_context_push_thread_default(context);
    GError *err = NULL;
    GDBusConnection *conn = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &err);
    if (conn == NULL) {
        fprintf(stderr, "file_picker: no session bus: %s\n", err != NULL ? err->message : "?");
        g_clear_error(&err);
        g_main_context_pop_thread_default(context);
        g_main_context_unref(context);
        finish(r, {});
        return NULL;
    }
    pthread_mutex_lock(&lock);
    r->conn = conn;
    pthread_mutex_unlock(&lock);

    // the Request object the portal will make, known in advance (portal documentation): subscribe
    // before the call so the answer cannot be missed
    char token[64];
    snprintf(token, sizeof token, "verdandi%d_%u", (int)getpid(), ++counter);
    std::string sender = g_dbus_connection_get_unique_name(conn) + 1;
    for (char &c : sender) {
        if (c == '.') {
            c = '_';
        }
    }
    std::string path = "/org/freedesktop/portal/desktop/request/" + sender + "/" + token;
    GMainLoop *loop = g_main_loop_new(context, FALSE);
    pthread_mutex_lock(&lock);
    r->loop = loop;
    pthread_mutex_unlock(&lock);
    guint sub = g_dbus_connection_signal_subscribe(conn, "org.freedesktop.portal.Desktop",
                                                   "org.freedesktop.portal.Request", "Response", path.c_str(), NULL,
                                                   G_DBUS_SIGNAL_FLAGS_NONE, portal_response, r, NULL);

    GVariantBuilder opts;
    g_variant_builder_init(&opts, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&opts, "{sv}", "handle_token", g_variant_new_string(token));
    g_variant_builder_add(&opts, "{sv}", "modal", g_variant_new_boolean(FALSE));
    g_variant_builder_add(&opts, "{sv}", "multiple", g_variant_new_boolean(r->mode == PICK_FILES));
    g_variant_builder_add(&opts, "{sv}", "directory", g_variant_new_boolean(r->mode == PICK_FOLDER));
    if (!r->start_dir.empty()) {
        g_variant_builder_add(&opts, "{sv}", "current_folder", g_variant_new_bytestring(r->start_dir.c_str()));
    }
    GVariant *reply = g_dbus_connection_call_sync(
        conn, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.FileChooser",
        "OpenFile", g_variant_new("(ss@a{sv})", "", r->title.c_str(), g_variant_builder_end(&opts)),
        G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 10000, NULL, &err);
    if (reply == NULL) {
        fprintf(stderr, "file_picker: portal OpenFile failed: %s\n", err != NULL ? err->message : "?");
        g_clear_error(&err);
        g_dbus_connection_signal_unsubscribe(conn, sub);
        pthread_mutex_lock(&lock);
        r->loop = NULL;
        pthread_mutex_unlock(&lock);
        finish(r, {});
        g_main_loop_unref(loop);
        g_object_unref(conn);
        g_main_context_pop_thread_default(context);
        g_main_context_unref(context);
        return NULL;
    }
    gchar *handle = NULL;
    g_variant_get(reply, "(o)", &handle);
    pthread_mutex_lock(&lock);
    r->handle = handle;
    pthread_mutex_unlock(&lock);
    g_free(handle);
    g_variant_unref(reply);

    if (!r->cancelled) {
        g_main_loop_run(loop);
    } else {
        // closed while the call was out
        g_dbus_connection_call_sync(conn, "org.freedesktop.portal.Desktop", r->handle.c_str(),
                                    "org.freedesktop.portal.Request", "Close", NULL, NULL, G_DBUS_CALL_FLAGS_NONE, 2000,
                                    NULL, NULL);
    }
    g_dbus_connection_signal_unsubscribe(conn, sub);
    pthread_mutex_lock(&lock);
    r->loop = NULL;
    pthread_mutex_unlock(&lock);
    std::vector<std::string> answer = r->result;
    finish(r, answer);
    g_main_loop_unref(loop);
    g_object_unref(conn);
    g_main_context_pop_thread_default(context);
    g_main_context_unref(context);
    return NULL;
}

//--- zenity, kdialog

void *command_thread(void *arg) {
    request *r = (request *)arg;
    std::vector<std::string> args;
    const std::string dir = r->start_dir.empty() ? "" : r->start_dir + "/";
    if (r->backend == B_ZENITY) {
        args = {"zenity", "--file-selection", "--title=" + r->title, "--separator=\n"};
        if (r->mode == PICK_FILES) {
            args.push_back("--multiple");
        }
        if (r->mode == PICK_FOLDER) {
            args.push_back("--directory");
        }
        if (!dir.empty()) {
            args.push_back("--filename=" + dir);
        }
    } else {
        args = {"kdialog", "--title", r->title};
        if (r->mode == PICK_FOLDER) {
            args.push_back("--getexistingdirectory");
        } else {
            args.push_back("--getopenfilename");
        }
        args.push_back(dir.empty() ? "." : dir);
        if (r->mode == PICK_FILES) {
            args.push_back("--multiple");
            args.push_back("--separate-output");
        }
    }
    std::vector<char *> argv;
    for (std::string &a : args) {
        argv.push_back(&a[0]);
    }
    argv.push_back(NULL);

    int out[2];
    if (pipe(out) != 0) {
        finish(r, {});
        return NULL;
    }
    pid_t pid = fork();
    if (pid == 0) {
        int null = open("/dev/null", O_RDWR);
        dup2(null, 0);
        dup2(out[1], 1);
        dup2(null, 2);
        close(out[0]);
        close(out[1]);
        execvp(argv[0], argv.data());
        _exit(127);
    }
    close(out[1]);
    if (pid < 0) {
        close(out[0]);
        finish(r, {});
        return NULL;
    }
    r->child = pid;
    std::string text;
    char buf[4096];
    ssize_t n;
    while ((n = read(out[0], buf, sizeof buf)) > 0 || (n < 0 && errno == EINTR)) {
        if (n > 0) {
            text.append(buf, (size_t)n);
        }
    }
    close(out[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    std::vector<std::string> paths;
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        size_t start = 0;
        while (start < text.size()) {
            size_t end = text.find('\n', start);
            if (end == std::string::npos) {
                end = text.size();
            }
            if (end > start) {
                paths.push_back(text.substr(start, end - start));
            }
            start = end + 1;
        }
    }
    finish(r, paths);
    return NULL;
}

} // namespace

const char *picker_backend(void) {
    pthread_mutex_lock(&lock);
    if (!detected) {
        chosen = detect();
        detected = true;
    }
    backend_t b = chosen;
    pthread_mutex_unlock(&lock);
    return b == B_PORTAL ? "portal" : b == B_ZENITY ? "zenity" : b == B_KDIALOG ? "kdialog" : "none";
}

int picker_open(int mode, const char *start_dir, const char *title, picker_done_fn done, void *ctx) {
    picker_backend(); // detects once
    pthread_mutex_lock(&lock);
    if (chosen == B_NONE) {
        pthread_mutex_unlock(&lock);
        return -1;
    }
    if (active != NULL) {
        // a dialog is open: it stays (the portal cannot be pointed somewhere else)
        pthread_mutex_unlock(&lock);
        return 0;
    }
    request *r = new request();
    r->mode = mode;
    r->start_dir = start_dir != NULL ? start_dir : "";
    r->title = title != NULL ? title : "Open";
    r->done = done;
    r->ctx = ctx;
    r->backend = chosen;
    r->cancelled = false;
    r->loop = NULL;
    r->child = 0;
    r->conn = NULL;
    active = r;
    pthread_mutex_unlock(&lock);
    pthread_t t;
    if (pthread_create(&t, NULL, chosen == B_PORTAL ? portal_thread : command_thread, r) != 0) {
        pthread_mutex_lock(&lock);
        active = NULL;
        pthread_mutex_unlock(&lock);
        delete r;
        return -1;
    }
    pthread_detach(t);
    return 0;
}

void picker_close(void) {
    pthread_mutex_lock(&lock);
    request *r = active;
    if (r == NULL) {
        pthread_mutex_unlock(&lock);
        return;
    }
    r->cancelled = true;
    if (r->child > 0) {
        kill(r->child, SIGTERM);
    }
    GMainLoop *loop = r->loop;
    if (loop != NULL) {
        // portal: ask the dialog to go, then end the wait. the thread frees the request
        if (r->conn != NULL && !r->handle.empty()) {
            g_dbus_connection_call(r->conn, "org.freedesktop.portal.Desktop", r->handle.c_str(),
                                   "org.freedesktop.portal.Request", "Close", NULL, NULL, G_DBUS_CALL_FLAGS_NONE, 2000,
                                   NULL, NULL, NULL);
        }
        g_main_loop_quit(loop);
    }
    pthread_mutex_unlock(&lock);
}
