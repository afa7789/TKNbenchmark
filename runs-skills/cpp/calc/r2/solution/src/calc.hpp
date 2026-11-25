#pragma once

#include <cstdint>
#include <optional>
#include <string_view>

namespace calc {

// Evaluates one expression line. Returns std::nullopt on any syntax error,
// division by zero, or 64-bit overflow.
[[nodiscard]] std::optional<std::int64_t> evaluate(std::string_view line);

// True if the line is empty or holds only spaces/tabs.
[[nodiscard]] bool is_blank(std::string_view line) noexcept;

}  // namespace calc
