cmake_minimum_required(VERSION 3.25)
project(kvhttp VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(KVHTTP_WERROR "Treat warnings as errors" OFF)

add_library(kvhttp_warnings INTERFACE)
target_compile_options(kvhttp_warnings INTERFACE
  -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion
  -Wnon-virtual-dtor -Wold-style-cast -Woverloaded-virtual -Wimplicit-fallthrough
  $<$<BOOL:${KVHTTP_WERROR}>:-Werror>)

find_package(Threads REQUIRED)

add_library(kvhttp_core
  src/http.cpp
  src/router.cpp
  src/server.cpp
  src/store.cpp)
target_include_directories(kvhttp_core PUBLIC src)
target_compile_definitions(kvhttp_core PUBLIC
  $<$<CONFIG:Release>:_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST>)
target_link_libraries(kvhttp_core PUBLIC Threads::Threads PRIVATE kvhttp_warnings)

add_executable(app src/main.cpp)
target_link_libraries(app PRIVATE kvhttp_core kvhttp_warnings)
