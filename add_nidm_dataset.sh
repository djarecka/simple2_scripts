#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: ./script.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY_DIR="$SCRIPT_DIR/.."
NIDM_URL_CSV="$SCRIPT_DIR/url-nidm.csv"


command -v datalad >/dev/null 2>&1      || { echo "ERROR: datalad not found" >&2; exit 1; }

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
nidm="derivatives/nidm_n5"
#raw_data="sourcedata/raw"
log_dir="$LOG_ROOT/$site"

# Ensure nidm subdataset
if datalad -C "$nidm" status >/dev/null 2>&1; then
    echo " - nidm subdataset present"
else
    echo " - creating nidm subdataset"
    datalad -C "." create -d . -c text2git "$nidm"
    datalad -C "." save -m "Add derivatives/nidm subdataset"
fi

# Add files from CSV into nidm (paths relative to nidm/)
echo " - addurls into nidm from CSV"
cd "$nidm"
# TODO: change to clone
cp -r "$SCRIPT_DIR" "."
#datalad addurls  --ifexists overwrite "$NIDM_URL_CSV" '{url}' 'code/{path}'
datalad save -m "Add the code directory"

echo "clone sourcedata"
mkdir sourcedata
datalad clone -d "." --reckless ephemeral ../../sourcedata/raw sourcedata/raw
raw_data="sourcedata/raw"
json_map="code/vars_to_nidm_map.json"
output_ttl="nidm.ttl"

datalad run bash code/create_nidm.sh "$raw_data" "$output_ttl"

cd $STUDY_DIR
datalad save -m "Run the pynidm script and creating the nidm files"

echo "✓ Done: $site"

