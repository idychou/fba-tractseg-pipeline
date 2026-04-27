#!/usr/bin/env bash
# estimate_fod.sh
#
# Estimate fibre orientation distributions (FODs) using (M)SMT-CSD / SS3T-style workflows,
# in preparation for fixel-based analysis (FBA) in MRtrix.
#
# Reference:
#   https://mrtrix.readthedocs.io/en/3.0.4/constrained_spherical_deconvolution/response_function_estimation.html
#
# Prerequisites:
#   - Preprocessed DWI images (e.g., produced by dwifslpreproc)
#   - MRtrix3 on PATH (mrgrid, mrconvert, dwi2fod, mtnormalise, mrcat, etc.)
#   - FSL BET on PATH if using the BET-based mask generation in this script
#   - Group-average response functions must already exist (paths below)
#
# Options:
#   rf_algorithm:
#     - dhollander : multi-tissue (WM/GM/CSF responses)
#     - fa         : single-tissue (WM response only)
#
#   fod_algorithm (used when rf_algorithm=dhollander and n_shells==1):
#     - msmt : two-tissue MSMT (WM+CSF)
#     - ss3t : three-tissue CSD via an external script (WM+GM+CSF)
#
#   n_shells:
#     Number of shells excluding b=0 (>=1). If >=2, runs standard MSMT-CSD (WM+GM+CSF).
#
# Created by Idy Chou on 13 May 2024

# ----------------------------- user parameters ------------------------------
topDir="/path/to/processed_data"
outDir="${topDir}"

# Subject discovery:
# - If subject_list is non-empty, use it (one subject ID per line, e.g., sub-0001)
# - Otherwise, use sub_prefix glob (e.g., "sub-")
subject_list=""
sub_prefix="sub-"

rf_algorithm="dhollander"   # dhollander | fa
fod_algorithm="ss3t"        # msmt | ss3t (used only for dhollander + n_shells==1)
n_shells=1                  # excluding b=0

# Upsampling voxel size (mm)
upsample_vox="1.25"

# BET fractional intensity threshold (tune if needed)
bet_f="0.19"
# ---------------------------------------------------------------------------

sep="--------------------------------------------------------"

die() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Command not found on PATH: $1"; }

need_cmd mrgrid
need_cmd mrconvert
need_cmd dwi2fod
need_cmd mtnormalise
need_cmd mrcat

# Only required if you use the BET-based mask generation below
need_cmd bet

[ -d "${topDir}" ] || die "topDir does not exist: ${topDir}"
mkdir -p "${outDir}"

grp_wm_file="${outDir}/average_response/group_average_response_wm_${rf_algorithm}_pittsburgh.txt"
grp_gm_file="${outDir}/average_response/group_average_response_gm_${rf_algorithm}_pittsburgh.txt"
grp_csf_file="${outDir}/average_response/group_average_response_csf_${rf_algorithm}_pittsburgh.txt"

# Basic checks for group response files (depending on chosen algorithm)
case "${rf_algorithm}" in
  dhollander)
    [ -f "${grp_wm_file}" ] || die "Missing group WM response: ${grp_wm_file}"
    [ -f "${grp_gm_file}" ] || die "Missing group GM response: ${grp_gm_file}"
    [ -f "${grp_csf_file}" ] || die "Missing group CSF response: ${grp_csf_file}"
    ;;
  fa)
    [ -f "${grp_wm_file}" ] || die "Missing group WM response: ${grp_wm_file}"
    ;;
  *)
    die "Invalid rf_algorithm: ${rf_algorithm} (use dhollander|fa)"
    ;;
esac

get_subjects() {
  if [ -n "${subject_list}" ]; then
    [ -f "${subject_list}" ] || die "subject_list not found: ${subject_list}"
    grep -v '^[[:space:]]*$' "${subject_list}" | grep -v '^[[:space:]]*#' || true
  else
    ls -1 "${topDir}" | grep -E "^${sub_prefix}" || true
  fi
}

printf "%s\nAlgorithm: %s\n" "${sep}" "${rf_algorithm}"
if [ "${rf_algorithm}" = "dhollander" ]; then
  printf "Number of shells (excluding b=0): %s\n" "${n_shells}"
  printf "FOD algorithm (n_shells==1): %s\n" "${fod_algorithm}"
fi
printf "%s\n" "${sep}"

subjects="$(get_subjects)"
[ -n "${subjects}" ] || die "No subjects found (check subject_list or sub_prefix)."

cd "${topDir}"

