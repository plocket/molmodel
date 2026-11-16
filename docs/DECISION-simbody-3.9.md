# Decision: pin Simbody 3.9 in the from-source build path

Date: 2025-11
Status: decided. Verified empirically against this codebase on Ubuntu
(arm64), GCC 15.2, CMake 4.2.

## Context

molmodel depends on Simbody, OpenMM, and gemmi 0.6.2. The current
verified setup (see BUILDING.md) installs Simbody and OpenMM from apt,
which pins Simbody to Ubuntu's packaged 3.7. With 3.7, 25 of 37 tests
segfault inside `libSimTKcommon.so.3.7` (a `SimTK::State` copy during
program teardown). The crash is in Simbody, not molmodel, but it makes
the test suite useless as a signal and raises the question of what
"working" means for this project.

The plan in docs/PLAN-pinned-build.md proposed pinning dependency
versions built from source. Before committing to that path, we tested
which Simbody version to pin.

## Options considered

1. Stay on apt Simbody 3.7. No build work, but 12/37 tests pass and the
   suite cannot distinguish real regressions from the known crashes.
2. Pin Simbody 3.8. Fixes all segfaults, but introduces one new
   failure (see below).
3. Pin Simbody 3.9 (latest release). Fixes all segfaults, fewest
   failures of the three versions tested.

## Evidence

| Simbody | pass | failures |
|---------|------|----------|
| 3.7 (apt) | 12/37 | 25 segfaults in libSimTKcommon State copy |
| 3.8 (source) | 34/37 | TestDuMMForces, TestNoseHooverThermostat, TestPdb |
| 3.9 (source) | 35/37 | TestNoseHooverThermostat, TestPdb |

Nature of each failure:

- TestDuMMForces (3.8 only): `updDefaultState(): topology has not been
  realized since the last topological change -- you must call
  realizeTopology() first`. Simbody 3.8 added stricter state validation;
  molmodel's call pattern was borderline-legal on 3.7 and rejected on
  3.8. 3.9 permits it again. This makes 3.8 the strictest release for
  this codebase, not a safe middle ground.
- TestNoseHooverThermostat (3.8 and 3.9): physics tolerance assertion
  (mean energy at tolerance 0.2). The behavior change arrived in 3.8
  and is unchanged in 3.9.
- TestPdb (all versions): round-trip string comparison in
  tests/TestPdb.cpp:73, in molmodel's own recently modified writePdb
  code. Unrelated to Simbody; would need fixing in molmodel regardless
  of the pin.

## Decision

Pin Simbody 3.9 for the from-source build path. Rationale: fewest
failures (35/37), and 3.8's extra failure indicates molmodel relies on
state handling that only 3.9 permits without complaint.

## Consequences

- The pinned Dockerfile (next step in the plan) uses Simbody-3.9.
- The apt path in scripts/setup.sh and BUILDING.md remains as a faster
  alternative, documented with its known 12/37 baseline. Update:
  after the version check was added, the direct-build path was changed
  to build Simbody 3.9 from source (matching the Dockerfile); apt
  Simbody 3.7 would now be rejected at configure time.
- CMakeLists.txt now refuses to configure against Simbody older than
  3.8 (the segfault threshold) and warns between 3.8 and 3.9. A hard
  error below 3.9 was considered but rejected: it would break any
  system still able to build against distro Simbody packages, and the
  recipes in BUILDING.md/scripts no longer produce such a setup.
  Implementation note: the check reads the "Found Simbody version"
  value, so a wrong Simbody_DIR that silently falls back to system
  Simbody now produces a visible warning or error instead of passing
  unnoticed.
- Two tests remain red under the pin. Their status is recorded here so
  future work does not re-litigate them: TestPdb is molmodel's own bug,
  TestNoseHooverThermostat is a Simbody behavior change to investigate
  only if 0.2 tolerance matters for actual use.
- OpenMM stays unpinned for now (apt's 8.1.2 works); pinning it is
  deferred until the Simbody pin is proven in the Dockerfile.
