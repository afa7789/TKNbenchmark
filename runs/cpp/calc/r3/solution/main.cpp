// calc: 64-bit signed integer expression evaluator (see SPEC.md).
//
// Each input line is evaluated with an iterative operator-precedence parser,
// so arbitrarily deep nesting cannot overflow the call stack.

#include <cstdint>
#include <iostream>
#include <iterator>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace {

using Value = std::int64_t;
constexpr Value kMin = std::numeric_limits<Value>::min();

enum class Op : char { Neg, Add, Sub, Mul, Div, Mod, LParen };

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

std::optional<Op> binaryOp(char c) {
    switch (c) {
        case '+': return Op::Add;
        case '-': return Op::Sub;
        case '*': return Op::Mul;
        case '/': return Op::Div;
        case '%': return Op::Mod;
        default: return std::nullopt;
    }
}

std::optional<Value> negate(Value a) {
    if (a == kMin) return std::nullopt;
    return -a;
}

std::optional<Value> applyBinary(Op op, Value a, Value b) {
    Value r{};
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
            if (b == 0 || (a == kMin && b == -1)) return std::nullopt;
            return a / b;
        case Op::Mod:
            if (b == 0) return std::nullopt;
            if (b == -1) return 0;  // avoids UB for kMin % -1
            return a % b;
        default:
            return std::nullopt;
    }
}

constexpr bool isBlank(char c) { return c == ' ' || c == '\t'; }
constexpr bool isDigit(char c) { return c >= '0' && c <= '9'; }

class Evaluator {
public:
    // Returns the value of `line`, or nullopt on any syntax or arithmetic error.
    std::optional<Value> evaluate(std::string_view line) {
        values_.clear();
        ops_.clear();

        bool expectOperand = true;
        std::size_t i = 0;
        const std::size_t n = line.size();

        while (true) {
            while (i < n && isBlank(line[i])) ++i;
            if (i == n) break;
            const char c = line[i];

            if (expectOperand) {
                if (c == '-') {
                    ops_.push_back(Op::Neg);
                    ++i;
                } else if (c == '(') {
                    ops_.push_back(Op::LParen);
                    ++i;
                } else if (isDigit(c)) {
                    auto v = parseNumber(line, i);
                    if (!v) return std::nullopt;
                    values_.push_back(*v);
                    expectOperand = false;
                } else {
                    return std::nullopt;
                }
            } else {
                if (c == ')') {
                    if (!reduceWhile([](Op op) { return op != Op::LParen; })) return std::nullopt;
                    if (ops_.empty()) return std::nullopt;  // unmatched ')'
                    ops_.pop_back();
                    ++i;
                } else if (auto op = binaryOp(c)) {
                    const int p = precedence(*op);
                    if (!reduceWhile([p](Op top) { return precedence(top) >= p; })) return std::nullopt;
                    ops_.push_back(*op);
                    expectOperand = true;
                    ++i;
                } else {
                    return std::nullopt;
                }
            }
        }

        if (expectOperand) return std::nullopt;  // missing operand
        if (!reduceWhile([](Op op) { return op != Op::LParen; })) return std::nullopt;
        if (!ops_.empty() || values_.size() != 1) return std::nullopt;  // unmatched '('
        return values_.back();
    }

private:
    static std::optional<Value> parseNumber(std::string_view line, std::size_t& i) {
        constexpr Value kMax = std::numeric_limits<Value>::max();
        Value v = 0;
        bool overflow = false;
        for (; i < line.size() && isDigit(line[i]); ++i) {
            const Value d = line[i] - '0';
            if (v > (kMax - d) / 10) overflow = true;
            else v = v * 10 + d;
        }
        if (overflow) return std::nullopt;
        return v;
    }

    // Applies the top operator to the value stack.
    bool reduceOnce() {
        const Op op = ops_.back();
        ops_.pop_back();
        std::optional<Value> result;
        if (op == Op::Neg) {
            result = negate(values_.back());
            values_.pop_back();
        } else {
            const Value b = values_.back();
            values_.pop_back();
            const Value a = values_.back();
            values_.pop_back();
            result = applyBinary(op, a, b);
        }
        if (!result) return false;
        values_.push_back(*result);
        return true;
    }

    template <typename Pred>
    bool reduceWhile(Pred pred) {
        while (!ops_.empty() && pred(ops_.back())) {
            if (!reduceOnce()) return false;
        }
        return true;
    }

    std::vector<Value> values_;
    std::vector<Op> ops_;
};

bool isBlankLine(std::string_view line) {
    for (char c : line) {
        if (!isBlank(c)) return false;
    }
    return true;
}

}  // namespace

int main() {
    std::ios::sync_with_stdio(false);

    const std::string input{std::istreambuf_iterator<char>(std::cin), std::istreambuf_iterator<char>()};
    const std::string_view all{input};

    Evaluator evaluator;
    std::string output;
    output.reserve(input.size() / 2 + 16);

    std::size_t start = 0;
    while (start < all.size()) {
        std::size_t end = all.find('\n', start);
        if (end == std::string_view::npos) end = all.size();
        const std::string_view line = all.substr(start, end - start);
        start = end + 1;

        if (isBlankLine(line)) continue;
        if (auto v = evaluator.evaluate(line)) output += std::to_string(*v);
        else output += "error";
        output += '\n';
    }

    std::cout.write(output.data(), static_cast<std::streamsize>(output.size()));
    std::cout.flush();
    return 0;
}
