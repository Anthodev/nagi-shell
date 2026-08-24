cmake_minimum_required(VERSION 3.20)

project(nagi-global-shortcut LANGUAGES CXX)

find_package(Qt6 6.6 REQUIRED COMPONENTS DBus Gui)
find_package(KF6GlobalAccel 6.0 REQUIRED)

qt_standard_project_setup()

qt_add_executable(nagi-global-shortcut main.cpp registration_policy.h shortcut_contract.h)
target_compile_features(nagi-global-shortcut PRIVATE cxx_std_20)
target_compile_options(nagi-global-shortcut PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(nagi-global-shortcut PRIVATE KF6::GlobalAccel Qt6::DBus Qt6::Gui)

qt_add_executable(nagi-global-shortcut-test ../../tests/global_shortcut_test.cpp registration_policy.h shortcut_contract.h)
target_compile_features(nagi-global-shortcut-test PRIVATE cxx_std_20)
target_compile_options(nagi-global-shortcut-test PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(nagi-global-shortcut-test PRIVATE Qt6::Gui)

qt_add_executable(nagi-global-shortcut-live-test ../../tests/global_shortcut_live_test.cpp shortcut_contract.h)
target_compile_features(nagi-global-shortcut-live-test PRIVATE cxx_std_20)
target_compile_options(nagi-global-shortcut-live-test PRIVATE -O2 -Wall -Wextra -Wpedantic)
target_link_libraries(nagi-global-shortcut-live-test PRIVATE Qt6::DBus Qt6::Gui)
