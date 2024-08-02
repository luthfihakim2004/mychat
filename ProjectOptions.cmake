include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(mychat_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(mychat_setup_options)
  option(mychat_ENABLE_HARDENING "Enable hardening" ON)
  option(mychat_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    mychat_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    mychat_ENABLE_HARDENING
    OFF)

  mychat_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR mychat_PACKAGING_MAINTAINER_MODE)
    option(mychat_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(mychat_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(mychat_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(mychat_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(mychat_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(mychat_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(mychat_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(mychat_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(mychat_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(mychat_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(mychat_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(mychat_ENABLE_PCH "Enable precompiled headers" OFF)
    option(mychat_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(mychat_ENABLE_IPO "Enable IPO/LTO" ON)
    option(mychat_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(mychat_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(mychat_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(mychat_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(mychat_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(mychat_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(mychat_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(mychat_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(mychat_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(mychat_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(mychat_ENABLE_PCH "Enable precompiled headers" OFF)
    option(mychat_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      mychat_ENABLE_IPO
      mychat_WARNINGS_AS_ERRORS
      mychat_ENABLE_USER_LINKER
      mychat_ENABLE_SANITIZER_ADDRESS
      mychat_ENABLE_SANITIZER_LEAK
      mychat_ENABLE_SANITIZER_UNDEFINED
      mychat_ENABLE_SANITIZER_THREAD
      mychat_ENABLE_SANITIZER_MEMORY
      mychat_ENABLE_UNITY_BUILD
      mychat_ENABLE_CLANG_TIDY
      mychat_ENABLE_CPPCHECK
      mychat_ENABLE_COVERAGE
      mychat_ENABLE_PCH
      mychat_ENABLE_CACHE)
  endif()

  mychat_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (mychat_ENABLE_SANITIZER_ADDRESS OR mychat_ENABLE_SANITIZER_THREAD OR mychat_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(mychat_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(mychat_global_options)
  if(mychat_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    mychat_enable_ipo()
  endif()

  mychat_supports_sanitizers()

  if(mychat_ENABLE_HARDENING AND mychat_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR mychat_ENABLE_SANITIZER_UNDEFINED
       OR mychat_ENABLE_SANITIZER_ADDRESS
       OR mychat_ENABLE_SANITIZER_THREAD
       OR mychat_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${mychat_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${mychat_ENABLE_SANITIZER_UNDEFINED}")
    mychat_enable_hardening(mychat_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(mychat_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(mychat_warnings INTERFACE)
  add_library(mychat_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  mychat_set_project_warnings(
    mychat_warnings
    ${mychat_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(mychat_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    mychat_configure_linker(mychat_options)
  endif()

  include(cmake/Sanitizers.cmake)
  mychat_enable_sanitizers(
    mychat_options
    ${mychat_ENABLE_SANITIZER_ADDRESS}
    ${mychat_ENABLE_SANITIZER_LEAK}
    ${mychat_ENABLE_SANITIZER_UNDEFINED}
    ${mychat_ENABLE_SANITIZER_THREAD}
    ${mychat_ENABLE_SANITIZER_MEMORY})

  set_target_properties(mychat_options PROPERTIES UNITY_BUILD ${mychat_ENABLE_UNITY_BUILD})

  if(mychat_ENABLE_PCH)
    target_precompile_headers(
      mychat_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(mychat_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    mychat_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(mychat_ENABLE_CLANG_TIDY)
    mychat_enable_clang_tidy(mychat_options ${mychat_WARNINGS_AS_ERRORS})
  endif()

  if(mychat_ENABLE_CPPCHECK)
    mychat_enable_cppcheck(${mychat_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(mychat_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    mychat_enable_coverage(mychat_options)
  endif()

  if(mychat_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(mychat_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(mychat_ENABLE_HARDENING AND NOT mychat_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR mychat_ENABLE_SANITIZER_UNDEFINED
       OR mychat_ENABLE_SANITIZER_ADDRESS
       OR mychat_ENABLE_SANITIZER_THREAD
       OR mychat_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    mychat_enable_hardening(mychat_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
