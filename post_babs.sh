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
# The update/get/unzip step is wrapped in 'datalad run', which commits
# (saves) the result automatically within the derivatives dataset, with the
# wrapped command recorded in the commit message.
#
# After 'datalad run' moves the derivatives dataset's HEAD forward, the site
# dataset's recorded pointer for it goes stale; this script commits that
# pointer update in the site dataset (two levels up).
#
# Use the 'datalad save -d "$SITE_DIR" ... -- <relpath>' form (verified on
# datalad 1.6.1). A plain path-scoped 'datalad save -m "..." <path>' silently
# no-ops on a pointer-only change (still true on 1.6.1). This form stays
# scoped (won't sweep in unrelated changes) and, unlike the old 'git add', it
# also registers a new subdataset in .gitmodules -- raw 'git add' left
# "gitlink-only" entries that broke 'git submodule status'.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <derivatives_dir>" >&2
  exit 1
fi

DERIVATIVES_DIR="$(realpath "$1")"
SITE_DIR="$(realpath "$DERIVATIVES_DIR/../..")"

[[ -d "$DERIVATIVES_DIR" ]] || { echo "ERROR: derivatives dir not found: $DERIVATIVES_DIR" >&2; exit 1; }
[[ -d "$SITE_DIR/.git"  ]] || { echo "ERROR: expected a site dataset at $SITE_DIR (no .git)" >&2; exit 1; }

command -v babs    >/dev/null 2>&1 || { echo "ERROR: babs not found" >&2; exit 1; }
command -v datalad >/dev/null 2>&1 || { echo "ERROR: datalad not found" >&2; exit 1; }
command -v unzip   >/dev/null 2>&1 || { echo "ERROR: unzip not found" >&2; exit 1; }

SUB_RELPATH="$(realpath --relative-to="$SITE_DIR" "$DERIVATIVES_DIR")"

echo "=== babs merge ==="
babs merge "$DERIVATIVES_DIR"

cd "$DERIVATIVES_DIR"

echo "=== datalad run: update, get, unzip ==="
datalad run -m "Merge and unzip babs results" bash -c '
  set -e
  datalad update --how ff-only --sibling output
  datalad get ./*.zip
  for zip_file in sub-*.zip; do
    [[ -e "$zip_file" ]] || continue
    echo "unzipping $zip_file"
    unzip -n "$zip_file"
  done
'

echo "=== committing site dataset (updating submodule pointer) ==="
# Run this from inside $SITE_DIR. datalad resolves the path argument relative
# to the current working directory, NOT relative to -d. Up to here cwd is
# still $DERIVATIVES_DIR (from the cd above), so a relative "derivatives/..."
# arg resolves to a nonexistent nested path and 'save' silently no-ops
# ("notneeded", exit 0) without registering the subdataset. cd'ing to
# $SITE_DIR first makes $SUB_RELPATH resolve correctly.
cd "$SITE_DIR"
datalad save -d "$SITE_DIR" -m "Update ${SUB_RELPATH} pointer after merge/unzip" -- "$SUB_RELPATH"

echo "Done."
