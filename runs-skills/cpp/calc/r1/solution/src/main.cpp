// calc: a 64-bit signed integer expression evaluator (see SPEC.md).
//
// Each input line is parsed and evaluated with an operator-precedence
// (shunting-yard) algorithm using explicit stacks, so arbitrarily deep
// nesting cannot exhaust the call stack.

#include <charconv>
#include <cstdint>
#include <iostream>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

namespace {

using Int = std::int64_t;

enum class Op : char { Add, Sub, Mul, Div, Mod, Neg, LParen };

[[nodiscard]] constexpr int precedence(Op op) noexcept {
    switch (op) {
        case Op::Add:
        case Op::Sub: return 1;
        case Op::Mul:
        case Op::Div:
        case Op::Mod: return 2;
        case Op::Neg: return 3;
        case Op::LParen: return 0;
    }
    return 0;
}

[[nodiscard]] std::optional<Op> binary_op(char c) noexcept {
    switch (c) {
        case '+': return Op::Add;
        case '-': return Op::Sub;
        case '*': return Op::Mul;
        case '/': return Op::Div;
        case '%': return Op::Mod;
        default: return std::nullopt;
    }
}

[[nodiscard]] std::optional<Int> apply_binary(Op op, Int a, Int b) noexcept {
    Int r{};
    switch (op) {
        case Op::Add:
            if (__builtin_add_overflow(a, b, &r)) return std::nullopt;
            return r;
        case Op::Sub:
            if (__builtin_sub_overflow(a, b, &r)) return std::nullopt;
            return r;
        case Op::Mul:
            if (__builtin_mul_overflow(a, b, &r)) return std::nullopt;
            return r;
        case Op::Div:
            if (b == 0 || (a == INT64_MIN && b == -1)) return std::nullopt;
            return a / b;
        case Op::Mod:
            if (b == 0) return std::nullopt;
            if (b == -1) return 0;
            return a % b;
        case Op::Neg:
        case Op::LParen: break;
    }
    return std::nullopt;
}

[[nodiscard]] constexpr bool is_blank(char c) noexcept { return c == ' ' || c == '\t'; }
[[nodiscard]] constexpr bool is_digit(char c) noexcept { return c >= '0' && c <= '9'; }

class Evaluator {
public:
    // Returns the value of `line`, or nullopt on any syntax or arithmetic error.
    [[nodiscard]] std::optional<Int> evaluate(std::string_view line) {
        values_.clear();
        ops_.clear();
        bool expect_operand = true;
        std::size_t i = 0;
        const std::size_t n = line.size();

        while (true) {
            while (i < n && is_blank(line[i])) ++i;
            if (i == n) break;
            const char c = line[i];

            if (expect_operand) {
                if (is_digit(c)) {
                    std::size_t end = i;
                    while (end < n && is_digit(line[end])) ++end;
                    Int v{};
                    auto [ptr, ec] = std::from_chars(line.data() + i, line.data() + end, v);
                    if (ec != std::errc{}) return std::nullopt;  // literal out of range
                    values_.push_back(v);
                    i = end;
                    expect_operand = false;
                } else if (c == '-') {
                    ops_.push_back(Op::Neg);
                    ++i;
                } else if (c == '(') {
                    ops_.push_back(Op::LParen);
                    ++i;
                } else {
                    return std::nullopt;
                }
            } else if (const auto op = binary_op(c)) {
                // Left-associative: reduce operators of equal or higher precedence.
                while (!ops_.empty() && precedence(ops_.back()) >= precedence(*op)) {
                    if (!reduce()) return std::nullopt;
                }
                ops_.push_back(*op);
                ++i;
                expect_operand = true;
            } else if (c == ')') {
                while (!ops_.empty() && ops_.back() != Op::LParen) {
                    if (!reduce()) return std::nullopt;
                }
                if (ops_.empty()) return std::nullopt;  // unmatched ')'
                ops_.pop_back();
                ++i;
            } else {
                return std::nullopt;
            }
        }

        if (expect_operand) return std::nullopt;  // missing operand (or empty input)
        while (!ops_.empty()) {
            if (ops_.back() == Op::LParen) return std::nullopt;  // unmatched '('
            if (!reduce()) return std::nullopt;
        }
        if (values_.size() != 1) return std::nullopt;
        return values_.back();
    }

private:
    // Pops the top operator and applies it to the value stack.
    [[nodiscard]] bool reduce() {
        const Op op = ops_.back();
        ops_.pop_back();
        if (op == Op::Neg) {
            if (values_.empty()) return false;
            Int& v = values_.back();
            if (v == INT64_MIN) return false;
            v = -v;
            return true;
        }
        if (op == Op::LParen || values_.size() < 2) return false;
        const Int rhs = values_.back();
        values_.pop_back();
        const auto result = apply_binary(op, values_.back(), rhs);
        if (!result) return false;
        values_.back() = *result;
        return true;
    }

    std::vector<Int> values_;
    std::vector<Op> ops_;
};

[[nodiscard]] bool is_blank_line(std::string_view line) noexcept {
    for (const char c : line) {
        if (!is_blank(c)) return false;
    }
    return true;
}

}  // namespace

int main() {
    std::ios::sync_with_stdio(false);
    const std::string input{std::istreambuf_iterator<char>{std::cin}, std::istreambuf_iterator<char>{}};

    Evaluator evaluator;
    std::string output;
    output.reserve(input.size());

    std::string_view rest{input};
    while (!rest.empty()) {
        const auto nl = rest.find('\n');
        const std::string_view line = rest.substr(0, nl);
        rest = nl == std::string_view::npos ? std::string_view{} : rest.substr(nl + 1);

        if (is_blank_line(line)) continue;
        if (const auto value = evaluator.evaluate(line)) {
            char buf[24];
            const auto [ptr, ec] = std::to_chars(std::begin(buf), std::end(buf), *value);
            output.append(buf, ptr);
        } else {
            output += "error";
        }
        output += '\n';
    }

    std::cout << output;
    return 0;
}
