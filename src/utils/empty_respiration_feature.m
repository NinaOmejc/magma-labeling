function b = empty_respiration_feature(basename)
% EMPTY_RESPIRATION_FEATURE Return the canonical unavailable belt-cycle struct.
% basename identifies the belt. b has ok=false; empty signal, peak, trough,
% selected/alternative amplitude, IBI, and RR vectors; and NaN recording-level
% RR summaries.

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
    b.amp_exp = [];
    b.amp_insp = [];
    b.amp_sym = [];
    b.ibi = [];
    b.rr_bpm = [];
    b.rr_mean_bpm = NaN;
    b.rr_std_bpm = NaN;
end
