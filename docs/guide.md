# Kontraband user guide

Kontraband builds Linux kernel modules containing freestanding C++ from CMake projects.

A normal CMake project declares a nested project for the kernel code. The nested project uses familiar CMake targets and properties. Kontraband reads the result and generates the Kbuild files needed to compile and link the module.

The generated module tree can also be installed as a standalone, CMake-free source tree for direct Kbuild or DKMS use.

For the shortest setup path, see the repository [README](../README.md). For a specific `Kontraband[...]` failure, see the [diagnostic reference](diagnostics.md).

## Requirements

Kontraband requires:

* CMake 3.31.6 or newer;
* GNU Make;
* a prepared Linux kernel build directory;
* Linux 6.12 as the oldest supported and continuously tested Kbuild baseline;
* the compiler and utilities required by that kernel;
* a linker supporting `--force-group-allocation`.

Kontraband checks the linker feature it needs, so compatible vendor backports are accepted. Upstream GNU ld added `--force-group-allocation` in binutils 2.29 and upstream LLD added it in LLD 19.1. The same check runs for normal builds and for detached projections.

Kontraband also checks the Kbuild internals used by its C++ compile rule. If the selected kernel does not provide them, configuration fails. Earlier kernels may work, but they are outside the supported test matrix.

Projected paths may contain non-ASCII characters. Kontraband rejects characters it cannot safely encode in the generated Make/Kbuild syntax. The private Kbuild workspace is passed through `M=`, so its path is more restricted and cannot contain characters such as spaces or `=`.

## Using Kontraband

### Installed package

Install Kontraband normally:

```sh
cmake -S path/to/kontraband -B build/kontraband -DCMAKE_INSTALL_PREFIX="$HOME/.local"
cmake --install build/kontraband
```

Then consume it with:

```cmake
find_package(kontraband 0.1 CONFIG REQUIRED)
```

If Kontraband is installed under a nonstandard prefix, add that prefix to the consuming project's `CMAKE_PREFIX_PATH`.

### Vendored subproject

Kontraband can also be included directly:

```cmake
add_subdirectory(external/kontraband)
```

When used this way, `kontraband_INSTALL` defaults to `OFF`. Enable it only if installing the parent project should also install the bundled Kontraband package for downstream `find_package()` users:

```cmake
set(kontraband_INSTALL ON CACHE BOOL "install bundled Kontraband transitively")
add_subdirectory(external/kontraband)
```

Do not use `EXCLUDE_FROM_ALL` if Kontraband's install rules need to participate in the parent installation. If Kontraband is only needed to build the parent project, leaving `kontraband_INSTALL` off makes `EXCLUDE_FROM_ALL` harmless.

Installed and vendored use expose the same public commands. Loading the same Kontraband version more than once is harmless. Loading different versions into one build fails rather than silently choosing one.

## Project model

A typical project has an outer CMake project and a nested project for kernel code:

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

The outer project declares the nested project and chooses one or more nested object-library targets to export as kernel modules:

```cmake
# project/CMakeLists.txt

find_package(kontraband CONFIG REQUIRED)

kontra_add_kernel_project(modules)

kontra_add_kernel_module(
    example
    PROJECT modules
    OUTPUT_NAME example_module
)
```

For this layout, `kontra_add_kernel_project(modules)` uses these defaults:

```cmake
DIRECTORY       "${CMAKE_CURRENT_SOURCE_DIR}/modules"
PROJECTION_ROOT "${CMAKE_CURRENT_SOURCE_DIR}"
```

`DIRECTORY` is the directory containing the nested `CMakeLists.txt`.

`PROJECTION_ROOT` is the source-tree anchor whose relative layout is preserved under `projection/` in generated module trees.

A monorepo can choose a narrower projection root:

```cmake
kontra_add_kernel_project(
    modules
    PROJECTION_ROOT "${PROJECT_SOURCE_DIR}/src"
)
```

The project name, nested target name, and module filename are separate:

```text
modules                 nested CMake project and outer aggregate target
example                 nested OBJECT_LIBRARY target
example_module.ko       kernel module selected by OUTPUT_NAME
```

The outer CMake target for the module is:

```text
modules.example
```

It can be built, cleaned, installed through the Kontraband APIs, or used in ordinary CMake dependencies.

## Nested CMake target model

The nested project uses normal CMake target APIs:

