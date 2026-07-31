# code

Scripts for this site dataset.

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
datalad run bash post_babs.sh /orcd/data/satra/002/datasets/simple2_datalad/study-ABIDE/site-KKI/derivatives/babs-fsl-nidm4.5.0
```

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
