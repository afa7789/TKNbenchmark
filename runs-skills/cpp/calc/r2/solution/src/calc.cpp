#include "calc.hpp"

#include <limits>
#include <vector>

namespace calc {
namespace {

using Value = std::int64_t;
constexpr Value kMin = std::numeric_limits<Value>::min();

[[nodiscard]] constexpr bool is_space(char c) noexcept { return c == ' ' || c == '\t'; }
[[nodiscard]] constexpr bool is_digit(char c) noexcept { return c >= '0' && c <= '9'; }

[[nodiscard]] std::optional<Value> negate(Value v) noexcept {
    if (v == kMin) return std::nullopt;
    return -v;
}

[[nodiscard]] std::optional<Value> apply(char op, Value a, Value b) noexcept {
    Value r{};
    switch (op) {
        case '+':
            if (__builtin_add_overflow(a, b, &r)) return std::nullopt;
            return r;
        case '-':
            if (__builtin_sub_overflow(a, b, &r)) return std::nullopt;
            return r;
        case '*':
            if (__builtin_mul_overflow(a, b, &r)) return std::nullopt;
            return r;
        case '/':
            if (b == 0 || (a == kMin && b == -1)) return std::nullopt;
            return a / b;
        case '%':
            if (b == 0) return std::nullopt;
            if (b == -1) return 0;  // avoids UB for kMin % -1
            return a % b;
        default:
            return std::nullopt;
    }
}

[[nodiscard]] constexpr int precedence(char op) noexcept {
    return (op == '*' || op == '/' || op == '%') ? 2 : 1;
}

// Iterative operator-precedence evaluator: explicit stacks keep arbitrarily
// deep nesting (long runs of '(' or unary '-') from exhausting the call stack.
class Evaluator {
public:
    explicit Evaluator(std::string_view text) noexcept : text_(text) {}

    [[nodiscard]] std::optional<Value> run() {
        bool expect_operand = true;
        while (true) {
            skip_spaces();
            if (pos_ == text_.size()) break;
            const char c = text_[pos_];

            if (expect_operand) {
                if (c == '-' || c == '(') {
                    ops_.push_back(c == '-' ? kNeg : '(');
                    ++pos_;
                } else if (is_digit(c)) {
                    const auto v = parse_number();
                    if (!v || !push_operand(*v)) return std::nullopt;
                    expect_operand = false;
                } else {
                    return std::nullopt;
                }
                continue;
            }

            switch (c) {
                case '+': case '-': case '*': case '/': case '%':
                    if (!reduce_binary(precedence(c))) return std::nullopt;
                    ops_.push_back(c);
                    expect_operand = true;
                    break;
                case ')': {
                    if (!reduce_binary(0)) return std::nullopt;
                    if (ops_.empty() || ops_.back() != '(') return std::nullopt;
                    ops_.pop_back();
                    const Value v = values_.back();
                    values_.pop_back();
                    if (!push_operand(v)) return std::nullopt;
                    break;
                }
                default:
                    return std::nullopt;
            }
            ++pos_;
        }

        if (expect_operand || !reduce_binary(0) || !ops_.empty()) return std::nullopt;
        return values_.back();
    }

private:
    static constexpr char kNeg = 'n';

    void skip_spaces() noexcept {
        while (pos_ < text_.size() && is_space(text_[pos_])) ++pos_;
    }

    [[nodiscard]] std::optional<Value> parse_number() noexcept {
        constexpr Value kMax = std::numeric_limits<Value>::max();
        Value v = 0;
        bool overflow = false;
        for (; pos_ < text_.size() && is_digit(text_[pos_]); ++pos_) {
            const Value d = text_[pos_] - '0';
            if (!overflow && v > (kMax - d) / 10) overflow = true;
            if (!overflow) v = v * 10 + d;
        }
        if (overflow) return std::nullopt;
        return v;
    }

    // A primary has completed: apply pending unary minuses, then store it.
    [[nodiscard]] bool push_operand(Value v) {
        while (!ops_.empty() && ops_.back() == kNeg) {
            ops_.pop_back();
            const auto n = negate(v);
            if (!n) return false;
            v = *n;
        }
        values_.push_back(v);
        return true;
    }

    // Reduce binary operators on top of the stack with precedence >= min_prec.
    [[nodiscard]] bool reduce_binary(int min_prec) {
        while (!ops_.empty() && ops_.back() != '(' && precedence(ops_.back()) >= min_prec) {
            const char op = ops_.back();
            ops_.pop_back();
            const Value rhs = values_.back();
            values_.pop_back();
            const auto r = apply(op, values_.back(), rhs);
            if (!r) return false;
            values_.back() = *r;
        }
        return true;
    }

    std::string_view text_;
    std::size_t pos_ = 0;
    std::vector<char> ops_;
    std::vector<Value> values_;
};

}  // namespace

bool is_blank(std::string_view line) noexcept {
    for (const char c : line) {
        if (!is_space(c)) return false;
    }
    return true;
}

std::optional<std::int64_t> evaluate(std::string_view line) {
    return Evaluator{line}.run();
}

}  // namespace calc
