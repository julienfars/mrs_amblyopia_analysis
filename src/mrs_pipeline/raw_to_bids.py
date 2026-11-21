"""raw_to_bids.py

Convert the raw scanner export of the amblyopia study into a BIDS dataset for
the MRS pipeline (anatomy + MRS only).

Adapted from ``steps/raw_to_bids.py`` of the pRF_amblyopia repository, which
also converts the fMRI, field-map and eye-tracking data. It replaces the Bash
scripts in ``scripts/legacy/``.

Raw layout expected (one folder per participant; session folders optional)::

    <raw>/sub-10/[sub-10-ses-1-pretraining/]F3T_2022_021_019/   NIfTI + JSON (dcm2niix)
    <raw>/sub-10/[sub-10-ses-1-pretraining/]2022_021_019/       MRS raw data (Siemens twix .dat), voxel screenshots

Sessions are the scan IDs in increasing order (019 -> ses-1, 023 -> ses-2). If
the folders also carry a session label (ses-1 / pretraining, ses-2 /
posttraining) it is checked against that order.

What the conversion does:
  * Files are COPIED; the raw export stays untouched. .nii files are gzipped.
  * T1w / T2w are found from their JSON sidecars (protocol name). Of the two
    copies the scanner exports, the intensity-normalised series (ImageType
    NORM) is kept; the other goes to sourcedata/. fMRI, field maps and
    eye-tracking data are left out (see the pRF_amblyopia repository).
  * Each MRS twix file is converted to NIfTI-MRS with spec2nii (anonymised)
    and named ``sub-XX_ses-Y_acq-<label>_voi-<V1|M1>_<svs|mrsref>.nii.gz``
    with a BIDS sidecar (see MRS_SCANS). The phase-correction scans of the
    MEGA-PRESS acquisition are extracted as ``acq-ecc`` (eddy-current
    reference used by fsl_mrs_preproc_edit). A scan acquired more than once:
    the last one (highest MID) is converted and the repeat is reported.
  * The twix files and voxel screenshots are kept unchanged in sourcedata/.
  * dataset_description.json is written, and a conversion log (source ->
    target) goes to sourcedata/<sub>/conversion_log.tsv.

Dry run by default (prints the plan). Use --apply to write.

Usage (command installed with ``pip install -e .``)::

    mrs-raw-to-bids /path/to/raw --bids-dir /path/to/bids
    mrs-raw-to-bids /path/to/raw --bids-dir /path/to/bids --include sub-10 --apply
    mrs-raw-to-bids /path/to/raw/sub-10 --bids-dir /path/to/bids --apply
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Optional

from .utils import subject_is_selected

# --------------------------------------------------------------------------- study-specific rules
PROJECT_ID = r"\d{4}_021"          # scan-ID prefix of this study (2022_021_NNN)
T1_ACQ = "MPRAGE"                  # protocol t1_mpr_ax_1mm_iso: MPRAGE
T2_ACQ = "TSE"                     # protocol t2_tse_tra: turbo spin echo

# MRS (MEGA-PRESS sequence uzay_svs_mpress, one set per voxel V1 / M1):
# twix protocol name without the voxel -> (acq label, BIDS suffix, sidecar fields specific to the scan)
MRS_SCANS = {
    "mega_press_TR1500": ("megapress", "svs", dict(        # metabolites: 160 averages x edit ON/OFF, TR 1.5 s
        WaterSuppression=True, WaterSuppressionTechnique="VAPOR", EditTarget="GABA",
        EditPulse={"ON": {"FrequencyOffset": 1.9}, "OFF": {"FrequencyOffset": 7.5}})),
    "mega_press_wref1": ("comb", "mrsref", dict(WaterSuppression=False)),    # water reference, OVS on (coil combination)
    "mega_press_wref3": ("quant", "mrsref", dict(WaterSuppression=False)),   # water reference, OVS off (quantification)
    "mega_press_lw": ("lw", "mrsref", dict(WaterSuppression=False)),         # linewidth (shim) check, 1 average
    "mega_press_fa_Cal": ("facal", "mrsref", dict(WaterSuppression=False)),  # flip-angle calibration
}
# Phase-correction scans stored in the MEGA-PRESS twix file (spec2nii twix -e phasecor),
# used as the eddy-current reference (--ecc) during preprocessing.
ECC_ACQ = "ecc"
MRS_VOI = {"V1": "primary visual cortex (calcarine sulcus)", "M1": "primary motor cortex (hand knob)"}
MRS_COMMON = dict(PulseSequenceType="MEGA-PRESS", BodyPart="BRAIN")
MRS_PRIVATE_KEYS = ["PatientWeight", "PatientSex", "PatientAge", "PatientName", "PatientID", "PatientDoB"]


def bids_name(sub: str, ses: str, *parts: str) -> str:
    return "_".join([sub, ses, *parts])


def mrs_filename(sub: str, ses: str, acq: str, voi: str, suffix: str) -> str:
    """BIDS file name of a converted MRS scan, e.g. sub-10_ses-1_acq-megapress_voi-V1_svs.nii.gz."""
    return f"{bids_name(sub, ses, f'acq-{acq}', f'voi-{voi}', suffix)}.nii.gz"


# --------------------------------------------------------------------------- plan data structures
@dataclass
class Action:
    src: Path
    dst: Path
    kind: str = "copy"                 # copy | json | spec2nii
    content: Optional[dict] = None
    note: str = ""


@dataclass
class Plan:
    actions: list = field(default_factory=list)
    warnings: list = field(default_factory=list)

    def add(self, src, dst, note="", kind="copy", content=None):
        self.actions.append(Action(Path(src), Path(dst), kind, content, note))

    def warn(self, msg):
        self.warnings.append(msg)


# --------------------------------------------------------------------------- discovery
def read_json(p: Path) -> dict:
    with open(p) as f:
        return json.load(f)


def session_folders(sub_dir: Path) -> dict:
    """{scan_id: {'f3t': Path, 'mrs': Path, 'label': 'ses-1'|None}} for one participant."""
    found = {}
    for p in sorted(sub_dir.rglob("*")):
        if not p.is_dir() or len(p.relative_to(sub_dir).parts) > 2:
            continue
        m = re.fullmatch(rf"(F3T_)?({PROJECT_ID})_(\d+)", p.name)
        if not m:
            continue
        sid = int(m.group(3))
        entry = found.setdefault(sid, {"f3t": None, "mrs": None, "label": None})
        entry["f3t" if m.group(1) else "mrs"] = p
        parent = p.parent.name.lower()
        lab = re.search(r"ses-(\d+)", parent)
        if lab:
            entry["label"] = f"ses-{lab.group(1)}"
        elif "posttraining" in parent:
            entry["label"] = "ses-2"
        elif "pretraining" in parent:
            entry["label"] = "ses-1"
    return found


def assign_sessions(found: dict, plan: Plan, sub: str) -> dict:
    """Scan IDs in increasing order -> ses-1, ses-2, ...; cross-checked with any label in the folder names."""
    out = {}
    for i, sid in enumerate(sorted(found), start=1):
        ses = f"ses-{i}"
        lab = found[sid]["label"]
        if lab and lab != ses:
            plan.warn(f"{sub}: scan {sid} is {ses} by order but its folder says {lab}; using the folder label")
            ses = lab
        out[ses] = found[sid]
    return out


def series(f3t: Path) -> list:
    """All dcm2niix series of a session folder: list of dicts with json, nii and metadata."""
    out = []
    for js in sorted(f3t.glob("*.json")):
        nii = next((js.with_suffix(ext) for ext in (".nii", ".nii.gz") if js.with_suffix(ext).exists()), None)
        if nii is None:
            continue
        meta = read_json(js)
        out.append(dict(json=js, nii=nii, meta=meta,
                        protocol=meta.get("ProtocolName") or meta.get("SeriesDescription", ""),
                        series=int(meta.get("SeriesNumber", 0)),
                        norm="NORM" in meta.get("ImageType", [])))
    return out


# --------------------------------------------------------------------------- planning
def plan_anat(sub: str, ses: str, sers: list, bids_ses: Path, src_ses: Path, plan: Plan) -> None:
    """T1w / T2w: keep the scanner-normalised (NORM) series; the other copies go to sourcedata.
    Other series (fMRI, field maps, localisers) are not part of this dataset and are left out: they are converted
    by the pRF_amblyopia repository."""
    for pattern, suffix in ((r"t1_mpr", f"acq-{T1_ACQ}_T1w"), (r"t2_tse", f"acq-{T2_ACQ}_T2w")):
        items = [s for s in sers if re.search(pattern, s["protocol"], re.I)]
        if not items:
            plan.warn(f"{sub} {ses}: no {suffix} series")
            continue
        chosen = max(items, key=lambda s: (s["norm"], s["series"]))
        if sum(s["norm"] for s in items) > 1 or (not chosen["norm"] and len(items) > 1):
            plan.warn(f"{sub} {ses}: {suffix} acquired more than once (series {[s['series'] for s in items]}); "
                      f"kept the last one ({chosen['series']}) - check that it is the good one")
        dst = bids_ses / "anat" / bids_name(sub, ses, suffix)
        note = "NORM" if chosen["norm"] else ""
        plan.add(chosen["nii"], dst.with_name(dst.name + ".nii.gz"), note)
        plan.add(chosen["json"], dst.with_name(dst.name + ".json"), note)
        for s in items:                                      # the other copies -> sourcedata, unchanged
            if s is not chosen:
                for f in (s["nii"], s["json"]):
                    plan.add(f, src_ses / "anat" / f.name, f"unused {suffix} copy")


def plan_mrs(sub: str, ses: str, mrs_dir: Path, bids_ses: Path, src_ses: Path, plan: Plan,
             t1_uri: Optional[str] = None) -> None:
    """Siemens twix (.dat) -> NIfTI-MRS in mrs/ (converted with spec2nii at --apply); every raw file (twix, voxel
    screenshots) is also copied unchanged to sourcedata/, as BIDS requires for vendor formats."""
    found = {}
    for f in sorted(p for p in mrs_dir.iterdir() if p.is_file()):
        plan.add(f, src_ses / "mrs" / f.name, "raw MRS file")
        m = re.fullmatch(r"(?:meas_MID(\d+)_FID\d+_)?(.+)_([VM]1)\.dat", f.name)
        if m and m.group(2) in MRS_SCANS:
            found.setdefault((m.group(2), m.group(3)), []).append((int(m.group(1) or 0), f))
        elif f.suffix.lower() == ".dat":
            plan.warn(f"{sub} {ses}: unrecognised MRS file {f.name} (kept in sourcedata only)")

    def uri(acq, voi, suffix):
        return f"bids::{sub}/{ses}/mrs/{mrs_filename(sub, ses, acq, voi, suffix)}"

    for (protocol, voi), items in sorted(found.items()):
        _, f = max(items)                                    # repeated scan: keep the last one (highest MID)
        if len(items) > 1:
            plan.warn(f"{sub} {ses}: {protocol}_{voi} acquired {len(items)} times; converted the last one ({f.name}), "
                      f"the others are in sourcedata only")
        acq, suffix, specific = MRS_SCANS[protocol]
        side = dict(MRS_COMMON, BodyPartDetails=MRS_VOI[voi], ProtocolName=f"{protocol}_{voi}", **specific)
        if suffix == "svs":
            refs = [MRS_SCANS[p][0] for p in ("mega_press_wref1", "mega_press_wref3") if (p, voi) in found]
            side["ReferenceSignal"] = [uri(ECC_ACQ, voi, "mrsref")] + [uri(a, voi, "mrsref") for a in refs]
        if t1_uri:
            side["AnatomicalImage"] = t1_uri
        dst = bids_ses / "mrs" / mrs_filename(sub, ses, acq, voi, suffix)
        plan.add(f, dst, "spec2nii", kind="spec2nii", content=dict(side, _extract="image"))
        if suffix == "svs":
            ecc = dict(MRS_COMMON, BodyPartDetails=MRS_VOI[voi], ProtocolName=f"{protocol}_{voi}",
                       WaterSuppression=False, Description="Phase-correction scans of the MEGA-PRESS acquisition "
                                                           "(spec2nii -e phasecor), eddy-current reference")
            if t1_uri:
                ecc["AnatomicalImage"] = t1_uri
            plan.add(f, bids_ses / "mrs" / mrs_filename(sub, ses, ECC_ACQ, voi, "mrsref"), "spec2nii phasecor",
                     kind="spec2nii", content=dict(ecc, _extract="phasecor"))
    for voi in sorted({v for _, v in found}):
        missing = [p for p in MRS_SCANS if (p, voi) not in found]
        if missing:
            plan.warn(f"{sub} {ses}: MRS voxel {voi}: no {', '.join(missing)}")


def warn_existing_files(sub: str, ses: str, bids_ses: Path, plan: Plan) -> None:
    """Images already in the session that this conversion does not write would be picked up by the pipeline."""
    planned = {a.dst for a in plan.actions}
    extra = [p for d in ("anat", "mrs") for p in sorted((bids_ses / d).glob("*.nii*")) if p not in planned]
    if extra:
        plan.warn(f"{sub} {ses}: {len(extra)} images already in the BIDS folder are not part of this conversion, e.g. "
                  f"{extra[0].name} (older conversion?); convert into an empty folder")


def plan_participant(sub_dir: Path, bids: Path, plan: Plan) -> None:
    sub = sub_dir.name
    if not re.fullmatch(r"sub-\d+", sub):
        plan.warn(f"skipping {sub_dir}: not a sub-<number> folder")
        return
    sessions = assign_sessions(session_folders(sub_dir), plan, sub)
    if not sessions:
        plan.warn(f"{sub}: no {PROJECT_ID}_NNN session folders found")
    for ses, folders in sorted(sessions.items()):
        bids_ses, src_ses = bids / sub / ses, bids / "sourcedata" / sub / ses
        t1_uri = None
        if folders["f3t"]:
            plan_anat(sub, ses, series(folders["f3t"]), bids_ses, src_ses, plan)
            t1 = next((a.dst for a in plan.actions
                       if a.dst.name.endswith("_T1w.nii.gz") and a.dst.parent.parent == bids_ses), None)
            t1_uri = f"bids::{t1.relative_to(bids).as_posix()}" if t1 else None
        else:
            plan.warn(f"{sub} {ses}: no F3T imaging folder (no anatomy)")
        if folders["mrs"]:
            plan_mrs(sub, ses, folders["mrs"], bids_ses, src_ses, plan, t1_uri)
        else:
            plan.warn(f"{sub} {ses}: no MRS folder")
        warn_existing_files(sub, ses, bids_ses, plan)


def dataset_files(bids: Path, plan: Plan) -> None:
    desc = bids / "dataset_description.json"
    if not desc.exists():
        plan.add(desc, desc, "new", kind="json", content={
            "Name": "MR spectroscopy in amblyopia before and after dichoptic training", "BIDSVersion": "1.10.0",
            "DatasetType": "raw", "GeneratedBy": [{"Name": "mrs_pipeline.raw_to_bids"}]})


# --------------------------------------------------------------------------- execution
def gzip_copy(src: Path, dst: Path) -> None:
    """Compress a .nii to .nii.gz: pigz (multi-threaded) when available, otherwise single-thread gzip."""
    pigz = shutil.which("pigz")
    if pigz:
        with open(dst, "wb") as fo:
            subprocess.run([pigz, "-c", "-1", str(src)], stdout=fo, check=True)
    else:
        with open(src, "rb") as fi, gzip.open(dst, "wb", compresslevel=1) as fo:
            shutil.copyfileobj(fi, fo, length=16 * 1024 * 1024)


def _run(cmd) -> None:
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"{' '.join(map(str, cmd))} failed:\n{r.stderr[-2000:]}")


def convert_twix(src: Path, dst: Path, extra: dict, spec2nii: str) -> None:
    """Siemens twix -> NIfTI-MRS with spec2nii (anonymised), plus a BIDS sidecar built from its header extension."""
    import nibabel as nib                                    # installed with FSL-MRS

    extra = dict(extra)
    extract = extra.pop("_extract", "image")
    with tempfile.TemporaryDirectory(dir=dst.parent) as tmp:
        tmp = Path(tmp)
        _run([spec2nii, "twix", "-e", extract, "--anon", "-q", "-f", "conv", "-o", tmp, src])
        # spec2nii --anon keeps weight and sex in the NIfTI-MRS header extension: remove them
        _run([spec2nii, "anon", *[x for k in MRS_PRIVATE_KEYS for x in ("-r", k)], "-f", "anon", "-o", tmp,
              tmp / "conv.nii.gz"])
        img = nib.load(tmp / "anon.nii.gz")
        hdr = json.loads(next(e for e in img.header.extensions if e.get_code() == 44).get_content())
        shape, zooms = img.shape, img.header.get_zooms()[:3]
        shutil.move(tmp / "anon.nii.gz", dst)
    dst.chmod(0o644)                                         # spec2nii writes owner-only files
    tags = [hdr.get(f"dim_{i}") for i in range(5, 8)]
    side = {k: v for k, v in hdr.items() if not k.startswith("dim_") and k not in MRS_PRIVATE_KEYS + ["kSpace"]}
    side.update(NumberOfSpectralPoints=int(shape[3]),
                NumberOfTransients=int(math.prod(n for n, t in zip(shape[4:], tags) if t in ("DIM_DYN", "DIM_EDIT"))),
                AcquisitionVoxelSize=[round(float(z), 2) for z in zooms], **extra)
    dst.with_name(dst.name.replace(".nii.gz", ".json")).write_text(json.dumps(side, indent=2) + "\n")


def execute(plan: Plan, overwrite: bool, log_rows: list, spec2nii: Optional[str] = None) -> int:
    n = 0
    for a in plan.actions:
        if a.kind in ("copy", "spec2nii") and a.dst.exists() and not overwrite:
            continue
        a.dst.parent.mkdir(parents=True, exist_ok=True)
        if a.kind == "spec2nii":
            convert_twix(a.src, a.dst, a.content, spec2nii)
        elif a.kind == "json":
            a.dst.write_text(json.dumps(a.content, indent=2) + "\n")
        elif a.src.suffix == ".nii" and a.dst.name.endswith(".nii.gz"):
            gzip_copy(a.src, a.dst)
        else:
            shutil.copy2(a.src, a.dst)
        log_rows.append((str(a.src), str(a.dst), a.note))
        n += 1
    return n


def convert(raw: str | Path, bids_dir: str | Path, include: Optional[Iterable[str]] = None,
            exclude: Optional[Iterable[str]] = None, *, apply: bool = False, overwrite: bool = False,
            spec2nii: Optional[str] = None, verbose: bool = False) -> int:
    """Plan (and with apply=True, run) the conversion. Returns the number of files written."""
    raw, bids = Path(raw).resolve(), Path(bids_dir).resolve()
    spec2nii = spec2nii or shutil.which("spec2nii")
    if raw.name.startswith("sub-"):
        subs = [raw]
    else:
        subs = sorted(p for p in raw.iterdir() if p.is_dir() and p.name.startswith("sub-")
                      and subject_is_selected(p.name, include, exclude))
    if apply and not spec2nii:
        raise RuntimeError("spec2nii not found: activate the FSL-MRS environment or pass spec2nii=PATH")

    print(f"raw:  {raw}\nbids: {bids}\nparticipants: {', '.join(s.name for s in subs)}\n")
    total = 0
    if apply:
        dplan = Plan()
        dataset_files(bids, dplan)
        total += execute(dplan, overwrite, [], spec2nii)
    for sub_dir in subs:
        plan = Plan()
        plan_participant(sub_dir, bids, plan)
        bids_files = [a for a in plan.actions if "sourcedata" not in a.dst.relative_to(bids).parts]
        print(f"{sub_dir.name}: {len(bids_files)} BIDS files, {len(plan.actions) - len(bids_files)} to sourcedata")
        for a in plan.actions if verbose else bids_files:
            print(f"  {a.src.name}  ->  {a.dst.relative_to(bids)}" + (f"   [{a.note}]" if a.note else ""))
        for w in plan.warnings:
            print(f"  WARNING: {w}")
        if apply:
            rows = []
            n = execute(plan, overwrite, rows, spec2nii)
            logp = bids / "sourcedata" / sub_dir.name / "conversion_log.tsv"
            logp.parent.mkdir(parents=True, exist_ok=True)
            with open(logp, "a", newline="") as f:
                w = csv.writer(f, delimiter="\t")
                for r in rows:
                    w.writerow([dt.datetime.now().isoformat(timespec="seconds"), *r])
            print(f"  wrote {n} files (log: {logp.relative_to(bids)})")
            total += n
        print()
    if not apply:
        print("dry run: nothing written. Add --apply to convert.")
    return total


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="mrs-raw-to-bids", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                allow_abbrev=False)
    p.add_argument("raw", help="raw export root (containing sub-XX folders) or one sub-XX folder")
    p.add_argument("--bids-dir", required=True, help="output BIDS root (also the data root of the pipeline)")
    p.add_argument("--include", nargs="+", metavar="SUB", help="only these participants (e.g. sub-01 sub-10)")
    p.add_argument("--exclude", nargs="+", metavar="SUB", help="all participants except these")
    p.add_argument("--spec2nii", default=None, help="spec2nii executable (default: found on PATH)")
    p.add_argument("--overwrite", action="store_true", help="replace files that already exist in the BIDS dataset")
    p.add_argument("--apply", action="store_true", help="write the dataset (default: dry run, print the plan)")
    p.add_argument("--verbose", action="store_true", help="print every file of the plan, including sourcedata")
    args = p.parse_args(argv)
    try:
        convert(args.raw, args.bids_dir, args.include, args.exclude, apply=args.apply,
                overwrite=args.overwrite, spec2nii=args.spec2nii, verbose=args.verbose)
    except RuntimeError as exc:
        sys.exit(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
