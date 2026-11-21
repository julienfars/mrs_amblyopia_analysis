#!/usr/bin/env bash
# pre_process.sh
#
# Pre-processing utilities for subject/session folders.
# Intended to be sourced from a main pipeline script:
#   source scripts/pre_process.sh
#
# Requires:
# - bash 4+
# - FSL tools: bet, fslmaths, fsl_prepare_fieldmap
# - immv (or replace with mv if that is what you intended)

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

ensure_dir() {
  mkdir -p "$1"
}

# Sort paths by file size, smallest first.
# GNU stat is expected here.
sort_paths_by_size() {
  local path size
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    size=$(stat -c '%s' "$path")
    printf '%s\t%s\n' "$size" "$path"
  done | sort -n -k1,1 | cut -f2-
}

fmap_files_process() {
  local -a folders_list=("$@")
  log "Processing fmap files"

  local folder pretraining_folder posttraining_folder subjnum
  for folder in "${folders_list[@]}"; do
    folder="${folder%/}"
    pretraining_folder="$folder/ses-1"
    posttraining_folder="$folder/ses-2"
    subjnum="$(basename "$folder")"

    process_fmap_folder() {
      local training_folder="$1"
      local session_label
      session_label="$(basename "$training_folder")"

      [[ -d "$training_folder" ]] || {
        warn "Folder does not exist: $training_folder. Skipping."
        return 0
      }

      local fmap_folder="$training_folder/fmap"
      ensure_dir "$fmap_folder"

      shopt -s nullglob

      local file
      # magnitude1 (e1)
      for file in "$training_folder"/*fieldmap*e1*; do
        [[ -e "$file" ]] || continue
        case "$file" in
          *.nii|*.nii.gz)
            immv "$file" "$fmap_folder/${subjnum}_${session_label}_magnitude1.nii.gz"
            ;;
          *.json)
            mv -- "$file" "$fmap_folder/${subjnum}_${session_label}_magnitude1.json"
            ;;
        esac
      done
      log "fmap e1 done for $training_folder"

      # phasediff (e2 + ph)
      for file in "$training_folder"/*fieldmap*e2*ph*; do
        [[ -e "$file" ]] || continue
        case "$file" in
          *.nii|*.nii.gz)
            immv "$file" "$fmap_folder/${subjnum}_${session_label}_phasediff.nii.gz"
            ;;
          *.json)
            mv -- "$file" "$fmap_folder/${subjnum}_${session_label}_phasediff.json"
            ;;
        esac
      done
      log "fmap phase done for $training_folder"

      # magnitude2 (e2 but not ph)
      for file in "$training_folder"/*fieldmap*e2*; do
        [[ -e "$file" ]] || continue
        [[ "$file" == *ph* ]] && continue

        case "$file" in
          *.nii|*.nii.gz)
            immv "$file" "$fmap_folder/${subjnum}_${session_label}_magnitude2.nii.gz"
            bet \
              "$fmap_folder/${subjnum}_${session_label}_magnitude2.nii.gz" \
              "$fmap_folder/${subjnum}_${session_label}_magnitude2-brain.nii.gz"
            fslmaths \
              "$fmap_folder/${subjnum}_${session_label}_magnitude2-brain.nii.gz" \
              -kernel boxv 3.8 -ero \
              "$fmap_folder/${subjnum}_${session_label}_magnitude2-brain.nii.gz"
            ;;
          *.json)
            mv -- "$file" "$fmap_folder/${subjnum}_${session_label}_magnitude2.json"
            ;;
        esac
      done

      local phase_file="$fmap_folder/${subjnum}_${session_label}_phasediff.nii.gz"
      local mag_brain_file="$fmap_folder/${subjnum}_${session_label}_magnitude2-brain.nii.gz"
      local rads_file="$fmap_folder/${subjnum}_${session_label}_rads.nii.gz"

      if [[ -f "$phase_file" && -f "$mag_brain_file" ]]; then
        fsl_prepare_fieldmap SIEMENS "$phase_file" "$mag_brain_file" "$rads_file" 2.46
      else
        warn "Required files for fsl_prepare_fieldmap not found in $training_folder"
      fi

      shopt -u nullglob
    }

    process_fmap_folder "$pretraining_folder"
    process_fmap_folder "$posttraining_folder"
  done
}

t1_files_process() {
  local -a folders_list=("$@")
  log "Processing T1/T2 files"

  local folder pretraining_folder posttraining_folder subjnum
  for folder in "${folders_list[@]}"; do
    folder="${folder%/}"
    pretraining_folder="$folder/ses-1"
    posttraining_folder="$folder/ses-2"
    subjnum="$(basename "$folder")"

    log "Starting $subjnum"

    process_t1_folder() {
      local training_folder="$1"
      local session_label
      session_label="$(basename "$training_folder")"

      [[ -d "$training_folder" ]] || {
        warn "Folder does not exist: $training_folder. Skipping."
        return 0
      }

      local anat_folder="$training_folder/anat"
      ensure_dir "$anat_folder"

      shopt -s nullglob

      local file
      # T1w files
      for file in "$training_folder"/*t1*; do
        [[ -e "$file" ]] || continue
        case "$file" in
          *.nii|*.nii.gz)
            immv "$file" "$anat_folder/${subjnum}_${session_label}_acq-MP2RAGE_T1w.nii.gz"
            bet \
              "$anat_folder/${subjnum}_${session_label}_acq-MP2RAGE_T1w.nii.gz" \
              "$anat_folder/${subjnum}_${session_label}_acq-MP2RAGE_T1w_brain.nii.gz"
            ;;
          *.json)
            mv -- "$file" "$anat_folder/${subjnum}_${session_label}_acq-MP2RAGE_T1w.json"
            ;;
        esac
      done
      log "Anat T1 processed for $training_folder"

      # T2w files
      for file in "$training_folder"/*t2*; do
        [[ -e "$file" ]] || continue
        case "$file" in
          *.nii|*.nii.gz)
            immv "$file" "$anat_folder/${subjnum}_${session_label}_acq-MP2RAGE_T2w.nii.gz"
            bet \
              "$anat_folder/${subjnum}_${session_label}_acq-MP2RAGE_T2w.nii.gz" \
              "$anat_folder/${subjnum}_${session_label}_acq-MP2RAGE_T2w_brain.nii.gz"
            ;;
          *.json)
            mv -- "$file" "$anat_folder/${subjnum}_${session_label}_acq-MP2RAGE_T2w.json"
            ;;
        esac
      done
      log "Anat T2 processed for $training_folder"

      shopt -u nullglob
    }

    process_t1_folder "$pretraining_folder"
    process_t1_folder "$posttraining_folder"
  done
}

rename_twix_file() {
  local -a folders_list=("$@")
  log "Processing MRS files"

  local folder pretraining_folder posttraining_folder subjnum
  for folder in "${folders_list[@]}"; do
    folder="${folder%/}"
    subjnum="$(basename "$folder")"
    pretraining_folder="$folder/ses-1"
    posttraining_folder="$folder/ses-2"

    process_mrs_folder() {
      local training_folder="$1"
      local session_label
      session_label="$(basename "$training_folder")"

      [[ -d "$training_folder" ]] || {
        warn "Folder does not exist: $training_folder. Skipping."
        return 0
      }

      local mrs_folder="$training_folder/mrs"
      ensure_dir "$mrs_folder"

      shopt -s nullglob

      local voxel file new_name
      for voxel in V1 M1; do
        for file in "$mrs_folder"/*"$voxel"*; do
          [[ -f "$file" ]] || continue
          new_name=""

          case "$file" in
            *_lw_*)
              new_name="${subjnum}_${session_label}_linewidth_run-${voxel}.dat"
              ;;
            *_fa_Cal_*)
              new_name="${subjnum}_${session_label}_flip_angle_calibration_run-${voxel}.dat"
              ;;
            *mega_press_TR1500*)
              new_name="${subjnum}_${session_label}_task-mega-press_acq-metab_run-${voxel}.dat"
              ;;
            *mega_press_wref1*)
              new_name="${subjnum}_${session_label}_task-mega-press_acq-wref-comb-raw_run-${voxel}.dat"
              ;;
            *mega_press_wref3*)
              new_name="${subjnum}_${session_label}_task-mega-press_acq-wref-quant-raw_run-${voxel}.dat"
              ;;
            *.png)
              new_name="${subjnum}_${session_label}_voxel-position_run-${voxel}.png"
              ;;
            *)
              continue
              ;;
          esac

          mv -- "$file" "$mrs_folder/$new_name"
        done

        log "Renamed MRS files for $voxel - $subjnum $session_label"
      done

      shopt -u nullglob
    }

    process_mrs_folder "$pretraining_folder"
    process_mrs_folder "$posttraining_folder"
  done
}

prf_files_process() {
  local -a folders_list=("$@")
  log "Processing pRF task files"

  local folder pretraining_folder posttraining_folder subjnum
  for folder in "${folders_list[@]}"; do
    folder="${folder%/}"
    subjnum="$(basename "$folder")"
    pretraining_folder="$folder/ses-1"
    posttraining_folder="$folder/ses-2"

    process_prf_folder() {
      local training_folder="$1"
      local session_label
      session_label="$(basename "$training_folder")"
      local func_folder="$training_folder/func"
      ensure_dir "$func_folder"

      shopt -s nullglob

      local side_label i file
      local -a prf_file_list nii_files json_files sorted_files

      for side_label in Left Right; do
        for i in {1..4}; do
          mapfile -t prf_file_list < <(
            find "$training_folder" -maxdepth 1 -type f -iname "*${side_label,,}_${i}*" 2>/dev/null | sort
          )

          nii_files=()
          json_files=()

          for file in "${prf_file_list[@]}"; do
            [[ -f "$file" ]] || continue
            case "$file" in
              *.nii|*.nii.gz) nii_files+=("$file") ;;
              *.json) json_files+=("$file") ;;
            esac
          done

          if (( ${#nii_files[@]} >= 2 )); then
            mapfile -t sorted_files < <(sort_paths_by_size "${nii_files[@]}")
            immv "${sorted_files[0]}" "$func_folder/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold_ref.nii.gz"
            immv "${sorted_files[1]}" "$func_folder/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold.nii.gz"
          elif (( ${#nii_files[@]} == 1 )); then
            immv "${nii_files[0]}" "$func_folder/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold.nii.gz"
          fi
          log "pRF NIfTI files: $subjnum run-$i $side_label done"

          if (( ${#json_files[@]} >= 2 )); then
            mapfile -t sorted_files < <(sort_paths_by_size "${json_files[@]}")
            mv -- "${sorted_files[0]}" "$func_folder/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold_ref.json"
            mv -- "${sorted_files[1]}" "$func_folder/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold.json"
          elif (( ${#json_files[@]} == 1 )); then
            mv -- "${json_files[0]}" "$func_folder/${subjnum}_${session_label}_task-${side_label}_run-${i}_bold.json"
          fi
          log "pRF JSON files: $subjnum run-$i $side_label done"
        done
      done

      log "Finished processing pRF files in $training_folder"

      shopt -u nullglob
    }

    process_prf_folder "$pretraining_folder"
    process_prf_folder "$posttraining_folder"
  done
}

resting_files_process() {
  local -a folders_list=("$@")
  log "Processing resting state fMRI files"

  local folder pretraining_folder posttraining_folder subjnum
  for folder in "${folders_list[@]}"; do
    folder="${folder%/}"
    subjnum="$(basename "$folder")"
    pretraining_folder="$folder/ses-1"
    posttraining_folder="$folder/ses-2"

    process_rest_folder() {
      local training_folder="$1"
      local session_label
      session_label="$(basename "$training_folder")"
      local rest_folder="$training_folder/rest"
      ensure_dir "$rest_folder"

      shopt -s nullglob

      local rest_file_list file
      local -a nii_files json_files sorted_files

      rest_file_list=("$training_folder"/*resting*)
      nii_files=()
      json_files=()

      for file in "${rest_file_list[@]}"; do
        [[ -f "$file" ]] || continue
        case "$file" in
          *.nii|*.nii.gz) nii_files+=("$file") ;;
          *.json) json_files+=("$file") ;;
        esac
      done

      if (( ${#nii_files[@]} >= 2 )); then
        mapfile -t sorted_files < <(sort_paths_by_size "${nii_files[@]}")
        immv "${sorted_files[0]}" "$rest_folder/${subjnum}_${session_label}_task-rest_bold_ref.nii.gz"
        immv "${sorted_files[1]}" "$rest_folder/${subjnum}_${session_label}_task-rest_bold.nii.gz"
      elif (( ${#nii_files[@]} == 1 )); then
        immv "${nii_files[0]}" "$rest_folder/${subjnum}_${session_label}_task-rest_bold.nii.gz"
      fi
      log "Resting state NIfTI files done for $subjnum $session_label"

      if (( ${#json_files[@]} >= 2 )); then
        mapfile -t sorted_files < <(sort_paths_by_size "${json_files[@]}")
        mv -- "${sorted_files[0]}" "$rest_folder/${subjnum}_${session_label}_task-rest_bold_ref.json"
        mv -- "${sorted_files[1]}" "$rest_folder/${subjnum}_${session_label}_task-rest_bold.json"
      elif (( ${#json_files[@]} == 1 )); then
        mv -- "${json_files[0]}" "$rest_folder/${subjnum}_${session_label}_task-rest_bold.json"
      fi
      log "Resting state JSON files done for $subjnum $session_label"

      shopt -u nullglob
    }

    process_rest_folder "$pretraining_folder"
    process_rest_folder "$posttraining_folder"
  done
}

move_remaining_files() {
  local -a folders_list=("$@")
  log "Moving extra files"

  local folder pretraining_folder posttraining_folder
  for folder in "${folders_list[@]}"; do
    folder="${folder%/}"
    pretraining_folder="$folder/ses-1"
    posttraining_folder="$folder/ses-2"

    move_remaining_files_process() {
      local training_folder="$1"
      local extra_folder="$training_folder/other"
      ensure_dir "$extra_folder"

      find "$training_folder" -maxdepth 1 -type f -exec mv -- {} "$extra_folder/" \;

      if find "$extra_folder" -mindepth 1 -maxdepth 1 -type f -print -quit | grep -q .; then
        log "Moved files to $extra_folder"
        find "$extra_folder" -maxdepth 1 -type f | sort
      else
        log "No extra files found in $training_folder"
      fi
    }

    [[ -d "$pretraining_folder" ]] && move_remaining_files_process "$pretraining_folder"
    [[ -d "$posttraining_folder" ]] && move_remaining_files_process "$posttraining_folder"
  done
}