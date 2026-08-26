#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: ./script.sh [--dry-run] <raw_data> <output_ttl> <PYNIDM_VERSION>
#
# --dry-run: do not touch datalad at all -- fetch the CSV map file(s) with curl
#   instead of `datalad addurls`, require the conda env to already exist (no
#   create/install), and skip every `datalad save`. Meant to be driven by
#   add_nidm_dataset.sh --dry-run.

DRY_RUN=0
POS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) POS+=("$arg") ;;
  esac
done
set -- "${POS[@]}"

raw_data="$1"
output_ttl="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Normally exported by add_nidm_dataset.sh (which resolves it per study).
# The fallback covers running this script directly from <study>/<site>/code.
if [[ -z "${NIDM_URL_CSV:-}" ]]; then
  STUDY_NAME="$(basename "$(cd "$SCRIPT_DIR/../.." && pwd)")"
  NIDM_URL_CSV="$SCRIPT_DIR/urls/$STUDY_NAME/url-nidm.csv"
fi
[[ -f "$NIDM_URL_CSV" ]] || { echo "ERROR: NIDM map CSV not found: $NIDM_URL_CSV" >&2; exit 1; }
echo " - using NIDM map CSV: $NIDM_URL_CSV"

# using specific version of pynidm
PYNIDM_VERSION="$3"
#PYNIDM_VERSION="dev"
ENV_NAME="pynidm_${PYNIDM_VERSION}"
# TODO: perhaps i can add  datalad to the environment to not have to activate inside the loop
# Check if env exists
if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  echo "Conda env '$ENV_NAME' already exists"
  source "$(conda info --base)/etc/profile.d/conda.sh"
else
  echo "Creating conda env '$ENV_NAME'"
  conda create -y -n "$ENV_NAME" python=3.11
  source "$(conda info --base)/etc/profile.d/conda.sh"
  conda activate "$ENV_NAME"
  conda install -c conda-forge -y git-annex
  pip install "pynidm==${PYNIDM_VERSION}"
  conda deactivate
fi


#command -v bidsmri2nidm >/dev/null 2>&1 || { echo "ERROR: bidsmri2nidm not found" >&2; exit 1; }


# Add files from CSV into nidm (paths relative to nidm/)
#echo " - addurls into nidm from CSV"
if [[ $DRY_RUN -eq 1 ]]; then
  command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found (needed for --dry-run)" >&2; exit 1; }
  echo " - DRY RUN: fetching map file(s) from CSV via curl (no datalad addurls/save)"
  # CSV columns: url,path  (path is relative to the current dir). Skip the header;
  # the `|| [[ -n "$url" ]]` keeps the last row when the file has no trailing newline.
  tail -n +2 "$NIDM_URL_CSV" | while IFS=, read -r url path || [[ -n "$url" ]]; do
    [[ -z "$url" ]] && continue
    path="${path%$'\r'}"
    mkdir -p "$(dirname "$path")"
    echo "   $url -> $path"
    curl -fsSL "$url" -o "$path"
  done
else
  datalad addurls  --ifexists overwrite "$NIDM_URL_CSV" '{url}' '{path}'
  datalad save -m "Add files via addurls from NIDM_URL_CSV"
fi

conda activate "$ENV_NAME"
echo "Environment '$ENV_NAME' with pynidm==${PYNIDM_VERSION} activated"

# Logs outside datasets
#mkdir -p "$log_dir"

# Run bidsmri2nidm
#raw_data
#json_map="code/vars_to_nidm_map.json"
#output_ttl="nidm.ttl"


echo " - running bidsmri2nidm"
[[ -d "$raw_data" ]] || echo "   WARNING: raw_data directory not found: $raw_data" >&2

bidsmri2nidm \
  -json_map  "vars_to_nidm_map.json" \
  -d "$raw_data" \
  --per_subject \
  -o "$output_ttl" \
  -no_concepts

# TODO: adding a flag
# renaming 
#for f in sub-*_nidm.ttl; do
#    sub="${f%_nidm.ttl}"
#    mkdir -p "$sub"
#    mv "$f" "$sub/nidm.ttl"
#done

#todo add logdir
echo "Environment '$ENV_NAME' deactivated"
conda deactivate
