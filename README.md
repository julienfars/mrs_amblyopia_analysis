# Amblyopia Plasticity Study — MRS Analysis Pipeline

[![Code license: MIT](https://img.shields.io/badge/code%20license-MIT-green.svg)](LICENSE)
[![Python 3.10](https://img.shields.io/badge/python-3.10-blue.svg)](https://www.python.org/)

Preprocessing and quantification pipeline for the magnetic resonance
spectroscopy (MRS) data of the study:

> Fars J. *et al.* **Dichoptic Training Boosts Binocular Vision and Reduces GABA
> in Adult Amblyopia** (in preparation).

It provides:
- A **Bash pipeline** that organises raw MRI/MRS data into a BIDS-like
  structure and runs the FSL-based anatomical preprocessing
- A **Python package (`mrs_pipeline`)** that runs MRS conversion,
  preprocessing, segmentation and quantification, and aggregates the results
- A **Jupyter notebook** that drives the full analysis
- **Voxel-overlap scripts** comparing voxel placement across sessions

For questions, contact Julien Fars — juju.fars@ndcn.ox.ac.uk.
For questions about FSL-MRS itself, see the
[FSL-MRS repository](https://github.com/wtclarke/fsl_mrs).

## Related repositories

This repository is one part of the study's code. The other parts are:

| Repository | Contents |
|---|---|
| [Amblyopia_plasticity_analysis](https://github.com/julienfars/Amblyopia_plasticity_analysis) | Statistical analysis and figures (behaviour, VR training, MRS results) |
| [visual_tests_amblyopia](https://github.com/julienfars/visual_tests_amblyopia) | Psychophysics test battery used to collect the behavioural data |
| [lazy_eye_VR_training](https://github.com/julienfars/lazy_eye_VR_training) | Unity app for the dichoptic VR training (Meta Quest 2) |

The summary tables produced here (GABA+/Glx concentrations, QC metrics, tissue
fractions) are the MRS inputs of `Amblyopia_plasticity_analysis`.

## Scientific background

Amblyopia ("lazy eye") is a visual disorder linked to disrupted binocular
processing, potentially mediated by GABAergic inhibition. This study
investigates whether **dichoptic visual training induces cortical
disinhibition**, measured as changes in **GABA+ and Glx** in:
- Primary visual cortex (V1), main hypothesis
- Sensorimotor cortex (M1), control region

## Data acquisition

### Anatomical MRI (T1)
- MPRAGE, 1 mm isotropic
- Used for registration, voxel placement and tissue segmentation

### MRS
- MEGA-PRESS, TE = 68 ms, TR = 1500 ms
- 160 ON / 160 OFF averages
- Voxels in V1 and M1

## Data availability

**No participant data is included in this repository.**

- **Raw MRS data:** requests for access can be addressed to Dr Betina Ip
  (betina.ip@ndcn.ox.ac.uk), subject to the study's ethics approval and a data
  sharing agreement.
- **Anatomical MRI data** will not be shared, to protect participant
  anonymity.

## Installation

### 1. Clone the repository
```bash
git clone https://github.com/julienfars/mrs_amblyopia_analysis.git
cd mrs_amblyopia_analysis
```

### 2. Install FSL
Install FSL separately, following the
[FSL installation guide](https://fsl.fmrib.ox.ac.uk/fsl/docs/install/).
Version used: **FSL X.X.X** <!-- TODO: confirm -->

### 3. Create the conda environment
```bash
conda env create -f environment.yml
conda activate mrs_pipeline
```
This installs FSL-MRS, spec2nii and the Python dependencies at the versions
used for the study.

### 4. Install the Python package
```bash
pip install -e .
```
Install in **editable mode** (`-e`): the package runs the modified
preprocessing script from this repository's `scripts/` folder.

### 5. Other external tools
- `immv` from [renameutils](https://www.nongnu.org/renameutils/), used by the
  Bash pipeline

Check that the tools are available:
```bash
which fslmaths fsl_anat svs_segment fsl_mrs spec2nii mrs_tools immv
```

## Pipeline

```mermaid
flowchart LR
    Raw["Raw MRI/MRS data\n(Siemens TWIX .dat, T1)"]
    Bash["scripts/run_preprocess.sh\norganise + anatomical preproc"]
    Conv["spec2nii\nconversion"]
    Pre["fsl_mrs_preproc_edit\n(modified, scripts/)"]
    Seg["fsl_anat + svs_segment\ntissue fractions"]
    Fit["fsl_mrs\nquantification"]
    Agg["summary / QC /\ntissue-fraction tables"]

    Raw --> Bash --> Conv --> Pre --> Fit --> Agg
    Bash --> Seg --> Fit
```

### 1. Preprocessing (Bash)

The Bash pipeline:
- Organises raw data into a **BIDS-like structure** with session folders
  (`ses-1`, `ses-2`)
- Renames files using consistent conventions
- Runs FSL-based preprocessing (fieldmaps, anatomical processing)
- Prepares the MRS data for the Python steps

```bash
scripts/run_preprocess.sh /path/to/data
```

### 2. MRS processing (Python)

The `mrs_pipeline` package runs:
- Conversion of the raw data (`spec2nii`)
- Visual QC (`mrs_tools`)
- Preprocessing (modified `fsl_mrs_preproc_edit`, see below)
- Segmentation (`fsl_anat`, `svs_segment`)
- Quantification (`fsl_mrs`)
- Aggregation of the summary, QC and tissue-fraction outputs

```python
from mrs_pipeline import preproc, mrs_analysis_process

data_dir = "/path/to/data"
basis_sets = "/path/to/basis_sets"

preproc(data_dir)
mrs_analysis_process(data_dir, basis_sets)
```

**Basis sets:** we used
[`uzay_svs_mpress_68_with_db`](https://git.fmrib.ox.ac.uk/wclarke/win-mrs-basis-sets/-/tree/master/basis_sets/uzay_svs_mpress/uzay_svs_mpress_68_with_db?ref_type=heads)
from the [WIN MRS basis sets](https://git.fmrib.ox.ac.uk/wclarke/win-mrs-basis-sets).

### Modified FSL-MRS preprocessing script

[`scripts/fsl_mrs_preproc_edit.py`](scripts/fsl_mrs_preproc_edit.py) is a
modified copy of FSL-MRS's `fsl_mrs_preproc_edit`. `preproc()` runs this copy,
not the one installed with FSL-MRS. Compared with the original, it:
- uses configurable ppm ranges for alignment across dynamics
  (`--dynamic_align_ppm`, 1.9–4.2 ppm) and across edit conditions
  (`--edit_align_ppm`, 2.5–3.5 ppm as called by the pipeline)
- disables apodisation during alignment

It needs **fsl_mrs ≤ 2.0.9**, as pinned in `environment.yml`.

### 3. Notebook

[`notebook/fsl_mrs_notebook.ipynb`](notebook/fsl_mrs_notebook.ipynb) walks
through each step, from conversion to the final summary tables. Set `DATA_DIR`
and `BASIS_SETS_DIR` in its configuration cell.

### Extra: voxel overlap

These scripts compare voxel placement across sessions, compute overlap
metrics, and project voxels into MNI space:

```bash
scripts/voxel_overlap.sh --data /path/to/data
scripts/combine_voxels.sh --data /path/to/data
```

## Reproducibility notes

- No paths are hardcoded: set them through script arguments or notebook
  variables.
- Intermediate outputs are written to `derivatives/`.
- Each step can be run on its own.
- The modified preprocessing script writes the exact options it ran with to
  `options.txt` in each output folder.

## Citation

If you use this code, please cite it. The metadata is in
[`CITATION.cff`](CITATION.cff), and GitHub's **"Cite this repository"** button
generates APA/BibTeX from it.

## License

- **Code** in this repository: [MIT](LICENSE)
- **Exception:** [`scripts/fsl_mrs_preproc_edit.py`](scripts/fsl_mrs_preproc_edit.py)
  is a modified version of FSL-MRS code © University of Oxford and is
  distributed under the [FSL-MRS licence](scripts/LICENSE-FSL-MRS)
  (non-commercial use only).
