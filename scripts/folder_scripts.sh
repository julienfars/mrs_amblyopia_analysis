#!/usr/bin/env bash
# folder_scripts.sh
# Utilities for organising subject folders and moving/renaming files.
#
# Intended to be sourced from a main pipeline script:
#   source scripts/folder_scripts.sh
#
# Requires bash 4+.

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

# Move all contents of a directory, including hidden files, into another directory.
move_dir_contents() {
  local src="$1"
  local dst="$2"

  [[ -d "$src" ]] || {
    warn "Source folder does not exist: $src"
    return 0
  }

  mkdir -p "$dst"

  shopt -s nullglob dotglob
  local items=("$src"/*)
  shopt -u nullglob dotglob

  if (( ${#items[@]} == 0 )); then
    warn "Nothing to move from $src"
    return 0
  fi

  mv -- "${items[@]}" "$dst/"
}

# Return all subject folders matching sub-* directly under a path.
list_folders() {
  local path="${1%/}"

  [[ -d "$path" ]] || die "The specified path does not exist: $path"

  find "$path" -maxdepth 1 -type d -name 'sub-*' -print | sort
}

# Filter out folders that already contain both ses-1 and ses-2.
filter_folders() {
  local folder
  local output_folders=()

  for folder in "$@"; do
    folder="${folder%/}"

    if [[ -d "$folder/ses-1" && -d "$folder/ses-2" ]]; then
      log "Skipping $folder because it already contains both ses-1 and ses-2."
    else
      output_folders+=("$folder")
    fi
  done

  printf '%s\n' "${output_folders[@]}"
}

# Filter folders by matching any of the given numbers.
# Usage:
#   filter_sub folder1 folder2 "12 14 18"
# The last argument is a whitespace-separated list of numbers to match.
filter_sub() {
  if (( $# < 2 )); then
    die "filter_sub expects at least one folder and one number list."
  fi

  local numbers_string="${!#}"
  local -a folders=("${@:1:$#-1}")
  local -a number_array=()
  local -a filtered=()
  local folder num

  read -r -a number_array <<< "$numbers_string"

  for folder in "${folders[@]}"; do
    for num in "${number_array[@]}"; do
      if [[ "$folder" == *"$num"* ]]; then
        filtered+=("$folder")
        break
      fi
    done
  done

  printf '%s\n' "${filtered[@]}"
}

# Create ses-1 and ses-2 folders for each subject directory.
create_training_folders() {
  log "Checking and creating ses-1 and ses-2 folders"

  local folder base_dir pretraining_folder posttraining_folder
  for folder in "$@"; do
    base_dir="${folder%/}"
    pretraining_folder="$base_dir/ses-1"
    posttraining_folder="$base_dir/ses-2"

    mkdir -p "$pretraining_folder" "$posttraining_folder"
  done
}

# Create required subfolders inside ses-1 and ses-2.
create_subfolders() {
  log "Checking and creating anat, fmap, func, mrs, and other folders"

  local -a required_subfolders=("anat" "fmap" "func" "mrs" "other")
  local folder base_dir training_folder subfolder

  for folder in "$@"; do
    base_dir="${folder%/}"

    for training_folder in "$base_dir/ses-1" "$base_dir/ses-2"; do
      mkdir -p "$training_folder"
      for subfolder in "${required_subfolders[@]}"; do
        mkdir -p "$training_folder/$subfolder"
      done
    done
  done
}

# Move files from F3T folders into ses-1 and ses-2.
move_files_from_f3t() {
  log "Moving files from F3T folders"

  local folder base_dir pretraining_folder posttraining_folder
  local -a f3t_folders sorted_folders
  local smallest_f3t_folder largest_f3t_folder

  for folder in "$@"; do
    base_dir="${folder%/}"
    pretraining_folder="$base_dir/ses-1"
    posttraining_folder="$base_dir/ses-2"

    mapfile -t f3t_folders < <(find "$base_dir" -maxdepth 1 -type d -name 'F3T_2022_021_*' 2>/dev/null | sort -V)

    if (( ${#f3t_folders[@]} == 0 )); then
      log "No F3T folders found in $base_dir"
      continue
    fi

    smallest_f3t_folder="${f3t_folders[0]}"
    largest_f3t_folder="${f3t_folders[$((${#f3t_folders[@]} - 1))]}"

    log "Moving files from $smallest_f3t_folder to $pretraining_folder"
    move_dir_contents "$smallest_f3t_folder" "$pretraining_folder"

    if [[ "$largest_f3t_folder" != "$smallest_f3t_folder" ]]; then
      log "Moving files from $largest_f3t_folder to $posttraining_folder"
      move_dir_contents "$largest_f3t_folder" "$posttraining_folder"
    fi
  done
}

# Move files from 2022_021_* folders into mrs inside ses-1 and ses-2.
move_files_from_2022_021() {
  log "Moving files from 2022_021_* folders to mrs"

  local folder base_dir pretraining_folder posttraining_folder
  local -a matching_folders sorted

  for folder in "$@"; do
    base_dir="${folder%/}"
    pretraining_folder="$base_dir/ses-1/mrs"
    posttraining_folder="$base_dir/ses-2/mrs"

    mkdir -p "$pretraining_folder" "$posttraining_folder"

    mapfile -t matching_folders < <(find "$base_dir" -maxdepth 1 -type d -name '2022_021_*' 2>/dev/null)

    if (( ${#matching_folders[@]} == 0 )); then
      log "No 2022_021_* folders found in $base_dir"
      continue
    fi

    mapfile -t sorted < <(printf '%s\n' "${matching_folders[@]}" | sort -t'_' -k3,3n)

    if (( ${#sorted[@]} == 1 )); then
      log "Only one 2022_021 folder found; moving to ses-1/mrs"
      move_dir_contents "${sorted[0]}" "$pretraining_folder"
    else
      log "Multiple 2022_021 folders found; moving first to ses-1/mrs and second to ses-2/mrs"
      move_dir_contents "${sorted[0]}" "$pretraining_folder"
      move_dir_contents "${sorted[1]}" "$posttraining_folder"

      if (( ${#sorted[@]} > 2 )); then
        warn "More than two 2022_021 folders found in $base_dir; extra folders were not moved."
      fi
    fi
  done
}

# Delete empty 2022_021_* and F3T_2022_021_* folders.
delete_folders() {
  log "Deleting empty 2022_021_* and F3T_2022_021_* folders"

  local folder subfolder base
  local -a subfolders

  for folder in "$@"; do
    folder="${folder%/}"
    mapfile -t subfolders < <(find "$folder" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

    for subfolder in "${subfolders[@]}"; do
      base="$(basename "$subfolder")"

      if [[ "$base" =~ ^[0-9]{4}_021_[0-9]+$ || "$base" =~ ^F3T_[0-9]{4}_021_[0-9]+$ ]]; then
        if [[ -z "$(find "$subfolder" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
          log "Deleting empty folder: $subfolder"
          rmdir "$subfolder"
        else
          log "Skipping non-empty folder: $subfolder"
        fi
      fi
    done
  done
}

# Rename and move EDF and MAT files into func folders using participants.tsv.
rename_and_move_edf_and_mat_files() {
  local -a folders_list=("$@")
  local first_folder base_dir participants_file

  [[ ${#folders_list[@]} -gt 0 ]] || die "No folders provided."

  first_folder="${folders_list[0]%/}"
  base_dir="$(dirname "$first_folder")"
  participants_file="$base_dir/participants.tsv"

  [[ -f "$participants_file" ]] || die "participants.tsv not found: $participants_file"

  declare -A amblyopic_eyes=()
  local participant eye subj_id normalized_subj_id

  log "Loading amblyopic eye information from: $participants_file"

  while IFS=$'\t' read -r participant eye _rest; do
    [[ "$participant" == "participant" ]] && continue
    [[ -z "${participant:-}" ]] && continue
    subj_id="${participant#sub-}"
    normalized_subj_id="$((10#$subj_id))"
    amblyopic_eyes["$normalized_subj_id"]="$eye"
  done < <(tail -n +2 "$participants_file")

  log "Renaming and moving .edf and .mat files"

  local folder base_subject_dir training_folder session_label
  local -a edf_files mat_files
  local edf_file mat_file subj_num_raw subj_num run_num_raw run_num eye task_eye new_run_num new_name

  for folder in "${folders_list[@]}"; do
    base_subject_dir="${folder%/}"
    session_label=""

    process_files_for_session() {
      local training_folder="$1"
      session_label="$(basename "$training_folder")"

      [[ -d "$training_folder" ]] || {
        warn "Folder does not exist: $training_folder. Skipping."
        return 0
      }

      mkdir -p "$training_folder/func"

      mapfile -t edf_files < <(find "$training_folder" -type f -name "*subj*_run*_exp93.edf" 2>/dev/null | sort)
      mapfile -t mat_files < <(find "$training_folder" -type f -name "*subj*_run*_exp93.mat" 2>/dev/null | sort)

      for edf_file in "${edf_files[@]}"; do
        if [[ "$edf_file" =~ _subj([0-9]+)_run([0-9]+)_exp93\.edf$ ]]; then
          subj_num_raw="${BASH_REMATCH[1]}"
          run_num_raw="${BASH_REMATCH[2]}"
          subj_num="$((10#$subj_num_raw))"
          run_num="$((10#$run_num_raw))"

          eye="${amblyopic_eyes[$subj_num]:-}"
          if [[ -z "$eye" ]]; then
            warn "No eye info for subject $subj_num. Skipping $edf_file"
            continue
          fi

          if (( run_num >= 1 && run_num <= 4 )); then
            task_eye="$eye"
            new_run_num="$run_num"
          else
            if [[ "$eye" == "left" ]]; then
              task_eye="right"
            else
              task_eye="left"
            fi
            new_run_num="$((run_num - 4))"
          fi

          new_name="sub-${subj_num}_${session_label}_task-${task_eye}_run-${new_run_num}_eyetracking.edf"
          mv -- "$edf_file" "$training_folder/func/$new_name"
        fi
      done

      for mat_file in "${mat_files[@]}"; do
        if [[ "$mat_file" =~ _subj([0-9]+)_run([0-9]+)_exp93\.mat$ ]]; then
          subj_num_raw="${BASH_REMATCH[1]}"
          run_num_raw="${BASH_REMATCH[2]}"
          subj_num="$((10#$subj_num_raw))"
          run_num="$((10#$run_num_raw))"

          eye="${amblyopic_eyes[$subj_num]:-}"
          if [[ -z "$eye" ]]; then
            warn "No eye info for subject $subj_num. Skipping $mat_file"
            continue
          fi

          if (( run_num >= 1 && run_num <= 4 )); then
            task_eye="$eye"
            new_run_num="$run_num"
          else
            if [[ "$eye" == "left" ]]; then
              task_eye="right"
            else
              task_eye="left"
            fi
            new_run_num="$((run_num - 4))"
          fi

          new_name="sub-${subj_num}_${session_label}_task-${task_eye}_run-${new_run_num}_run-details.mat"
          mv -- "$mat_file" "$training_folder/func/$new_name"
        fi
      done
    }

    process_files_for_session "$base_subject_dir/ses-1"
    process_files_for_session "$base_subject_dir/ses-2"
  done
}

# Create derivatives folder structure.
create_derivatives_structure() {
  local -a folders_list=("$@")
  local first_folder base_dir derivatives_dir folder subject_id subject_derivatives_path

  [[ ${#folders_list[@]} -gt 0 ]] || die "No folders provided."

  first_folder="${folders_list[0]%/}"
  base_dir="$(dirname "$first_folder")"
  derivatives_dir="$base_dir/derivatives"

  log "Base directory detected as: $base_dir"
  log "Creating derivatives directory structure..."

  mkdir -p "$derivatives_dir"

  for folder in "${folders_list[@]}"; do
    subject_id="$(basename "${folder%/}")"
    subject_derivatives_path="$derivatives_dir/$subject_id"

    mkdir -p "$subject_derivatives_path"
  done
}