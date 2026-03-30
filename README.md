# Amblyopia Plasticity Study — MRS Analysis Pipeline

## Overview

This repository contains the analysis pipeline for magnetic resonance spectroscopy (MRS) data associated with the study:

> *[Paper title — tbc]*

It provides:
- A **Bash-based preprocessing pipeline** to organise and standardise MRI/MRS data
- A **Python package (`mrs_pipeline`)** for MRS preprocessing, analysis, and data aggregation
- A **Jupyter notebook** demonstrating the full analysis workflow

The code is modular and designed for **reproducibility and reuse**.

For questions, contact:  
📧 Juju Fars — juju.fars@ndcn.ox.ac.uk

---

## Installation 

### 1. Clone the repo 
```bash
git clone https://github.com/your-username/your-repo.git
cd your-repo
```

### 2. Create the environment using Conda 
```bash
conda env create -f environment.yml
conda activate mrs_pipeline
```

### 3. Install the Python package 
```bash
pip install -e .
```

### 4. External tools
- FSL --> tested with version > 6.0
- fsl_mrs --> v2.1.19 
- spec2nii --> 0.7.4
- mrs_tools (included within fsl_mrs)
- svs_segment (included within FSL)
- immv (renameutils; often available with FSL environments)

Make sure they are available in your environment:
```bash
which fslmaths
which fsl_mrs
which spec2nii
```

## Scientific Background

Amblyopia (“lazy eye”) is a visual disorder linked to disrupted binocular processing, potentially mediated by GABAergic inhibition.

This study investigates:
- Whether **visual training induces cortical disinhibition**
- Changes in **GABA+/Glx levels** in:
  - Primary visual cortex (V1)
  - Sensorimotor cortex (M1, control)

Data were acquired using **MRS and fMRI**, alongside a dichoptic task.

👉 See the full methods and results in the associated paper: *[link tbc]*

---

## Data Overview

### Anatomical MRI (T1)
- 1 mm isotropic resolution  
- MPRAGE sequence  
- Used for:
  - registration
  - voxel placement
  - tissue segmentation  

### MRS Acquisition
- MEGA-PRESS sequence  
- TE = 68 ms, TR = 1500 ms  
- 160 ON / 160 OFF averages  
- Voxels:
  - V1 (main hypothesis)
  - M1 (control)

---

## Pipeline Overview

---

## 1. Preprocessing (Bash)

The Bash pipeline:
- Organises raw data into a **BIDS-like structure**
- Creates session folders (`ses-1`, `ses-2`)
- Renames files using consistent conventions
- Runs FSL-based preprocessing (e.g., fieldmaps, anatomical processing)
- Prepares MRS data for downstream analysis

### Run preprocessing

```bash
bash scripts/run_preprocess.sh /path/to/data
```

## 2. MRS Processing (Python)

The Python package mrs_pipeline performs:
- Conversion (spec2nii)
- Visual QC (mrs_tools)
- Preprocessing (fsl_mrs_preproc_edit)
- Segmentation (svs_segment)
- Quantification (fsl_mrs)
- Data aggregation (summary/QC/tissue fractions)

### Example usage
```python
from mrs_pipeline import preproc, mrs_analysis_process

data_dir = "/path/to/data"
basis_sets = "/path/to/basis_sets"

preproc(data_dir)
mrs_analysis_process(data_dir, basis_sets)
```
## Notebook Analysis

The notebook (notebooks/fsl_mrs_repo_ready.ipynb) provides:
- A step-by-step walkthrough of the pipeline
- Data exploration and visualisation
- Final aggregation of results

## Extra: Voxel Overlap Analysis

Additional scripts allow:
- Comparison of voxel placement across sessions
- Computation of overlap metrics
- Projection of voxels into MNI space

```bash
scripts/voxel_overlap.sh
scripts/combine_voxels.sh
```
## Dependencies

This project requires:

### Python

See [requirements.txt](requirements.txt)

Ensure these are available in your environment before running the pipeline.

## Reproducibility Notes
Paths are not hardcoded — configure via script arguments or notebook variables
Intermediate outputs are written to derivatives/
The pipeline is modular: each step can be run independently

## Citation

If you use this repository, please cite:
The associated paper: [tbc]
The repository DOI (Zenodo): [tbc]

## License

This project is licensed under:
CC BY-NC-SA 4.0

You are free to:
Share and adapt the material (non-commercially)
As long as attribution is given and derivatives use the same license

See [LICENSE](LICENCE.md)
