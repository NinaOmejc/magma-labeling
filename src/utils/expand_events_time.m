
function ev = expand_events_time(ev, pad_sec, t_max)
% Expand each event by +/- pad_sec seconds (clipped to [0, t_max]).
    for i = 1:numel(ev)
        ev(i).start_t = max(0, ev(i).start_t - pad_sec);
        ev(i).end_t   = min(t_max, ev(i).end_t + pad_sec);
    end
end
