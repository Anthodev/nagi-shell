cmake_minimum_required(VERSION 3.20)

project(nagi-launcher-shortcut LANGUAGES CXX)

find_package(Qt6 6.6 REQUIRED COMPONENTS DBus Gui)
find_package(KF6GlobalAccel 6.0 REQUIRED)

qt_standard_project_setup()

qt_add_executable(nagi-launcher-shortcut main.cpp registration_policy.h)
target_compile_features(nagi-launcher-shortcut PRIVATE cxx_std_20)
target_compile_options(nagi-launcher-shortcut PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(nagi-launcher-shortcut PRIVATE KF6::GlobalAccel Qt6::DBus Qt6::Gui)

qt_add_executable(nagi-launcher-shortcut-test ../../tests/launcher_shortcut_test.cpp registration_policy.h)
target_compile_features(nagi-launcher-shortcut-test PRIVATE cxx_std_20)
target_compile_options(nagi-launcher-shortcut-test PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(nagi-launcher-shortcut-test PRIVATE Qt6::Gui)