```cmake
# project/modules/CMakeLists.txt

cmake_minimum_required(VERSION 3.31.6)
project(example_modules LANGUAGES C CXX)

add_library(example_core OBJECT EXCLUDE_FROM_ALL)

target_sources(example_core PRIVATE
    ../src/shared.cpp
    ../include/example/shared.hpp
)

target_include_directories(example_core PUBLIC
    "${CMAKE_CURRENT_LIST_DIR}/../include"
)

target_compile_features(example_core PUBLIC cxx_std_20)

add_library(example OBJECT EXCLUDE_FROM_ALL)

target_sources(example PRIVATE
    entry.c
    module.cpp
    module.hpp
)

target_link_libraries(example PRIVATE example_core)
```

CMake resolves sources, usage requirements, generator expressions, and target settings. Kontraband reads that resolved information instead of maintaining a second CMake-like dependency model.

There is one important addition to normal CMake object-library behavior: when one `OBJECT_LIBRARY` links another, Kontraband includes the linked library's objects in the kernel module as well. CMake itself uses that relationship to propagate usage requirements but does not normally include the linked object's files in another object library.

`INTERFACE_LIBRARY` usage requirements and `INTERFACE_SOURCES` work through the information CMake resolves for the object targets.

Set the final module name with `OUTPUT_NAME` on `kontra_add_kernel_module()`. An `OBJECT_LIBRARY` has no linked artifact of its own, so its CMake `OUTPUT_NAME` is not used.

## Files and projections

A projection contains the files represented by the CMake target graph. Include directories do not cause whole directory trees to be copied.

Attach every source, header, script, or other support file needed by a detached build through `target_sources()` or a supported file set:

```cmake
target_sources(example PRIVATE
    entry.c
    module.cpp
    module.hpp
    protocol.hpp
    developer-helper.sh
)
```

CMake decides which entries are compilation units. Other declared files are carried as support files regardless of their suffix.

An undeclared header is not present in the development workspace or an installed projection. This keeps local and detached builds on the same declared file set.

### Compiled languages

Kontraband supports C, C++, and ASM compile groups.

C and assembly use Kbuild's native rules. Preprocessed `.S` sources are supported and receive their CMake-resolved per-object settings through `AFLAGS_<object>`.

Lowercase `.s` assembly sources are not supported by Kbuild's kernel compilation rules. Use preprocessed assembly (`.S`) instead.

### Lexical paths and directory symlinks

Projection paths follow the spelling used in the CMake project. Kontraband does not resolve a directory symlink and then recreate every alternate path to the same file.

For example:

```text
real/header.hpp
link -> real
```

If code reaches the header through `link/header.hpp`, declare the file through that spelling. Declaring only `real/header.hpp` does not create a second `link/header.hpp` path in the projection.

### File globs

Nested uses of:

```cmake
file(GLOB ... CONFIGURE_DEPENDS ...)
```

and:

```cmake
file(GLOB_RECURSE ... CONFIGURE_DEPENDS ...)
```

keep their normal CMake reconfiguration behavior. Kontraband reads the matching information from the nested File API and registers equivalent checks in the outer build, so adding or removing a matching path refreshes the projection.

A glob without `CONFIGURE_DEPENDS` remains a configure-time result and does not gain automatic membership tracking.

### Generated files

Files that exist before the nested project finishes configuring can be projected normally. This includes configure-time output from facilities such as:

```cmake
configure_file(...)
file(CONFIGURE ...)
```

Files under a CMake build tree are placed under `generated/` in the projection. This placement comes from the file's path; it is separate from CMake's `GENERATED` property.

A source reported as `GENERATED` by the nested File API is rejected. The File API does not give Kontraband enough information to distinguish every safe generation-time file from build-time output that may be missing or stale, so Kontraband does not try to reconstruct CMake's generation graph.

CMake-generated compilation units that cannot be traced back to a declared source are also rejected. Unity-build translation units fall into this category because their generated contents refer back to the original source tree.

Configure-time files explicitly attached to a target remain supported. Files produced by the outer project follow the same rule: they must already exist and have a stable path under `PROJECTION_ROOT` or one of the nested source/build roots.

`add_dependencies()` is not supported in the nested graph. It describes CMake build ordering, while Kontraband needs object composition and does not run a second nested build before invoking Kbuild.

## Freestanding C++

Kontraband makes freestanding C++ translation units participate in Kbuild. It does not provide a C++ runtime for the kernel.

In particular, Kontraband does not provide:

* allocation operators;
* exception runtime support;
* RTTI runtime support;
* pure-virtual failure handlers;
* startup or teardown machinery for nontrivial static objects;
* mappings from C++ allocation to kernel allocators.

