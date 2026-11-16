Vendored third-party dependencies, downloaded and built in place by
scripts/setup.sh (or inside the Docker image):

- gemmi-0.6.2/   required, exact version; newer gemmi does not compile
                 against this code
- simbody-Simbody-3.9/   pinned per docs/DECISION-simbody-3.9.md

Nothing in this directory is committed except this README.
