"""preprocessing.py

Preprocessing utilities for the MRS pipeline.

Inputs are read from the BIDS dataset written by ``mrs_pipeline.raw_to_bids``::

    root/sub-01/ses-1/anat/sub-01_ses-1_acq-MPRAGE_T1w.nii.gz
    root/sub-01/ses-1/mrs/sub-01_ses-1_acq-megapress_voi-V1_svs.nii.gz      metabolites (MEGA-PRESS)
    root/sub-01/ses-1/mrs/sub-01_ses-1_acq-ecc_voi-V1_mrsref.nii.gz         eddy-current reference (phasecor)
    root/sub-01/ses-1/mrs/sub-01_ses-1_acq-comb_voi-V1_mrsref.nii.gz        water reference (coil combination)
    root/sub-01/ses-1/mrs/sub-01_ses-1_acq-quant_voi-V1_mrsref.nii.gz       water reference (quantification)

Outputs are written to ``root/derivatives/mrs/sub-01/ses-1/mrs/``.
"""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path
from typing import Iterable, Optional

from .raw_to_bids import ECC_ACQ, MRS_SCANS, mrs_filename
from .utils import ensure_dir, iter_subject_session_dirs, require_command, run_command

LOGGER = logging.getLogger(__name__)

REGIONS = ("V1", "M1")

# BIDS acquisition labels of the MRS scans used by the pipeline
_ACQ = {protocol: (acq, suffix) for protocol, (acq, suffix, _) in MRS_SCANS.items()}
METAB = _ACQ["mega_press_TR1500"]        # ("megapress", "svs")
REF_COMB = _ACQ["mega_press_wref1"]      # ("comb", "mrsref")
REF_QUANT = _ACQ["mega_press_wref3"]     # ("quant", "mrsref")
ECC = (ECC_ACQ, "mrsref")


# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

def derivatives_dir(root: Path, subject: str, session: str) -> Path:
    """Derivatives folder of one subject/session: root/derivatives/mrs/<sub>/<ses>/mrs."""
    return root / "derivatives" / "mrs" / subject / session / "mrs"


def mrs_file(ses_path: Path, region: str, acq_suffix: tuple[str, str]) -> Path:
    """Path of a converted MRS scan in the BIDS session folder (may not exist)."""
    subject, session = ses_path.parent.name, ses_path.name
    acq, suffix = acq_suffix
    return ses_path / "mrs" / mrs_filename(subject, session, acq, region, suffix)


# -----------------------------------------------------------------------------
# Quick-look visualisation
# -----------------------------------------------------------------------------

def glance_from_derivatives(
    folder: str | Path,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
) -> None:
    """Create PNG and text summaries (mrs_tools vis / info) of the converted MRS data.

    Outputs go to ``derivatives/mrs/<sub>/<ses>/mrs/glance/``.
    """
    require_command("mrs_tools")

    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")

    ppm_ranges = {METAB: ("0", "6.65"), ECC: ("0", "6.65"), REF_COMB: ("2.65", "6.65"), REF_QUANT: ("2.65", "6.65")}

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        out_folder = derivatives_dir(root, subj_path.name, ses_path.name) / "glance"

        for region in REGIONS:
            for acq_suffix, (ppm_min, ppm_max) in ppm_ranges.items():
                nii_file = mrs_file(ses_path, region, acq_suffix)
                if not nii_file.exists():
                    continue

                ensure_dir(out_folder)
                stem = nii_file.name.replace(".nii.gz", "")
                run_command([
                    "mrs_tools", "vis", str(nii_file),
                    "--save", str(out_folder / f"{stem}.png"),
                    "--ppmlim", ppm_min, ppm_max,
                ])

                with open(out_folder / f"{stem}.txt", "w", encoding="utf-8") as handle:
                    subprocess.run(
                        ["mrs_tools", "info", str(nii_file)],
                        stdout=handle,
                        stderr=subprocess.STDOUT,
                        text=True,
                        check=True,
                    )


# -----------------------------------------------------------------------------
# Anatomical processing
# -----------------------------------------------------------------------------

def process_anatomical_file(anat_file: str | Path, derivatives_folder: str | Path) -> Path:
    """Run fsl_anat on a single anatomical image and return the output prefix."""
    require_command("fsl_anat")

    anat_file = Path(anat_file)
    derivatives_folder = ensure_dir(derivatives_folder)

    base_name = anat_file.name.replace(".nii.gz", "").replace(".nii", "")
    output_path = derivatives_folder / f"MRS_{base_name}"

    run_command([
        "fsl_anat",
        "-i", str(anat_file),
        "-o", str(output_path),
    ])

    return output_path


