
function ev_samp = grid_events_to_sample_events(ev_grid, fs, N)
% ev_grid start_t/end_t are seconds already; map to samples.
    ev_samp = ev_grid;
    for i = 1:numel(ev_samp)
        s = round(ev_samp(i).start_t*fs) + 1;
        e = round(ev_samp(i).end_t*fs)   + 1;
        s = max(1, min(N, s));
        e = max(1, min(N, e));
        ev_samp(i).start_idx = s;
        ev_samp(i).end_idx   = e;
        ev_samp(i).start_t   = (s-1)/fs;
        ev_samp(i).end_t     = (e-1)/fs;
    end
end