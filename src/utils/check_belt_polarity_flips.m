
%% MAGMA - Count respiratory belt polarity flips
% Standalone script. Reads saved feature-cache metadata only.

clear; clc;

% Change this path if needed
resultsRoot = 'D:\Projects\MAGMA\data_analysis\statistical_labeling';

% Find recordings
files = dir(fullfile(resultsRoot, 'Sub*_M*', '*_features.mat'));
assert(~isempty(files), 'No feature caches found. Check resultsRoot.');

n = numel(files);
recording = strings(n,1);
relChecked = nan(n,1);
relFlipped = nan(n,1);
absChecked = nan(n,1);
absFlipped = nan(n,1);

for i = 1:n
    recording(i) = erase(string(files(i).name), '_features.mat');
    filename = fullfile(files(i).folder, files(i).name);

    try
        S = load(filename, 'feature_cache_meta');
        if ~isfield(S, 'feature_cache_meta')
            warning('Missing metadata: %s', filename);
            continue;
        end
        m = S.feature_cache_meta;

        if isfield(m, 'belt_polarity_checked')
            relChecked(i) = double(m.belt_polarity_checked);
        end
        if isfield(m, 'diaphragm_polarity_flipped')
            relFlipped(i) = double(m.diaphragm_polarity_flipped);
        end
        if isfield(m, 'absolute_polarity_checked')
            absChecked(i) = double(m.absolute_polarity_checked);
        end
        if isfield(m, 'absolute_polarity_flipped')
            absFlipped(i) = double(m.absolute_polarity_flipped);
        end
    catch ME
        warning('Cannot read %s: %s', filename, ME.message);
    end
end

% Build recording-level table
T = table(recording, relChecked, relFlipped, ...
    absChecked, absFlipped, ...
    'VariableNames', {'recording', 'relative_checked', ...
    'relative_flipped', 'absolute_checked', 'absolute_flipped'});

T = sortrows(T, 'recording');

r = T.relative_flipped == 1;
a = T.absolute_flipped == 1;
known = isfinite(T.relative_flipped) & ...
        isfinite(T.absolute_flipped);

fprintf('\n===== MAGMA POLARITY QC =====\n');
fprintf('Feature caches found:  %d\n', height(T));
fprintf('Relative checks:        %d\n', nnz(T.relative_checked == 1));
fprintf('Absolute checks:        %d\n', nnz(T.absolute_checked == 1));
fprintf('Relative flips:         %d\n', nnz(r));
fprintf('Absolute flips:         %d\n', nnz(a));
fprintf('Relative only:          %d\n', nnz(known & r & ~a));
fprintf('Absolute only:          %d\n', nnz(known & ~r & a));
fprintf('Both methods:           %d\n', nnz(r & a));
fprintf('Either method:          %d\n', nnz(r | a));
fprintf('Incomplete flip metadata: %d\n', nnz(~known));

fprintf('\n===== RECORDINGS WITH FLIPS =====\n');
disp(T(r | a, {'recording', 'relative_flipped', ...
                'absolute_flipped'}));

% Export all recording-level decisions
outputFile = fullfile(resultsRoot, 'polarity_qc_summary.csv');
writetable(T, outputFile);
fprintf('\nSaved summary: %s\n', outputFile);
