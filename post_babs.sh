#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: ./post_babs.sh <derivatives_dir>
#
# Post-processing for a single BABS derivatives dataset after job submission
# has completed: merges per-subject result branches, syncs the checked-out
# branch with the output RIA sibling, fetches the result zips, and unzips
# them in place.
#
# Example:
#   ./post_babs.sh /orcd/data/satra/002/datasets/simple2_datalad/study-ABIDE/site-KKI/derivatives/babs-fsl-nidm4.5.0
#
# Note: each result zip's own top-level folder is already named after the
# subject (e.g. sub-0051456/...), so we unzip WITHOUT -d <subject> -- adding
# an extra subject-named destination folder would double-nest the results.
#
# The get/unzip step is wrapped in 'datalad run', which commits (saves) the
# result automatically within the derivatives dataset, with the wrapped
# command recorded in the commit message. The branch sync deliberately sits
# OUTSIDE that run: it is a repo-sync operation, not a data transformation,
# so re-running the recorded command should not re-fetch from a sibling.
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
# git-annex is a hard prerequisite, not just for 'datalad get': these datasets
# set filter.annex.process in their local config, so ANY git checkout or rebase
# shells out to 'git-annex filter-process'. Without it on PATH, git empties or
# deletes tracked files partway through the operation (this is how a rebase
# attempt once left code/participant_job.sh deleted and a stale
# .git/rebase-merge behind). The sync step below can rebase, so check up front.
command -v git-annex >/dev/null 2>&1 || {
  echo "ERROR: git-annex not found on PATH." >&2
  echo "  These datasets set filter.annex.process; git checkout/rebase invokes" >&2
  echo "  'git-annex filter-process' and will damage the working tree without it." >&2
  echo "  Load the git-annex module before running this script." >&2
  exit 1
}

SUB_RELPATH="$(realpath --relative-to="$SITE_DIR" "$DERIVATIVES_DIR")"

cd "$DERIVATIVES_DIR"

echo "=== checking dataset state ==="
# The sync step below may rebase, so refuse to start from a half-finished
# state: a leftover rebase directory or uncommitted changes would either abort
# the rebase or get swept into it.
for stale in .git/rebase-merge .git/rebase-apply; do
  [[ -e "$stale" ]] && {
    echo "ERROR: stale rebase state at $DERIVATIVES_DIR/$stale" >&2
    echo "  Finish it ('git rebase --continue') or discard it ('git rebase --abort')." >&2
    exit 1
  }
done
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "ERROR: uncommitted changes in $DERIVATIVES_DIR -- save or stash first:" >&2
  git status --short >&2
  exit 1
fi
echo "clean, no rebase in progress"

echo "=== babs merge ==="
babs merge "$DERIVATIVES_DIR"

# ---------------------------------------------------------------------------
# Sync the local branch with the output RIA sibling.
#
# 'babs merge' advances the output RIA's branch; the local checkout then has to
# catch up before the zips can be fetched and unzipped. This used to be a bare
# 'datalad update --how ff-only --sibling output' inside the 'datalad run'
# below, which fails outright whenever the two histories have diverged.
#
# Divergence is NORMAL here, not an error. Every job clones the dataset at the
# commit BABS published to the input RIA, runs, and pushes its own result
# branch; 'babs merge' joins those into a new commit on the output RIA branch.
# Meanwhile any local 'datalad save' of code/ -- e.g. raising #SBATCH --time or
# moving off a preemptable partition after jobs were already submitted, which
# is a routine thing to have to do -- commits to the SAME base. Both sides then
# sit one step off a common ancestor, so no fast-forward exists and 'ff-only'
# refuses (correctly). It is a topology problem, NOT a dirty working tree.
#
# So: fast-forward when we can, and replay local commits onto the output
# history when we cannot, restoring the linear history the rest of this script
# assumes. Auto-replay is limited to commits whose net effect is confined to
# code/ -- anything reaching into results means the two histories disagree
# about data, which a rebase would paper over rather than resolve. A timestamped
# backup branch is left behind either way, and a conflicting rebase is aborted
# so HEAD is never left mid-operation. Every case prints what it did and which
# commits were involved; silence here would mean history was rewritten with no
# record of it in the log.
# ---------------------------------------------------------------------------
echo "=== sync with output RIA sibling ==="

BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "ERROR: detached HEAD in $DERIVATIVES_DIR; cannot sync" >&2; exit 1; }
# Key on the branch NAME, not output/HEAD: newer BABS projects publish 'master'
# while older ones use 'main', and output/HEAD is not always set.
OUT_REF="output/$BRANCH"

git fetch --quiet output
git rev-parse --verify --quiet "refs/remotes/$OUT_REF" >/dev/null || {
  echo "ERROR: $OUT_REF does not exist after fetching the output sibling" >&2; exit 1; }

# Oldest-first (apply order) and capped, so a 40-subject octopus merge does not
# bury the one line that matters. The elision is announced, never silent.
# Captured into a variable rather than piped to 'head': under 'set -o pipefail'
# a closing head would SIGPIPE git and kill the script.
show_commits() {   # $1 = label, $2 = rev range
  local n out
  n="$(git rev-list --count "$2")"
  echo "  $1 ($n):"
  out="$(git log --reverse --format='    %h %s' "$2")"
  if (( n > 10 )); then
    printf '%s\n' "$out" | sed -n '1,10p'
    echo "    ... and $((n - 10)) more"
  else
    printf '%s\n' "$out"
  fi
}

