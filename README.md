# code

Scripts for this site dataset.

## Setup — required before running any of these scripts

**1. Use an environment that has `git-annex`.** These datasets set
`filter.annex.process`, so *any* `git checkout` or `git rebase` shells out to
`git-annex filter-process`. Without it on `PATH`, git empties or deletes tracked
files partway through the operation. On the MIT cluster:

```
source /home/software/anaconda3/2023.07/etc/profile.d/conda.sh
conda activate babs_dev
command -v git-annex     # must print a path
```

`post_babs.sh` checks for it and refuses to start without it. Note that
`conda activate` *replaces* rather than stacks, so activating another env later
can silently remove it again.

**2. If you are not the owner of these datasets, add `safe.directory` entries.**
Git refuses to operate on a repository owned by another user
("`fatal: detected dubious ownership in repository at ...`"). You need one
exception per repository that someone *else* owns — which repositories those are
depends on the split, so check first:

```
SITE=/orcd/data/satra/002/datasets/simple2_datalad/study-ABIDE/site-Caltech
DERIV=$SITE/derivatives/<name>
stat -c '%U  %n' "$SITE/.git" "$SITE/code" "$DERIV/.git" \
                 "$DERIV/.babs/input_ria" "$DERIV/.babs/output_ria"
```

Then add an entry for each one not owned by you:

```
git config --global --add safe.directory <path>
```

In the usual arrangement — the site dataset and `code` belong to whoever set the
study up, and you created the derivatives dataset yourself with `babs init` — only
the site dataset and `code` need entries; the derivatives dataset and its RIA
stores are already yours. If you are instead re-processing *someone else's*
derivatives dataset, the `.babs/input_ria` and `.babs/output_ria` entries matter
too, and they are easy to miss: the site and `code` alone let the script start,
then the merge/sync steps fail later.

This is deliberately *not* done by the scripts themselves. `safe.directory`
exists to stop a repository owned by someone else from running code at you
through its own config and hooks; a script that adds the exception silently, for
a path it was merely pointed at, removes that protection without the person
running it ever seeing the decision. Adding the entries is a one-time, per-user
setup step and should stay a conscious one.

## post_babs.sh

Post-processing for a single BABS derivatives dataset after job submission
has completed: merges per-subject result branches, updates from the output
RIA sibling, fetches the result zips, and unzips them in place. Also updates
the site dataset's submodule pointer for the derivatives dataset afterward.

Usage:
```
./post_babs.sh <derivatives_dir>
```

Example (requires babs):
```
./post_babs.sh /orcd/data/satra/002/datasets/simple2_datalad/study-ABIDE/site-KKI/derivatives/babs-fsl-nidm4.5.0
```

(No outer `datalad run` wrapper needed — `post_babs.sh` already commits at the
correct dataset levels internally, unlike `add_nidm_dataset.sh` below.)

## add_nidm_dataset.sh

Creates a `derivatives/<NIDM_DERIVATIVE>` subdataset for this site (if it
doesn't already exist), clones `code` and `sourcedata/raw` (reckless
ephemeral) into it, and runs `create_nidm.sh` via `datalad run` to generate
the NIDM output for the site's raw data with the given pynidm version.
`NIDM_DERIVATIVE` is `<name>_<PYNIDM_VERSION>`, where `<name>` defaults to
`nidm` if not given.

Usage:
```
./add_nidm_dataset.sh <PYNIDM_VERSION> [name]
```

Example (requires babs):
```
datalad run bash add_nidm_dataset.sh 4.5.0
# creates derivatives/nidm_4.5.0

datalad run bash add_nidm_dataset.sh 4.5.0 mynidm
# creates derivatives/mynidm_4.5.0
```
