# Kontraband tests

The test tree doubles as executable documentation for the build model. Prefer the ordinary fixtures when looking for usage examples; failure fixtures are deliberately unsupported counterexamples.

- `fixture/project/` is the representative CMake/Kbuild project used by most fast tests. Its unusual compiler properties and global flag assignment are deliberate probes and are called out where they appear.
- `fixture/real/` is the real-kernel C/C++/assembly fixture. It exercises COMDAT linking, virtual dispatch, ELF and kernel-LTO intermediate objects, Kbuild warning inheritance, checked/unchecked builds, and detached installation against an actual prepared kernel tree.
- `fixture/fake_kernel*` implements only the small Kbuild protocol needed by fast tests. These directories are test doubles, not examples of valid kernel build trees.
- `cmake/failure/` contains minimal projects that are expected to fail. They pin diagnostic boundaries and should be read as counterexamples rather than supported usage.

Most script tests create isolated source/build trees under the CTest work directory so they can exercise configuration-time behavior without mutating the checked-in fixtures. Comments explain constructs that are intentionally unusual or encode a boundary that is easy to misread from syntax alone.
