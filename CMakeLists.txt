cmake_minimum_required(VERSION 3.23)
project(kioto)

include(cmake/CheckCompiler.cmake)
include(cmake/CompileOptions.cmake)
include(cmake/Sanitize.cmake)

add_subdirectory(benchmarks)
add_subdirectory(examples)
add_subdirectory(kioto)
add_subdirectory(playground)
add_subdirectory(tests)
add_subdirectory(third_party)
