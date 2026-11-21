"""preprocessing.py

Preprocessing utilities for the MRS pipeline.

This module should contain functions that transform raw or semi-processed data
into analysis-ready derivatives. It is designed to be imported from notebooks or
from a small CLI wrapper script.
"""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path
from typing import Iterable, Optional, Sequence
import joblib

from .utils import ensure_dir, iter_subject_session_dirs, require_command, run_command

LOGGER = logging.getLogger(__name__)


# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

def _single_match(directory: str | Path, pattern: str) -> Path:
    """Return exactly one file matching a glob pattern in a directory."""
    directory = Path(directory)
    matches = sorted(directory.glob(pattern))

    if not matches:
        raise FileNotFoundError(f"No file matching {pattern!r} found in {directory}")
    if len(matches) > 1:
        raise RuntimeError(
            f"More than one file matching {pattern!r} found in {directory}: {matches}"
        )
    return matches[0]


def _move_if_exists(src: Path, dst: Path) -> bool:
    """Move a file if it exists; return True when moved."""
    if not src.exists():
        return False
    ensure_dir(dst.parent)
    src.rename(dst)
    return True


def _validate_subject_paths(root: Path, subject: Path, session: Path) -> None:
    if not subject.exists():
        raise FileNotFoundError(f"Missing subject folder: {subject}")
    if not session.exists():
        raise FileNotFoundError(f"Missing session folder: {session}")
    if not root.exists():
        raise FileNotFoundError(f"Missing root folder: {root}")


# -----------------------------------------------------------------------------
# spec2nii conversion
# -----------------------------------------------------------------------------

def process_files_with_spec2nii(
    folder: str | Path,
    exclude: Optional[Iterable[str]] = None,
    include: Optional[Iterable[str]] = None,
    *,
    derivatives_root_name: str = "derivatives",
) -> None:
    """Convert raw MRS .dat files into NIfTI outputs using spec2nii.

    Expected input structure:
        root/sub-01/ses-1/mrs/*.dat
        root/sub-01/ses-2/mrs/*.dat

    Outputs are written to:
        root/derivatives/mrs/sub-01/ses-1/mrs/
        root/derivatives/mrs/sub-01/ses-2/mrs/
    """
    require_command("spec2nii")

    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        mrs_folder = ses_path / "mrs"
        if not mrs_folder.exists():
            LOGGER.info("No mrs folder found: %s", mrs_folder)
            continue

        derivatives_folder = root / derivatives_root_name / "mrs" / subj_path.name / ses_path.name / "mrs"
        ensure_dir(derivatives_folder)

        LOGGER.info("Processing %s", mrs_folder)

        for dat_file in sorted(mrs_folder.glob("*.dat")):
            file_name = dat_file.name
            base = dat_file.stem

            if "mega-press_acq-metab" in file_name:
                run_command([
                    "spec2nii", "twix",
                    "-e", "image",
                    "-f", f"{base}_metab",
                    "-o", str(derivatives_folder),
                    "-j", "-q",
                    str(dat_file),
                ])
                run_command([
                    "spec2nii", "twix",
                    "-e", "phasecor",
                    "-f", f"{base}_phase_correlated",
                    "-o", str(derivatives_folder),
                    "-j", "-q",
                    str(dat_file),
                ])

            elif "mega-press_acq-wref-comb-raw" in file_name:
                run_command([
                    "spec2nii", "twix",
                    "-e", "image",
                    "-f", f"{base}_wref-comb-raw",
                    "-o", str(derivatives_folder),
                    "-j", "-q",
                    str(dat_file),
                ])

            elif "mega-press_acq-wref-quant-raw" in file_name:
                run_command([
                    "spec2nii", "twix",
                    "-e", "image",
                    "-f", f"{base}_wref-quant-raw",
                    "-o", str(derivatives_folder),
                    "-j", "-q",
                    str(dat_file),
                ])
            else:
                LOGGER.debug("Skipping unrecognised .dat file: %s", dat_file)


# -----------------------------------------------------------------------------
# Quick-look visualisation from derivatives
# -----------------------------------------------------------------------------

