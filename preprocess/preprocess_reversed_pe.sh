#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# preprocess_reversed_pe.sh
#
# Preprocess DWI data (AP/PA) using MRtrix3 + FSL (native installs):
#   1) mrconvert (NIfTI -> MIF)
#   2) dwidenoise + residuals
#   3) mrdegibbs + residuals
#   4) dwiextract b=0 + mrmath mean (AP & PA) -> b0 pair
#   5) mrcat AP+PA -> combined series
#   6) dwifslpreproc (topup+eddy; includes slice-to-volume via mporder; slspec)
#   7) optional: dwibiascorrect (ANTs) + BET mask, repeated n_iter times
#
# Notes:
# - This script expects an interleaved acquisition slspec file for eddy's --mporder.
#   See: https://note.com/brain_surfing2/n/na635e2b1f6bf
# - TotalReadoutTime is read from the AP JSON sidecar.
#
# Requirements (on PATH):
#   MRtrix3: mrconvert, dwidenoise, mrcalc, mrdegibbs, dwiextract, mrmath,
#           mrcat, dwifslpreproc, dwibiascorrect
#   FSL:    bet, topup, eddy (called by dwifslpreproc)
#
# Created by Idy Chou (2024-03-05).
# -----------------------------------------------------------------------------

# ------------------------------- configuration ------------------------------

# Root directory for dataset and subject ID
topDir="path/to/study/directory"    #SUBSTITUTE
sub="subject_id"                    #SUBSTITUTE

# Options
CORRECT_BIAS="${CORRECT_BIAS:-1}"   # 0=no, 1=yes
n_iter="${n_iter:-1}"               # iterations for bias correction + mask

# BET option for mask generation during bias correction
BET_F="${BET_F:-0.2}"

# Eddy options (passed through dwifslpreproc)
EDDY_OPTIONS_DEFAULT="--slm=linear --mporder=23 --repol --fep --cnr_maps --ol_type=both --data_is_shelled --b0_peas"
EDDY_OPTIONS="${EDDY_OPTIONS:-$EDDY_OPTIONS_DEFAULT}"

# slspec file (slice acquisition order; used by eddy with mporder)
slspec_data="${SLSPEC_FILE:-${topDir}/slspec.txt}"

# ------------------------------- helpers -----------------------------------

sep='-------------------------------------------'
die() { echo "ERROR: $*" >&2; exit 1; }
log() { printf "%s\n%s\n" "${sep}" "$*"; }

need_file() { [[ -f "$1" ]] || die "Missing file: $1"; }
need_dir()  { [[ -d "$1" ]] || die "Missing directory: $1"; }
need_cmd()  { command -v "$1" >/dev/null 2>&1 || die "Command not found on PATH: $1"; }

usage() {
  cat <<EOF
Usage:
  $(basename "$0") <sub_id>

Environment variables:
  CORRECT_BIAS        0 or 1 (default: 1)
  n_iter              integer >=1 (default: 1)
  BET_F               BET -f threshold (default: 0.2)
  SLSPEC_FILE         path to slspec.txt
  EDDY_OPTIONS        eddy options string passed via dwifslpreproc -eddy_options

Assumed directory structure:
  \$topDir/raw_data/<sub>/dwi/preprocessed/         (source)
  \$topDir/processed_data/<sub>/dwi/preprocessed/   (workdir)

Assumed input filenames (inside dwi/preprocessed):
  <sub>_acq-AP_dwi.nii.gz / .bvec / .bval / .json
  <sub>_acq-PA_dwi.nii.gz / .bvec / .bval
  <sub>_acq-all_dwi.bvec / .bval  (gradients for concatenated AP+PA series)

EOF
}

# --------------------------------- main ------------------------------------

