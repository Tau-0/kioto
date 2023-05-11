# List sources

file(GLOB_RECURSE PLAYGROUND_SOURCES "./*.cpp")
file(GLOB_RECURSE PLAYGROUND_HEADERS "./*.hpp")

# All tests target

add_executable(kioto_playground ${PLAYGROUND_SOURCES} ${PLAYGROUND_HEADERS})
target_link_libraries(kioto_playground kioto Catch2WithMain benchmark::benchmark_main)
