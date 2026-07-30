# Kontraband

Kontraband builds C++ in the Linux kernel.

It lets a CMake project describe a kernel module with normal targets, sources, include directories, compile features, definitions, and dependencies. Kontraband turns that description into a Kbuild project, and Kbuild performs the actual kernel compilation, dependency checking, and linking.

Kontraband can also install the generated Kbuild tree as a standalone, CMake-free source package for direct builds or systems such as DKMS.

It also supports [dual-compiling kernel-independent C++](docs/guide.md#dual-compiling-kernel-and-user-code) in both the kernel build and an ordinary hosted CMake target. This makes normal user-mode unit and integration testing available to code that also runs in the kernel, and allows carefully designed interfaces to be shared across the kernel/user boundary.

See the [user guide](docs/guide.md) for the full project model, build and installation options, and technical details. See the [diagnostic reference](docs/diagnostics.md) for `Kontraband[...]` diagnostics.

## Requirements

* CMake 3.31.6 or newer;
* GNU Make;
* a prepared Linux kernel build directory;
* Linux 6.12 as the oldest supported and continuously tested Kbuild baseline;
* the compiler and utilities required by that kernel;
* a linker supporting `--force-group-allocation`.

Kontraband checks the Kbuild and linker features it needs rather than relying only on version numbers. See [Kernel and toolchain selection](docs/guide.md#kernel-and-toolchain-selection) for the full compatibility and selection rules.

## Quick start

Consume an installed package:

```cmake
find_package(kontraband 0.1 CONFIG REQUIRED)
```

Or vendor Kontraband with `add_subdirectory()`. The [user guide](docs/guide.md#using-kontraband) covers both forms.

A common layout is:

```text
project/
├── CMakeLists.txt
├── include/
├── src/
└── modules/
    ├── CMakeLists.txt
    ├── entry.c
    └── module.cpp
```

The outer project declares the nested kernel project and exports one of its object-library targets as a module:

```cmake
find_package(kontraband CONFIG REQUIRED)

kontra_add_kernel_project(modules)

kontra_add_kernel_module(
    example
    PROJECT modules
    OUTPUT_NAME example_module
)
```

The nested project uses normal CMake target APIs:

```cmake
cmake_minimum_required(VERSION 3.31.6)
project(example_modules LANGUAGES C CXX)

add_library(example OBJECT EXCLUDE_FROM_ALL)

target_sources(example PRIVATE
    entry.c
    module.cpp
    module.hpp
)

target_compile_features(example PRIVATE cxx_std_20)
```

Build the module through its outer target:

```sh
cmake --build build --target modules.example
```

Or install a standalone Kbuild tree:

```cmake
kontra_install_kernel_module(
    modules.example
    DESTINATION "src/example-${PROJECT_VERSION}"
    COMPONENT dkms
)
```

For IDE or other CMake-driven development, set `KONTRA_KBUILD_VERBOSE=ON` to show Kbuild's command lines. Kernel projects also expose clean targets such as `modules.clean`; see [Build targets](docs/guide.md#build-targets).

## Important boundaries

Kontraband enables freestanding C++ compilation inside Kbuild; it does not provide a C++ runtime. Allocation operators, pure-virtual failure handlers, nontrivial static-object startup and teardown, and other runtime services must be supplied by projects that need them. Templates, `constexpr`, concepts, classes, value semantics, and other language facilities that do not require unavailable runtime machinery remain available. See [Freestanding C++](docs/guide.md#freestanding-c).

Kontraband does not make Linux kernel C headers directly usable from C++. Linux-facing code still needs a language boundary: C translation units include kernel headers, project-owned C-compatible headers expose the interface toward C++, and `extern "C"` entry points expose C++ implementation back toward C where needed.

## Dual-compiling kernel and user code

Kernel-independent source can be compiled once in the nested freestanding target and again in a normal hosted target. This is useful for algorithms, parsers, fixed-point code, protocol types, and other implementation that can run in either environment or should be exercised with ordinary user-mode tests.

The kernel and hosted builds are separate CMake projects and may use different compiler and runtime policies. Shared declarations that cross an IPC or ABI boundary should still define and version that boundary explicitly.

See [Dual-compiling kernel and user code](docs/guide.md#dual-compiling-kernel-and-user-code) for the detailed pattern.

## Documentation

* [User guide](docs/guide.md) - project setup, file projections, freestanding C++, dual-compilation, kernel and toolchain selection, build targets, installation, supported CMake behavior, and troubleshooting.
* [Diagnostic reference](docs/diagnostics.md) - every emitted `Kontraband[...]` diagnostic identifier, grouped by problem area.

## Bug reports

Include the complete `Kontraband[...]` diagnostic and surrounding configure or build output. The [troubleshooting and bug-report guide](docs/guide.md#troubleshooting-and-bug-reports) lists the environment and reproducer information that is most useful.

## License

Kontraband is licensed under the terms of the MIT License. The buildable kernel module test fixture is available under either the MIT License or the GPL-2.0-or-later license.
