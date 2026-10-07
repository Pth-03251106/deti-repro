#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# DETI -- "Polynomial Time Cryptanalytic Extraction of Neural Network Models"
# (CRYPTO 2023) -- reproduction helper.
#
# Why this wrapper exists:
#   1. The code uses absolute imports of the form `from deti.blackbox import ...`,
#      so it has to be run as a package named `deti`. A checkout directory named
#      `deti-main` or `deti-repro` is not a valid Python identifier, so this
#      script symlinks the repo into a temp dir as `deti` and puts that on
#      PYTHONPATH. It works no matter what you named the checkout.
#   2. The code needs Keras 2. The compat/ shim below restores the Keras-2 APIs
#      it uses and is a no-op on TensorFlow <= 2.15.
#   3. cwd is the repo, so `results/` is written into the clone.
#
# Usage:
#   ./run_deti.sh soe          --model models/unitary_784_128_1.h5 --layerID 1 --runID soe
#   ./run_deti.sh lastLayer    --model models/unitary_784_128_1.h5 --layerID 1 --runID lastLayer
#   ./run_deti.sh neuronWiggle --model models/unitary_100_200x3_10.h5 --layerID 1 \
#                              --runID neuronWiggle --tgtNeurons 4 26 30 77 168
#
# Override the interpreter with DETI_PYTHON, e.g.
#   DETI_PYTHON=/opt/anaconda3/envs/deti/bin/python ./run_deti.sh soe ...
# ---------------------------------------------------------------------------
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${DETI_PYTHON:-python3}"

module="${1:?usage: $0 <soe|lastLayer|neuronWiggle> [args...]}"
shift

# Expose the repo under the importable package name `deti`.
PKGROOT="$(mktemp -d)"
trap 'rm -rf "$PKGROOT"' EXIT
ln -s "$REPO" "$PKGROOT/deti"

cd "$REPO"
export PYTHONPATH="$PKGROOT:$REPO/compat${PYTHONPATH:+:$PYTHONPATH}"
export TF_CPP_MIN_LOG_LEVEL=2

exec "$PYTHON" -m "deti.${module}" "$@"
