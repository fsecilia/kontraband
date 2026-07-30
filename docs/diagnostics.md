# Kontraband diagnostic reference

Kontraband diagnostics have the form `Kontraband[identifier]: message`. The identifier names the diagnostic category; the message carries the concrete target, path, argument, tool output, or other detail for that occurrence. Include both when reporting a problem.

The reference is grouped by the part of the build that can usually correct the condition. See the [user guide](guide.md) for the surrounding configuration and projection model.

## Package and public API

### `missing-package-version`

The public package entry point was loaded without the version value supplied by the package configuration or top-level project. Consume Kontraband through `find_package()` or its top-level `add_subdirectory()` entry rather than including `kontraband.cmake` directly.

### `version-conflict`

One enclosing CMake build loaded two different Kontraband versions. Ensure dependency resolution selects one Kontraband version for the entire outer build.

### `invalid-arguments`

A public Kontraband command received missing required positional information, unexpected trailing arguments, or a missing required keyword such as `PROJECT` or `DESTINATION`. Check the command invocation named by the message against the [user guide](guide.md).

### `missing-keyword-value`

A recognized public keyword was present without a value. Supply a value for every keyword named by the diagnostic.

### `invalid-name`

A kernel project/module target name violates CMake target-name rules, a configuration name cannot be represented safely as its workspace path component, or a kernel project uses a reserved generator/Kontraband target name. Use a non-reserved name satisfying the rule identified by the diagnostic.

### `invalid-module-output-name`

A requested module `OUTPUT_NAME` cannot be represented as a single `.ko` basename. Supply a portable basename without a directory component or extension.

### `missing-target`

A public operation named an outer CMake target that does not exist. Check the target name and ensure its declaration has already executed.

### `not-a-kernel-project`

An outer CMake target exists but was not created as a Kontraband kernel-project target. Pass the target created by `kontra_add_kernel_project()`.

### `not-a-kernel-module`

An outer CMake target exists but is not an exported Kontraband module target. Pass the module target created by `kontra_add_kernel_module()`, such as `kernel_project.module`.

### `target-already-exists`

Kontraband needs to create an outer target name that is already owned by something else. Rename the conflicting project/module/aggregate target so Kontraband can create its targets without taking over caller-owned targets.

## Project configuration and File API

### `missing-kernel-project`

The nested project directory does not contain the expected `CMakeLists.txt`. Correct `DIRECTORY` or provide the default `kernel/CMakeLists.txt`.

### `missing-projection-root`

`PROJECTION_ROOT` does not name an existing directory. Correct the path or omit it to use the enclosing source directory.

### `missing-kbuild-include`

`KBUILD_INCLUDE` does not name an existing regular file. Correct the path or omit the option.

### `invalid-nested-cmake-argument`

A `CMAKE_ARGUMENTS` entry is not one complete `-D<NAME>[:<TYPE>]=<VALUE>` cache argument. Pass each cache definition as one list element.

### `unsafe-nested-cmake-argument`

A `CMAKE_ARGUMENTS` entry attempts to override nested-project setup owned by Kontraband, such as compiler/launcher, generator, configuration, toolchain, project include hooks, user Make-rules overrides, Make program, or module-scanning state. Use the dedicated Kontraband parameter when one exists; otherwise leave that setup under Kontraband's control.

### `kernel-project-configure-failed`

The nested CMake configure/generate step failed. The diagnostic includes the nested CMake output; fix that configure error before exporting modules.

### `missing-configuration`

The outer and nested configuration models do not provide the configuration Kontraband needs. Check the enclosing generator's configuration list and any configuration-dependent nested CMake logic.

### `missing-module-target`

The selected nested File API configuration contains no target with the name passed to `kontra_add_kernel_module()`. Declare that nested target or correct the module name.

### `file-api`

Kontraband could not read, parse, or consistently resolve required CMake File API data. The message identifies the missing/malformed reply or inconsistent target relationship. If the nested project otherwise configures normally, include the full diagnostic and nested build tree details in a bug report.

### `unprojected-compiler-option`

The nested CMake target resolves to one or more compiler options that Kontraband cannot safely attribute to a project declaration, so those options are not copied into the generated Kbuild and will not be used when the kernel module is compiled. The diagnostic lists each distinct discarded option and reports an occurrence count when the same option appears in multiple compile groups.

Ambient `CFLAGS`, `CXXFLAGS`, `ASMFLAGS`, and `LDFLAGS` are removed before the nested configure because Kbuild owns that compiler and linker baseline. CMake's remaining initialized language/configuration compiler baseline is intentionally excluded from this diagnostic for the same reason. The warning instead identifies additional unattributed options, commonly from direct edits to `CMAKE_<LANG>_FLAGS` or `CMAKE_<LANG>_FLAGS_<CONFIG>` after language initialization, or from CMake target properties whose generated compile-command fragments do not carry usable declaration provenance in the supported File API. At the minimum supported CMake version, known examples include some position-independent-code, visibility, and warning-as-error settings.

If the option is a module-local compiler requirement, express it through a project declaration that Kontraband can project, such as `target_compile_options()`. If it came from a higher-level CMake property, do not blindly replace that property with its current compiler flag unless the semantics are genuinely equivalent; the warning may instead identify a current Kontraband/File API projection limitation worth reporting.

## Kernel and toolchain

### `missing-kernel-build-directory`

Kontraband could not select a unique prepared kernel build directory, or the explicitly selected directory does not exist. Supply `KERNEL_BUILD_DIRECTORY` when automatic selection is unavailable or ambiguous.

### `unprepared-kernel-build-directory`

The selected kernel build directory lacks `include/config/auto.conf`. Prepare/configure the kernel tree before using it for an external-module build.

### `missing-gnu-make`

