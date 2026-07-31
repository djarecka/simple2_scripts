#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: ./post_babs.sh <derivatives_dir>
#
# Post-processing for a single BABS derivatives dataset after job submission
# has completed: merges per-subject result branches, updates the checked-out
# branch from the output RIA sibling, fetches the result zips, and unzips
# them in place.
#
# Example:
#   ./post_babs.sh /orcd/data/satra/002/datasets/simple2_datalad/study-ABIDE/site-KKI/derivatives/babs-fsl-nidm4.5.0
#
# Note: each result zip's own top-level folder is already named after the
# subject (e.g. sub-0051456/...), so we unzip WITHOUT -d <subject> -- adding
# an extra subject-named destination folder would double-nest the results.
#
# Ends with 'datalad save' to commit the unzipped results.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <derivatives_dir>" >&2
  exit 1
fi

DERIVATIVES_DIR="$1"

[[ -d "$DERIVATIVES_DIR" ]] || { echo "ERROR: derivatives dir not found: $DERIVATIVES_DIR" >&2; exit 1; }

command -v babs    >/dev/null 2>&1 || { echo "ERROR: babs not found" >&2; exit 1; }
command -v datalad >/dev/null 2>&1 || { echo "ERROR: datalad not found" >&2; exit 1; }
command -v unzip   >/dev/null 2>&1 || { echo "ERROR: unzip not found" >&2; exit 1; }

echo "=== babs merge ==="
babs merge "$DERIVATIVES_DIR"

cd "$DERIVATIVES_DIR"

echo "=== datalad update from output sibling ==="
datalad update --how ff-only --sibling output

echo "=== datalad get result zips ==="
datalad get ./*.zip

echo "=== unzipping ==="
for zip_file in sub-*.zip; do
  [[ -e "$zip_file" ]] || continue
  echo "unzipping $zip_file"
  unzip -n "$zip_file"
done

echo "=== datalad save ==="
datalad save -m "Merge and unzip babs results"

echo "Done."
