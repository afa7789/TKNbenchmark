#include "calc.hpp"

#include <charconv>
#include <limits>
#include <system_error>
#include <vector>

namespace calc {
namespace {

using Int = std::int64_t;
using Limits = std::numeric_limits<Int>;

[[nodiscard]] constexpr bool is_space(char c) noexcept { return c == ' ' || c == '\t'; }
[[nodiscard]] constexpr bool is_digit(char c) noexcept { return c >= '0' && c <= '9'; }

// ---- checked arithmetic ----------------------------------------------------

[[nodiscard]] std::optional<Int> checked_add(Int a, Int b) noexcept {
    if ((b > 0 && a > Limits::max() - b) || (b < 0 && a < Limits::min() - b)) return std::nullopt;
    return a + b;
}

[[nodiscard]] std::optional<Int> checked_sub(Int a, Int b) noexcept {
    if ((b < 0 && a > Limits::max() + b) || (b > 0 && a < Limits::min() + b)) return std::nullopt;
    return a - b;
}

[[nodiscard]] std::optional<Int> checked_mul(Int a, Int b) noexcept {
    if (a == 0 || b == 0) return Int{0};
    if (a > 0) {
        if (b > 0 ? a > Limits::max() / b : b < Limits::min() / a) return std::nullopt;
    } else {
        if (b > 0 ? a < Limits::min() / b : b < Limits::max() / a) return std::nullopt;
    }
    return a * b;
}

[[nodiscard]] std::optional<Int> checked_div(Int a, Int b) noexcept {
    if (b == 0 || (a == Limits::min() && b == -1)) return std::nullopt;
    return a / b;
}

[[nodiscard]] std::optional<Int> checked_rem(Int a, Int b) noexcept {
    if (b == 0) return std::nullopt;
    if (b == -1) return Int{0};  // avoids UB for MIN % -1; result is exactly 0
    return a % b;
}

[[nodiscard]] std::optional<Int> checked_neg(Int a) noexcept {
    if (a == Limits::min()) return std::nullopt;
    return -a;
}

// ---- evaluator ---------------------------------------------------------------

enum class Op : char { Add, Sub, Mul, Div, Rem, Neg, LParen };

[[nodiscard]] constexpr int precedence(Op op) noexcept {
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

[[nodiscard]] constexpr std::optional<Op> binary_op(char c) noexcept {
    switch (c) {
        case '+': return Op::Add;
        case '-': return Op::Sub;
        case '*': return Op::Mul;
        case '/': return Op::Div;
        case '%': return Op::Rem;
        default: return std::nullopt;
    }
}

// Operator-precedence evaluator with explicit stacks, so arbitrarily deep
// nesting cannot overflow the call stack.
class Evaluator {
public:
    [[nodiscard]] std::optional<Int> run(std::string_view s) {
        bool expect_operand = true;
        std::size_t i = 0;
        while (true) {
            while (i < s.size() && is_space(s[i])) ++i;
            if (i == s.size()) break;
            const char c = s[i];

            if (expect_operand) {
                if (c == '-') {
                    ops_.push_back(Op::Neg);
                    ++i;
                } else if (c == '(') {
                    ops_.push_back(Op::LParen);
                    ++i;
                } else if (is_digit(c)) {
                    Int value{};
                    const auto [end, ec] = std::from_chars(s.data() + i, s.data() + s.size(), value);
                    if (ec != std::errc{}) return std::nullopt;  // literal out of range
                    i = static_cast<std::size_t>(end - s.data());
                    values_.push_back(value);
                    expect_operand = false;
                } else {
                    return std::nullopt;
                }
                continue;
            }

            if (c == ')') {
                if (!reduce_while([](Op top) { return top != Op::LParen; })) return std::nullopt;
                if (ops_.empty()) return std::nullopt;  // unbalanced ')'
                ops_.pop_back();
                ++i;
            } else if (const auto op = binary_op(c)) {
                const int prec = precedence(*op);
                if (!reduce_while([prec](Op top) { return precedence(top) >= prec; })) return std::nullopt;
                ops_.push_back(*op);
                expect_operand = true;
                ++i;
            } else {
                return std::nullopt;
            }
        }

        if (expect_operand) return std::nullopt;  // missing operand (or empty)
        if (!reduce_while([](Op top) { return top != Op::LParen; })) return std::nullopt;
        if (!ops_.empty() || values_.size() != 1) return std::nullopt;  // unbalanced '('
        return values_.back();
    }

private:
    // Applies operators from the top of the stack while pred(top) holds.
    template <typename Pred>
    [[nodiscard]] bool reduce_while(Pred pred) {
        while (!ops_.empty() && pred(ops_.back())) {
            const Op op = ops_.back();
            ops_.pop_back();
            if (!apply(op)) return false;
        }
        return true;
    }

    [[nodiscard]] bool apply(Op op) {
        std::optional<Int> result;
        if (op == Op::Neg) {
            result = checked_neg(values_.back());
            values_.pop_back();
        } else {
            const Int rhs = values_.back();
            values_.pop_back();
            const Int lhs = values_.back();
            values_.pop_back();
            switch (op) {
                case Op::Add: result = checked_add(lhs, rhs); break;
                case Op::Sub: result = checked_sub(lhs, rhs); break;
                case Op::Mul: result = checked_mul(lhs, rhs); break;
                case Op::Div: result = checked_div(lhs, rhs); break;
                case Op::Rem: result = checked_rem(lhs, rhs); break;
                case Op::Neg:
                case Op::LParen: return false;
            }
        }
        if (!result) return false;
        values_.push_back(*result);
        return true;
    }

    std::vector<Op> ops_;
    std::vector<Int> values_;
};

}  // namespace

bool is_blank(std::string_view line) noexcept {
    for (const char c : line) {
        if (!is_space(c)) return false;
    }
    return true;
}

std::optional<std::int64_t> evaluate(std::string_view line) {
    return Evaluator{}.run(line);
}

}  // namespace calc
