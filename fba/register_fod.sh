#!/usr/bin/env bash
# register_fod.sh
#
# Generate a study-specific FOD template, register each subject to the template,
# and create masks in template space.
#
# Reference:
#   https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/mt_fibre_density_cross-section.html#
#
# Prerequisites:
#   - Subject FOD images already generated (e.g., wmfod_norm.mif per subject)
#   - Subject upsampled DWI masks already generated (e.g., dwi_mask_upsampled.mif per subject)
#   - MRtrix3 on PATH (population_template, mrregister, mrtransform, mrmath)
#
# Options:
#   SUBSET:
#     1 = build template from subjects listed in subset_file
#     0 = build template from all subjects matching sub_prefix
#
# Created by Idy Chou on 8 Oct 2024

# ----------------------------- user parameters ------------------------------
topDir="/path/to/processed_data"
outDir="${topDir}"
templateDir="${topDir}/template"

sub_prefix="sub-"
rf_algorithm="dhollander"
fod_algorithm="ss3t"

SUBSET=1
subset_file="path/to/subset/list"

template_voxel_size="1.25"
# ---------------------------------------------------------------------------

sep="-----------------------------------------------------------------------------"

die() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Command not found on PATH: $1"; }

need_cmd population_template
need_cmd mrregister
need_cmd mrtransform
need_cmd mrmath

[ -d "${topDir}" ] || die "topDir does not exist: ${topDir}"
mkdir -p "${outDir}"
mkdir -p "${templateDir}/fod_input" "${templateDir}/mask_input"

grp_wm_template="${templateDir}/wm_fod_template.mif"
grp_template_mask="${templateDir}/template_mask.mif"

# ---------------------- generate FOD template inputs ------------------------
printf "%s\nGenerating study specific unbiased FOD template...\n%s\n" "${sep}" "${sep}"
printf "Creating symbolic links of template inputs...\n"

# Clean previous links (avoid mixing runs)
rm -f "${templateDir}/fod_input/"*.mif "${templateDir}/mask_input/"*.mif 2>/dev/null || true

cd "${topDir}"

if [ "${SUBSET}" -eq 1 ]; then
  [ -f "${subset_file}" ] || die "subset_file not found: ${subset_file}"
  subjects="$(grep -v '^[[:space:]]*$' "${subset_file}" | grep -v '^[[:space:]]*#' || true)"
else
  subjects="$(ls -1 "${topDir}" | grep -E "^${sub_prefix}" || true)"
fi

[ -n "${subjects}" ] || die "No subjects found for template generation."

while IFS= read -r sub; do
  [ -n "${sub}" ] || continue

  wm_fod_norm_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_wm_fod_norm.mif"

  # Mask path used in earlier scripts:
  #   ${sub}/dwi/preprocessed/${sub}_..._mask_unbiased_1_upsampled.mif
  # Keep wildcard support but resolve to exactly one file.
  mask_candidates=( "${outDir}/${sub}/dwi/preprocessed/${sub}_acq-"*"_dwi_mask_unbiased_1_upsampled.mif" )
  if [ ! -e "${mask_candidates[0]}" ]; then
    die "No upsampled mask found for ${sub} at: ${outDir}/${sub}/dwi/preprocessed/${sub}_acq-*_dwi_mask_unbiased_1_upsampled.mif"
  fi
  if [ "${#mask_candidates[@]}" -ne 1 ]; then
    die "Multiple masks match for ${sub}. Please disambiguate: ${mask_candidates[*]}"
  fi
  ups_mask_file="${mask_candidates[0]}"

  [ -f "${wm_fod_norm_file}" ] || die "Missing WM FOD (norm) for ${sub}: ${wm_fod_norm_file}"
  [ -f "${ups_mask_file}" ] || die "Missing mask for ${sub}: ${ups_mask_file}"

  ln -s "${wm_fod_norm_file}" "${templateDir}/fod_input/${sub}_PRE.mif"
  ln -s "${ups_mask_file}" "${templateDir}/mask_input/${sub}_PRE.mif"
done <<< "${subjects}"

