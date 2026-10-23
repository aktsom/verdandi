#ifndef CRONE_AUDIOSTATUS_H
#define CRONE_AUDIOSTATUS_H

// what crone connected to, and what went wrong, for the norns window and SYSTEM > AUDIO (Linux desktop)

#include <mutex>
#include <string>

namespace crone {
namespace AudioStatus {

struct State {
    std::mutex mtx;
    std::string warning;
    std::string inClient;
    std::string outClient;
};

inline State &state() {
    static State s;
    return s;
}

inline void addWarning(const std::string &w) {
    if (w.empty()) {
        return;
    }
    State &s = state();
    std::lock_guard<std::mutex> l(s.mtx);
    if (!s.warning.empty()) {
        s.warning += "; ";
    }
    s.warning += w;
}

inline void setClient(bool input, const std::string &c) {
    State &s = state();
    std::lock_guard<std::mutex> l(s.mtx);
    (input ? s.inClient : s.outClient) = c;
}

inline std::string get(int which) { // 0 warning, 1 input client, 2 output client
    State &s = state();
    std::lock_guard<std::mutex> l(s.mtx);
    return which == 0 ? s.warning : which == 1 ? s.inClient : s.outClient;
}

} // namespace AudioStatus
} // namespace crone

#endif
