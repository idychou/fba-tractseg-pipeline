#!/usr/bin/env bash
# estimate_rf.sh
#
# Estimate response function(s) for (M)SMT-CSD / FOD estimation in MRtrix3,
# in preparation for fixel-based analysis (FBA).
#
# Reference (MRtrix docs):
#   Response function estimation — MRtrix 3.0.4 documentation
#   https://mrtrix.readthedocs.io/en/3.0.4/constrained_spherical_deconvolution/response_function_estimation.html
#
# Recommended algorithms (per MRtrix docs):
#   - Single-tissue CSD (single-shell): tournier (alternatives: fa, tax)
#   - Multi-tissue MSMT-CSD / global tractography: dhollander (alternative: msmt_5tt)
#
# This script supports:
#   - dhollander: outputs WM/GM/CSF responses (multi-tissue), requires only DWI
#   - tournier: outputs WM response (single-tissue)
#   - fa: outputs WM response (single-tissue; less robust, but can replicate older pipelines)
#
# Inputs expected per subject (edit patterns below):
#   - Preprocessed DWI .mif
#   - Brain mask .mif
#   - (Optional) .bvec/.bval if you prefer -fslgrad
#
# Output per subject:
#   - <sub>_wm.txt (and gm/csf for dhollander)
#   - <sub>_voxels.mif: voxel selection map (-voxels), for QC in mrview
#
# Author: Idy Chou
# Created: 2024-05-13
#
# ----------------------- User-configurable parameters -----------------------
TOPDIR="/path/to/processed_data"          # EDIT ME
OUTDIR="${TOPDIR}"                        # Usually same; can set elsewhere

# How to find subjects:
# Option A: prefix glob under TOPDIR (original style)
SUB_GLOB_PREFIX="sub-"                    # e.g., "sub-" or "sub-P"
# Option B (recommended): provide a subject list file (one ID per line)
SUBJECT_LIST_FILE=""                      # e.g., "${TOPDIR}/subject_list.txt" or leave empty

# Algorithm: dhollander | tournier | fa
RF_ALGORITHM="dhollander"

# Overwrite existing outputs? (0 = skip if outputs exist, 1 = overwrite)
OVERWRITE=0

# Input file patterns (relative to subject directory)
# Adjust these to match your pipeline outputs.
DWI_REL="path/to/subject/dwi"
MASK_REL="path/to/dwi/mask"
BVEC_REL="path/to/bvec"
BVAL_REL="path/to/bval"

# Output folder (relative to subject directory)
OUT_REL_BASE="dwi/fod"
# ---------------------------------------------------------------------------

sep="--------------------------------------------------------"

die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found on PATH: $1"
}

# MRtrix commands needed
need_cmd dwi2response

# Validate inputs
[ -d "${TOPDIR}" ] || die "TOPDIR does not exist: ${TOPDIR}"
mkdir -p "${OUTDIR}"

# Subject iterator
get_subjects() {
  if [ -n "${SUBJECT_LIST_FILE}" ]; then
    [ -f "${SUBJECT_LIST_FILE}" ] || die "SUBJECT_LIST_FILE not found: ${SUBJECT_LIST_FILE}"
    # Read non-empty, non-comment lines
    grep -v '^[[:space:]]*$' "${SUBJECT_LIST_FILE}" | grep -v '^[[:space:]]*#' || true
  else
    # shellcheck disable=SC2010
    ls -1 "${TOPDIR}" | grep -E "^${SUB_GLOB_PREFIX}" || true
  fi
}

printf "%s\nAlgorithm: %s\n%s\n" "${sep}" "${RF_ALGORITHM}" "${sep}"

cd "${TOPDIR}"

subjects="$(get_subjects)"
[ -n "${subjects}" ] || die "No subjects found (check SUB_GLOB_PREFIX or SUBJECT_LIST_FILE)."

