cmake_minimum_required(VERSION 3.20)
project(kvhttp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Threads REQUIRED)

add_executable(app src/main.cpp src/http.cpp src/router.cpp)
target_compile_options(app PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(app PRIVATE Threads::Threads)
