cmake_minimum_required(VERSION 3.20)

project(nagi-wallpaper LANGUAGES CXX)

find_package(Qt6 6.6 REQUIRED COMPONENTS Concurrent Core DBus Gui)

qt_standard_project_setup()

qt_add_executable(nagi-wallpaper main.cpp analyzer.cpp analyzer.h)
target_compile_features(nagi-wallpaper PRIVATE cxx_std_20)
target_compile_options(nagi-wallpaper PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(nagi-wallpaper PRIVATE Qt6::Concurrent Qt6::Core Qt6::DBus Qt6::Gui)

qt_add_executable(
    nagi-wallpaper-analyzer-test
    ../../tests/wallpaper_analyzer_test.cpp
    analyzer.cpp
    analyzer.h
)
target_include_directories(nagi-wallpaper-analyzer-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(nagi-wallpaper-analyzer-test PRIVATE cxx_std_20)
target_compile_options(nagi-wallpaper-analyzer-test PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(nagi-wallpaper-analyzer-test PRIVATE Qt6::Core Qt6::Gui)

qt_add_executable(
    nagi-wallpaper-dbus-test
    ../../tests/wallpaper_dbus_test.cpp
    main.cpp
    analyzer.cpp
    analyzer.h
)
target_include_directories(nagi-wallpaper-dbus-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(
    nagi-wallpaper-dbus-test
    PRIVATE NAGI_WALLPAPER_NO_MAIN NAGI_WALLPAPER_TESTING
)
target_compile_features(nagi-wallpaper-dbus-test PRIVATE cxx_std_20)
target_compile_options(nagi-wallpaper-dbus-test PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(
    nagi-wallpaper-dbus-test
    PRIVATE Qt6::Concurrent Qt6::Core Qt6::DBus Qt6::Gui
)

qt_add_executable(nagi-wallpaper-live-test ../../tests/wallpaper_live_test.cpp)
target_compile_features(nagi-wallpaper-live-test PRIVATE cxx_std_20)
target_compile_options(nagi-wallpaper-live-test PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(nagi-wallpaper-live-test PRIVATE Qt6::Core)
