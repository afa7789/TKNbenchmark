#include "calc.hpp"

#include <charconv>
#include <iostream>
#include <string>

int main() {
    std::ios::sync_with_stdio(false);

    std::string line;
    std::string out;
    out.reserve(1 << 16);

    while (std::getline(std::cin, line)) {
        if (calc::is_blank(line)) continue;
        if (const auto value = calc::evaluate(line)) {
            char buf[24];
            const auto [end, ec] = std::to_chars(buf, buf + sizeof buf, *value);
            out.append(buf, end);
        } else {
            out += "error";
        }
        out += '\n';
        if (out.size() >= (1 << 16)) {
            std::cout << out;
            out.clear();
        }
    }
    std::cout << out;
    std::cout.flush();
    return 0;
}
