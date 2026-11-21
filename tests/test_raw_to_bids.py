"""Tests of the raw -> BIDS conversion plan (no spec2nii needed: the plan is checked, not executed)."""

import json

from mrs_pipeline import raw_to_bids
from mrs_pipeline.utils import subject_is_selected

MRS_SET = [f"meas_MID{100 + i:05d}_FID{i}_mega_press_{p}_V1.dat"
           for i, p in enumerate(["lw", "fa_Cal", "TR1500", "wref1", "wref3"])]


def _series(folder, number, protocol, image_type=("ORIGINAL", "PRIMARY", "M")):
    name = f"images_{number:03d}_{protocol}"
    (folder / f"{name}.nii").write_bytes(b"nii")
    (folder / f"{name}.json").write_text(json.dumps(
        dict(ProtocolName=protocol, SeriesNumber=number, ImageType=list(image_type))))


def make_raw(tmp_path, mrs_names=MRS_SET, sub="sub-03", label="sub-03-ses-1-pretraining", scan=5):
    """One session: T1 (raw + NORM copies), T2 (NORM), a BOLD run, and an MRS folder."""
    ses = tmp_path / "raw" / sub / label
    f3t = ses / f"F3T_2022_021_{scan:03d}"
    f3t.mkdir(parents=True)
    _series(f3t, 3, "t1_mpr_ax_1mm_iso")
    _series(f3t, 4, "t1_mpr_ax_1mm_iso", ("ORIGINAL", "PRIMARY", "M", "NORM"))
    _series(f3t, 5, "t2_tse_tra", ("ORIGINAL", "PRIMARY", "M", "NORM"))
    _series(f3t, 10, "bold_mb_Right_1")
    mrs = ses / f"2022_021_{scan:03d}"
    mrs.mkdir()
    for n in mrs_names:
        (mrs / n).write_bytes(b"twix")
    return tmp_path / "raw" / sub


def _plan(tmp_path, **kw):
    sub = make_raw(tmp_path, **kw)
    plan = raw_to_bids.Plan()
    raw_to_bids.plan_participant(sub, tmp_path / "bids", plan)
    return {str(a.dst.relative_to(tmp_path / "bids")): a for a in plan.actions}, plan.warnings


def test_norm_t1_kept_other_copy_to_sourcedata(tmp_path):
    dst, _ = _plan(tmp_path)
    assert dst["sub-03/ses-1/anat/sub-03_ses-1_acq-MPRAGE_T1w.nii.gz"].src.name == "images_004_t1_mpr_ax_1mm_iso.nii"
    assert dst["sub-03/ses-1/anat/sub-03_ses-1_acq-TSE_T2w.nii.gz"].src.name == "images_005_t2_tse_tra.nii"
    assert "sourcedata/sub-03/ses-1/anat/images_003_t1_mpr_ax_1mm_iso.nii" in dst


def test_fmri_left_out(tmp_path):
    dst, _ = _plan(tmp_path)
    assert not any("bold" in k for k in dst)


def test_mrs_converted_to_bids_names(tmp_path):
    dst, warnings = _plan(tmp_path, mrs_names=MRS_SET + ["V1 Position.png"])
    conv = {k: a for k, a in dst.items() if a.kind == "spec2nii"}
    assert sorted(conv) == sorted(f"sub-03/ses-1/mrs/sub-03_ses-1_acq-{a}_voi-V1_{s}.nii.gz" for a, s in
                                  [("lw", "mrsref"), ("facal", "mrsref"), ("megapress", "svs"), ("ecc", "mrsref"),
                                   ("comb", "mrsref"), ("quant", "mrsref")])
    svs = conv["sub-03/ses-1/mrs/sub-03_ses-1_acq-megapress_voi-V1_svs.nii.gz"].content
    assert svs["_extract"] == "image"
    assert svs["ReferenceSignal"] == [f"bids::sub-03/ses-1/mrs/sub-03_ses-1_acq-{a}_voi-V1_mrsref.nii.gz"
                                      for a in ("ecc", "comb", "quant")]
    assert svs["AnatomicalImage"] == "bids::sub-03/ses-1/anat/sub-03_ses-1_acq-MPRAGE_T1w.nii.gz"
    assert svs["WaterSuppression"] and svs["BodyPart"] == "BRAIN"
    # the eddy-current reference is the phasecor part of the MEGA-PRESS twix file
    ecc = conv["sub-03/ses-1/mrs/sub-03_ses-1_acq-ecc_voi-V1_mrsref.nii.gz"]
    assert ecc.content["_extract"] == "phasecor" and "TR1500" in ecc.src.name
    # raw twix and screenshots only in sourcedata, never as vendor files in the BIDS tree
    assert all(f"sourcedata/sub-03/ses-1/mrs/{n}" in dst for n in MRS_SET + ["V1 Position.png"])
    assert not any(k.startswith("sub-03/") and k.endswith((".dat", ".png")) for k in dst)
    assert not any("MRS" in w for w in warnings)


