#pragma once

#include <cstdint>
#include <optional>
#include <string_view>

namespace calc {

// Evaluates one expression line per SPEC.md.
// Returns std::nullopt on syntax error, division by zero or overflow.
[[nodiscard]] std::optional<std::int64_t> evaluate(std::string_view line);

// True when the line holds only spaces/tabs (or nothing).
[[nodiscard]] bool is_blank(std::string_view line) noexcept;

}  // namespace calc
