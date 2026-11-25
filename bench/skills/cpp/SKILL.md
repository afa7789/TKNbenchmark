---
name: cpp
description: "Version-correct, idiomatic C++ for the installed toolchain (Apple clang version 17.0.0 (clang-1700.0.13.5)): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing C++ code."
---

# C++20 on Apple clang 17 (macOS arm64)

Apple clang 17.0.0 + libc++ 20.1, SDK 26.x; deployment target defaults to host macOS. CLT ship no clang-tidy/clang-format/clang-scan-deps (`brew install llvm` for tidy/format). Use `clang++ -std=c++20` (`clang` gives `Undefined symbols ... std::`).

## Not available: don't write these
| Don't write (`-std=c++20`) | Write instead |
|---|---|
| `std::print/println` | `std::cout << std::format(...)` |
| `std::expected` | `std::optional`, `std::variant<T, Err>`, or exceptions |
| `std::ranges::to` | `auto c = r \| std::views::common; std::vector<T> v(c.begin(), c.end());` |
| `views::zip/enumerate/chunk/slide/join_with`, `ranges::fold_left` | index loop, `std::accumulate` |
| `std::to_underlying`, `std::unreachable` | `static_cast<std::underlying_type_t<E>>(e)`, `std::terminate()` |
| `str.contains(x)` (string) | `str.find(x) != npos`; `starts_with`/`ends_with` are fine |
| `format("{}", vec)` / `thread::id` / enum | loop, or specialize `std::formatter` |
| `std::generator`, `std::move_only_function` | hand-written `promise_type`; `std::function` |

Missing from this libc++ even in C++20:
- Time zones (`current_zone`, `zoned_time`, `tzdb`): absent. Calendar types and UTC `{:%F %T}` work.
- `std::osyncstream`: absent. `std::execution::par`: only with `-fexperimental-library`; avoid.
- Named modules: `export module`/`import` fail to parse; CMake: "does not provide a way to discover the import graph". Use headers; `CMAKE_CXX_SCAN_FOR_MODULES OFF`.

Deployment-target errors (`'X' is unavailable: introduced in macOS N`):
- `from_chars` into `double` needs macOS 26: use `std::strtod`. Integer `from_chars` is fine.
- float `to_chars`/`format` need ≥13.3; `atomic::wait`, `latch`, `barrier`, semaphores ≥11.0. Set `-mmacosx-version-min=` / `CMAKE_OSX_DEPLOYMENT_TARGET`.

## Verified C++20 idioms
```cpp
// format: the format string must be a compile-time constant.
std::format("{:>8.3f}|{:#x}|{:08b}", 3.14159, 255, 5); // mixing {} and {0}: compile error
std::format_to(std::back_inserter(out), "{:.2f}", x);
// runtime format string: args must be LVALUES (rvalues fail with
// "no matching function for call to 'make_format_args'")
int a = 1, b = 2; std::vformat(fmt, std::make_format_args(a, b)); // throws std::format_error
// bad literal spec -> "call to consteval function ... not a constant expression"

struct Money { long cents; };
template <> struct std::formatter<Money> : std::formatter<long> {
  auto format(const Money& m, std::format_context& ctx) const {
    return std::format_to(ctx.out(), "${}.{:02}", m.cents / 100, m.cents % 100);
  }
};

// integer parsing: no exceptions, check the whole input was consumed
std::optional<int> parse_int(std::string_view s) noexcept {
  int v{}; auto [p, ec] = std::from_chars(s.data(), s.data() + s.size(), v);
  if (ec != std::errc{} || p != s.data() + s.size()) return std::nullopt;
  return v;
}

std::ranges::sort(v); auto it = std::ranges::find(v, 4);
for (auto w : std::string_view{"a,b"} | std::views::split(','))
  std::string_view(w.begin(), w.end());
std::erase_if(v, pred); std::ssize(v); m.contains(k); std::cmp_less(int_v, size_v);

template <std::integral T> constexpr T twice(T v) { return v * 2; }
void show(const auto& x);                       // abbreviated template
struct P { int x{}, y{}; auto operator<=>(const P&) const = default; };
P p{.x = 1, .y = 2}; P q(1, 2);                 // designated / paren aggregate init
constinit int g = 0; consteval int sq(int v) { return v * v; }
void log(std::string_view m, std::source_location l = std::source_location::current());
long long sum(std::span<const int> xs);         // accepts vector, array, C array
switch (c) { using enum Color; case red: ...; }
auto t = std::to_array({1, 2, 3}); auto buf = std::make_unique_for_overwrite<char[]>(n);

// threads: jthread joins on destruction; use stop_token, never detach
std::condition_variable_any cv; std::mutex m;
std::jthread w([&](std::stop_token st) {
  std::unique_lock lk(m);
  while (cv.wait(lk, st, [&] { return !q.empty(); })) { /* pop q */ }
});                       // ~jthread: request_stop() + join(); wait returns false
{ std::scoped_lock lk(m); q.push_back(1); } cv.notify_one();

using namespace std::chrono;
auto d = 2024y / February / 29d;                 // d.ok(); format("{}", d) -> 2024-02-29
std::format("{}", 1500ms);                       // "1500ms"
auto now = floor<seconds>(system_clock::now());  // format("{:%F %T}", now) (UTC)
```

