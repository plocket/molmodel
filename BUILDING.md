# Building molmodel

## Debian/Ubuntu

You can build in a Docker container that is using Debian or Ubuntu, or directly
on a computer with the Debian or Ubuntu operating system.

### Option 1: Docker

```bash
docker build -t molmodel .
docker run --rm molmodel          # runs a smoke-test program
docker run -it --rm molmodel bash # shell with molmodel built and installed
```

The image builds gemmi 0.6.2 and Simbody 3.9 from pinned source releases
and takes OpenMM from Ubuntu's repository. See
docs/DECISION-simbody-3.9.md for why Simbody is pinned.

### Option 2: Direct build on Debian/Ubuntu

`scripts/setup.sh` does the same thing as the Dockerfile, natively:
installs apt packages, fetches and builds gemmi 0.6.2 and Simbody 3.9
under `third_party/`, then builds molmodel.

```bash
./scripts/setup.sh
```

By hand, the steps are:

```bash
# 1. System packages
sudo apt install -y build-essential cmake git curl \
    libblas-dev liblapack-dev zlib1g-dev libopenmm-dev

# 2. gemmi 0.6.2, built in place under third_party/
mkdir -p third_party
curl -sL https://github.com/project-gemmi/gemmi/archive/refs/tags/v0.6.2.tar.gz -o /tmp/gemmi.tar.gz
tar -xzf /tmp/gemmi.tar.gz -C third_party/ && rm /tmp/gemmi.tar.gz
cmake -S third_party/gemmi-0.6.2 -B third_party/gemmi-0.6.2 \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DUSE_PYTHON=OFF
cmake --build third_party/gemmi-0.6.2 -j"$(nproc)"
sudo cmake --install third_party/gemmi-0.6.2

# 3. Simbody 3.9 from source. Do not use Ubuntu's libsimbody-dev (3.7);
#    it crashes most of molmodel's test suite.
curl -sL https://github.com/simbody/simbody/archive/refs/tags/Simbody-3.9.tar.gz -o /tmp/simbody.tar.gz
tar -xzf /tmp/simbody.tar.gz -C third_party/ && rm /tmp/simbody.tar.gz
cmake -S third_party/simbody-Simbody-3.9 -B third_party/simbody-Simbody-3.9 \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF
cmake --build third_party/simbody-Simbody-3.9 -j"$(nproc)"
sudo cmake --install third_party/simbody-Simbody-3.9 && sudo ldconfig

# 4. molmodel. GEMMI_DIR defaults to third_party/gemmi-0.6.2 in
#    CMakeLists.txt; Simbody_DIR is passed explicitly so the freshly
#    built 3.9 is used rather than any system copy.
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    -DSimbody_DIR=/usr/local/lib/cmake/simbody
cmake --build build -j"$(nproc)"
sudo cmake --install build && sudo ldconfig   # optional
```

## Other Linux distributions or macOS

The same steps apply, but the packages may have different names. OpenMM
must come from somewhere (package manager or built from source). If you
build from source, note that molmodel uses the CMake variable
`GEMMI_DIR`.

### Finding the package names

Search your package manager's index; the search terms are the library names,
not the tool names:

```bash
dnf search openmm lapack    # Fedora/RHEL
pacman -Ss openmm           # Arch
brew search openmm lapack   # macOS (Homebrew)
```

or look them up on <https://pkgs.org>, which indexes package names across
most RPM- and .deb-based distributions. What you are looking for, in terms
of what each provides:

- a C/C++ compiler and CMake (any recent versions)
- BLAS and LAPACK (Simbody needs them at build time)
- zlib
- OpenMM — needs to include `OpenMM.h` and provide `libOpenMM`

Simbody and gemmi are built from pinned source in every recipe above, so
no packages are needed for them beyond BLAS/LAPACK/zlib.

## Versions this was verified with

- Ubuntu (arm64), GCC 15.2, CMake 4.2
- Simbody 3.9 (source, pinned), OpenMM 8.1.2 (apt), gemmi 0.6.2
  (source, pinned), zlib 1.3.1

Details:

- **gemmi must be 0.6.x.** The source was adapted to gemmi 0.6 (commits
  "Adapt to gemmi 0.6", "Do not call functions from gemmi::impl
  namespace"). Newer gemmi versions do not compile against this code.
- **GEMMI_DIR must point at a built gemmi tree.** molmodel adds
  `${GEMMI_DIR}/include` and `${GEMMI_DIR}/lib` directly, so the tree
  needs both. The default assumes `third_party/gemmi-0.6.2` has been
  built in place (steps above do exactly that).
- **Simbody 3.9 is pinned.** See docs/DECISION-simbody-3.9.md. Ubuntu's
  packaged 3.7 segfaults 25 of 37 tests. CMakeLists.txt refuses to
  configure against Simbody older than 3.8 and warns below 3.9. Watch
  the "Found Simbody version X" line in cmake output: a wrong
  Simbody_DIR falls back silently to a system Simbody.
- **OpenMM is a hard dependency** (`find_package(OpenMM REQUIRED)`),
  even though most of molmodel does not use it. The OpenMM plugin is
  always built. OpenMM is currently not pinned; pinning it is deferred
  (docs/PLAN-pinned-build.md).
- **C++14** is set in CMakeLists.txt (`CMAKE_CXX_STANDARD 14`); any
  newer compiler that still defaults to a compatible standard works.

## What a successful build looks like

`ctest --test-dir build` reports 35 of 37 tests passing. The 2 failures
are known and recorded in docs/DECISION-simbody-3.9.md:

1. `TestPdb` — a round-trip string comparison in molmodel's own
   recently modified writePdb code (tests/TestPdb.cpp:73).
2. `TestNoseHooverThermostat` — a physics tolerance assertion
   (mean energy at tolerance 0.2); a Simbody behavior change since 3.8.

Tests and examples that open a Simbody visualizer window fail on
headless systems; that is expected and not counted above.

## Layout

- `third_party/` — vendored gemmi and Simbody source and build trees
  (downloaded by the script; not committed; see third_party/README.md)
- `build/` — CMake build directory (not committed)
- `scripts/setup.sh` — the one-command local build
- `docs/` — decision and plan records
