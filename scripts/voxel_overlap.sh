#!/usr/bin/env bash
# scripts/voxel_overlap.sh
#
# ------------------------------------------------------------------------------
# Script name:  voxel_overlap_final.sh
#
# Description:  
# Author:	Hanna Willis, 18/06/25
# Modified by: Juju, 30/03/26
#
# Compare MRS voxel overlap between ses-1 and ses-2, and project voxels to MNI space.
# Requires FSL tools and a BIDS-like directory structure:
#   DATA_DIR/sub-01/ses-1/anat
#   DATA_DIR/sub-01/ses-2/anat
#   DATA_DIR/derivatives/mrs/sub-01/ses-1/mrs
#   DATA_DIR/derivatives/mrs/sub-01/ses-2/mrs

set -euo pipefail
IFS=$'\n\t'

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") --data /path/to/data [--subjects sub-01 sub-02 ...] [--voxels V1 M1 ...] [--csv /path/to/output.csv]

Options:
  --data       Root data directory containing sub-* folders
  --subjects   Optional list of subject IDs to process; if omitted, all sub-* folders are used
  --voxels     Optional list of voxel labels; default: V1 M1
  --csv        Output CSV path; default: DATA_DIR/derivatives/mrs/voxel_overlap.csv
  -h, --help   Show this help message

Examples:
  $(basename "$0") --data /path/to/data
  $(basename "$0") --data /path/to/data --subjects sub-01 sub-02 --voxels V1 M1
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

single_match() {
  local dir="$1"
  local pattern="$2"
  local -a matches=()

  mapfile -t matches < <(find "$dir" -maxdepth 1 -type f -name "$pattern" | sort)

  case "${#matches[@]}" in
    0) die "No file matching '$pattern' found in $dir" ;;
    1) printf '%s\n' "${matches[0]}" ;;
    *) die "More than one file matching '$pattern' found in $dir" ;;
  esac
}

# ---------- Defaults ----------
DATA_DIR=""
CSV_OUT=""
declare -a SUBJECTS=()
declare -a VOXELS=("V1" "M1")