def test_mrs_repeated_scan_keeps_last(tmp_path):
    dst, warnings = _plan(tmp_path, mrs_names=MRS_SET + ["meas_MID00200_FID9_mega_press_fa_Cal_V1.dat"])
    assert dst["sub-03/ses-1/mrs/sub-03_ses-1_acq-facal_voi-V1_mrsref.nii.gz"].src.name.startswith("meas_MID00200")
    assert any("acquired 2 times" in w for w in warnings)


def test_mrs_missing_reference_reported(tmp_path):
    _, warnings = _plan(tmp_path, mrs_names=[n for n in MRS_SET if "wref3" not in n])
    assert any("voxel V1: no mega_press_wref3" in w for w in warnings)


def test_unrecognised_twix_reported(tmp_path):
    dst, warnings = _plan(tmp_path, mrs_names=MRS_SET + ["meas_MID00300_FID9_something_else_V1.dat"])
    assert "sourcedata/sub-03/ses-1/mrs/meas_MID00300_FID9_something_else_V1.dat" in dst
    assert any("unrecognised MRS file" in w for w in warnings)


def test_sessions_follow_scan_order(tmp_path):
    make_raw(tmp_path, label="pre", scan=19)
    make_raw(tmp_path, label="post", scan=23)
    plan = raw_to_bids.Plan()
    raw_to_bids.plan_participant(tmp_path / "raw" / "sub-03", tmp_path / "bids", plan)
    sources = {str(a.dst.relative_to(tmp_path / "bids")): a.src for a in plan.actions}
    assert "2022_021_019" in str(sources["sub-03/ses-1/mrs/sub-03_ses-1_acq-megapress_voi-V1_svs.nii.gz"])
    assert "2022_021_023" in str(sources["sub-03/ses-2/mrs/sub-03_ses-2_acq-megapress_voi-V1_svs.nii.gz"])


def test_folder_label_overrides_scan_order(tmp_path):
    make_raw(tmp_path, label="sub-03-ses-2-posttraining", scan=5)
    plan = raw_to_bids.Plan()
    raw_to_bids.plan_participant(tmp_path / "raw" / "sub-03", tmp_path / "bids", plan)
    assert any(a.dst.parts[-3] == "ses-2" for a in plan.actions if a.kind == "spec2nii")
    assert any("folder says ses-2" in w for w in plan.warnings)


def test_older_conversion_in_bids_folder_is_reported(tmp_path):
    old = tmp_path / "bids" / "sub-03" / "ses-1" / "anat" / "sub-03_ses-1_acq-MP2RAGE_T1w.nii.gz"
    old.parent.mkdir(parents=True)
    old.touch()
    _, warnings = _plan(tmp_path)
    assert any("acq-MP2RAGE_T1w" in w and "empty folder" in w for w in warnings)


def test_dry_run_writes_nothing(tmp_path):
    make_raw(tmp_path)
    raw_to_bids.main([str(tmp_path / "raw"), "--bids-dir", str(tmp_path / "bids")])
    assert not (tmp_path / "bids").exists()


def test_subject_filter_is_exact():
    assert subject_is_selected("sub-10", include=["sub-10"])
    assert not subject_is_selected("sub-10", include=["sub-1"])
    assert subject_is_selected("sub-10", exclude=["sub-1"])
    assert not subject_is_selected("sub-01", exclude=["sub-01"])