The usable part of C++ is the part that does not depend on runtime services the project has not supplied. That still includes templates, `constexpr`, concepts, classes, value semantics, overloads, compile-time machinery, ordinary function calls, and RAII for normal scoped lifetimes.

Exceptions and RTTI are disabled by the generated C++ rule. Function-local static initialization is not made thread-safe by the compiler baseline.

Virtual dispatch itself does not require a hosted runtime, but pure virtual functions can introduce ABI hooks such as `__cxa_pure_virtual`. Provide any hook you depend on, or avoid the construct.

Static storage with trivial initialization is straightforward. If a project needs nontrivial static construction or other runtime support, it must provide and manage that support itself.

### Linux kernel headers and the C++ boundary

Kontraband does not make Linux kernel headers C++ compatible.

Kernel headers often rely on C constructs and on the include environment Kbuild creates for C translation units. Recreating that entire environment for C++ would conflict with the freestanding C++ environment Kontraband is trying to provide.

There is also an easy failure mode that can look like success. C++ keeps the compiler's normal system include search, so:

```cpp
#include <linux/types.h>
```

may find a userspace/UAPI header under `/usr/include` instead of the headers from the kernel being built.

The same issue applies to architecture-specific and generated kernel headers. Kontraband does not try to maintain a complete denylist.

Keep Linux-facing leaves in C where needed. Expose project-owned C-compatible interfaces toward C++, and expose C++ implementation back toward C through explicit `extern "C"` entry points.

This is also the supported boundary for versioned exported kernel symbols. Kontraband does not run Kbuild's C `genksyms` source-processing step on C++ translation units. Imports still use normal Kbuild and MODPOST behavior.

### x86-64 floating point

Linux x86-64 Kbuild normally disables x87 code generation with `-mno-80387`, which also catches accidental floating-point use.

Some C++ standard-library headers still need the target ABI's `long double` type even when the program itself uses only integer facilities. With some supported compiler/library combinations, headers such as `<limits>` and `<algorithm>` do not compile when x87 is disabled.

For `CONFIG_X86_64=y`, Kontraband therefore adds:

```text
-m80387
```

to C++ compilation. The condition comes from the target kernel's Kbuild configuration. C and assembly keep Kbuild's normal floating-point policy, and non-x86-64 C++ does not receive this flag.

This makes the C++ language environment usable; it does **not** make floating point supported in ordinary kernel C++.

Because `-m80387` allows x87 instructions, C++ translation units no longer get Kbuild's usual compile-time x87 tripwire. Do not use `float`, `double`, `long double`, floating-point arithmetic, x87 or floating-point SIMD operations, or related intrinsics merely because the compiler accepts them.

Code that explicitly manages architecture floating-point or SIMD state through kernel facilities is outside Kontraband's freestanding C++ model.

### Function tracing

Kontraband does not apply Kbuild's function-tracing compiler instrumentation to C++ translation units.

C++ template and inline code can produce duplicate COMDAT sections in several translation units, while ftrace's mcount-location metadata lives outside those groups. During the relocatable module link, metadata can otherwise retain references to discarded duplicates.

The generated C++ rule removes Kbuild's `CC_FLAGS_FTRACE` and related `CC_USING_*` definitions from the inherited C flags. C and assembly keep Kbuild's normal tracing policy.

Reintroducing those compiler flags for C++ is outside the supported model.

## Dual-compiling kernel and user code

Dual-compilation is optional. It lets the same source build once as freestanding kernel C++ through Kontraband and again as an ordinary hosted CMake target. The hosted build can then use normal user-mode unit and integration testing tools against code that also runs in the kernel.

Project-owned protocol and interface declarations can use the same pattern when they are designed for both environments. An IPC or ABI boundary should still be explicit and versioned; compiling the declarations in both places does not remove compatibility concerns between independently deployed components.

These are two real CMake projects. Kontraband does not recreate one target graph from the other. A simple way to share file declarations is an ordinary CMake function included by both projects:

```cmake
# src/library/config.cmake

function(configure_shared target)
    set(root "${CMAKE_CURRENT_FUNCTION_LIST_DIR}")

    target_sources("${target}" PRIVATE
        "${root}/shared.cpp"
        "${root}/shared.hpp"
    )
endfunction()
```

Each project includes `config.cmake` and calls `configure_shared()` for its own target.

Projects that intentionally share directory-wide C++ defaults can do the same with a normal policy file:

```cmake
# cmake/shared-cxx-policy.cmake

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
```

This is just ordinary project organization. Target-specific requirements should still use APIs such as `target_compile_features()` and target properties.