def MRS_anat_process(
    folder: str | Path,
    use_parallel: bool = False,
    n_jobs: int = -1,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
) -> None:
    """Run fsl_anat on the T1w image of every selected subject and session."""
    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")

    tasks: list[tuple[Path, Path]] = []

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        anat_file = ses_path / "anat" / f"{subj_path.name}_{ses_path.name}_acq-MPRAGE_T1w.nii.gz"
        if not anat_file.exists():
            LOGGER.info("No T1w image: %s", anat_file)
            continue
        tasks.append((anat_file, derivatives_dir(root, subj_path.name, ses_path.name)))

    if not tasks:
        LOGGER.info("No anatomical files found.")
        return

    if use_parallel:
        try:
            from joblib import Parallel, delayed
        except ImportError as exc:
            raise ImportError("joblib is required for parallel processing") from exc

        results = Parallel(n_jobs=n_jobs)(
            delayed(process_anatomical_file)(anat_file, derivatives_folder)
            for anat_file, derivatives_folder in tasks
        )
        for result in results:
            LOGGER.info("Processed anatomical file: %s", result)
    else:
        for anat_file, derivatives_folder in tasks:
            result = process_anatomical_file(anat_file, derivatives_folder)
            LOGGER.info("Processed anatomical file: %s", result)


# -----------------------------------------------------------------------------
# SVS segmentation
# -----------------------------------------------------------------------------

def svs_segment_process(
    folder: str | Path,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
) -> None:
    """Run svs_segment for the V1 and M1 voxels (tissue fractions and voxel masks).

    Writes ``MRS_fit_<region>_mask.nii.gz`` and ``MRS_fit_<region>_segmentation.json``
    to the derivatives folder.
    """
    require_command("svs_segment")

    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        derivatives_folder = derivatives_dir(root, subj_path.name, ses_path.name)
        if not derivatives_folder.exists():
            LOGGER.info("No derivatives folder found: %s", derivatives_folder)
            continue

        anat_folder = next((p for p in derivatives_folder.iterdir() if p.is_dir() and p.name.endswith(".anat")), None)
        if anat_folder is None:
            LOGGER.warning("No .anat folder found in %s", derivatives_folder)
            continue

        for region in REGIONS:
            metab_file = mrs_file(ses_path, region, METAB)
            if not metab_file.exists():
                LOGGER.info("No %s metabolite file: %s", region, metab_file)
                continue

            run_command([
                "svs_segment",
                str(metab_file),
                "-a", str(anat_folder),
                "-o", str(derivatives_folder),
                "-f", f"MRS_fit_{region}",
            ])
            LOGGER.info("Processed SVS segmentation for %s in %s", region, derivatives_folder)


# -----------------------------------------------------------------------------
# Preprocessing of edited/reference data
# -----------------------------------------------------------------------------

def preproc(
    folder: str | Path,
    ref_water: Optional[str] = None,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
) -> None:
    """Run fsl_mrs_preproc_edit on the converted MRS data of each voxel.

    Outputs go to ``derivatives/mrs/<sub>/<ses>/mrs/<region>/MRS_preproc_data/``.

    Parameters
    ----------
    folder:
        Root data directory (the BIDS dataset).
    ref_water:
        Reserved for future use. Kept for compatibility with the notebook API.
    include, exclude:
        Subject filters.
    """
    require_command("fsl_mrs_preproc_edit")

    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        derivatives_folder = derivatives_dir(root, subj_path.name, ses_path.name)

        for region in REGIONS:
            metab_file = mrs_file(ses_path, region, METAB)
            ref_file = mrs_file(ses_path, region, REF_COMB)
            quant_file = mrs_file(ses_path, region, REF_QUANT)
            ecc_file = mrs_file(ses_path, region, ECC)

            if not metab_file.exists() or not ref_file.exists():
                LOGGER.warning("Required files for %s not found in %s", region, ses_path / "mrs")
                continue

            preproc_folder = ensure_dir(derivatives_folder / region / "MRS_preproc_data")

            cmd = [
                "fsl_mrs_preproc_edit",
                "--data", str(metab_file),
                "--reference", str(ref_file),
                "--quant", str(quant_file) if quant_file.exists() else str(ref_file),
                "--output", str(preproc_folder),
                "--hlsvd",
                "--report",
                "--overwrite",
                "--align_window_dynamic", "16",
                "--align_ppm_edit", "2.5", "3.5",
            ]

            if ecc_file.exists():
                cmd.extend(["--ecc", str(ecc_file)])

            run_command(cmd)
            LOGGER.info("Processed %s files in %s", region, derivatives_folder)
