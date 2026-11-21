#!/usr/bin/env bash
# scripts/combine_voxels.sh
#
# Combine standard-space voxel masks across subjects.
#
# Examples:
#   scripts/combine_voxels.sh --data /path/to/data --session ses-2 --voxel M1 --side S2
#   scripts/combine_voxels.sh --data /path/to/data --subjects sub-01 sub-02 --submit
#   scripts/combine_voxels.sh --data /path/to/data --dry-run

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
  $(basename "$0") --data /path/to/data [options]

Options:
  --data DIR        Root data directory containing derivatives/mrs
  --subjects LIST   Optional list of subjects (e.g. sub-01 sub-02)
  --session LABEL   Session folder to read from (default: ses-2)
  --voxel LABEL    Voxel label (default: M1)
  --side LABEL     Prefix used in filenames (default: S2)
  --output DIR     Output directory (default: DATA_DIR/derivatives/mrs/average_voxels)
  --submit         Submit the fslmaths job with fsl_sub
  --dry-run        Print the constructed command and exit
  --help, -h       Show this help message

Notes:
  - If --subjects is omitted, all sub-* folders in --data are used.
  - This script expects files named like:
      derivatives/mrs/sub-01/ses-2/mrs/S2_M1_mask_standard.nii.gz
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# -------------------- Defaults --------------------
DATA_DIR=""
OUTPUT_DIR=""
SESSION="ses-2"
VOXEL="M1"
SIDE="S2"
DO_SUBMIT=0
DRYRUN=0

declare -a SUBJECTS=()

# -------------------- Parse arguments --------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data)
      [[ $# -ge 2 ]] || die "--data requires a value"
      DATA_DIR="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --session)
      [[ $# -ge 2 ]] || die "--session requires a value"
      SESSION="$2"
      shift 2
      ;;
    --voxel)
      [[ $# -ge 2 ]] || die "--voxel requires a value"
      VOXEL="$2"
      shift 2
      ;;
    --side)
      [[ $# -ge 2 ]] || die "--side requires a value"
      SIDE="$2"
      shift 2
      ;;
    --subjects)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        SUBJECTS+=("$1")
        shift
      done
      ;;
    --submit)
      DO_SUBMIT=1
      shift
      ;;
    --dry-run|-n)
      DRYRUN=1
      shift
      ;;
    --help|-h)
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

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$DATA_DIR/derivatives/mrs/average_voxels"
fi

# -------------------- Dependencies --------------------
require_cmd fslmaths

if [[ "$DO_SUBMIT" -eq 1 ]]; then
  require_cmd fsl_sub
fi

if [[ -n "${FSLDIR:-}" ]]; then
  FSL_LOAD_NOTE="FSLDIR is set"
else
  warn "FSLDIR is not set. Make sure FSL is loaded in your environment."
fi

# -------------------- Subject list --------------------
if [[ ${#SUBJECTS[@]} -eq 0 ]]; then
  mapfile -t SUBJECTS < <(
    find "$DATA_DIR" -maxdepth 1 -mindepth 1 -type d -name 'sub-*' | sort
  )
fi

[[ ${#SUBJECTS[@]} -gt 0 ]] || die "No subject folders found"

# -------------------- Paths --------------------
LOGDIR="$DATA_DIR/derivatives/mrs/logs"
TMP_DIR="$DATA_DIR/derivatives/mrs/tmp_scripts"
mkdir -p "$LOGDIR" "$OUTPUT_DIR" "$TMP_DIR"

OUT_BASE="$OUTPUT_DIR/${VOXEL}_voxel_sum_${SIDE}.nii.gz"

# -------------------- Build input file list --------------------
declare -a FILES=()

for subj in "${SUBJECTS[@]}"; do
  subj="${subj%/}"
  mask_path="$DATA_DIR/derivatives/mrs/$subj/$SESSION/mrs/${SIDE}_${VOXEL}_mask_standard.nii.gz"

  if [[ -f "$mask_path" ]]; then
    FILES+=("$mask_path")
  else
    warn "File not found, skipping: $mask_path"
  fi
done

[[ ${#FILES[@]} -gt 0 ]] || die "No valid mask files found"

# -------------------- Build command --------------------
cmd=(fslmaths "${FILES[0]}")
for ((i=1; i<${#FILES[@]}; i++)); do
  cmd+=(-add "${FILES[i]}")
done
cmd+=("${OUT_BASE}")

# -------------------- Summary --------------------
log "Subjects used: ${#FILES[@]}"
printf '  - %s\n' "${FILES[@]}"
log "Output: $OUT_BASE"
log "Constructed command:"
printf ' %q' "${cmd[@]}"
printf '\n'

if [[ "$DRYRUN" -eq 1 ]]; then
  log "Dry run enabled; exiting without execution"
  exit 0
fi

# -------------------- Run locally or submit --------------------
if [[ "$DO_SUBMIT" -eq 1 ]]; then
  tmp_sh="$(mktemp "$TMP_DIR/combine_voxels.XXXXXX.sh")"
  chmod +x "$tmp_sh"

  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    printf '%q ' "${cmd[@]}"
    echo
  } > "$tmp_sh"

  log "Submitting job with fsl_sub"
  fsl_sub -s 16 -q short -T 500 -R 30 --logdir "$LOGDIR" "$tmp_sh"
  log "Submitted. Logdir: $LOGDIR"
  log "Temporary script: $tmp_sh"
else
  log "Running locally"
  "${cmd[@]}"
  log "Done"
fi