## Kernel and toolchain selection

### Selecting the kernel

Specify a prepared kernel build directory when needed:

```cmake
kontra_add_kernel_project(
    modules
    KERNEL_BUILD_DIRECTORY "/path/to/kernel/build"
)
```

The enclosing variable:

```cmake
KONTRA_KERNEL_BUILD_DIRECTORY
```

provides a project-wide default and may be a normal or cache variable.

Without either setting, Kontraband uses the running kernel's build directory or, if there is only one, the available `/lib/modules/*/build` directory.

The selected kernel must contain:

```text
include/config/auto.conf
```

Changes to `auto.conf` cause the outer CMake project to reconfigure so the kernel and toolchain information can be refreshed.

### Matching Kbuild's compiler

Kontraband asks Kbuild for its resolved:

```make
$(CC)
$(LD)
```

commands and `UTS_MACHINE`.

For the nested CMake configure, it uses that compiler command plus only Kbuild's target selectors:

```text
-m32
-m64
--target=...
```

This gives CMake the same compiler family and target architecture as Kbuild without importing Kbuild's full compiler flag set into the nested project.

Kbuild's native rules compile C and assembly. Kontraband's C++ rule also invokes Kbuild's `$(CC)`; it does not discover or invoke `CXX`, `g++`, or `clang++`.

When the kernel target differs from the CMake host, the nested project is configured as a Linux cross build with `CMAKE_SYSTEM_PROCESSOR` taken from `UTS_MACHINE`. Compiler checks use static libraries so configuration does not require a target userspace linker environment or sysroot.

The remaining compiler policy stays with Kbuild.

Kontraband reproduces the prepared kernel's compiler/linker family with the smallest Kbuild selection needed:

```text
GCC   + GNU ld -> Kbuild defaults
Clang + GNU ld -> CC=clang
GCC   + LLD    -> LD=ld.lld
Clang + LLD    -> LLVM=1
```

`LLVM=1` is used only when both the compiler and linker are LLVM. Mixed GNU/LLVM kernels stay mixed.

Cross-compiling C++ also requires suitable target standard-library headers. Kontraband selects the compiler and target architecture; it does not provide a C++ standard library or sysroot. For example, host Clang targeting `aarch64-linux-gnu` needs appropriate arm64 C++ headers before freestanding standard-library facilities can be used.

## Kbuild arguments

Use `KBUILD_ARGUMENTS` for Kbuild settings that belong to the configured projection:

```cmake
kontra_add_kernel_project(
    modules
    KBUILD_ARGUMENTS
        "ARCH=arm64"
        "LLVM=-21"
        "CROSS_COMPILE=aarch64-linux-gnu-"
)
```

Kontraband passes these entries to Kbuild unchanged. It does not interpret `ARCH=`, `LLVM=`, `CC=`, `LD=`, `CROSS_COMPILE=`, or other Make/Kbuild semantics.

The arguments are applied after Kontraband's derived toolchain selection and are written into every generated wrapper `Makefile`, so normal builds, clean operations, installation, DKMS, and detached builds all use the same list.

GNU Make and Kbuild decide how user arguments interact with Kontraband's derived settings. If the selections contradict each other, that is a configuration error in the consuming project.

After applying the arguments, Kontraband asks Kbuild for the resulting `$(CC)` and `$(LD)` rather than trying to predict the result.

### Baked arguments are persistent

A projection records one Kbuild context.

If it is configured with:

```text
ARCH=arm64
```

then later invoking its wrapper with:

```sh
make ARCH=x86
```

does not turn it into an x86 projection. Configure another projection when architecture or other compiler-sensitive Kbuild context needs to change.

Because `KBUILD_ARGUMENTS` is opaque, anything placed there becomes persistent, including invocation settings such as:

```text
-j16
V=1
```

or machine-local paths.

Do not put a setting in `KBUILD_ARGUMENTS` if callers need to vary it from one build to another.

