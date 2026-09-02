function [lungs_analysis, diaph_analysis, fs_analysis] = resample_respiration_for_analysis( ...
    lungs_master, diaph_master, master_fs, analysis_fs)
% resample_respiration_for_analysis
% Create an anti-aliased, detector-local respiratory representation.
% Master signals and sample indices are not modified.

% MATLAB resample applies the required low-pass anti-aliasing filter before
% downsampling. analysis_fs is capped at master_fs to avoid local upsampling.

    if ~isscalar(master_fs) || ~isfinite(master_fs) || master_fs <= 0
        error('master_fs must be a positive finite scalar.');
    end
    if ~isscalar(analysis_fs) || ~isfinite(analysis_fs) || analysis_fs <= 0
        error('analysis_fs must be a positive finite scalar.');
    end

    if numel(lungs_master) ~= numel(diaph_master)
        error('MAGMA:RespiratoryAsynchrony:LengthMismatch', ...
            'Master respiratory signals must have identical sample counts.');
    end

    lungs_analysis = lungs_master(:);
    diaph_analysis = diaph_master(:);

    fs_analysis = min(analysis_fs, master_fs);
    if abs(fs_analysis - master_fs) > 10 * eps(master_fs)
        [p, q] = rat(fs_analysis / master_fs, 1e-12);
        lungs_analysis = resample(lungs_analysis, p, q);
        diaph_analysis = resample(diaph_analysis, p, q);
        fs_analysis = master_fs * p / q;
    end

    if numel(lungs_analysis) ~= numel(diaph_analysis)
        error('MAGMA:RespiratoryAsynchrony:LengthMismatch', ...
            'Locally resampled respiratory signals have mismatched sample counts.');
    end
end
