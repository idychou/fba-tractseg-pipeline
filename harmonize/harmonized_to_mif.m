%% harmonize_to_mif.m
%
% Convert ComBat-harmonized metric matrices (features x subjects) back to
% individual MRtrix .mif images per subject.
%
% Reference:
%   https://github.com/Jfortin1/ComBatHarmonization
%
% Prerequisites:
%   - MRtrix3 MATLAB utilities on the MATLAB path (read_mrtrix, write_mrtrix)
%   - Original subject metric .mif files (used here as a header/template)
%   - Harmonized metric matrices written as tab-delimited text, e.g.:
%       <matrixDir>/<metric>_matrix_harmonized.txt
%     where rows = features, columns = subjects (in the same order as subject list).
%
% Author:
%   Created by Idy Chou on 22 Nov 2024

clear; clc;

%% ----------------------- User-configurable parameters -----------------------
topDir = "/path/to/processed_data";  % EDIT ME

matrixDir = fullfile(topDir, "combat");

% Subject list file (one subject ID per line; e.g., "001", "002", ...)
% Script will prepend "sub-" below.
subjectListFile = fullfile(topDir, "subject_list.txt"); % EDIT ME

subPrefix = "sub-";

% Metrics to convert back to .mif
metrics = ["fdc"]; % e.g., ["fd","log_fc","fdc"]

% Original metric .mif naming convention (used as template header)
% Expected: <metricDir>/<subID><inputSuffix>
inputSuffix = "_PRE.mif";

% Safety: expected number of features in the matrix (rows)
% Set [] to skip this check.
expectedNFeatures = 849637;

% Output: create <metric>_harmonized folder next to original metric folder
outputSuffixDir = "_harmonized";

% Data cleaning options
clipNegativesToZero = true;
%% ---------------------------------------------------------------------------

sep = repmat("-", 1, 55);

%% ------------------------------ Setup & checks ------------------------------
if ~isfolder(topDir)
    error("topDir does not exist: %s", topDir);
end
if ~isfolder(matrixDir)
    error("matrixDir does not exist: %s", matrixDir);
end
if ~isfile(subjectListFile)
    error("subjectListFile does not exist: %s", subjectListFile);
end

if exist("read_mrtrix", "file") ~= 2 || exist("write_mrtrix", "file") ~= 2
    error("MRtrix MATLAB utilities not found on path (read_mrtrix/write_mrtrix). Add mrtrix3/matlab/ to MATLAB path.");
end

% Read subject list (expects one ID per line, no header)
subTable = readtable(subjectListFile, "ReadVariableNames", false, "TextType", "string");
subIDsRaw = subTable{:, 1};
subIDsRaw = string(subIDsRaw);
subIDsRaw = strip(subIDsRaw);

% Build full subject IDs (e.g., sub-001)
subIDs = subPrefix + subIDsRaw;
nSub = numel(subIDs);

if nSub == 0
    error("No subjects found in subject list file: %s", subjectListFile);
end

fprintf("%s\nFound %d subject(s) in list.\n%s\n", sep, nSub, sep);
%% ---------------------------------------------------------------------------

%% ------------------------------- Main loop ---------------------------------
for iMetric = 1:numel(metrics)
    metric = metrics(iMetric);

    % Input directories
    metricDir = fullfile(topDir, "template", "fba", sprintf("%s", metric));
    if ~isfolder(metricDir)
        error("Metric directory not found: %s", metricDir);
    end

    % Output directory
    outDir = fullfile(topDir, "template", "fba", sprintf("%s%s", metric, outputSuffixDir));
    if ~isfolder(outDir)
        mkdir(outDir);
    end

    % Harmonized matrix file
    matrixFile = fullfile(matrixDir, sprintf("%s_matrix_harmonized.txt", metric));
    if ~isfile(matrixFile)
        error("Harmonized matrix file not found: %s", matrixFile);
    end

    fprintf("\n%s\nReading harmonized %s matrix...\n%s\n", sep, metric, sep);

    % Read harmonized matrix (no headers expected)
    metricTable = readtable(matrixFile, ...
        "FileType", "text", ...
        "Delimiter", "\t", ...
        "ReadVariableNames", false);

    nFeatures = size(metricTable, 1);
    nCols = size(metricTable, 2);

    % Validate sizes
    if ~isempty(expectedNFeatures) && nFeatures ~= expectedNFeatures
        error("Unexpected number of features for metric %s. Expected %d, got %d.", metric, expectedNFeatures, nFeatures);
    end
    if nCols ~= nSub
        error("Column mismatch for metric %s: matrix has %d columns but subject list has %d IDs.", metric, nCols, nSub);
    end

    fprintf("Matrix size: %d features x %d subjects\n", nFeatures, nCols);
    fprintf("Writing %s MIF files to: %s\n", metric, outDir);

    % Loop through subjects/columns
    for j = 1:nSub
        subID = subIDs(j);

        inMif = fullfile(metricDir, subID + inputSuffix);
        if ~isfile(inMif)
            error("Template MIF not found for subject %s: %s", subID, inMif);
        end

        % Read original .mif as template (header/transform, etc.)
        mr = read_mrtrix(inMif);

        % Extract column j from harmonized matrix
        vec = table2array(metricTable(:, j));
        vec = vec(:);

        if numel(vec) ~= numel(mr.data(:))
            error("Vector length mismatch for %s (%s). Matrix column has %d values; template MIF has %d.", ...
                subID, metric, numel(vec), numel(mr.data(:)));
        end

        if clipNegativesToZero
            vec(vec < 0) = 0;
        end

        % Assign harmonized data back into MRtrix structure
        mr.data = reshape(vec, size(mr.data));

        % Write out harmonized .mif
        outMif = fullfile(outDir, subID + inputSuffix);
        write_mrtrix(mr, outMif);

        % Progress output (compact)
        if mod(j, 10) == 0 || j == nSub
            fprintf("  [%d/%d] %s\n", j, nSub, subID);
        end
    end
end

fprintf("\nDone.\n");
%% ---------------------------------------------------------------------------
