
function ev_samp = grid_events_to_sample_events(ev_grid, fs, N)
% GRID_EVENTS_TO_SAMPLE_EVENTS Convert time-grid events to sample-aligned events.
%
% Syntax:
%   ev_samp = grid_events_to_sample_events(ev_grid, fs, N)
%
% Inputs:
%   ev_grid - Event structure array with time boundaries.
%   fs - Sampling frequency in hertz.
%   N - Number of samples.
%
% Outputs:
%   ev_samp - Event structure array with sample-aligned boundaries.

    ev_samp = ev_grid;
    for i = 1:numel(ev_samp)
        s = round(ev_samp(i).start_t*fs) + 1;
        e = round(ev_samp(i).end_t*fs);
        s = max(1, min(N, s));
        e = max(s, min(N, e));
        ev_samp(i).start_idx = s;
        ev_samp(i).end_idx   = e;
        ev_samp(i).start_t   = (s-1)/fs;
        ev_samp(i).end_t     = e/fs;
        ev_samp(i).duration  = (e-s+1)/fs;
    end
end
