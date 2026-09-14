
function ev_samp = grid_events_to_sample_events(ev_grid, fs, N)
% GRID_EVENTS_TO_SAMPLE_EVENTS Convert time-grid events to sample-aligned events.
% ev_grid supplies half-open start_t/end_t in seconds. fs and N map them to
% clamped inclusive sample indices, then times and duration are recomputed from
% those sample bounds without changing other event fields.

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