# ----------------------------- build template -------------------------------
printf "Building FOD template...\n"
population_template \
  "${templateDir}/fod_input" \
  -mask_dir "${templateDir}/mask_input" \
  "${grp_wm_template}" \
  -voxel_size "${template_voxel_size}"

# ----------------------- register subjects to template ----------------------
printf "%s\nRegistering subject FOD images to FOD template...\n%s\n" "${sep}" "${sep}"

all_subjects="$(ls -1 "${topDir}" | grep -E "^${sub_prefix}" || true)"
[ -n "${all_subjects}" ] || die "No subjects found for registration (prefix: ${sub_prefix})."

while IFS= read -r sub; do
  [ -n "${sub}" ] || continue
  printf "%s...\n" "${sub}"

  wm_fod_norm_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_wm_fod_norm.mif"

  mask_candidates=( "${outDir}/${sub}/dwi/preprocessed/${sub}_acq-"*"_dwi_mask_unbiased_1_upsampled.mif" )
  if [ ! -e "${mask_candidates[0]}" ]; then
    die "No upsampled mask found for ${sub} (registration)."
  fi
  if [ "${#mask_candidates[@]}" -ne 1 ]; then
    die "Multiple masks match for ${sub} (registration). Please disambiguate: ${mask_candidates[*]}"
  fi
  ups_mask_file="${mask_candidates[0]}"

  sub2templ_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_subject2template_warp.mif"
  templ2sub_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_template2subject_warp.mif"

  [ -f "${wm_fod_norm_file}" ] || die "Missing WM FOD (norm) for ${sub}: ${wm_fod_norm_file}"
  [ -f "${ups_mask_file}" ] || die "Missing mask for ${sub}: ${ups_mask_file}"
  [ -f "${grp_wm_template}" ] || die "Missing template: ${grp_wm_template}"

  mrregister \
    "${wm_fod_norm_file}" \
    -mask1 "${ups_mask_file}" \
    "${grp_wm_template}" \
    -nl_warp "${sub2templ_file}" "${templ2sub_file}"

  printf "done\n"
done <<< "${all_subjects}"

# -------------------- warp masks + compute intersection ---------------------
printf "%s\nComputing template mask (intersection of all subject masks in template space)...\n%s\n" "${sep}" "${sep}"
printf "Warping subject masks into template space...\n"

warped_masks=()

while IFS= read -r sub; do
  [ -n "${sub}" ] || continue
  printf "\t%s...\n" "${sub}"

  mask_candidates=( "${outDir}/${sub}/dwi/preprocessed/${sub}_acq-"*"_dwi_mask_unbiased_1_upsampled.mif" )
  if [ ! -e "${mask_candidates[0]}" ]; then
    die "No upsampled mask found for ${sub} (mask warping)."
  fi
  if [ "${#mask_candidates[@]}" -ne 1 ]; then
    die "Multiple masks match for ${sub} (mask warping). Please disambiguate: ${mask_candidates[*]}"
  fi
  ups_mask_file="${mask_candidates[0]}"

  sub2templ_file="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_subject2template_warp.mif"
  sub2templ_mask="${outDir}/${sub}/dwi/fod/${rf_algorithm}/${fod_algorithm}/${sub}_dwi_mask_in_template_space.mif"

  [ -f "${ups_mask_file}" ] || die "Missing mask for ${sub}: ${ups_mask_file}"
  [ -f "${sub2templ_file}" ] || die "Missing warp for ${sub}: ${sub2templ_file}"

  mrtransform \
    "${ups_mask_file}" \
    -warp "${sub2templ_file}" \
    -interp nearest \
    -datatype bit \
    "${sub2templ_mask}"

  warped_masks+=( "${sub2templ_mask}" )
  printf "done\n"
done <<< "${all_subjects}"

printf "Computing template mask...\n"
[ "${#warped_masks[@]}" -ge 1 ] || die "No warped masks were generated."
mrmath "${warped_masks[@]}" min "${grp_template_mask}" -datatype bit

printf "%s\nDone.\n" "${sep}"
cd ~
