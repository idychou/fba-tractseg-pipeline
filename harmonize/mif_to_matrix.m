% Convert FBA metric maps (e.g., FD) from MRtrix images to a study-wise matrix
% (features x subjects) for ComBat harmonization.
%
% This script reads per-subject metric files and writes a tab-delimited text
% matrix per metric, ready to be used as input for ComBat.
%
% Reference:
%
%  	https://github.com/Jfortin1/ComBatHarmonization
%
% Prerequisites:
%   - MRtrix3 MATLAB utilities on the MATLAB path (e.g., read_mrtrix)
%   - FBA metric maps exported per subject (e.g., *_PRE.mif)
%
% Author:
%   Created by Idy Chou on 22 Nov 2024
%

clear; clc;

%% ----------------------- User-configurable parameters -----------------------
% Project root directory (edit this)
topDir = "/path/to/project_directory";

% Output directory
outDir = fullfile(topDir, "combat");

% Subject folder/file prefix used to identify subjects under topDir
subPrefix = "sub-";

% Metrics to process (folder naming convention: <metric>_smooth)
fbaMetrics = ["fd", "log_fc", "fdc"];

% Expected number of features (rows) per metric map after vectorization
% (Adjust to your template mask / fixel count / vector length.)
nCells = 849637;

% Input filename suffix/pattern (edit if your naming differs)
% Expected input: <metricDir>/<subID>_PRE.mif
inputSuffix = "_PRE.mif";

% Output format
outputDelimiter = "\t";
writeVariableNames = false;
% ---------------------------------------------------------------------------

%% ------------------------------ Setup & checks ------------------------------
if ~isfolder(topDir)
    error("topDir does not exist: %s", topDir);
end

if ~isfolder(outDir)
    mkdir(outDir);
end

sep = repmat("-", 1, 55);

% List subjects
subEntries = dir(fullfile(topDir, subPrefix + "*"));
subEntries = subEntries([subEntries.isdir]); % keep folders only, if applicable
nSub = numel(subEntries);

if nSub == 0
    error("No subjects found with prefix '%s' under: %s", subPrefix, topDir);
end

fprintf("%s\nFound %d subject(s).\n%s\n", sep, nSub, sep);

% Confirm MRtrix reader exists
if exist("read_mrtrix", "file") ~= 2
    error("read_mrtrix not found on MATLAB path. Add MRtrix3 matlab/ utilities to your path.");
end
%% ---------------------------------------------------------------------------

%% ------------------------------- Main loop ---------------------------------
for iMetric = 1:numel(fbaMetrics)
    metric = fbaMetrics(iMetric);
    metricDir = fullfile(topDir, "template", "fba", sprintf("%s_smooth", metric));

    if ~isfolder(metricDir)
        warning("Metric directory not found, skipping: %s", metricDir);
        continue;
    end

    fprintf("%s\nCreating group matrix for metric: %s\n%s\n", sep, metric, sep);

    % Preallocate output matrix: features x subjects
    outMat = zeros(nCells, nSub, "double");

    for j = 1:nSub
        subID = string(subEntries(j).name);
        inFile = fullfile(metricDir, subID + inputSuffix);

        if ~isfile(inFile)
            error("Missing input file for subject '%s': %s", subID, inFile);
        end

        % Read MRtrix image
        mr = read_mrtrix(inFile);

        % Basic shape/length check
        vec = mr.data(:);
        if numel(vec) ~= nCells
            error("Unexpected feature count for %s (%s). Expected %d, got %d.", ...
                subID, metric, nCells, numel(vec));
        end

        outMat(:, j) = vec;

        % Progress printing (compact)
        fprintf("  [%d/%d] %s\n", j, nSub, subID);
    end

    % Clean matrix
    outMat(~isfinite(outMat)) = 0;
    outMat(outMat < 0) = 0;

    % Write as tab-delimited text (no column headers)
    outTable = array2table(outMat);
    outFile = fullfile(outDir, sprintf("%s_matrix.txt", metric));
    writetable(outTable, outFile, ...
        "Delimiter", outputDelimiter, ...
        "WriteVariableNames", writeVariableNames);

    fprintf("%s\nSaved: %s\n%s\n", sep, outFile, sep);
end
%% ---------------------------------------------------------------------------

fprintf("Done.\n");

