# This script calculates total readout time for Philips MRI. Effective echo spacing is calculated based on water-fat shift, echo train length, and acceleration. Total readout time is calculated based on the derived effective echo spacing and reconstruction matrix along PE. Note that the BIDS specification formula is chosen.(Reference: https://neurostars.org/t/consolidating-epi-echo-spacing-and-readout-time-for-philips-scanner/4406)
# Created by Idy Chou on 29th Feb, 2024

## Formulae
### EffectiveEchoSpacing = (1000 * WFS)/(434.215 * (ETL+1))/acceleration					(OSF formula)
### ActualEchoSpacing = WaterFatShift / (ImagingFrequency * 3.4 * (EPI_Factor + 1))
### EffectiveEchoSpacing = TotalReadoutTime / (ReconMatrixPE - 1)
### TotalReadoutTime = EffectiveEchoSpacing * (ReconMatrixPE - 1) 							(BIDS specification)***
### Other formulae:
### TotalReadoutTime = ActualEchoSpacing * EPI_Factor										(TOPUP FAQ formula)
### TotalReadoutTime = ActualEchoSpacing * (EPI_Factor - 1)								(FSL forum formula)
## DICOM tags
### WaterFatShift = 2001,1022
### ImagingFrequency = 0018,0084
### EPI_Factor = 0018,0091 or 2001,1013
### ReconMatrixPE = 0028,0010 or 0028,0011 depending on 0018,1312

# Import packages
import sys
import pydicom

# Path to the DICOM file
dicom_file = sys.argv[1]
wfs_tag = "2001,1022"			# WaterFatShift
etl_tag = "0018,0091"			# EchoTrainLength
rpe_tag = "0018,1312"			# Phase encoding direction
row_tag = "0028,0010"			# Reconstruction Matrix in ROW
col_tag = "0028,0010"			# Reconstruction Matrix in COL
accl_f = float(sys.argv[2])			# Acceleration Factor

# # Convert the tag argument to a tuple of integers
wfs_tag = tuple(int(x, 16) for x in wfs_tag.split(','))
etl_tag = tuple(int(x, 16) for x in etl_tag.split(','))
rpe_tag = tuple(int(x, 16) for x in rpe_tag.split(','))
row_tag = tuple(int(x, 16) for x in row_tag.split(','))
col_tag = tuple(int(x, 16) for x in col_tag.split(','))

# Read the DICOM file
ds = pydicom.dcmread(dicom_file)

# Extract the value of the DICOM tags
wfs = ds[wfs_tag].value
etl = ds[etl_tag].value
rpe = ds[rpe_tag].value
## Choose the correct reconstruction matrix direction
if rpe == "ROW":
	dim = ds[row_tag].value
elif rpe == "COL":
	dim = ds[col_tag].value
else:
	dim = ds[col_tag].value			# Default: PE = COL

# Calculate total readout time
ees = (1000*wfs)/(434.215*etl)/accl_f			# EffectiveEchoSpacing
trt = ees*(dim-1)/1000							# TotalReadOutTime in sec

# Print the value to stdout
print(trt)

