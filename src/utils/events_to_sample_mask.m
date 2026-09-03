function mask = events_to_sample_mask(events, N, fs)
    mask = false(N,1);
    for k = 1:numel(events)
        has_indices = isfield(events, 'start_idx') && isfield(events, 'end_idx') && ...
            isnumeric(events(k).start_idx) && isnumeric(events(k).end_idx) && ...
            isscalar(events(k).start_idx) && isscalar(events(k).end_idx) && ...
            isfinite(events(k).start_idx) && isfinite(events(k).end_idx);

        if has_indices
            s = round(events(k).start_idx);
            e = round(events(k).end_idx);
        else
            s = round(events(k).start_t*fs)+1;
            e = round(events(k).end_t*fs);
        end

        s = max(1, min(N, s));
        e = max(1, min(N, e));
        if e >= s
            mask(s:e) = true;
        end
    end
end