def glance_from_derivatives(
    folder: str | Path,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
) -> None:
    """Create PNG and text summaries from reconstructed MRS derivative images."""
    require_command("mrs_tools")

    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        derivatives_folder = root / "derivatives" / "mrs" / subj_path.name / ses_path.name / "mrs"
        if not derivatives_folder.exists():
            LOGGER.info("No derivatives folder found: %s", derivatives_folder)
            continue

        for nii_file in sorted(derivatives_folder.glob("*.nii.gz")):
            name = nii_file.name
            png_out = nii_file.with_name(nii_file.name.replace(".nii.gz", ".png"))
            txt_out = nii_file.with_name(nii_file.name.replace(".nii.gz", ".txt"))

            if "metab.nii" in name or "phase_correlated.nii" in name:
                ppm_min, ppm_max = "0", "6.65"
            elif "wref-comb-raw" in name or "wref-quant-raw" in name:
                ppm_min, ppm_max = "2.65", "6.65"
            else:
                continue

            run_command([
                "mrs_tools", "vis", str(nii_file), "--save", str(png_out), "--ppmlim", ppm_min, ppm_max
            ])

            with open(txt_out, "w", encoding="utf-8") as handle:
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
    """Process anatomical files for all selected subjects and sessions."""
    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")

    tasks: list[tuple[Path, Path]] = []

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        derivatives_folder = root / "derivatives" / "mrs" / subj_path.name / ses_path.name / "mrs"
        anat_folder = ses_path / "anat"

        if not derivatives_folder.exists() or not anat_folder.exists():
            continue

        for anat_file in anat_folder.glob("sub-*_acq-MPRAGE_T1w.nii.gz"):
            tasks.append((anat_file, derivatives_folder))

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
    """Run svs_segment for V1 and M1 metabolite maps."""
    require_command("svs_segment")

    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"The folder does not exist: {root}")

    for subj_path, ses_path in iter_subject_session_dirs(root, include=include, exclude=exclude):
        derivatives_folder = root / "derivatives" / "mrs" / subj_path.name / ses_path.name / "mrs"
        if not derivatives_folder.exists():
            LOGGER.info("No derivatives folder found: %s", derivatives_folder)
            continue

        anat_folder = next((p for p in derivatives_folder.iterdir() if p.is_dir() and p.name.endswith(".anat")), None)
        if anat_folder is None:
            LOGGER.warning("No .anat folder found in %s", derivatives_folder)
            continue

        v1_metab_file = derivatives_folder / "MRS_fit_V1_metab.nii.gz"
        m1_metab_file = derivatives_folder / "MRS_fit_M1_metab.nii.gz"

        if v1_metab_file.exists():
            run_command([
                "svs_segment",
                str(v1_metab_file),
                "-a", str(anat_folder),
                "-o", str(derivatives_folder),
                "-f", "MRS_fit_V1",
            ])
            LOGGER.info("Processed SVS segmentation for V1 in %s", derivatives_folder)
        else:
            LOGGER.info("No V1 metab file found in %s", derivatives_folder)

        if m1_metab_file.exists():
            run_command([
                "svs_segment",
                str(m1_metab_file),
                "-a", str(anat_folder),
                "-o", str(derivatives_folder),
                "-f", "MRS_fit_M1",
            ])
            LOGGER.info("Processed SVS segmentation for M1 in %s", derivatives_folder)
        else:
            LOGGER.info("No M1 metab file found in %s", derivatives_folder)


# -----------------------------------------------------------------------------
# Preprocessing of edited/reference data
# -----------------------------------------------------------------------------

def preproc(
    folder: str | Path,
    ref_water: Optional[str] = None,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
) -> None:
    """Run fsl_mrs_preproc_edit on MRS derivatives.

    Parameters
    ----------
    folder:
        Root data directory.
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
        derivatives_folder = root / "derivatives" / "mrs" / subj_path.name / ses_path.name / "mrs"
        if not derivatives_folder.exists():
            LOGGER.info("No derivatives folder found: %s", derivatives_folder)
            continue

        for region in ("V1", "M1"):
            region_folder = derivatives_folder / region
            preproc_folder = region_folder / "MRS_preproc_data"

            # Inputs expected from the previous pipeline stages.
            metab_file = None
            ref_file = None
            quant_file = None
            ecc_file = None

            for file in derivatives_folder.rglob("*.nii.gz"):
                name = file.name
                if region not in name:
                    continue

                if "metab" in name and "phase_correlated" not in name:
                    metab_file = file
                elif "phase_correlated" in name:
                    ecc_file = file
                elif "wref-comb-raw" in name:
                    ref_file = file
                elif "wref-quant-raw" in name:
                    quant_file = file

            if metab_file is None or ref_file is None:
                LOGGER.warning(
                    "Required files for %s not found in %s", region, derivatives_folder
                )
                continue

            ensure_dir(preproc_folder)

            cmd = [
                "fsl_mrs_preproc_edit",
                "--data", str(metab_file),
                "--reference", str(ref_file),
                "--quant", str(quant_file) if quant_file is not None else str(ref_file),
                "--output", str(preproc_folder),
                "--hlsvd",
                "--report",
                "--overwrite",
                "--align_window_dynamic", "16",
                "--align_ppm_edit", "2.5", "3.5",
            ]

            if ecc_file is not None:
                cmd.extend(["--ecc", str(ecc_file)])

            run_command(cmd)
            LOGGER.info("Processed %s files in %s", region, derivatives_folder)


# -----------------------------------------------------------------------------
# Optional small helper for early cleanup
# -----------------------------------------------------------------------------

def move_file_to_other_folder(
    file_path: str | Path,
    other_folder: str | Path,
) -> Path:
    """Move a file into an 'other' folder and return the new path."""
    file_path = Path(file_path)
    other_folder = ensure_dir(other_folder)
    target = other_folder / file_path.name
    file_path.rename(target)
    return target