# ---------- Parse arguments ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data)
      [[ $# -ge 2 ]] || die "--data requires a value"
      DATA_DIR="$2"
      shift 2
      ;;
    --csv)
      [[ $# -ge 2 ]] || die "--csv requires a value"
      CSV_OUT="$2"
      shift 2
      ;;
    --subjects)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        SUBJECTS+=("$1")
        shift
      done
      ;;
    --voxels)
      shift
      VOXELS=()
      while [[ $# -gt 0 && "$1" != --* ]]; do
        VOXELS+=("$1")
        shift
      done
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ -n "$DATA_DIR" ]] || { usage; exit 1; }
[[ -d "$DATA_DIR" ]] || die "Data directory does not exist: $DATA_DIR"

require_cmd flirt
require_cmd fnirt
require_cmd invwarp
require_cmd applywarp
require_cmd fslmaths
require_cmd fslstats

[[ -n "${FSLDIR:-}" ]] || die "FSLDIR is not set. Load FSL before running this script."

STANDARD_DIR="${FSLDIR}/data/standard"
STANDARD_T1="${STANDARD_DIR}/MNI152_T1_1mm.nii.gz"

[[ -f "$STANDARD_T1" ]] || die "Standard template not found: $STANDARD_T1"

if [[ -z "$CSV_OUT" ]]; then
  CSV_OUT="$DATA_DIR/derivatives/mrs/voxel_overlap.csv"
fi

mkdir -p "$(dirname "$CSV_OUT")"
: > "$CSV_OUT"
printf 'Subj,Voxel,Ses1_Voxel_Size,Ses2_Voxel_Size,Ses2_Non_Overlap_Size,Ses2_Overlap_Size\n' > "$CSV_OUT"

# If no subjects were passed, auto-detect sub-* folders.
if [[ ${#SUBJECTS[@]} -eq 0 ]]; then
  mapfile -t SUBJECTS < <(
    find "$DATA_DIR" -maxdepth 1 -mindepth 1 -type d -name 'sub-*' | sort
  )
fi

[[ ${#SUBJECTS[@]} -gt 0 ]] || die "No subject folders found"

log "Data directory: $DATA_DIR"
log "Output CSV: $CSV_OUT"
log "Subjects: ${#SUBJECTS[@]}"
log "Voxels: ${VOXELS[*]}"

# ---------- Step 1: create anat->MNI warps ----------
log "Creating anat-to-MNI warps"

for subj_dir in "${SUBJECTS[@]}"; do
  subj_dir="${subj_dir%/}"
  subj="$(basename "$subj_dir")"

  for timepoint in ses-1 ses-2; do
    anat_dir="$subj_dir/$timepoint/anat"
    warp_dir="$DATA_DIR/derivatives/mrs/$subj/$timepoint/warps"

    [[ -d "$anat_dir" ]] || { warn "Missing anat directory: $anat_dir"; continue; }

    t1_file="$(single_match "$anat_dir" '*acq-MPRAGE_T1w.nii.gz')"
    mkdir -p "$warp_dir"

    log "Building warp for $subj $timepoint"

    flirt \
      -in "$t1_file" \
      -ref "$STANDARD_T1" \
      -omat "$warp_dir/struct2mni.mat" \
      -interp nearestneighbour

    fnirt \
      --ref="$STANDARD_T1" \
      --in="$t1_file" \
      --aff="$warp_dir/struct2mni.mat" \
      --cout="$warp_dir/warpxfm_struct2mni.nii.gz"

    invwarp \
      -w "$warp_dir/warpxfm_struct2mni.nii.gz" \
      -o "$warp_dir/warpxfm_mni2struct.nii.gz" \
      -r "$t1_file"
  done
done

# ---------- Step 2: compute voxel overlap ----------
log "Computing voxel overlap"

for subj_dir in "${SUBJECTS[@]}"; do
  subj_dir="${subj_dir%/}"
  subj="$(basename "$subj_dir")"

  anat_base="$subj_dir/ses-1/anat"
  anat_s2="$subj_dir/ses-2/anat"
  warp_base="$DATA_DIR/derivatives/mrs/$subj/ses-1/warps"
  warp_s2="$DATA_DIR/derivatives/mrs/$subj/ses-2/warps"

  mrs_base="$DATA_DIR/derivatives/mrs/$subj/ses-1/mrs"
  mrs_s2="$DATA_DIR/derivatives/mrs/$subj/ses-2/mrs"

  [[ -d "$anat_base" && -d "$anat_s2" ]] || {
    warn "Missing anat folders for $subj; skipping overlap step"
    continue
  }

  t1_base="$(single_match "$anat_base" '*acq-MPRAGE_T1w.nii.gz')"
  t1_s2="$(single_match "$anat_s2" '*acq-MPRAGE_T1w.nii.gz')"

  mkdir -p "$mrs_base" "$mrs_s2"

  for voxel in "${VOXELS[@]}"; do
    log "Processing $subj voxel $voxel"

    s2_mask_raw="$mrs_s2/MRS_fit_${voxel}_mask.nii.gz"
    s1_mask_raw="$mrs_base/MRS_fit_${voxel}_mask.nii.gz"

    [[ -f "$s2_mask_raw" ]] || { warn "Missing mask: $s2_mask_raw"; continue; }
    [[ -f "$s1_mask_raw" ]] || { warn "Missing mask: $s1_mask_raw"; continue; }

    # S2 -> S1 rigid registration in T1 space
    flirt \
      -in "$t1_s2" \
      -ref "$t1_base" \
      -out "$warp_s2/my_S2_struct2struct.nii.gz" \
      -omat "$warp_s2/my_S2_struct2struct.mat" \
      -interp nearestneighbour

    # Resample S2 mask into its own T1 space
    flirt \
      -applyxfm -usesqform \
      -in "$s2_mask_raw" \
      -ref "$t1_s2" \
      -out "$mrs_s2/S2_${voxel}_mask_full_fov.nii.gz" \
      -interp nearestneighbour

    fslmaths "$mrs_s2/S2_${voxel}_mask_full_fov.nii.gz" -bin "$mrs_s2/S2_${voxel}_mask_full_fov.nii.gz"

    # Register S2 mask into S1 T1 space
    flirt \
      -applyxfm -usesqform \
      -in "$mrs_s2/S2_${voxel}_mask_full_fov.nii.gz" \
      -ref "$t1_base" \
      -init "$warp_s2/my_S2_struct2struct.mat" \
      -out "$mrs_base/S2_${voxel}_mask_reg.nii.gz" \
      -interp nearestneighbour

    fslmaths "$mrs_base/S2_${voxel}_mask_reg.nii.gz" -bin "$mrs_base/S2_${voxel}_mask_reg.nii.gz"

    # Resample S1 mask into S1 T1 space
    flirt \
      -applyxfm -usesqform \
      -in "$s1_mask_raw" \
      -ref "$t1_base" \
      -out "$mrs_base/S1_${voxel}_mask_fov.nii.gz" \
      -interp nearestneighbour

    fslmaths "$mrs_base/S1_${voxel}_mask_fov.nii.gz" -bin "$mrs_base/S1_${voxel}_mask_fov.nii.gz"

    # Overlap maps
    fslmaths "$mrs_base/S1_${voxel}_mask_fov.nii.gz" -sub "$mrs_base/S2_${voxel}_mask_reg.nii.gz" "$mrs_base/S2_mrs_${voxel}_non_overlap.nii.gz"
    fslmaths "$mrs_base/S2_mrs_${voxel}_non_overlap.nii.gz" -thr 0 "$mrs_base/S2_mrs_${voxel}_non_overlap_thr.nii.gz"
    fslmaths "$mrs_base/S1_${voxel}_mask_fov.nii.gz" -mas "$mrs_base/S2_${voxel}_mask_reg.nii.gz" "$mrs_base/S2_mrs_${voxel}_overlap.nii.gz"

    # Summary stats
    s1_size="$(fslstats "$mrs_base/S1_${voxel}_mask_fov.nii.gz" -V | awk '{print $2}')"
    s2_size="$(fslstats "$mrs_base/S2_${voxel}_mask_reg.nii.gz" -V | awk '{print $2}')"
    non_overlap_size="$(fslstats "$mrs_base/S2_mrs_${voxel}_non_overlap.nii.gz" -V | awk '{print $2}')"
    overlap_size="$(fslstats "$mrs_base/S2_mrs_${voxel}_overlap.nii.gz" -V | awk '{print $2}')"

    printf '%s,%s,%s,%s,%s,%s\n' \
      "$subj" "$voxel" "$s1_size" "$s2_size" "$non_overlap_size" "$overlap_size" \
      >> "$CSV_OUT"
  done
done

# ---------- Step 3: project voxels to standard space ----------
log "Projecting voxels to standard space"

for subj_dir in "${SUBJECTS[@]}"; do
  subj_dir="${subj_dir%/}"
  subj="$(basename "$subj_dir")"

  anat_base="$subj_dir/ses-1/anat"
  anat_s2="$subj_dir/ses-2/anat"
  warp_base="$DATA_DIR/derivatives/mrs/$subj/ses-1/warps"
  warp_s2="$DATA_DIR/derivatives/mrs/$subj/ses-2/warps"

  mrs_base="$DATA_DIR/derivatives/mrs/$subj/ses-1/mrs"
  mrs_s2="$DATA_DIR/derivatives/mrs/$subj/ses-2/mrs"

  for voxel in "${VOXELS[@]}"; do
    [[ -f "$mrs_base/S1_${voxel}_mask_fov.nii.gz" ]] || continue
    [[ -f "$mrs_s2/S2_${voxel}_mask_full_fov.nii.gz" ]] || continue

    applywarp \
      -r "$STANDARD_T1" \
      -i "$mrs_base/S1_${voxel}_mask_fov.nii.gz" \
      -o "$mrs_base/S1_${voxel}_mask_standard.nii.gz" \
      -w "$warp_base/warpxfm_struct2mni.nii.gz"

    applywarp \
      -r "$STANDARD_T1" \
      -i "$mrs_s2/S2_${voxel}_mask_full_fov.nii.gz" \
      -o "$mrs_s2/S2_${voxel}_mask_standard.nii.gz" \
      -w "$warp_s2/warpxfm_struct2mni.nii.gz"
  done
done

log "Done"
log "Results saved to: $CSV_OUT"