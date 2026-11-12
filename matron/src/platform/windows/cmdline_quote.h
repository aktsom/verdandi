// cmdline_quote.h (Windows build): one argument for a Windows command line, by the rules of CommandLineToArgvW and the C runtime (busybox-w32, MinGW programs and Windows' own ones parse them alike): the argument is put
// in double quotes; a quote inside is \" ; backslashes are literal EXCEPT those directly before a quote (they are doubled, and one more makes the quote literal) or before the closing quote (doubled). the sidecar
// used to put a backslash before EVERY backslash: "home\ input" (a blank escaped for the shell) arrived as "home\\ input" and the shell saw an escaped backslash and a blank. pure: linux/tests/cmdline_quote_test.cpp
#pragma once
#include <string>

static inline std::string quote_cmdline_arg(const std::string &a) {
    std::string out = "\"";
    size_t i = 0;
    while (i < a.size()) {
        size_t slashes = 0;
        while (i < a.size() && a[i] == '\\') {
            slashes++;
            i++;
        }
        if (i == a.size()) {
            out.append(slashes * 2, '\\'); // before the closing quote
            break;
        }
        if (a[i] == '"') {
            out.append(slashes * 2 + 1, '\\');
            out += '"';
        } else {
            out.append(slashes, '\\');
            out += a[i];
        }
        i++;
    }
    out += '"';
    return out;
}
