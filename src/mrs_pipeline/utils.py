"""
Utility helpers for the MRS pipeline.

This module should contain small, reusable functions that do not depend on the
specific analysis steps. Keep it lightweight and importable from the rest of
the package.
"""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path
from shutil import which
from typing import Iterable, Iterator, Optional, Sequence, Tuple

LOGGER = logging.getLogger(__name__)


def configure_logging(level: int = logging.INFO) -> None:
    """
    Configure a simple logging format for scripts and notebooks.

    Parameters
    ----------
    level:
        Logging level, e.g. logging.INFO or logging.DEBUG.
    """
    logging.basicConfig(level=level, format="[%(levelname)s] %(message)s")


def require_command(command: str) -> None:
    """
    Raise a clear error if an external command is not available.

    Parameters
    ----------
    command:
        Name of the executable to check.

    Raises
    ------
    FileNotFoundError
        If the command cannot be found on PATH.
    """
    if which(command) is None:
        raise FileNotFoundError(
            f"Required command not found: {command}. "
            "Make sure the correct software environment is loaded."
        )


def run_command(
    cmd: Sequence[str],
    *,
    check: bool = True,
    capture_output: bool = False,
    text: bool = True,
) -> subprocess.CompletedProcess:
    """
    Run an external command with consistent error handling.

    Parameters
    ----------
    cmd:
        Command and arguments, for example ["fslmaths", "a.nii.gz", "-bin", "b.nii.gz"].
    check:
        If True, raise CalledProcessError when the command fails.
    capture_output:
        If True, capture stdout and stderr.
    text:
        If True, decode stdout/stderr as text.

    Returns
    -------
    subprocess.CompletedProcess
    """
    LOGGER.debug("Running command: %s", " ".join(map(str, cmd)))
    return subprocess.run(
        list(cmd),
        check=check,
        capture_output=capture_output,
        text=text,
    )


def ensure_dir(path: str | Path) -> Path:
    """
    Create a directory if it does not already exist.

    Parameters
    ----------
    path:
        Directory path to create.

    Returns
    -------
    Path
        The created directory as a Path object.
    """
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p


def subject_is_selected(
    subject: str,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
) -> bool:
    """
    Decide whether a subject should be processed.

    Parameters
    ----------
    subject:
        Subject folder name, e.g. "sub-01".
    include:
        Optional collection of subject names (e.g. "sub-01"). If provided,
        only these subjects are kept.
    exclude:
        Optional collection of subject names to skip. Ignored if include is set.

    Names must match exactly, so "sub-1" does not select "sub-10".

    Returns
    -------
    bool
    """
    include_set = set(include or [])
    exclude_set = set(exclude or [])

    if include_set:
        return subject in include_set

    return subject not in exclude_set


def iter_subject_session_dirs(
    folder: str | Path,
    include: Optional[Iterable[str]] = None,
    exclude: Optional[Iterable[str]] = None,
) -> Iterator[Tuple[Path, Path]]:
    """
    Yield (subject_dir, session_dir) pairs from a BIDS-like directory tree.

    Expected structure:
        root/
          sub-01/
            ses-1/
            ses-2/
          sub-02/
            ses-1/
            ses-2/

    Parameters
    ----------
    folder:
        Root data directory.
    include:
        Optional subject filters.
    exclude:
        Optional subject filters.

    Yields
    ------
    tuple[Path, Path]
        (subject_dir, session_dir)
    """
    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"Folder does not exist: {root}")

    subject_dirs = sorted(
        p for p in root.iterdir()
        if p.is_dir() and p.name.startswith("sub-")
    )

    for subj_path in subject_dirs:
        if not subject_is_selected(subj_path.name, include=include, exclude=exclude):
            continue

        session_dirs = sorted(
            p for p in subj_path.iterdir()
            if p.is_dir() and p.name.startswith("ses-")
        )

        for ses_path in session_dirs:
            yield subj_path, ses_path