while IFS= read -r sub; do
  [ -n "${sub}" ] || continue

  printf "%s\nSubject: %s\n%s\n" "${sep}" "${sub}" "${sep}"

  subDir="${TOPDIR}/${sub}"
  [ -d "${subDir}" ] || die "Subject directory not found: ${subDir}"

  # Resolve filenames
  # shellcheck disable=SC2059
  in_file="${subDir}/$(printf "${DWI_REL}" "${sub}")"
  # shellcheck disable=SC2059
  mask_file="${subDir}/$(printf "${MASK_REL}" "${sub}")"
  # shellcheck disable=SC2059
  bvec_file="${subDir}/$(printf "${BVEC_REL}" "${sub}")"
  # shellcheck disable=SC2059
  bval_file="${subDir}/$(printf "${BVAL_REL}" "${sub}")"

  [ -f "${in_file}" ] || die "Missing DWI file: ${in_file}"
  [ -f "${mask_file}" ] || die "Missing mask file: ${mask_file}"

  outBase="${OUTDIR}/${sub}/${OUT_REL_BASE}/${RF_ALGORITHM}"
  mkdir -p "${outBase}"

  wm_file="${outBase}/${sub}_wm.txt"
  gm_file="${outBase}/${sub}_gm.txt"
  csf_file="${outBase}/${sub}_csf.txt"
  voxel_file="${outBase}/${sub}_voxels.mif"

  # Decide whether to run
  run_it=1
  if [ "${OVERWRITE}" -eq 0 ]; then
    case "${RF_ALGORITHM}" in
      dhollander)
        if [ -f "${wm_file}" ] && [ -f "${gm_file}" ] && [ -f "${csf_file}" ] && [ -f "${voxel_file}" ]; then
          run_it=0
        fi
        ;;
      tournier|fa)
        if [ -f "${wm_file}" ] && [ -f "${voxel_file}" ]; then
          run_it=0
        fi
        ;;
      *)
        die "Unknown RF_ALGORITHM: ${RF_ALGORITHM} (use dhollander|tournier|fa)"
        ;;
    esac
  fi

  if [ "${run_it}" -eq 0 ]; then
    echo "Outputs exist; skipping (set OVERWRITE=1 to rerun)."
    continue
  fi

  printf "Estimating response function(s)...\n"

  case "${RF_ALGORITHM}" in
    dhollander)
      # Multi-tissue: outputs WM/GM/CSF responses; does not require extra inputs beyond DWI.
      dwi2response dhollander \
        "${in_file}" \
        "${wm_file}" "${gm_file}" "${csf_file}" \
        -mask "${mask_file}" \
        -voxels "${voxel_file}"
      ;;

    tournier)
      # Single-tissue: WM response only (recommended default for single-tissue CSD).
      dwi2response tournier \
        "${in_file}" \
        "${wm_file}" \
        -mask "${mask_file}" \
        -voxels "${voxel_file}"
      ;;

    fa)
      # Single-tissue: WM response only (FA-based; replicates older approaches).
      # -fslgrad is optional in many MRtrix workflows if gradients are embedded in .mif,
      # but we keep it here for compatibility with pipelines that rely on external bvec/bval.
      [ -f "${bvec_file}" ] || die "Missing bvec file (required for fa mode here): ${bvec_file}"
      [ -f "${bval_file}" ] || die "Missing bval file (required for fa mode here): ${bval_file}"

      dwi2response fa \
        "${in_file}" \
        "${wm_file}" \
        -fslgrad "${bvec_file}" "${bval_file}" \
        -mask "${mask_file}" \
        -voxels "${voxel_file}"
      ;;
  esac

  echo "Saved outputs in: ${outBase}"
  echo "QC tips:"
  echo "  mrview \"${in_file}\" -overlay.load \"${voxel_file}\""
  echo "  shview \"${wm_file}\""
  if [ "${RF_ALGORITHM}" = "dhollander" ]; then
    echo "  shview \"${gm_file}\""
    echo "  shview \"${csf_file}\""
  fi

done <<< "${subjects}"

printf "%s\nDone.\n" "${sep}"