read -r AHEAD BEHIND < <(git rev-list --left-right --count "HEAD...$OUT_REF")
echo "local $BRANCH @ $(git rev-parse --short HEAD) -- $AHEAD ahead / $BEHIND behind $OUT_REF"

if (( AHEAD == 0 && BEHIND == 0 )); then
  echo "no sync needed: already identical to $OUT_REF"

elif (( BEHIND == 0 )); then
  echo "no sync needed: $OUT_REF has nothing new"
  show_commits "local-only commits" "$OUT_REF..HEAD"

elif (( AHEAD == 0 )); then
  echo "sync needed: fast-forward"
  show_commits "incoming from $OUT_REF" "HEAD..$OUT_REF"
  datalad update --how ff-only --sibling output
  echo "  -> now at $(git rev-parse --short HEAD)"

else
  echo "WARNING: sync needed but histories have diverged -- no fast-forward exists."
  echo "  Usual cause: code/ was saved after jobs were submitted."
  show_commits "incoming from $OUT_REF" "HEAD..$OUT_REF"
  show_commits "local-only, to be replayed" "$OUT_REF..HEAD"

  # Net effect of the local side since the merge base (three-dot is deliberate:
  # it asks what the LOCAL side changed, not how the two tips differ).
  offending="$(git diff --name-only "$OUT_REF...HEAD" | grep -v '^code/' || true)"
  [[ -z "$offending" ]] || {
    echo "ERROR: local changes reach outside code/:" >&2
    sed 's/^/    /' <<<"$offending" >&2
    echo "  Not replaying automatically -- the histories disagree about data." >&2
    echo "  Resolve by hand, then re-run." >&2
    exit 1
  }

  BACKUP="backup/pre-rebase-$(date +%Y%m%dT%H%M%S)"
  git branch "$BACKUP"
  echo "  backup ref: $BACKUP"
  if ! git rebase "$OUT_REF"; then
    git rebase --abort || true
    echo "ERROR: rebase onto $OUT_REF conflicted and was aborted." >&2
    echo "  HEAD is unchanged; pre-rebase state also kept at $BACKUP." >&2
    exit 1
  fi
  if [[ -z "$(git rev-list "$OUT_REF..HEAD")" ]]; then
    # Rebase drops commits already present upstream; the range is then empty
    # and printing an empty "rewritten" list would read as a failure.
    echo "  -> local commit(s) were already upstream; nothing left to replay"
  else
    echo "  -> replayed onto $OUT_REF; commit(s) rewritten (new hashes):"
    git log --reverse --format='    %h %s' "$OUT_REF..HEAD"
  fi
  echo "  -> pre-rebase state preserved at $BACKUP"
fi

# A completed run leaves the zips tracked but content-dropped (broken symlinks).
# Re-running would then re-fetch every zip from the RIA -- hundreds of MB to tens
# of GB -- only for 'unzip -n' to skip all of it and the drop step below to throw
# it away again. Detect that state and say so rather than doing it silently.
#
# Key on "does this zip's subject dir already exist", NOT on "is the zip content
# present". Newly merged zips are ALSO content-less until 'datalad get' runs, so
# a content-based test would skip extracting new subjects on an incremental run
# (post_babs re-run after a second batch of jobs finishes) -- the common case on
# a site where jobs trickle in. Each zip is named sub-<id>_<...>.zip and extracts
# to sub-<id>/, so the prefix before the first underscore is the expected dir.
SKIP_UNZIP=no
n_zip=0; n_pending=0
for zip_file in sub-*.zip; do
  [[ -L "$zip_file" || -f "$zip_file" ]] || continue   # unmatched glob stays literal
  n_zip=$((n_zip + 1))
  [[ -d "${zip_file%%_*}" ]] || n_pending=$((n_pending + 1))
done
if (( n_zip == 0 )); then
  echo "WARNING: no sub-*.zip tracked -- no completed jobs to extract."
  echo "  Check 'babs status' if you expected results."
  SKIP_UNZIP=yes
elif (( n_pending == 0 )); then
  echo "WARNING: all $n_zip zip(s) are already extracted to sub-*/ dirs."
  echo "  This looks like an already-completed run. Skipping get/unzip: re-fetching"
  echo "  the zips would transfer them only to discard them again. Remove the sub-*/"
  echo "  dirs first if you really mean to redo the extraction."
  SKIP_UNZIP=yes
else
  echo "$n_pending of $n_zip zip(s) not yet extracted"
fi

if [[ "$SKIP_UNZIP" == yes ]]; then
  echo "=== skipping datalad run (nothing to unzip) ==="
else
  echo "=== datalad run: get, unzip ==="
  datalad run -m "Merge and unzip babs results" bash -c '
    set -e
    datalad get ./*.zip
    for zip_file in sub-*.zip; do
      [[ -e "$zip_file" ]] || continue
      echo "unzipping $zip_file"
      unzip -n "$zip_file"
    done
  '
fi

echo "=== dropping now-redundant result zips ==="
# The zip content is now redundant with the unzipped sub-*/ dirs. Drop the
# annexed content to reclaim local disk (the symlinks stay tracked; content
# is still in the 'output' RIA sibling we just got it from, so datalad drop's
# default numcopies check passes). Run from inside $DERIVATIVES_DIR (still cwd
# here). Guard the glob so a re-run with no zips doesn't error under set -e.
if compgen -G "sub-*.zip" >/dev/null; then
  datalad drop sub-*.zip
else
  echo "no zips to drop"
fi

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