Kontraband could not find a GNU Make executable named `make` or `gmake`. Install GNU Make or make one of those executable names available on the configuration `PATH`.

### `unsupported-kbuild-path`

A path selected while Kontraband is generating an external-module build contains ASCII syntax outside the supported Make/Kbuild path repertoire. Non-ASCII path components are supported. Move or rename the offending configured path; detached projections that are later relocated do not receive this CMake-side validation.

### `unsupported-kbuild`

The selected kernel's Kbuild does not expose symbols required by Kontraband's C++ compilation rule. Use a supported/prepared kernel or report the kernel version and missing symbols if compatible support appears possible.

### `kernel-toolchain-probe-failed`

The Kbuild toolchain probe failed without producing a more specific Kontraband diagnostic. The message includes the probe output; use it to diagnose the selected kernel/toolchain setup.

### `invalid-kernel-toolchain`

Kbuild's reported compiler/linker command or target-processor information is missing or unusable. Check the selected kernel's toolchain configuration and any `KBUILD_ARGUMENTS` that affect compiler or architecture selection.

### `missing-linker`

The linker selected by Kbuild could not be executed. Install/fix that linker or adjust the Kbuild toolchain selection.

### `unsupported-linker`

The linker selected by Kbuild does not support `--force-group-allocation`, which Kontraband requires for the generated module link. Use a compatible linker or vendor version providing that feature.

### `unsupported-kbuild-argument`

A `KBUILD_ARGUMENTS` entry cannot be serialized safely into the generated Make wrapper. Pass each supported Make/Kbuild argument as one list element without unsupported separators or control characters.

### `unsupported-compiler-argument`

A compiler option, definition, or include-derived token cannot be represented safely in generated Make syntax. The message identifies the offending token and context; express the setting without unsupported list/control characters.

## Projection and target graph

### `invalid-projection-path`

A path that would be written into the detached projection cannot be represented safely in generated Make/Kbuild syntax. Non-ASCII path components are supported; rename or relocate ASCII Make metacharacters or other structurally invalid path components.

### `ambiguous-projection`

A source or include directory outside the primary projection roots maps equally well to multiple reachable target roots. Restructure the nested target/source layout or widen `PROJECTION_ROOT` so the path has one stable projected location.

### `unprojected-path`

A source or include directory is outside `PROJECTION_ROOT`, the nested source/build roots, and every reachable target source/build directory. Choose a `PROJECTION_ROOT` or target layout that gives the path a stable local projection home.

### `missing-projection-file`

A declared nested-project file does not exist after nested configuration. Materialize configure-time files before the File API is read, or correct/remove the declaration.

### `source-is-directory`

A nested target lists a directory as a source entry. Declare files rather than directories.

### `unsupported-generated-source`

A compiled source cannot be represented safely in the static projection. This includes sources reported as `GENERATED` and compilation units synthesized internally by CMake, such as unity-build sources. Materialize project-generated files during configuration and compile ordinary declared C, C++, or assembly sources through Kontraband.

### `unsupported-prebuilt-object`

A nested target lists a prebuilt `.o` or `.obj` as a source. Kontraband exports compilation units for Kbuild to compile rather than embedding precompiled objects.

### `unsupported-precompiled-header`

The nested target uses CMake precompiled headers. Kbuild owns compilation and Kontraband does not translate CMake's PCH workflow; express required headers through ordinary source/include/compiler mechanisms instead.

### `unsupported-source-language`

A compiled source uses a CMake language other than C, C++, or ASM. Restrict the exported object graph to supported compilation languages.

### `source-language-mismatch`

CMake's resolved source language and the projected file suffix disagree with the suffix rules required by Kbuild. Rename the source to an appropriate C, C++, or assembly extension or correct its CMake language treatment.

### `projection-path-collision`

Two different declared files map to the same detached projection path. Change the source/target layout so every projected path has one owner.

### `object-path-collision`

Multiple compiled sources map to the same Kbuild object path, commonly because different source suffixes collapse to the same `.o` name. Rename or relocate one source so object paths are unique.

### `workspace-path-collision`

A non-symlink file or directory occupies a private workspace path that Kontraband needs to own as a projected source link. Remove or relocate the conflicting path; Kontraband will not overwrite it.

### `module-has-no-compilation-units`

The exported module graph contains no C, C++, or assembly compilation units. Add at least one supported compiled source to the terminal/reachable object graph.

### `multi-config-file-sequence-mismatch`

Different configurations of one module resolve to different ordered source-to-projection sequences. Kontraband can vary compile metadata by configuration, but Kbuild consumes module objects in order and the installed projection has one shared file mapping; keep both membership and ordering configuration-independent.

### `unsupported-build-order-dependency`

A reachable target dependency comes from `add_dependencies()`. That command establishes CMake build ordering but does not compose an object library into another target, so Kontraband will not treat the edge as module content. Express compiled composition through supported object-library link relationships instead.

### `unsupported-target-type`

A reachable nested build dependency is not an `OBJECT_LIBRARY`. Kernel module compilation graphs exported by Kontraband must use object libraries for compiled dependencies; move other behavior to supported usage requirements or native Kbuild policy.

## Installation

### `kernel-project-has-no-modules`

`kontra_install_kernel_project()` was called for a kernel project that has no exported modules. Export at least one module with `kontra_add_kernel_module()` or install a specific module target instead.

### `duplicate-project-install-output-name`

Two modules in one project-wide installation use the same output name, so their detached installation directories would collide. Give the modules distinct `OUTPUT_NAME` values or install them separately to distinct destinations.

## Internal failures

### `internal-error`

A Kontraband invariant was violated rather than a supported user error being recognized. Preserve the complete diagnostic and surrounding output and report it with the smallest reproducer available.
