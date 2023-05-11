# List sources

file(GLOB_RECURSE BENCHMARK_SOURCES "./*.cpp")
file(GLOB_RECURSE BENCHMARK_HEADERS "./*.hpp")

# All tests target

add_executable(kioto_benchmarks ${BENCHMARK_SOURCES} ${BENCHMARK_HEADERS})
target_link_libraries(kioto_benchmarks kioto benchmark::benchmark_main)
