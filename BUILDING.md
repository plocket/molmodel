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

### Option 2: Direct build on Debian/Ubuntu

Install apt packages, fetch and build gemmi, and build molmodel:

```bash
./scripts/setup.sh
```

Or by hand:

```bash
# 1. System packages
sudo apt install -y build-essential cmake git curl \
    libblas-dev liblapack-dev zlib1g-dev \
    libsimbody-dev libopenmm-dev

# 2. gemmi 0.6.2, built in place under third_party/
mkdir -p third_party
curl -sL https://github.com/project-gemmi/gemmi/archive/refs/tags/v0.6.2.tar.gz -o /tmp/gemmi.tar.gz
tar -xzf /tmp/gemmi.tar.gz -C third_party/ && rm /tmp/gemmi.tar.gz
cmake -S third_party/gemmi-0.6.2 -B third_party/gemmi-0.6.2 \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DUSE_PYTHON=OFF
cmake --build third_party/gemmi-0.6.2 -j"$(nproc)"
sudo cmake --install third_party/gemmi-0.6.2 && sudo ldconfig

# 3. molmodel. No GEMMI_DIR needed; CMakeLists.txt defaults to
#    third_party/gemmi-0.6.2.
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
sudo cmake --install build && sudo ldconfig   # optional
```

## Other Linux distributions or macOS

The same steps apply, but the packages may have different names. Simbody and
OpenMM must come from somewhere (package manager or built from source). If you
build from source, note that molmodel uses the CMake variable `GEMMI_DIR`.

### Finding the package names

Search your package manager's index using the library names, not the tool names:

```bash
dnf search simbody openmm lapack   # Fedora/RHEL
pacman -Ss simbody openmm          # Arch
brew search simbody openmm         # macOS (Homebrew)
```

or look them up on <https://pkgs.org>, which indexes package names across
most RPM- and .deb-based distributions. What you are looking for, in terms
of what each provides:

- a C/C++ compiler and CMake (any recent versions)
- BLAS and LAPACK (Simbody needs them at build time)
- zlib
- Simbody — needs to include `Simbody.h` and ship a `SimbodyConfig.cmake`
  (usually in a `-dev`/`-devel` package, like `simbody-dev`)
- OpenMM — needs to include `OpenMM.h` and provide `libOpenMM`

If a distro has no Simbody or OpenMM package (which is fairly common), build
those from source with CMake the same way the commands above build gemmi; the
previous Dockerfile did this and can serve as a reference. Anything that
installs a `SimbodyConfig.cmake` will be found automatically by molmodel's
`find_package(Simbody)`.

## Versions this was verified with

- Ubuntu (arm64), GCC 15.2, CMake 4.2
- Simbody 3.7 (apt), OpenMM 8.1.2 (apt), gemmi 0.6.2 (source), zlib 1.3.1

Details:

- **gemmi must be 0.6.x.** The source was adapted to gemmi 0.6 (commits
  "Adapt to gemmi 0.6", "Do not call functions from gemmi::impl
  namespace"). Newer gemmi versions do not compile against this code.
- **GEMMI_DIR must point at a built gemmi tree.** molmodel adds
  `${GEMMI_DIR}/include` and `${GEMMI_DIR}/lib` directly, so the tree
  needs both. The default assumes `third_party/gemmi-0.6.2` has been
  built in place (steps above do exactly that).
- **OpenMM is a hard dependency** (`find_package(OpenMM REQUIRED)`),
  even though most of molmodel does not use it. The OpenMM plugin is
  always built.
- **Simbody 3.7 works** because it keeps multithreading off. Commit
  messages in this repo claim it requires 3.8+, but FindSimbody.cmake
  doesn't check for the version.
- **C++14** is set in CMakeLists.txt (`CMAKE_CXX_STANDARD 14`); any
  newer compiler that still defaults to a compatible standard works.

## Test

`ctest --test-dir build` should report roughly 12 of 37 tests passing.
The rest fail for two known reasons, neither caused by the build recipe:

1. Tests and examples that open a Simbody visualizer window fail on
   headless systems.
2. A number of tests segfault inside Simbody 3.7 itself (a `SimTK::State`
   copy in `libSimTKcommon.so.3.7`), e.g. `TestSerine`, `TestRna`,
   `TestPdb` (assertion failure). These are properties of the
   dependencies, not of this build recipe.

Programs that avoid visualizer output and the affected Simbody paths run
correctly.

## Layout

- `third_party/gemmi-0.6.2/` — vendored gemmi source and build tree
  (downloaded by the script; not committed)
- `build/` — CMake build directory (not committed)
- `scripts/setup.sh` — the one-command local build