For verbose CMake-driven development builds, prefer [`KONTRA_KBUILD_VERBOSE`](#verbose-kbuild-output) instead of baking `V=1` into the projection.

### Supplying Kbuild arguments from the CMake command line

A consuming project can expose its own cache variable:

```cmake
set(MODULE_KBUILD_ARGUMENTS
    ""
    CACHE STRING
    "Additional arguments passed to Kbuild"
)

set(module_project_arguments)

if(MODULE_KBUILD_ARGUMENTS)
    list(APPEND module_project_arguments
        KBUILD_ARGUMENTS
        ${MODULE_KBUILD_ARGUMENTS}
    )
endif()

kontra_add_kernel_project(
    modules
    ${module_project_arguments}
)
```

Then configure with a normal CMake list:

```sh
cmake -S . -B build \
    -DMODULE_KBUILD_ARGUMENTS="ARCH=arm64;LLVM=-21;CROSS_COMPILE=aarch64-linux-gnu-"
```

### Kontraband-required Kbuild settings

Kontraband always supplies:

```text
LDFLAGS_MODULE=--force-group-allocation
CONFIG_DEBUG_INFO_BTF_MODULES=
```

These assignments override conflicting `KBUILD_ARGUMENTS`.

`--force-group-allocation` keeps C++ COMDAT contents intact through Kbuild's relocatable module link. Kontraband checks the linker selected by Kbuild for support during configuration and again when a detached build needs that linker. `clean` does not require a working linker.

Module BTF is disabled because the current BTF toolchain does not support this C++ module model end to end. In particular, `pahole` can encounter C++ DWARF constructs it cannot translate, producing noisy diagnostics or failing the module build.

Consumers do not need to repeat either setting in DKMS commands.

## CMake compile settings

A projection stores the concrete compile settings resolved by one nested CMake configuration.

For example:

```cmake
target_compile_options(example PRIVATE
    "$<$<CXX_COMPILER_ID:GNU>:-Wsome-gcc-option>"
)
```

becomes either the resolved compiler option or nothing. The generator expression itself is gone by the time Kbuild sees the projection.

Kontraband exports compile-command fragments when CMake's File API can attribute them to a declaration, along with the resolved language-standard option when one is needed.

Before configuring the nested project, Kontraband removes ambient `CFLAGS`, `CXXFLAGS`, `ASMFLAGS`, and `LDFLAGS`. Those variables would otherwise change CMake's compiler or linker baseline even though that ambient baseline is not replayed when Kbuild performs the real module build.

Ambient `CMAKE_<LANG>_COMPILER_LAUNCHER` settings are left alone. They may affect CMake's configure-time compiler probes, but they are not written into Kbuild.

CMake's initialized language and configuration baseline is also not copied into Kbuild. Options originating from `CMAKE_<LANG>_FLAGS_INIT` and `CMAKE_<LANG>_FLAGS_<CONFIG>_INIT` are ignored because Kbuild supplies the kernel compiler baseline.

Other compiler fragments that CMake reports without enough information to identify their source are also left out. Kontraband warns with [`Kontraband[unprojected-compiler-option]`](diagnostics.md#unprojected-compiler-option) and lists the discarded options. Repeated occurrences are counted separately, so a baseline option does not hide an additional project-supplied copy of the same option.

At CMake 3.31.6, this can affect some flag-producing properties whose generated command fragments do not carry declaration provenance, including some position-independent-code, visibility, and warning-as-error settings. Direct edits to `CMAKE_<LANG>_FLAGS` or `CMAKE_<LANG>_FLAGS_<CONFIG>` after language initialization are also unattributed and are warned about when omitted.

If kernel compiler policy must survive into the module build, prefer `target_compile_options()` or native Kbuild policy.

Kontraband does not add `NDEBUG` by itself. An explicit target or directory compile definition is handled like any other CMake-resolved definition.

Kbuild's warning policy remains in effect where it makes sense for C++. Kontraband removes inherited flags only when they are invalid or specifically C-only in the C++ frontend. Projects can still override ordinary warning policy through target options:

```cmake
target_compile_options(example PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:-Wno-missing-declarations>"
)
```

Other compiler options and definitions are replayed verbatim after CMake resolves them. Kontraband does not parse compiler-specific syntax looking for hidden filesystem dependencies or embedded paths, and it does not try to rebase paths encoded inside those options.

That means paths embedded in facilities such as:

```text
-include
-imacros
response files
compiler plugins
compiler configuration options
compile definitions
```

remain the consuming project's responsibility. Prefer CMake's structured source and include-directory APIs for files that must be present in a detached projection.

CMake itself drops compile definitions containing `#` instead of placing them on the compiler command line and reports that during nested configuration. Use a configured header when such a definition is needed.

### Multi-config generators

Compile settings may vary by configuration, but the ordered source list for a module must be the same in every configuration.

Kbuild consumes one ordered module object list, and installation uses one common file mapping. Kontraband therefore rejects configuration-dependent changes to source membership or source order.

Configuration names still control the nested CMake graph and its resolved definitions, options, include directories, and other settings. Kontraband only requires the final ordered source mapping to remain the same. Configuration names do not import CMake's initialized Debug/Release compiler baseline into Kbuild.

For single-config generators, an empty `CMAKE_BUILD_TYPE` stays empty. Kontraband does not treat it as `Release`.

## Build-time Kbuild policy

Use `KBUILD_INCLUDE` for settings that must remain conditional until Kbuild actually builds the module:

```cmake
kontra_add_kernel_project(
    modules
    KBUILD_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/modules/options.kbuild"
)
```

For example:

```make
# options.kbuild

ifeq ($(CONFIG_CC_IS_CLANG),y)
    ccflags-y += -Wno-some-clang-warning
else
    ccflags-y += -Wno-some-gcc-warning
endif

ccflags-y += $(call cc-option,-foptional-optimization)
```

During development and in detached projections, the file is named:

```text
kontra-user.kbuild
```

The generated Kbuild includes it directly. Kontraband does not parse or lint its contents.

Use nested CMake for settings that should be resolved while the projection is configured. Use `KBUILD_INCLUDE` for native Kbuild logic that must remain conditional at module-build time.

## Build targets

Normal module targets are checked builds:

```sh
# One module
cmake --build build --target modules.example

# Every module in one nested project
cmake --build build --target modules

# Every Kontraband module in the outer build
cmake --build build --target kontra_kernel_modules
```

A checked target always enters Kbuild. Kbuild then decides whether anything actually needs recompilation using its own `.cmd` dependency and command records, including dependencies the outer CMake graph cannot see.

Every level also has an `.unchecked` target:

```sh
cmake --build build --target modules.example.unchecked
cmake --build build --target modules.unchecked
cmake --build build --target kontra_kernel_modules.unchecked
```

Unchecked targets look only at dependencies known to the outer CMake graph:

* declared module files;
* generated `Kbuild`;
* generated wrapper `Makefile`;
* `KBUILD_INCLUDE`, when present;
* the selected kernel's `include/config/auto.conf`.

If none of those changed, an unchecked build can be a true outer-build no-op without entering Kbuild.

Use `.unchecked` only when you know the prepared kernel tree, toolchain, and dependencies known only to Kbuild have not changed. Normal development, CI, and release validation should generally use checked targets.

Every level has a clean target too:

```sh
# One module
cmake --build build --target modules.example.clean

# Every module in one nested project
cmake --build build --target modules.clean

# Every Kontraband module in the outer build
cmake --build build --target kontra_kernel_modules.clean
```

Kontraband module targets are not part of the outer project's default build unless the project adds ordinary CMake dependencies that make them so.

### Verbose Kbuild output

`KONTRA_KBUILD_VERBOSE` is a cache `BOOL` for verbose Kbuild output during CMake-driven development builds:

```sh
cmake -S . -B build -DKONTRA_KBUILD_VERBOSE=ON
cmake --build build --target modules.example
```

This passes `V=1` when Kontraband enters the development wrapper. It applies to checked, unchecked, and clean development targets and is convenient for IDEs that expose the CMake cache.

The setting is not stored in the projection and does not affect installed or otherwise detached builds. Pass `V=1` directly to Make when building a detached projection.

### Build workspace

During outer configuration, Kontraband:

* configures the nested project;
* reads `codemodel-v2` and `cmakeFiles-v1` from CMake's File API;
* creates symlinks for the declared file set in a private writable Kbuild workspace;
* writes `Kbuild` and the wrapper `Makefile`;
* registers nested CMake inputs as dependencies of the outer configuration.

Normal development builds do not copy source contents. The workspace symlinks point Kbuild at the current files while keeping `.o`, `.cmd`, and other Kbuild output out of the source tree.

Changing a nested CMake input triggers normal outer CMake regeneration, which refreshes the graph and workspace membership.

### Parallel builds

With Ninja, Kontraband runs Kbuild through Ninja's terminal pool. This keeps checked, unchecked, and clean operations from mutating the same module workspace at the same time and keeps Kbuild output attached to the terminal.

The terminal pool also serializes Kbuild invocations for otherwise independent modules.

Ninja has no GNU Make jobserver to pass into the nested build, so `cmake --build build -jN` does not automatically set Kbuild's inner parallelism. Manual and detached wrapper builds can pass `-jN` directly to Make. Putting `-jN` in `KBUILD_ARGUMENTS` makes it persistent and should only be done intentionally.

With Unix Makefiles, nested Make invocations are marked jobserver-aware, so outer `-j` parallelism can flow into Kbuild.

Unix Makefiles do not provide Ninja's per-workspace serialization. If checked, unchecked, or clean operations for the same module are placed under one parallel aggregate target, they can race while changing the shared workspace. Avoid aggregating conflicting operations for one module under the same parallel Makefiles target.

## Installation and detached builds

A projection can be installed without building the module first.

Install one module:

```cmake
kontra_install_kernel_module(
    modules.example
    DESTINATION "src/example-${PROJECT_VERSION}"
    COMPONENT dkms
)
```

Or install every module in a kernel project:

```cmake
kontra_install_kernel_project(
    modules
    DESTINATION "share/example/modules"
    COMPONENT dkms
)
```

A project with one module installs directly at `DESTINATION`. A project with several modules creates one subdirectory per module output name. Two modules in the same project installation cannot share an output name because their detached trees would collide.

### What gets installed

Installation uses the source-to-projection mapping captured during configuration.

At install time, Kontraband creates a fresh staging tree from the declared files, adds the generated `Kbuild` and wrapper `Makefile`, and installs that tree with normal CMake installation machinery.

A typical detached module contains:

```text
Makefile
Kbuild
projection/...
components/...
generated/...
kontra-user.kbuild    # only when KBUILD_INCLUDE is used
```

It does not contain the nested CMake project, File API replies, the development workspace, the Kontraband package itself, or a separate Kontraband install manifest. CMake's normal install manifest still records the installed files.

### Source freshness

The module does not need to be built before installation.

Source contents are read at install time, so ordinary edits made after the most recent build are included. Changes to file membership or compile metadata still require CMake reconfiguration, just as they do for the generated buildsystem itself.

A `CONFIGURE_DEPENDS` glob causes the next build-system check, such as:

```sh
cmake --build build
```

to reconfigure when its match set changes.

A direct:

```sh
cmake --install build
```

does not perform that build-system check first.

### Symlinks during installation

CMake normally preserves source symlinks while installing directories. Kontraband instead dereferences declared source symlinks when it creates a detached module tree, so the installed projection does not depend on an external source path.

The installed entries are regular files with the source file's permissions.

As with normal CMake installation, Kontraband does not remove files left in an existing prefix by an older file set. Use a clean staging prefix when exact installed membership matters.

### Building a detached projection

Run the generated wrapper directly:

```sh
make -C path/to/installed/module KERNEL_DIR="/lib/modules/$(uname -r)/build"
```

The default target is `modules`. The wrapper also forwards Kbuild's:

```text
modules_install
clean
```

targets.

`KERNEL_DIR` defaults to the build directory for the running kernel.

Kontraband validates the paths it creates while generating the projection. After installation, the caller can relocate the tree or choose another `KERNEL_DIR`; those paths must themselves be valid for GNU Make and external-module Kbuild. The detached wrapper does not rerun Kontraband's CMake-side path checks.

Settings not stored in `KBUILD_ARGUMENTS` remain normal Make command-line arguments:

```sh
make -C path/to/installed/module KERNEL_DIR=/path/to/kernel/build -j16 V=1
```

A command-line assignment cannot override the same variable if that variable was baked into `KBUILD_ARGUMENTS`.

### Installing a built kernel module

Use Kbuild's `modules_install` target to install the resulting `.ko`:

```sh
make -C path/to/installed/module KERNEL_DIR=/path/to/kernel/build INSTALL_MOD_STRIP=1 modules_install
```

Installation policy remains Kbuild's. For example, `INSTALL_MOD_PATH` stages beneath another root, while `INSTALL_MOD_STRIP=1` requests stripping during installation. Kontraband does not force stripping.

Prefer Kbuild's install-time stripping to manually stripping the module afterward so Kbuild remains in control of its installation pipeline.

### DKMS

A DKMS package should invoke the generated wrapper's `modules` target:

```bash
MAKE[0]="make KERNEL_DIR=\"$kernel_source_dir\" modules"
```

Do not duplicate Kontraband's required Kbuild arguments or invoke `modules_install`; DKMS handles deployment of the built module.

DKMS also controls stripping in this workflow. By default it strips debug symbols from built modules. Set the corresponding `STRIP[#]` entry to `no` when symbols must be retained; `STRIP[0]` supplies the default for entries without their own value.

No additional Makefile wrapper is needed. Package identity, `BUILT_MODULE_NAME`, installation destination, signing, and other DKMS policy remain the package's responsibility.

## Additional nested CMake arguments

`CMAKE_PREFIX_PATH` extends the nested project's package search path.

Use `CMAKE_ARGUMENTS` for additional ordinary CMake cache definitions:

```cmake
kontra_add_kernel_project(
    modules
    CMAKE_ARGUMENTS
        "-DEXAMPLE_FEATURE=ON"
)
```

Each entry must be one complete argument of the form:

```text
-D<NAME>[:<TYPE>]=<VALUE>
```

Some nested CMake settings are controlled by Kontraband because they define the private configure itself. These include compiler selection, explicit compiler-launcher cache arguments, global compiler flags, generator, source/build directories, toolchain file, build type, configuration list, project include hooks, Make-rules overrides, Make program, prefix-path transport, and C++ module-scanning setup.

Those settings cannot be overridden through `CMAKE_ARGUMENTS`. Use the dedicated `CMAKE_PREFIX_PATH` parameter for package search paths and `KBUILD_ARGUMENTS` for Kbuild settings.

Other CMake command-line forms such as `--toolchain`, `-C`, `-U`, split `-D` arguments, and presets are rejected.

Kontraband starts the nested configure with:

```text
CMAKE_OPTIMIZE_DEPENDENCIES=OFF
```

CMake's dependency optimization can remove object-library relationships that Kontraband uses to assemble a module. `OFF` is only the default: `CMAKE_ARGUMENTS` may override it, and the nested project may set the variable or target property itself. If optimization removes a reachable object-library relationship, those objects will not appear in the projection.

## Supported CMake graph

Kontraband supports:

* module targets declared as `OBJECT_LIBRARY`;
* reachable `OBJECT_LIBRARY` dependencies used to compose a module;
* normal transitive CMake usage requirements;
* `INTERFACE_LIBRARY` requirements and `INTERFACE_SOURCES` resolved by CMake;
* C, C++, and ASM compilation units;
* explicitly declared noncompiled support files;
* `HEADERS` file sets;
* `CONFIGURE_DEPENDS` globs reported through the nested File API;
* files created by configure-time logic before the nested File API is read.

It does not support:

* build-order edges introduced by `add_dependencies()`;
* reachable static, shared, module, executable, or `UTILITY` targets;
* imported compiled libraries;
* raw archive or library paths;
* other link-only inputs;
* prebuilt `.o` or `.obj` source entries;
* CMake precompiled headers;
* sources reported as `GENERATED` by the nested File API;
* CMake-created compilation units such as unity-build sources;
* sources or include directories without a stable local projection path;
* paths that cannot be represented safely in Kbuild;
* undeclared recursive include-tree copying;
* automatic proof that opaque compiler options or definitions are relocatable, including discovery of hidden filesystem dependencies;
* automatic proof that compiler-sensitive CMake logic remains valid under a different detached toolchain.

Non-ASCII projected path components are supported. Kontraband rejects ASCII syntax it cannot safely encode in generated Make/Kbuild paths.

### Object ordering

Source order is preserved within each object library. The CMake 3.31 File API does not expose a meaningful link order between sibling object-library dependencies, so code should not depend on sibling object libraries being ordered in a particular way. Ordinary symbol references do not depend on that order.

### Link-only dependencies

Kontraband uses the relationship information available in the CMake 3.31.6 File API model across all supported CMake versions. It does not change graph interpretation when run under newer CMake releases.

That model does not expose every kind of object-library link input. In particular, imported compiled-library targets and raw library items may be absent from the information Kontraband receives. These forms are unsupported, and Kontraband cannot always diagnose them before they disappear from the projection.

### C++ modules

C++ module units and CMake's module dependency-scanning workflow are not supported.

Kontraband disables `CXX_SCAN_FOR_MODULES` because Kbuild, not the nested CMake project, performs the actual compilation and dependency ordering.

## Troubleshooting and bug reports

Kontraband diagnostics use identifiers such as:

```text
Kontraband[unsupported-generated-source]
```

The [diagnostic reference](diagnostics.md) documents every emitted identifier.

When reporting a problem, include the complete diagnostic and the surrounding configure or build output. It is also useful to include:

* CMake version and generator;
* kernel release and prepared kernel build directory;
* whether the kernel uses GCC or Clang;
* whether it uses GNU ld or LLD;
* relevant `KBUILD_ARGUMENTS`;
* relevant `CMAKE_ARGUMENTS`;
* the smallest nested `CMakeLists.txt` that reproduces the graph;
* Kontraband test output, when readily available.

For supported input, Kontraband is intended to fail rather than produce a plausible but incomplete module. If it does produce incomplete output, that is a bug worth reporting. So is a rejected CMake construct that can be projected safely without recreating CMake or Kbuild inside Kontraband.
