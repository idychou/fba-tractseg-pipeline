#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# preprocess_single_pe_presynb0.sh
#
# Single-PE DWI "pre-Synb0" preprocessing:
#   - Convert raw DWI NIfTI -> MIF
#   - Denoise (dwidenoise) + residuals
#   - Remove Gibbs ringing (mrdegibbs) + residuals
#   - Extract mean b=0
#   - Convert outputs to NIfTI and stage files for Synb0-DISCO
#
# IMPORTANT NOTE (pipeline intent)
#   The outputs staged into ${synb0Dir}/raw_data/${sub}/... are meant to be used
#   as inputs to Synb0-DISCO (synb0-DISCO) to synthesize an *undistorted* b=0
#   image. That synthesized undistorted b=0 should then be supplied to FSL eddy
#   (or MRtrix3 dwifslpreproc) to improve eddy-current + motion + susceptibility
#   distortion correction when only a single phase-encoding DWI is available.
#   Please refer to the Github repository of Synb0-DISCO for instructions and
#   scripts needed to run the program: https://github.com/MASILab/Synb0-DISCO.git
#
# Slice-to-volume motion correction note (slspec)
#   If you plan to run eddy with within-volume motion correction (--mporder),
#   you must provide a slice specification ("slspec") file. A slspec file lists
#   slice indices (0-based) in acquisition order; for multiband, simultaneously
#   acquired slices are listed side-by-side on the same row.
#   (Reference described in: https://note.com/brain_surfing2/n/na635e2b1f6bf)
#
# Original script: Idy Chou (2024-03-01)
# Edited: removed Singularity requirement (this script only *stages inputs* for
# Synb0-DISCO; running Synb0-DISCO can be done via container or native install).
# -----------------------------------------------------------------------------

# ------------------------------- configuration ------------------------------

# Required positional arg
sub="subject_id"	#SUBSTITUTE
if [[ -z "${sub}" ]]; then
  echo "Usage: $(basename "$0") <sub-id>" >&2
  exit 2
fi

# User-editable paths (prefer env vars so this script is portable)
topDir="path/to/study/directory"
dcmDir="path/to/raw/dcm/directory"
synb0Dir="path/to/Synb0-DISCO-master"   # staging dir for Synb0-DISCO inputs
cal_TRT_Script="/path/to/calculate_TotalReadoutTime.py"

# Acquisition parameter for your TRT calculator
acceleration_factor="2.5"

# slspec (only needed later if you run eddy with --mporder / slice-to-volume)
slspec_data="path/to/slspec.txt}"  # ref: note.com article

# ------------------------------- helpers -----------------------------------

