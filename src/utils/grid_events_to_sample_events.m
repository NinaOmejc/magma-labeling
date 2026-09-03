
function ev_samp = grid_events_to_sample_events(ev_grid, fs, N)
% Map half-open grid events to included master samples.
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
