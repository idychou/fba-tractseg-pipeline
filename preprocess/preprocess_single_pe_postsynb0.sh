#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# preprocess_single_pe_postsynb0.sh
#
# This script runs MRtrix3 dwifslpreproc (FSL topup/eddy wrapper) for a SINGLE
# phase-encoding (single-PE) DWI dataset, using a synthetic undistorted b=0
# image produced by Synb0-DISCO as the "reverse-phase/susceptibility-free"
# reference EPI for distortion correction.
#
# Pipeline intent (important):
#   1) Pre-Synb0 script produces:
#        - denoised+degibbs DWI (AP)  + mean b0
#        - files needed to run Synb0-DISCO
#   2) Synb0-DISCO synthesizes an UNDISTORTED b=0 image.
#   3) This Post-Synb0 script uses that synthesized undistorted b=0 as -se_epi
#      input to dwifslpreproc, so eddy can do eddy-current + motion correction
#      with improved susceptibility distortion handling despite only having a
#      single-PE DWI acquisition.
#
# Options:
#   CORRECT_BIAS: 0=no, 1=yes (default: 1)
#   n_iter: number of iterations for bias correction + mask generation (default: 1)
#
# Requirements (native installs on PATH; no Singularity):
#   MRtrix3: mrconvert, dwifslpreproc, dwibiascorrect
#   FSL: bet (and eddy/topup invoked by dwifslpreproc)
#   ANTs: required by dwibiascorrect ants (unless you switch method)
#
# Created by Idy Chou (2024-03-06); edited to remove Singularity usage.
# -----------------------------------------------------------------------------

# ------------------------------- configuration ------------------------------

sub="subject_id"	#SUBSTITUTE
if [[ -z "${sub}" ]]; then
  echo "Usage: $(basename "$0") <sub-id>" >&2
  exit 2
fi

topDir="path/to/study/directory"

CORRECT_BIAS="${CORRECT_BIAS:-1}"
n_iter="${n_iter:-1}"

# Eddy options passed through dwifslpreproc
EDDY_OPTIONS_DEFAULT="--slm=linear --repol --cnr_maps --data_is_shelled"
EDDY_OPTIONS="${EDDY_OPTIONS:-$EDDY_OPTIONS_DEFAULT}"

# Threads for dwifslpreproc
NTHREADS="${NTHREADS:-20}"

# If you want slice-to-volume motion correction (eddy --mporder), you must set:
#   USE_S2V=1 and provide SLSPEC_FILE.
USE_S2V="${USE_S2V:-0}"
SLSPEC_FILE="path/to/slspec.txt"

# ------------------------------- helpers -----------------------------------

