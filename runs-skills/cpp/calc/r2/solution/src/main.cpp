#include <cstdio>
#include <iostream>
#include <iterator>
#include <string>
#include <string_view>

#include "calc.hpp"

int main() {
    std::ios::sync_with_stdio(false);

    const std::string input{std::istreambuf_iterator<char>{std::cin}, {}};
    std::string output;
    output.reserve(input.size());

    std::string_view rest{input};
    while (!rest.empty()) {
        const auto nl = rest.find('\n');
        const std::string_view line = rest.substr(0, nl);
        rest = (nl == std::string_view::npos) ? std::string_view{} : rest.substr(nl + 1);

        if (calc::is_blank(line)) continue;
        if (const auto value = calc::evaluate(line)) {
            output += std::to_string(*value);
        } else {
            output += "error";
        }
        output += '\n';
    }

    std::cout << output;
    std::cout.flush();
    return 0;
}
