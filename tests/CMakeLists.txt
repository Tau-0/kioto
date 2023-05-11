# List sources

file(GLOB_RECURSE TEST_SOURCES "./*.cpp")
file(GLOB_RECURSE TEST_HEADERS "./*.hpp")

# All tests target

add_executable(kioto_tests ${TEST_SOURCES} ${TEST_HEADERS})
target_link_libraries(kioto_tests kioto Catch2WithMain)
