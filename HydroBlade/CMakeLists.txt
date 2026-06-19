cmake_minimum_required(VERSION 3.20)

project(HydroBlade LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(HydroBlade WIN32
    src/main.cpp
)

add_executable(update
    src/update.cpp
)

target_compile_definitions(HydroBlade PRIVATE
    UNICODE
    _UNICODE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
)

target_compile_definitions(update PRIVATE
    UNICODE
    _UNICODE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
    HYDROBLADE_SOURCE_DIR=\"${CMAKE_CURRENT_SOURCE_DIR}\"
    HYDROBLADE_CXX_COMPILER=\"${CMAKE_CXX_COMPILER}\"
)

target_link_libraries(HydroBlade PRIVATE
    comctl32
    winhttp
    shell32
    shlwapi
    ws2_32
    iphlpapi
    gdi32
    bcrypt
    gdiplus
    ole32
)

target_link_options(HydroBlade PRIVATE
    -municode
    -Wl,--no-insert-timestamp
)

target_link_libraries(update PRIVATE
    bcrypt
)

target_link_options(update PRIVATE
    -municode
)

set_target_properties(update PROPERTIES
    OUTPUT_NAME "update"
)

add_custom_command(TARGET HydroBlade POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_CURRENT_SOURCE_DIR}/assets"
        "$<TARGET_FILE_DIR:HydroBlade>/assets"
)
