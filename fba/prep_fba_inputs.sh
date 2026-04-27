#!/usr/bin/env bash
# prepare_fba_inputs.sh
#
# Prepare inputs for fixel-based analysis (multi-tissue CSD pipeline):
#   - Create template fixel mask from the FOD template
#   - Warp subject WM FODs to template space (without reorientation)
#   - Segment FODs into fixels and compute Fibre Density (FD; AFD per fixel)
#   - Reorient fixels using the subject->template warp
#   - Map subject fixel-wise FD onto the common template fixels (fixelcorrespondence)
#
# Reference:
#   https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/mt_fibre_density_cross-section.html#
#
# Prerequisites:
#   - Template already built: template/wm_fod_template.mif and template/template_mask.mif
#   - Subject warps already computed: <sub>_subject2template_warp.mif
#   - Subject WM FODs (normalised) already computed: <sub>_wm_fod_norm.mif
#   - MRtrix3 on PATH
#
# Created by Idy Chou on 12 Nov 2024

# ----------------------------- user parameters ------------------------------
topDir="/path/to/processed_data"
outDir="${topDir}"
templateDir="${topDir}/template"

subject_prefix="sub-" 
rf_algorithm="dhollander"
fod_algorithm="ss3t"

fmls_peak_value="0.06"
# ---------------------------------------------------------------------------

sep="-----------------------------------------------------------------------------"

# Create output dirs
mkdir -p "${templateDir}/fd"

# Template inputs
grp_wm_template="${templateDir}/wm_fod_template.mif"
grp_template_mask="${templateDir}/template_mask.mif"
fixelDir="${templateDir}/fixel_mask"

# Compute white matter template analysis fixel mask (template fixels)
cd "${topDir}"
if [ ! -d "${fixelDir}" ]; then
  printf "%s\nComputing group fixel mask...\n%s\n" "${sep}" "${sep}"
  fod2fixel -mask "${grp_template_mask}" -fmls_peak_value "${fmls_peak_value}" "${grp_wm_template}" "${fixelDir}"
  printf "\nDone.\n\n"
fi

# Loop over subjects
cd "${topDir}"
for sub in ${subject_prefix}*; do
  [ -d "${sub}" ] || continue

  printf "%s\n%s\n%s\n" "${sep}" "${sub}" "${sep}"

  # Subject inputs
  wm_fod_norm_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_wm_fod_norm.mif"
  sub2templ_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_subject2template_warp.mif"

  # Subject outputs / intermediates
  fod_in_template_nro_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_fod_in_template_space_NOT_REORIENTED.mif"
  fixel_in_template_nro_dir="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_fixel_in_template_space_NOT_REORIENTED"
  fixel_in_template_dir="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_fixel_in_template_space"

  subj_fd_file="${fixel_in_template_nro_dir}/${sub}_fd.mif"
  mapped_fd_file="${templateDir}/fd/${sub}_PRE.mif"

  # Warp FOD images to template space (no FOD reorientation)
  if [ ! -f "${fod_in_template_nro_file}" ]; then
    printf "\nWarping FOD images to template space...\n"
    mrtransform "${wm_fod_norm_file}" \
      -warp "${sub2templ_file}" \
      -reorient_fod no \
      "${fod_in_template_nro_file}"
  fi

  # Segment FOD images to estimate fixels and FD (AFD per fixel)
  if [ ! -f "${subj_fd_file}" ]; then
    printf "\nSegmenting FOD images to estimate fixels and their fibre density (FD)...\n"
    mkdir -p "${fixel_in_template_nro_dir}"
    fod2fixel -mask "${grp_template_mask}" \
      "${fod_in_template_nro_file}" \
      "${fixel_in_template_nro_dir}" \
      -afd "${sub}_fd.mif"
  fi

  # Reorient fixels (uses warp field)
  if [ ! -d "${fixel_in_template_dir}" ]; then
    printf "\nReorienting fixels...\n"
    fixelreorient "${fixel_in_template_nro_dir}" "${sub2templ_file}" "${fixel_in_template_dir}"
  fi

  # Assign subject fixels to template fixels (store FD in template fixel space)
  if [ ! -f "${mapped_fd_file}" ]; then
    printf "\nAssigning subject fixels to template fixels...\n"
    fixelcorrespondence \
      "${subj_fd_file}" \
      "${fixelDir}" \
      "${templateDir}/fd" \
      "${sub}_PRE.mif"
  fi
done

printf "%s\nDone.\n" "${sep}"
cd ~