while IFS= read -r sub; do
  [ -n "${sub}" ] || continue

  printf "%s\nSubject: %s\n%s\n" "${sep}" "${sub}" "${sep}"

  # Output directories
  mkdir -p "${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}"

  # Inputs
  in_file="path/to/subject/dwi"

  # Derived / intermediate
  ups_file="path/to/upsampled/dwi"
  ups_mask_file="path/to/upsampled/mask"

  # Outputs
  wm_fod_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_wm_fod.mif"
  gm_fod_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_gm_fod.mif"
  csf_fod_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_csf_fod.mif"

  wm_fod_norm_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_wm_fod_norm.mif"
  gm_fod_norm_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_gm_fod_norm.mif"
  csf_fod_norm_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_csf_fod_norm.mif"

  vf_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_vf.mif"
  vf_norm_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_vf_norm.mif"

  [ -f "${in_file}" ] || die "Missing input DWI: ${in_file}"

  # Upsample DWI
  if [ ! -f "${ups_file}" ]; then
    printf "Upsampling DW image...\n"
    mrgrid "${in_file}" regrid -vox "${upsample_vox}" "${ups_file}"
  fi

  # Compute brain mask (BET-based)
  if [ ! -f "${ups_mask_file}" ]; then
    printf "Computing brain mask...\n"
    tmp_mif="${ups_file%.mif}_tmp.mif"
    tmp_nii="${ups_file%.mif}_tmp.nii.gz"
    bet_out_base="${ups_mask_file%.mif}"
    bet_mask_nii="${bet_out_base}_mask.nii.gz"

    mrconvert "${ups_file}" -coord 3 0 -axes 0,1,2 "${tmp_mif}"
    mrconvert "${tmp_mif}" "${tmp_nii}"
    bet "${tmp_nii}" "${bet_out_base}" -m -n -f "${bet_f}"
    mrconvert "${bet_mask_nii}" "${ups_mask_file}"

    rm -f "${tmp_mif}" "${tmp_nii}" "${bet_mask_nii}"
  fi

  [ -f "${ups_mask_file}" ] || die "Mask generation failed: ${ups_mask_file}"

  # Estimate FODs
  printf "Estimating fibre orientation distributions...\n"

  case "${rf_algorithm}" in
    dhollander)
      if [ "${n_shells}" -lt 1 ]; then
        die "Invalid n_shells: ${n_shells} (must be >= 1)"
      fi

      if [ "${n_shells}" -ge 2 ]; then
        dwi2fod msmt_csd \
          "${ups_file}" \
          "${grp_wm_file}" "${wm_fod_file}" \
          "${grp_gm_file}" "${gm_fod_file}" \
          "${grp_csf_file}" "${csf_fod_file}" \
          -mask "${ups_mask_file}"

        mrconvert -coord 3 0 "${wm_fod_file}" - | mrcat "${csf_fod_file}" "${gm_fod_file}" - "${vf_file}"
      else
        case "${fod_algorithm}" in
          msmt)
            dwi2fod msmt_csd \
              "${ups_file}" \
              "${grp_wm_file}" "${wm_fod_file}" \
              "${grp_csf_file}" "${csf_fod_file}" \
              -mask "${ups_mask_file}"

            mrconvert -coord 3 0 "${wm_fod_file}" - | mrcat "${csf_fod_file}" - "${vf_file}"
            ;;
          ss3t)
            # External SS3T script (edit this path to your installation)
            ss3t_cmd="/path/to/MRtrix3Tissue/bin/ss3t_csd_beta1"
            [ -x "${ss3t_cmd}" ] || die "SS3T command not found/executable: ${ss3t_cmd}"

            "${ss3t_cmd}" \
              "${ups_file}" \
              "${grp_wm_file}" "${wm_fod_file}" \
              "${grp_gm_file}" "${gm_fod_file}" \
              "${grp_csf_file}" "${csf_fod_file}" \
              -mask "${ups_mask_file}"

            mrconvert -coord 3 0 "${wm_fod_file}" - | mrcat "${csf_fod_file}" "${gm_fod_file}" - "${vf_file}"
            ;;
          *)
            die "Invalid fod_algorithm: ${fod_algorithm} (use msmt|ss3t)"
            ;;
        esac
      fi
      ;;

    fa)
      dwi2fod csd \
        "${ups_file}" \
        "${grp_wm_file}" "${wm_fod_file}" \
        -mask "${ups_mask_file}"

      mrconvert -coord 3 0 "${wm_fod_file}" "${vf_file}"
      ;;
  esac

  # Intensity normalisation (for multi-subject analysis)
  printf "Performing intensity normalisation...\n"

  case "${rf_algorithm}" in
    dhollander)
      if [ "${n_shells}" -ge 2 ]; then
        mtnormalise \
          "${wm_fod_file}" "${wm_fod_norm_file}" \
          "${gm_fod_file}" "${gm_fod_norm_file}" \
          "${csf_fod_file}" "${csf_fod_norm_file}" \
          -mask "${ups_mask_file}"

        mrconvert -coord 3 0 "${wm_fod_norm_file}" - | mrcat "${csf_fod_norm_file}" "${gm_fod_norm_file}" - "${vf_norm_file}"
      else
        case "${fod_algorithm}" in
          msmt)
            mtnormalise \
              "${wm_fod_file}" "${wm_fod_norm_file}" \
              "${csf_fod_file}" "${csf_fod_norm_file}" \
              -mask "${ups_mask_file}"

            mrconvert -coord 3 0 "${wm_fod_norm_file}" - | mrcat "${csf_fod_norm_file}" - "${vf_norm_file}"
            ;;
          ss3t)
            mtnormalise \
              "${wm_fod_file}" "${wm_fod_norm_file}" \
              "${gm_fod_file}" "${gm_fod_norm_file}" \
              "${csf_fod_file}" "${csf_fod_norm_file}" \
              -mask "${ups_mask_file}"

            mrconvert -coord 3 0 "${wm_fod_norm_file}" - | mrcat "${csf_fod_norm_file}" "${gm_fod_norm_file}" - "${vf_norm_file}"
            ;;
        esac
      fi
      ;;

    fa)
      mtnormalise \
        "${wm_fod_file}" "${wm_fod_norm_file}" \
        -mask "${ups_mask_file}"

      mrconvert -coord 3 0 "${wm_fod_norm_file}" "${vf_norm_file}"
      ;;
  esac

  # Optional inspection:
  # mrview "${vf_file}" -odf.load_sh "${wm_fod_file}"

done <<< "${subjects}"

printf "%s\nDone.\n" "${sep}"
cd ~