sep='---------------------------------------------------'
die(){ echo "ERROR: $*" >&2; exit 1; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Command not found on PATH: $1"; }
need_file(){ [[ -f "$1" ]] || die "Missing file: $1"; }
need_dir(){ [[ -d "$1" ]] || die "Missing directory: $1"; }

printf '%s\nPreprocessing data of subject %s (Pre-Synb0)\n%s\n' "$sep" "$sub" "$sep"

# Require core MRtrix commands
need_cmd mrconvert
need_cmd dwidenoise
need_cmd mrcalc
need_cmd mrdegibbs
need_cmd dwiextract
need_cmd mrmath
need_cmd python3

# ----------------------------- directories ----------------------------------

subDir="${topDir}/processed_data/${sub}"

# Copy files if not exist
if [[ ! -d "${subDir}" ]]; then
  printf '%s\ncopying files...\n' "$sep"
  mkdir -p "${topDir}/processed_data"
  cp -r "${topDir}/raw_data/${sub}" "${topDir}/processed_data" \
    || die "Failed copying ${topDir}/raw_data/${sub} -> ${topDir}/processed_data"
fi

need_dir "${subDir}/dwi"
need_dir "${subDir}/anat"

cd "${subDir}/dwi"

# ------------------------------ file naming --------------------------------
# AP (single PE)
ap_raw_nii="${sub}_acq-AP_dwi.nii"
ap_raw_data="${sub}_acq-AP_dwi.mif"
ap_den_data="${sub}_acq-AP_dwi_den.mif"
ap_noise_data="${sub}_acq-AP_dwi_noise.mif"
ap_residual_data="${sub}_acq-AP_dwi_residual.mif"
ap_unr_data="${sub}_acq-AP_dwi_den_degibbs.mif"
ap_unr_residual_data="${sub}_acq-AP_dwi_residualUnringed.mif"
ap_bvec_data="${sub}_acq-AP_dwi.bvec"
ap_bval_data="${sub}_acq-AP_dwi.bval"
ap_mean_b0_data="${sub}_acq-AP_dwi_den_degibbs_meanb0.mif"
ap_unr_nii="${sub}_acq-AP_dwi_den_degibbs.nii.gz"
ap_mean_b0_nii="${sub}_acq-AP_dwi_den_degibbs_meanb0.nii.gz"

# Other
json_file="${sub}_acq-AP_dwi.json"          # kept for completeness (not parsed here)
acqparams_data="${sub}_acq-AP_dwi_acqparams.txt"
eddy_indices_local="eddy_indices.txt"       # will be created in ${topDir}/scripts like original

# ------------------------------ sanity checks ------------------------------
need_file "${ap_raw_nii}"
need_file "${ap_bvec_data}"
need_file "${ap_bval_data}"
need_file "${json_file}"
need_file "${cal_TRT_Script}"
need_file "${slspec_data}"
need_file "${subDir}/anat/${sub}_T1w.nii"

# ----------------------- locate representative DICOM ------------------------
# (Used by your calculate_totalReadoutTime.py script)
dcm_data="${dcmDir}/${sub#sub-}/DTI_high_iso_E SENSE" 

[[ -n "${dcm_data}" ]] || die "Could not find a representative DICOM file for ${sub} under ${dcmDir}"

# ------------------------------ preprocessing ------------------------------

## Convert data
printf '%s\nconverting data...\n' "$sep"
mrconvert "${ap_raw_nii}" "${ap_raw_data}"

## Denoise
printf '%s\ndenoising...\n' "$sep"
dwidenoise "${ap_raw_data}" "${ap_den_data}" -noise "${ap_noise_data}"
mrcalc "${ap_raw_data}" "${ap_den_data}" -subtract "${ap_residual_data}"

## Unring (degibbs)
printf '%s\nunringing...\n' "$sep"
mrdegibbs "${ap_den_data}" "${ap_unr_data}" -axes 0,1
mrcalc "${ap_den_data}" "${ap_unr_data}" -subtract "${ap_unr_residual_data}"

## Calculate TotalReadoutTime (via your python script)
printf '%s\ncalculating TotalReadoutTime...\n' "$sep"
TotalReadoutTime="$(python3 "${cal_TRT_Script}" "${dcm_data}" "${acceleration_factor}")"
[[ -n "${TotalReadoutTime}" ]] || die "TotalReadoutTime calculation returned empty"
printf "TotalReadoutTime = %s\n" "${TotalReadoutTime}"

## Create acqparams.txt and eddy_indices.txt
# acqparams: for a single-PE dataset, you typically still provide one line that
# matches your PE direction and TRT. Original script wrote 2 lines; keep it but
# note the second line "0 1 0 0" is likely a placeholder and may be wrong for
# your acquisition—edit if needed.
printf '%s\nwriting acqparams / indices...\n' "$sep"
printf "0 -1 0 %s\n0 1 0 0\n" "${TotalReadoutTime}" > "${subDir}/dwi/${acqparams_data}"

# Index file: original script hard-coded 33 volumes. Keep behavior but make it configurable.
nvols="${nvols:-33}"
mkdir -p "${topDir}/scripts"
python3 - <<PY > "${topDir}/scripts/${eddy_indices_local}"
n=${nvols}
print(" ".join(["1"]*n))
PY

## Extract mean b0 image
printf '%s\nextracting mean b0...\n' "$sep"
dwiextract -fslgrad "${ap_bvec_data}" "${ap_bval_data}" "${ap_unr_data}" - -bzero \
  | mrmath - mean "${ap_mean_b0_data}" -axis 3

## Convert data to NIfTI (gz)
printf '%s\nconverting data to NIfTI...\n' "$sep"
mrconvert "${ap_unr_data}" "${ap_unr_nii}"
mrconvert "${ap_mean_b0_data}" "${ap_mean_b0_nii}"

# ----------------------------- stage for Synb0 ------------------------------

printf '%s\nstaging files for Synb0-DISCO...\n' "$sep"

mkdir -p "${synb0Dir}/raw_data/${sub}/anat" "${synb0Dir}/raw_data/${sub}/dwi"

cp "${topDir}/scripts/${eddy_indices_local}"
