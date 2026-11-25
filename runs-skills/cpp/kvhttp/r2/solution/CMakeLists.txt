cmake_minimum_required(VERSION 3.25)
project(kvhttp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(KVHTTP_WERROR "Treat warnings as errors" OFF)

find_package(Threads REQUIRED)

add_executable(kvhttp
  src/main.cpp
  src/http.cpp
  src/router.cpp
  src/server.cpp)
target_compile_options(kvhttp PRIVATE
  -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion
  -Wnon-virtual-dtor -Wold-style-cast -Woverloaded-virtual -Wimplicit-fallthrough
  $<$<BOOL:${KVHTTP_WERROR}>:-Werror>)
target_compile_definitions(kvhttp PRIVATE
  $<$<CONFIG:Release>:_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST>)
target_link_libraries(kvhttp PRIVATE Threads::Threads)
