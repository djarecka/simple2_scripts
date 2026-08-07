#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: ./script.sh [--dry-run] <PYNIDM_VERSION> [NIDM_DERIVATIVE_NAME]
#
# --dry-run: generate the NIDM files into a plain, UNTRACKED directory
#   (derivatives/<name>_<version>_test) -- no datalad subdataset, no save.
#   Remove it afterwards with a plain `rm -rf`. Handy for trying an unreleased
#   pynidm (e.g. the linkml branch via the pynidm_dev env, i.e. VERSION=dev).

DRY_RUN=0
POS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) POS+=("$arg") ;;
  esac
done
set -- "${POS[@]}"

PYNIDM_VERSION="$1"
NIDM_DERIVATIVE="${2:-nidm}_$PYNIDM_VERSION"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY_DIR="$SCRIPT_DIR/.."
NIDM_URL_CSV="$SCRIPT_DIR/url-nidm.csv"


# datalad only needed for the real (tracked) run
[[ $DRY_RUN -eq 1 ]] || command -v datalad >/dev/null 2>&1 || { echo "ERROR: datalad not found" >&2; exit 1; }

[[ -d "$STUDY_DIR"    ]] || { echo "ERROR: study dir not found: $STUDY_DIR" >&2; exit 1; }
[[ -f "$NIDM_URL_CSV" ]] || { echo "ERROR: CSV file not found: $NIDM_URL_CSV" >&2; exit 1; }


# Logs outside datasets, under the caller's cwd
ORIG_PWD="$(pwd)"
LOG_ROOT="$ORIG_PWD/logs"
mkdir -p "$LOG_ROOT"

site="$(basename "$STUDY_DIR")"
echo "=== Site: $site"
cd $STUDY_DIR
echo "===Current dir: $(pwd)"
nidm_dir="derivatives/$NIDM_DERIVATIVE"
#raw_data="sourcedata/raw"
log_dir="$LOG_ROOT/$site"

# Dry run: plain untracked dir, run the generator directly (no datalad), done.
if [[ $DRY_RUN -eq 1 ]]; then
    nidm_dir="${nidm_dir}_test"
    echo " - DRY RUN: writing untracked NIDM into $nidm_dir (no datalad create/save)"
    mkdir -p "$nidm_dir"
    ( cd "$nidm_dir" && bash "$SCRIPT_DIR/create_nidm.sh" "$STUDY_DIR/sourcedata/raw" "$STUDY_DIR/$nidm_dir" "$PYNIDM_VERSION" --dry-run )
    echo "✓ DRY RUN done: $nidm_dir (UNTRACKED; remove with: rm -rf '$STUDY_DIR/$nidm_dir')"
    exit 0
fi

# Ensure nidm subdataset
if datalad -C "$nidm_dir" status >/dev/null 2>&1; then
    echo " - nidm subdataset present"
else
    echo " - creating nidm subdataset"
    datalad -C "." create -d . -c text2git "$nidm_dir"
    datalad -C "." save -m "Add derivatives/$NIDM_DERIVATIVE subdataset"
fi

# Add files from CSV into nidm (paths relative to nidm/)
echo " - addurls into nidm from CSV"
cd "$nidm_dir"
datalad clone -d . git@github.com:djarecka/simple2_scripts.git code

echo "clone sourcedata"
mkdir sourcedata
datalad clone -d "." --reckless ephemeral ../../sourcedata/raw sourcedata/raw
raw_data="sourcedata/raw"
json_map="code/vars_to_nidm_map.json"
output_ttl="$STUDY_DIR/$nidm_dir"
echo "output ttl $output_ttl"

datalad run bash code/create_nidm.sh "$raw_data" "$output_ttl" "$PYNIDM_VERSION"

cd $STUDY_DIR
datalad save -m "Run the pynidm script and creating the nidm files, using pynidm verion: $PYNIDM_VERSION"

echo "✓ Done: $site"