sep='-------------------------------------------------------------'
die(){ echo "ERROR: $*" >&2; exit 1; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Command not found on PATH: $1"; }
need_file(){ [[ -f "$1" ]] || die "Missing file: $1"; }
need_dir(){ [[ -d "$1" ]] || die "Missing directory: $1"; }

# Commands
need_cmd mrconvert
need_cmd dwifslpreproc
need_cmd dwibiascorrect
need_cmd bet

printf '%s\nPreprocessing data of subject %s (Post-Synb0)\n%s\n' "$sep" "$sub" "$sep"

subDir="${topDir}/processed_data/${sub}"
workDir="${subDir}/dwi/preprocessed"
need_dir "${workDir}"
cd "${workDir}"

# ------------------------------ file naming --------------------------------
# Input DWI (after pre-synb0 denoise/degibbs)
unr_data="${sub}_acq-AP_dwi_den_degibbs.mif"

# A copy with phase-encode + index imported (for eddy)
unr_in_data="${sub}_acq-AP_dwi_den_degibbs_in.mif"

# Synthesized undistorted b0 (from Synb0-DISCO)
# NOTE: confirm this filename matches YOUR Synb0-DISCO output.
synb0_nii="${sub}_acq-AP_dwi_synb0_all_out.nii.gz"
synb0_data="${sub}_acq-AP_dwi_synb0_all_out.mif"

# Gradients + eddy config
bvec_data="${sub}_acq-AP_dwi.bvec"
bval_data="${sub}_acq-AP_dwi.bval"
acqparams_data="${sub}_acq-AP_dwi_acqparams.txt"
eddy_inds_data="${topDir}/scripts/eddy_indices.txt"

# Outputs
preproc_data="${sub}_acq-AP_dwi_den_degibbs_synb0_preproc.mif"

unbiased_prefix="${sub}_acq-AP_dwi_den_degibbs_synb0_preproc_unbiased"
bias_prefix="${sub}_acq-AP_dwi_den_degibbs_synb0_preproc_bias"
mask_prefix="${sub}_acq-AP_dwi_mask_unbiased"

# Eddy QC output directory (optional but recommended)
eddy_qcDir="${eddy_qcDir:-${subDir}/eddyqc_synb0}"
mkdir -p "${eddy_qcDir}"

# ------------------------------ sanity checks ------------------------------
need_file "${unr_data}"
need_file "${synb0_nii}"
need_file "${bvec_data}"
need_file "${bval_data}"
need_file "${acqparams_data}"
need_file "${eddy_inds_data}"

if [[ "${USE_S2V}" -eq 1 ]]; then
  need_file "${SLSPEC_FILE}"
fi

# ------------------------------ conversion ---------------------------------
# Import PE table into Synb0 b0 (so dwifslpreproc knows its PE)
# Import eddy PE/index info into DWI
#
# NOTE: Strides are kept from your original script. Adjust if needed for your setup.
printf '%s\nImporting PE/index tables and converting Synb0 b0 to .mif...\n' "$sep"
mrconvert "${synb0_nii}" "${synb0_data}" \
  -import_pe_table "${acqparams_data}" \
  -strides '-1,+2,+3,+4'

printf '%s\nPreparing DWI input with -import_pe_eddy...\n' "$sep"
mrconvert "${unr_data}" "${unr_in_data}" \
  -import_pe_eddy "${acqparams_data}" "${eddy_inds_data}" \
  -strides '-1,+2,+3,+4'

# -------------------- motion + distortion correction ------------------------
printf '%s\nRunning dwifslpreproc (using Synb0-DISCO synthesized undistorted b0)...\n' "$sep"

dwifslpreproc "${unr_in_data}" "${preproc_data}" \
  -rpe_header \
  -se_epi "${synb0_data}" \
  -fslgrad "${bvec_data}" "${bval_data}" \
  -align_seepi \
  -eddyqc_all "${eddy_qcDir}" \
  -eddy_options " ${EDDY_OPTIONS} " \
  -nthreads "${NTHREADS}" \
  $( [[ "${USE_S2V}" -eq 1 ]] && printf '%s' "-eddy_slspec ${SLSPEC_FILE}" ) \
  -force

# If you want true slice-to-volume correction, you typically also add eddy options like:
#   --mporder=<N> --s2v_niter=<N> --s2v_lambda=<...> --s2v_interp=<...>
# You can pass these via EDDY_OPTIONS. Example:
#   EDDY_OPTIONS="--slm=linear --repol --cnr_maps --data_is_shelled --mporder=6 --s2v_niter=5 --s2v_lambda=1 --s2v_interp=trilinear"
# and set USE_S2V=1 plus SLSPEC_FILE.

# -------------------------- bias correction + mask --------------------------
if [[ "${CORRECT_BIAS}" -eq 1 ]]; then
  printf '%s\nCorrecting bias field and creating brain mask...\n' "$sep"

  [[ "${n_iter}" -ge 1 ]] || die "n_iter must be >= 1 (got ${n_iter})"

  # Iteration 1
  if [[ ! -f "${unbiased_prefix}_1.mif" ]]; then
    dwibiascorrect ants "${preproc_data}" "${unbiased_prefix}_1.mif" \
      -bias "${bias_prefix}_1.mif" \
      -fslgrad "${bvec_data}" "${bval_data}"

    mrconvert "${unbiased_prefix}_1.mif" "${unbiased_prefix}_1.nii.gz"
    bet "${unbiased_prefix}_1.nii.gz" "${unbiased_prefix}_1" -m -n -f 0.2
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
          -fslgrad "${bvec_data}" "${bval_data}"

        mrconvert "${unbiased_prefix}_${i}.mif" "${unbiased_prefix}_${i}.nii.gz"
        bet "${unbiased_prefix}_${i}.nii.gz" "${unbiased_prefix}_${i}" -m -n -f 0.2
        mrconvert "${unbiased_prefix}_${i}_mask.nii.gz" "${mask_prefix}_${i}.mif"
        rm -f "${unbiased_prefix}_${i}.nii.gz" "${unbiased_prefix}_${i}_mask.nii.gz"
      fi
    done
  fi
fi

printf "%s\nDone.\n" "$sep"
cd ~