[[ $# -eq 1 ]] || { usage; exit 2; }

# Check required commands
need_cmd mrconvert
need_cmd dwidenoise
need_cmd mrcalc
need_cmd mrdegibbs
need_cmd dwiextract
need_cmd mrmath
need_cmd mrcat
need_cmd dwifslpreproc
need_cmd dwibiascorrect
need_cmd bet

rawDir="${topDir}/raw_data/${sub}"
subDir="${topDir}/processed_data/${sub}"

need_dir "${rawDir}"

# Copy subject folder if needed
if [[ ! -d "${subDir}" ]]; then
  log "Copying files for ${sub} ..."
  mkdir -p "${topDir}/processed_data"
  cp -r "${rawDir}" "${topDir}/processed_data/"
fi

workDir="${subDir}/dwi/preprocessed"
need_dir "${workDir}"
cd "${workDir}"

log "Preprocessing data of subject ${sub}"

# ------------------------------ file naming --------------------------------
# AP
ap_raw_nii="${sub}_acq-AP_dwi.nii.gz"
ap_raw_data="${sub}_acq-AP_dwi.mif"
ap_den_data="${sub}_acq-AP_dwi_den.mif"
ap_noise_data="${sub}_acq-AP_dwi_noise.mif"
ap_residual_data="${sub}_acq-AP_dwi_residual.mif"
ap_unr_data="${sub}_acq-AP_dwi_den_degibbs.mif"
ap_unr_residual_data="${sub}_acq-AP_dwi_residualUnringed.mif"
ap_bvec_data="${sub}_acq-AP_dwi.bvec"
ap_bval_data="${sub}_acq-AP_dwi.bval"
ap_mean_b0_data="${sub}_acq-AP_dwi_den_degibbs_meanb0.mif"

# PA
pa_raw_nii="${sub}_acq-PA_dwi.nii.gz"
pa_raw_data="${sub}_acq-PA_dwi.mif"
pa_den_data="${sub}_acq-PA_dwi_den.mif"
pa_noise_data="${sub}_acq-PA_dwi_noise.mif"
pa_residual_data="${sub}_acq-PA_dwi_residual.mif"
pa_unr_data="${sub}_acq-PA_dwi_den_degibbs.mif"
pa_unr_residual_data="${sub}_acq-PA_dwi_residualUnringed.mif"
pa_bvec_data="${sub}_acq-PA_dwi.bvec"
pa_bval_data="${sub}_acq-PA_dwi.bval"
pa_mean_b0_data="${sub}_acq-PA_dwi_den_degibbs_meanb0.mif"

# All
json_file="${sub}_acq-AP_dwi.json"
b0_pair_data="${sub}_acq-AP-PA_dwi_den_degibbs_meanb0_pair.mif"
all_unr_data="${sub}_acq-all_dwi_den_degibbs.mif"
all_bvec_data="${sub}_acq-all_dwi.bvec"
all_bval_data="${sub}_acq-all_dwi.bval"
preproc_data="${sub}_acq-all_dwi_den_degibbs_preproc.mif"

unbiased_prefix="${sub}_acq-all_dwi_den_degibbs_preproc_unbiased"
bias_prefix="${sub}_acq-all_dwi_den_degibbs_preproc_bias"
mask_prefix="${sub}_acq-all_dwi_mask_unbiased"

# ------------------------------ sanity checks ------------------------------
need_file "${ap_raw_nii}"
need_file "${pa_raw_nii}"
need_file "${ap_bvec_data}"
need_file "${ap_bval_data}"
need_file "${pa_bvec_data}"
need_file "${pa_bval_data}"
need_file "${json_file}"
need_file "${all_bvec_data}"
need_file "${all_bval_data}"
need_file "${slspec_data}"

# ------------------------------ conversion ---------------------------------
log "Converting data (NIfTI -> MIF) ..."
mrconvert "${ap_raw_nii}" "${ap_raw_data}"
mrconvert "${pa_raw_nii}" "${pa_raw_data}"

# ------------------------------ denoise ------------------------------------
log "Denoising (dwidenoise) ..."
dwidenoise "${ap_raw_data}" "${ap_den_data}" -noise "${ap_noise_data}"
mrcalc "${ap_raw_data}" "${ap_den_data}" -subtract "${ap_residual_data}"

dwidenoise "${pa_raw_data}" "${pa_den_data}" -noise "${pa_noise_data}"
mrcalc "${pa_raw_data}" "${pa_den_data}" -subtract "${pa_residual_data}"

# ------------------------------ degibbs -----------------------------------
log "Removing Gibbs ringing (mrdegibbs) ..."
mrdegibbs "${ap_den_data}" "${ap_unr_data}" -axes 0,1
mrcalc "${ap_den_data}" "${ap_unr_data}" -subtract "${ap_unr_residual_data}"

mrdegibbs "${pa_den_data}" "${pa_unr_data}" -axes 0,1
mrcalc "${pa_den_data}" "${pa_unr_data}" -subtract "${pa_unr_residual_data}"

# --------------------- read TotalReadoutTime from JSON ---------------------
# Robust-ish extraction without jq; expects a key "TotalReadoutTime": <number>
TotalReadoutTime="$(
  grep -m 1 '"TotalReadoutTime"' "${json_file}" \
    | sed -E 's/.*"TotalReadoutTime"[[:space:]]*:[[:space:]]*([0-9eE\.+-]+).*/\1/'
)"
[[ -n "${TotalReadoutTime}" ]] || die "Failed to parse TotalReadoutTime from ${json_file}"
log "TotalReadoutTime = ${TotalReadoutTime}"

# -------------------- mean b0 (AP & PA) and b0 pair ------------------------
log "Calculating mean b=0 for AP and PA ..."
dwiextract -fslgrad "${ap_bvec_data}" "${ap_bval_data}" "${ap_unr_data}" - -bzero \
  | mrmath - mean "${ap_mean_b0_data}" -axis 3

dwiextract -fslgrad "${pa_bvec_data}" "${pa_bval_data}" "${pa_unr_data}" - -bzero \
  | mrmath - mean "${pa_mean_b0_data}" -axis 3

mrcat "${ap_mean_b0_data}" "${pa_mean_b0_data}" -axis 3 "${b0_pair_data}"

# ---------------------- concat AP+PA and dwifslpreproc ---------------------
log "Concatenating AP + PA series ..."
mrcat "${ap_unr_data}" "${pa_unr_data}" -axis 3 "${all_unr_data}"

log "Performing motion & distortion correction (dwifslpreproc: topup+eddy) ..."
dwifslpreproc "${all_unr_data}" "${preproc_data}" \
  -pe_dir AP \
  -rpe_pair -se_epi "${b0_pair_data}" \
  -fslgrad "${all_bvec_data}" "${all_bval_data}" \
  -readout_time "${TotalReadoutTime}" \
  -eddy_slspec "${slspec_data}" \
  -eddyqc_all "${subDir}/eddyqc" \
  -eddy_options " ${EDDY_OPTIONS} " \
  -align_seep \
  -force

# -------------------------- bias correction + mask --------------------------
if [[ "${CORRECT_BIAS}" -eq 1 ]]; then
  log "Bias field correction + mask generation (n_iter=${n_iter}) ..."

  [[ "${n_iter}" -ge 1 ]] || die "n_iter must be >= 1 (got ${n_iter})"

  # Iteration 1: bias correct from preproc_data
  if [[ ! -f "${unbiased_prefix}_1.mif" ]]; then
    dwibiascorrect ants "${preproc_data}" "${unbiased_prefix}_1.mif" \
      -bias "${bias_prefix}_1.mif" \
      -fslgrad "${all_bvec_data}" "${all_bval_data}"
  fi

  if [[ ! -f "${mask_prefix}_1.mif" ]]; then
    # BET requires NIfTI; use b0 volume
    mrconvert "${unbiased_prefix}_1.mif" -coord 3 0 -axes 0,1,2 "${unbiased_prefix}_1.nii.gz"
    bet "${unbiased_prefix}_1.nii.gz" "${unbiased_prefix}_1" -m -n -f "${BET_F}"
    mrconvert "${unbiased_prefix}_1_mask.nii.gz" "${mask_prefix}_1.mif"
    rm -f "${unbiased_prefix}_1.nii.gz" "${unbiased_prefix}_1_mask.nii.gz"
  fi

  # Iteration 2..n_iter
  if [[ "${n_iter}" -gt 1 ]]; then
    for ((i=2; i<=n_iter; i++)); do
      j=$((i-1))

      if [[ ! -f "${unbiased_prefix}_${i}.mif" ]]; then
        dwibiascorrect ants "${unbiased_prefix}_${j}.mif" "${unbiased_prefix}_${i}.mif" \
          -bias "${bias_prefix}_${i}.mif" \
          -fslgrad "${all_bvec_data}" "${all_bval_data}"
      fi

      if [[ ! -f "${mask_prefix}_${i}.mif" ]]; then
        mrconvert "${unbiased_prefix}_${i}.mif" -coord 3 0 -axes 0,1,2 "${unbiased_prefix}_${i}.nii.gz"
        bet "${unbiased_prefix}_${i}.nii.gz" "${unbiased_prefix}_${i}" -m -n -f "${BET_F}"
        mrconvert "${unbiased_prefix}_${i}_mask.nii.gz" "${mask_prefix}_${i}.mif"
        rm -f "${unbiased_prefix}_${i}.nii.gz" "${unbiased_prefix}_${i}_mask.nii.gz"
      fi
    done
  fi
fi

log "Done."
cd ~
