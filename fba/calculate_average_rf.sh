#!/usr/bin/env bash
# calculate_average_rf.sh
#
# Calculate group-averaged response functions for subsequent fixel-based analysis (multi-tissue pipeline).
#
# Reference:
#   https://mrtrix.readthedocs.io/en/3.0.2/fixel_based_analysis/mt_fibre_density_cross-section.html#
#
# Prerequisites:
#   - Subject-level response functions already estimated (e.g., via dwi2response dhollander)
#   - MRtrix3 on PATH (responsemean)
#
# Created by Idy Chou on 30 Sep 2024

# ----------------------------- user parameters ------------------------------
topDir="/path/to/processed_data"
outDir="${topDir}"

rf_algorithm="dhollander"
sub_prefix="sub-"

# Response function locations (relative to subject dir):
#   ${sub}/dwi/fod/${rf_algorithm}/..._wm.txt
#   ${sub}/dwi/fod/${rf_algorithm}/..._gm.txt
#   ${sub}/dwi/fod/${rf_algorithm}/..._csf.txt
# ---------------------------------------------------------------------------

sep="--------------------------------------------------------"

die() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Command not found on PATH: $1"; }

need_cmd responsemean

[ -d "${outDir}" ] || die "outDir does not exist: ${outDir}"

grp_wm_file="${outDir}/group_average_response_wm_${rf_algorithm}.txt"
grp_gm_file="${outDir}/group_average_response_gm_${rf_algorithm}.txt"
grp_csf_file="${outDir}/group_average_response_csf_${rf_algorithm}.txt"

cd "${outDir}"

printf "%s\nCalculating group average response functions...\n%s\n" "${sep}" "${sep}"

wm_inputs=( "${sub_prefix}"*/dwi/fod/"${rf_algorithm}"/*wm.txt )
gm_inputs=( "${sub_prefix}"*/dwi/fod/"${rf_algorithm}"/*gm.txt )
csf_inputs=( "${sub_prefix}"*/dwi/fod/"${rf_algorithm}"/*csf.txt )

# Basic checks to avoid passing literal globs to responsemean
[ -e "${wm_inputs[0]}" ] || die "No WM response files found at: ${sub_prefix}*/dwi/fod/${rf_algorithm}/*wm.txt"
[ -e "${gm_inputs[0]}" ] || die "No GM response files found at: ${sub_prefix}*/dwi/fod/${rf_algorithm}/*gm.txt"
[ -e "${csf_inputs[0]}" ] || die "No CSF response files found at: ${sub_prefix}*/dwi/fod/${rf_algorithm}/*csf.txt"

printf "White matter...\n"
responsemean "${wm_inputs[@]}" "${grp_wm_file}"

printf "Grey matter...\n"
responsemean "${gm_inputs[@]}" "${grp_gm_file}"

printf "CSF...\n"
responsemean "${csf_inputs[@]}" "${grp_csf_file}"

printf "Done.\n"
cd ~