## Pitfalls → fixes
- `filter`/`drop_while` views aren't const-iterable ("function is not marked const"): take `auto&&`, not `const auto&`.
- `const std::map` has no `operator[]`: use `.at()`/`.find()`/`.contains()`.
- `vector<unique_ptr<T>> v{make_unique<T>()}` fails (`__construct_at`; init-lists copy): use `emplace_back`.
- No `string_view + string`: `std::string(sv) + s`. A `string_view` of a temporary dangles (`-Wdangling-gsl`, `-Wreturn-stack-address`): return `std::string`.
- "non-virtual member function marked 'override' hides virtual": signature mismatch.
- `int i < v.size()` → `-Wsign-compare`: range-for or `std::ssize`. Designators out of order only warn with `-Wreorder-init-list`. Name locks (`std::scoped_lock lk(m);`).
- `'\n'` not `std::endl`; `reserve()`; `string_view`/`span` params; sinks by value + `std::move`; return by value, `[[nodiscard]]`.

## Project layout and CMake (CMake ≥3.25; Ninja)
```
CMakeLists.txt  CMakePresets.json  include/<proj>/*.hpp  src/*.cpp  app/main.cpp  tests/*_test.cpp
```
```cmake
cmake_minimum_required(VERSION 3.25)
project(demo VERSION 0.1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_library(demo_warnings INTERFACE)
target_compile_options(demo_warnings INTERFACE -Wall -Wextra -Wpedantic -Wshadow
  -Wconversion -Wsign-conversion -Wnon-virtual-dtor -Wold-style-cast
  -Woverloaded-virtual -Wimplicit-fallthrough $<$<BOOL:${DEMO_WERROR}>:-Werror>)
add_library(demo src/demo.cpp)
target_include_directories(demo PUBLIC include)
target_link_libraries(demo PRIVATE demo_warnings)
add_executable(demo_app app/main.cpp)
target_link_libraries(demo_app PRIVATE demo demo_warnings)
include(CTest)
if(BUILD_TESTING)
  include(FetchContent)
  FetchContent_Declare(googletest
    URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.tar.gz
    FIND_PACKAGE_ARGS NAMES GTest)
  FetchContent_MakeAvailable(googletest)
  add_executable(demo_tests tests/demo_test.cpp)
  target_link_libraries(demo_tests PRIVATE demo demo_warnings GTest::gtest_main)
  include(GoogleTest)
  gtest_discover_tests(demo_tests)
endif()
```
Only `target_*` commands; no global flags, no `-Werror` on deps.
```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DDEMO_WERROR=ON
cmake --build build && ctest --test-dir build --output-on-failure -j 8
cmake -S . -B build-rel -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build build-rel && cmake --install build-rel --prefix dist
```
Presets (`"version": 6`, `generator`/`binaryDir`/`cacheVariables`): `cmake --preset debug && cmake --build --preset debug && ctest --preset debug`.

## Safety and debugging builds
- Debug/CI: `-fsanitize=address,undefined -fno-omit-frame-pointer -g` via `CMAKE_CXX_FLAGS` (reaches link). TSan (`-fsanitize=thread`) separately. LSan unsupported on macOS: `leaks --atExit -- ./prog`.
- libc++ hardening defaults to NONE. Release: `-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST` (OOB `[]` traps, exit 133, silent). Tests: `..._MODE_DEBUG` prints `vector[] index out of bounds`. Set once, project-wide.
