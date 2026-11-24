// calc: a 64-bit signed integer expression evaluator.
//
// Reads one expression per line from standard input and prints its value or
// "error". Parsing uses an explicit operator stack (shunting-yard) rather than
// recursion, so arbitrarily deep nesting cannot overflow the call stack.

#include <cstdint>
#include <iostream>
#include <iterator>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace {

using Int = std::int64_t;
constexpr Int kMax = std::numeric_limits<Int>::max();
constexpr Int kMin = std::numeric_limits<Int>::min();

enum class Op : char { Add, Sub, Mul, Div, Mod, Neg, LParen };

constexpr int precedence(Op op) {
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

std::optional<Op> binary_op(char c) {
    switch (c) {
        case '+': return Op::Add;
        case '-': return Op::Sub;
        case '*': return Op::Mul;
        case '/': return Op::Div;
        case '%': return Op::Mod;
        default: return std::nullopt;
    }
}

// Checked arithmetic: std::nullopt signals overflow or division by zero.
std::optional<Int> checked_add(Int a, Int b) {
    if ((b > 0 && a > kMax - b) || (b < 0 && a < kMin - b)) return std::nullopt;
    return a + b;
}

std::optional<Int> checked_sub(Int a, Int b) {
    if ((b < 0 && a > kMax + b) || (b > 0 && a < kMin + b)) return std::nullopt;
    return a - b;
}

std::optional<Int> checked_mul(Int a, Int b) {
    if (a == 0 || b == 0) return Int{0};
    if (a > 0) {
        if (b > 0 ? a > kMax / b : b < kMin / a) return std::nullopt;
    } else {
        if (b > 0 ? a < kMin / b : a < kMax / b) return std::nullopt;
    }
    return a * b;
}

std::optional<Int> checked_div(Int a, Int b) {
    if (b == 0 || (a == kMin && b == -1)) return std::nullopt;
    return a / b;
}

std::optional<Int> checked_mod(Int a, Int b) {
    if (b == 0) return std::nullopt;
    if (b == -1) return Int{0};  // avoids UB for kMin % -1
    return a % b;
}

std::optional<Int> checked_neg(Int a) {
    if (a == kMin) return std::nullopt;
    return -a;
}

class Evaluator {
public:
    // Returns the value of `line`, or std::nullopt on any error.
    std::optional<Int> evaluate(std::string_view line) {
        values_.clear();
        ops_.clear();
        bool expect_operand = true;
        std::size_t i = 0;
        const std::size_t n = line.size();

        while (true) {
            while (i < n && (line[i] == ' ' || line[i] == '\t')) ++i;
            if (i == n) break;
            const char c = line[i];

            if (expect_operand) {
                if (c >= '0' && c <= '9') {
                    Int value = 0;
                    for (; i < n && line[i] >= '0' && line[i] <= '9'; ++i) {
                        const Int digit = line[i] - '0';
                        if (value > (kMax - digit) / 10) return std::nullopt;
                        value = value * 10 + digit;
                    }
                    values_.push_back(value);
                    expect_operand = false;
                    continue;
                }
                if (c == '-') {
                    ops_.push_back(Op::Neg);
                } else if (c == '(') {
                    ops_.push_back(Op::LParen);
                } else {
                    return std::nullopt;
                }
                ++i;
                continue;
            }

            if (c == ')') {
                while (!ops_.empty() && ops_.back() != Op::LParen) {
                    if (!reduce()) return std::nullopt;
                }
                if (ops_.empty()) return std::nullopt;
                ops_.pop_back();
            } else if (const auto op = binary_op(c)) {
                // Left associativity: reduce operators of equal or higher precedence.
                while (!ops_.empty() && precedence(ops_.back()) >= precedence(*op)) {
                    if (!reduce()) return std::nullopt;
                }
                ops_.push_back(*op);
                expect_operand = true;
            } else {
                return std::nullopt;
            }
            ++i;
        }

        if (expect_operand) return std::nullopt;
        while (!ops_.empty()) {
            if (ops_.back() == Op::LParen || !reduce()) return std::nullopt;
        }
        return values_.back();
    }

private:
    // Applies the operator on top of the stack to its operand(s).
    bool reduce() {
        const Op op = ops_.back();
        ops_.pop_back();

        if (op == Op::Neg) {
            const auto r = checked_neg(values_.back());
            if (!r) return false;
            values_.back() = *r;
            return true;
        }

        const Int rhs = values_.back();
        values_.pop_back();
        const Int lhs = values_.back();
        std::optional<Int> r;
        switch (op) {
            case Op::Add: r = checked_add(lhs, rhs); break;
            case Op::Sub: r = checked_sub(lhs, rhs); break;
            case Op::Mul: r = checked_mul(lhs, rhs); break;
            case Op::Div: r = checked_div(lhs, rhs); break;
            case Op::Mod: r = checked_mod(lhs, rhs); break;
            case Op::Neg:
            case Op::LParen: break;
        }
        if (!r) return false;
        values_.back() = *r;
        return true;
    }

    std::vector<Int> values_;
    std::vector<Op> ops_;
};

bool is_blank(std::string_view line) {
    return line.find_first_not_of(" \t") == std::string_view::npos;
}

}  // namespace

int main() {
    std::ios::sync_with_stdio(false);

    const std::string input{std::istreambuf_iterator<char>(std::cin), std::istreambuf_iterator<char>()};
    const std::string_view text{input};

    Evaluator evaluator;
    std::string output;
    output.reserve(text.size());

    std::size_t pos = 0;
    while (pos < text.size()) {
        std::size_t end = text.find('\n', pos);
        if (end == std::string_view::npos) end = text.size();
        const std::string_view line = text.substr(pos, end - pos);
        pos = end + 1;

        if (is_blank(line)) continue;
        if (const auto value = evaluator.evaluate(line)) {
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
