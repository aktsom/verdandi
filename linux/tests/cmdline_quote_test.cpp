// the quoting of one argument for a Windows command line (matron/src/platform/windows/cmdline_quote.h), checked against a second, independent parser of the CommandLineToArgvW rules.
//   g++ -std=c++17 -I matron/src/platform/windows linux/tests/cmdline_quote_test.cpp -o /tmp/cqt && /tmp/cqt
#include <stdio.h>
#include <string>
#include <vector>
#include "cmdline_quote.h"
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)
// the rules of the C runtime / CommandLineToArgvW for the arguments after the program name
static std::vector<std::string> parse(const std::string &s) {
    std::vector<std::string> args;
    size_t i = 0;
    while (i < s.size()) {
        while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) i++;
        if (i >= s.size()) break;
        std::string cur;
        bool inq = false;
        while (i < s.size() && (inq || (s[i] != ' ' && s[i] != '\t'))) {
            size_t bs = 0;
            while (i < s.size() && s[i] == '\\') { bs++; i++; }
            if (i < s.size() && s[i] == '"') {
                cur.append(bs / 2, '\\');
                if (bs % 2) { cur += '"'; i++; }
                else { inq = !inq; i++; }
            } else {
                cur.append(bs, '\\');
                if (i < s.size()) cur += s[i++];
            }
        }
        args.push_back(cur);
    }
    return args;
}
int main() {
    for (const std::string a : {"plain", "with space", "D:/a/user home input/dust/x", "home\\ input", "a\\b", "back\\\\slash", "ends with slash\\", "ends two\\\\", "quote\"inside", "quote\\\"after slash", "two\\\\\"slashes quote", "echo same > /a/b && cp \"x y\" 'z w'", "", "tab\there", "\\\\server\\share\\dir with space\\"}) {
        auto got = parse(quote_cmdline_arg(a));
        CHECK(got.size() == 1 && got[0] == a, "round trip of [%s]: got %zu args, first [%s]", a.c_str(), got.size(), got.empty() ? "" : got[0].c_str());
    }
    // a whole command line: sh -c "<command>"
    std::string cmd = "cp /home/we/a\\ b /x && echo \"hi\"";
    auto got = parse("sh -c " + quote_cmdline_arg(cmd));
    CHECK(got.size() == 3 && got[2] == cmd, "sh -c with a command that has escaped blanks and quotes");
    printf(fails == 0 ? "cmdline_quote: all checks pass\n" : "cmdline_quote: %d failures\n", fails);
    return fails != 0;
}
