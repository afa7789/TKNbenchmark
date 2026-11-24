// calc: a 64-bit signed integer expression evaluator.
//
// Reads one expression per line from standard input and prints its value or
// "error". Parsing uses an explicit-stack operator-precedence algorithm so that
// deeply nested input cannot overflow the call stack.

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

// ---------- checked arithmetic ----------

std::optional<Int> checkedAdd(Int a, Int b) {
    if ((b > 0 && a > kMax - b) || (b < 0 && a < kMin - b)) return std::nullopt;
    return a + b;
}

std::optional<Int> checkedSub(Int a, Int b) {
    if ((b < 0 && a > kMax + b) || (b > 0 && a < kMin + b)) return std::nullopt;
    return a - b;
}

std::optional<Int> checkedMul(Int a, Int b) {
    if (a == 0 || b == 0) return Int{0};
    if (a > 0) {
        if (b > 0 ? a > kMax / b : b < kMin / a) return std::nullopt;
    } else {
        if (b > 0 ? a < kMin / b : a < kMax / b) return std::nullopt;
    }
    return a * b;
}

std::optional<Int> checkedDiv(Int a, Int b) {
    if (b == 0 || (a == kMin && b == -1)) return std::nullopt;
    return a / b;
}

std::optional<Int> checkedRem(Int a, Int b) {
    if (b == 0) return std::nullopt;
    if (b == -1) return Int{0};  // avoids the kMin % -1 trap; result is always 0
    return a % b;
}

std::optional<Int> checkedNeg(Int a) {
    if (a == kMin) return std::nullopt;
    return -a;
}

// ---------- evaluator ----------

enum class Op : char { Add, Sub, Mul, Div, Rem, Neg, LParen };

constexpr int precedence(Op op) {
    switch (op) {
        case Op::Add:
        case Op::Sub: return 1;
        case Op::Mul:
        case Op::Div:
        case Op::Rem: return 2;
        case Op::Neg: return 3;
        case Op::LParen: return 0;
    }
    return 0;
}

std::optional<Op> binaryOp(char c) {
    switch (c) {
        case '+': return Op::Add;
        case '-': return Op::Sub;
        case '*': return Op::Mul;
        case '/': return Op::Div;
        case '%': return Op::Rem;
        default: return std::nullopt;
    }
}

constexpr bool isBlank(char c) { return c == ' ' || c == '\t'; }
constexpr bool isDigit(char c) { return c >= '0' && c <= '9'; }

class Evaluator {
public:
    // Returns the value of `line`, or nullopt on any syntax or arithmetic error.
    std::optional<Int> evaluate(std::string_view line) {
        values_.clear();
        ops_.clear();

        bool expectOperand = true;
        std::size_t i = 0;
        const std::size_t n = line.size();

        while (i < n) {
            const char c = line[i];
            if (isBlank(c)) {
                ++i;
                continue;
            }
            if (expectOperand) {
                if (isDigit(c)) {
                    Int value = 0;
                    for (; i < n && isDigit(line[i]); ++i) {
                        const Int digit = line[i] - '0';
                        if (value > (kMax - digit) / 10) return std::nullopt;
                        value = value * 10 + digit;
                    }
                    values_.push_back(value);
                    expectOperand = false;
                    continue;
                }
                if (c == '-') {
                    ops_.push_back(Op::Neg);
                } else if (c == '(') {
                    ops_.push_back(Op::LParen);
                } else {
                    return std::nullopt;
                }
            } else {
                if (c == ')') {
                    while (!ops_.empty() && ops_.back() != Op::LParen) {
                        if (!reduce()) return std::nullopt;
                    }
                    if (ops_.empty()) return std::nullopt;  // unbalanced ')'
                    ops_.pop_back();
                } else if (const auto op = binaryOp(c)) {
                    // All binary operators are left-associative.
                    while (!ops_.empty() && precedence(ops_.back()) >= precedence(*op)) {
                        if (!reduce()) return std::nullopt;
                    }
                    ops_.push_back(*op);
                    expectOperand = true;
                } else {
                    return std::nullopt;
                }
            }
            ++i;
        }

        if (expectOperand) return std::nullopt;  // missing operand (or empty)
        while (!ops_.empty()) {
            if (ops_.back() == Op::LParen) return std::nullopt;  // unbalanced '('
            if (!reduce()) return std::nullopt;
        }
        if (values_.size() != 1) return std::nullopt;
        return values_.back();
    }

private:
    // Applies the operator on top of the stack. Returns false on arithmetic error.
    bool reduce() {
        const Op op = ops_.back();
        ops_.pop_back();

        std::optional<Int> result;
        if (op == Op::Neg) {
            result = checkedNeg(values_.back());
            values_.pop_back();
        } else {
            const Int rhs = values_.back();
            values_.pop_back();
            const Int lhs = values_.back();
            values_.pop_back();
            switch (op) {
                case Op::Add: result = checkedAdd(lhs, rhs); break;
                case Op::Sub: result = checkedSub(lhs, rhs); break;
                case Op::Mul: result = checkedMul(lhs, rhs); break;
                case Op::Div: result = checkedDiv(lhs, rhs); break;
                case Op::Rem: result = checkedRem(lhs, rhs); break;
                case Op::Neg:
                case Op::LParen: break;
            }
        }
        if (!result) return false;
        values_.push_back(*result);
        return true;
    }

    std::vector<Int> values_;
    std::vector<Op> ops_;
};

bool isBlankLine(std::string_view line) {
    for (const char c : line) {
        if (!isBlank(c)) return false;
    }
    return true;
}

}  // namespace

int main() {
    std::ios::sync_with_stdio(false);

    const std::string input{std::istreambuf_iterator<char>(std::cin), std::istreambuf_iterator<char>()};
    const std::string_view text{input};

    Evaluator evaluator;
    std::string output;
    output.reserve(text.size() / 2 + 64);

    std::size_t start = 0;
    while (start < text.size()) {
        std::size_t end = text.find('\n', start);
        if (end == std::string_view::npos) end = text.size();
        const std::string_view line = text.substr(start, end - start);
        start = end + 1;

        if (isBlankLine(line)) continue;
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
