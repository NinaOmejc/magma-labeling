function mask = events_to_sample_mask(events, N, fs)
    mask = false(N,1);
    for k = 1:numel(events)
        s = max(1, min(N, round(events(k).start_t*fs)+1));
        e = max(1, min(N, round(events(k).end_t*fs)+1));
        mask(s:e) = true;
    end
end