# Plan: pinned-from-source build

Status: segfault investigation done; Simbody 3.9 chosen
(docs/DECISION-simbody-3.9.md). Done: CMake version check, pinned
Dockerfile (verified with docker build/run), setup.sh rewritten to match
Dockerfile policy, BUILDING.md updated, OpenMM 8.6.1 pinned (2025-11,
verified: plugin compiles, same 35/37 suite result). Not started: CI
workflow.

## Segfault verification

Question: does a newer Simbody fix the test segfaults seen with Ubuntu's
apt Simbody 3.7?

Answer: yes. Built Simbody 3.9 (latest release tag Simbody-3.9) from
source, installed to a scratch prefix, and rebuilt molmodel against it:

    curl -sL https://github.com/simbody/simbody/archive/refs/tags/Simbody-3.9.tar.gz | tar xz -C /tmp
    cmake -S /tmp/simbody-Simbody-3.9 -B /tmp/simbody-build \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/tmp/simbody-install \
        -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF
    cmake --build /tmp/simbody-build -j$(nproc) && cmake --install /tmp/simbody-build
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
        -DSimbody_DIR=/tmp/simbody-install/lib/cmake/simbody

Note: Simbody's CMake package dir is lowercase `simbody`. If the
Simbody_DIR hint is wrong, CMake silently falls back to system Simbody
and reports "Found Simbody version 3.7" — always check that line in the
configure output.

Results: 35/37 tests pass (baseline with 3.7 was 12/37). All 25
segfaults gone. Remaining failures, both assertion failures, not crashes:

- TestPdb: fails identically on 3.7, 3.8, and 3.9. Round-trip string
  comparison in tests/TestPdb.cpp:73, in molmodel's own recently
  modified writePdb code. Unrelated to Simbody version.
- TestNoseHooverThermostat: fails on 3.8 and 3.9, passes on 3.7.
  Physics tolerance assertion (mean energy at tolerance 0.2). Behavior
  change in the thermostat arrived in 3.8 and is unchanged in 3.9.

## Simbody 3.8 verification (done after 3.9)

Built Simbody-3.8 the same way as 3.9. Result: 34/37 pass. Failures:
TestDuMMForces (new, see below), TestNoseHooverThermostat, TestPdb.

TestDuMMForces fails on 3.8 only, with:

    System::Guts::updDefaultState(): System MultibodySystem topology has
    not been realized since the last topological change -- you must call
    realizeTopology() first.

Interpretation: Simbody 3.8 added stricter state validation and molmodel
calls updDefaultState() at a point 3.7 silently permitted. 3.9 passes
this test again (check relaxed or fixed upstream). So 3.8 is the
strictest release for this codebase; 3.9 dominates it.

## Version comparison table

| Simbody | pass | failures |
|---------|------|----------|
| 3.7 (apt) | 12/37 | 25 segfaults in libSimTKcommon State copy |
| 3.8 (source) | 34/37 | TestDuMMForces (realizeTopology strictness), TestNoseHooverThermostat (tolerance), TestPdb (molmodel's own) |
| 3.9 (source) | 35/37 | TestNoseHooverThermostat (tolerance), TestPdb (molmodel's own) |

Conclusion: pin Simbody 3.9. It has the fewest failures of the three,
and 3.8's extra failure indicates molmodel relies on state handling
that only 3.9 permits without complaint.

## Goal

Replace distro packages (apt) with pinned source builds of Simbody,
OpenMM, and gemmi, so every builder gets identical dependency versions
regardless of OS or distro. Expected side benefit: test segfaults caused
by Ubuntu's Simbody 3.7 may disappear if we pin a newer Simbody.

## Versions to pin

Decide these before starting. Candidates:

- gemmi 0.6.2 — required, current code does not compile against 0.7.x
- Simbody — try the newest release; if tests still segfault, try 3.8,
  then 3.7
- OpenMM — try the newest release; molmodel also builds an OpenMM
  plugin, so the plugin API must still match

Record the final choices in this file, in BUILDING.md's versions table,
and in the pin variables in the build files. All three must match.

## Steps

1. Add a Simbody version check to CMakeLists.txt.

   In `CMakeLists.txt`, after `GET_SIMBODY_VERSION(${Simbody_VERSION})`,
   compare `${Simbody_VERSION}` against the chosen minimum and fail with
   a clear message if it is older. The variable is a plain string like
   "3.7". Use CMake's `if(VERSION_LESS)`.

2. Write a pinned Dockerfile.

   Base image: ubuntu:24.04 (or debian:bookworm-slim for smaller size).
   Install only build tools from apt: build-essential, cmake, git, curl,
   ca-certificates, libblas-dev, liblapack-dev, zlib1g-dev.

   At the top of the file, define ARG variables for the three versions
   and use release tarball URLs, for example:
   - https://github.com/simbody/simbody/archive/refs/tags/Simbody-<V>.tar.gz
   - https://github.com/openmm/openmm/archive/refs/tags/<V>.tar.gz
   - https://github.com/project-gemmi/gemmi/archive/refs/tags/v<V>.tar.gz

   Build order matters (each installs into /usr/local):
   a. gemmi (same cmake flags as today: Release, shared, no python)
   b. Simbody: cmake -DCMAKE_INSTALL_PREFIX=/usr/local
      -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF, then build and install
   c. OpenMM: plain cmake, build, install (long build; can pass
      -DCMAKE_BUILD_TYPE=Release)
   d. molmodel from the copied source, GEMMI_DIR pointing at the built
      gemmi tree, same as the current Dockerfile

   Smoke test: docker run should execute build/tests/TestEthane
   successfully.

3. Verify locally.

   - docker build completes
   - docker run exits 0
   - ctest inside the container: record pass count. Compare against the
     known baseline of 12/37 passing with apt Simbody 3.7. If the count
     improves, note it. If TestSerine/TestRna/TestPdb still fail, check
     the gdb backtrace; if the crash is still inside libSimTKcommon,
     try a different pinned Simbody version.

4. Update scripts/setup.sh (optional second path).

   Keep the apt path for Debian/Ubuntu users who want speed. Add a
   flag (e.g. ./scripts/setup.sh --from-source) that runs the same
   pinned source builds natively instead of apt. Share the version
   variables with the Dockerfile by duplicating them in one place at
   the top of each file (simple) or a sourced versions.sh (cleaner).

5. Update BUILDING.md.

   - Add the pinned Docker instructions as the primary path, apt as the
     fast alternative, with one sentence on the trade-off (apt: fast,
     distro versions; pinned: slower first build, identical versions
     everywhere).
   - Update the versions table with the pinned versions after
     verification.
   - Update the "what a successful build looks like" section with the
     new test pass count if it changed.

6. Optional: GitHub Actions workflow.

   .github/workflows/build.yml: on push and pull_request, run
   docker build and docker run. This catches rot (dead URLs, distro
   changes) automatically. Do this last, after steps 1-5 are stable.

## Rollback

Nothing in the current working setup is deleted by this plan except the
Dockerfile contents, which git history preserves. The apt recipe in
scripts/setup.sh and BUILDING.md stays valid throughout.

## Open questions

- Which Simbody version actually fixes the State-copy segfaults, if
  any? Only step 3 answers this.
- OpenMM version compatibility with the OpenMMPlugin source in this
  repo. ANSWERED 2025-11: OpenMM 8.6.1 works (plugin compiles, 35/37
  tests, same as apt 8.1.2). Pinned in Dockerfile and setup.sh.
