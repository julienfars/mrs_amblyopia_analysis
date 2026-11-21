# Legacy data organisation scripts

These Bash scripts organised the raw scanner export into the folder structure
used to produce the **published results**. They are kept unchanged for
provenance and are no longer part of the pipeline.

They are superseded by `mrs_pipeline.raw_to_bids` (see the main README), which:
- copies the raw data instead of moving it, and writes nothing without `--apply`
- keeps the intensity-normalised (NORM) T1w series when the scanner exports two copies
- converts a repeated MRS scan from its last acquisition and reports the repeat
- anonymises the NIfTI-MRS headers
- writes BIDS 1.10 names and sidecars, plus a conversion log

Note: these scripts label the T1w/T2w files `acq-MP2RAGE`, although the T1w
sequence was MPRAGE. The new conversion uses `acq-MPRAGE` (T1w) and
`acq-TSE` (T2w).

Usage, as originally run:

```bash
scripts/legacy/run_preprocess.sh /path/to/data [--include sub-01 ...] [--exclude sub-09 ...]
```
