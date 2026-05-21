function b = empty_respiration_feature(basename)
% empty_respiration_feature  Invalid breath feature struct for missing belts.

    if nargin < 1
        basename = '';
    end

    b = struct();
    b.basename = basename;
    b.ok = false;
    b.x0 = [];
    b.peak_idx = [];
    b.peak_t = [];
    b.peak_val = [];
    b.trough_idx = [];
    b.trough_t = [];
    b.trough_val = [];
    b.amp = [];
    b.ibi = [];
    b.rr_bpm = [];
    b.rr_mean_bpm = NaN;
    b.rr_std_bpm = NaN;
end
