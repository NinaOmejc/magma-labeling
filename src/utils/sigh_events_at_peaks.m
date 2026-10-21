function [selected, selected_candidates] = sigh_events_at_peaks(events, candidates, panel_peaks, fs)
% SIGH_EVENTS_AT_PEAKS Migrate legacy breath intervals to confirmed peak identities.
% Historical rounds remain untouched; this conversion applies to the new GUI state.
    events = normalize_review_events(events, fs);
    selected = normalize_review_events(empty_events(), fs);
    selected_candidates = false(numel(candidates), 1);
    keep = false(numel(candidates), 1);
    for i = 1:numel(events)
        peaks = panel_peaks;
        if strcmp(events(i).belt, 'lungs'), peaks(:, 2) = NaN;
        elseif strcmp(events(i).belt, 'diaph'), peaks(:, 1) = NaN; end
        if events(i).start_idx == events(i).end_idx
            match = any(abs(peaks - events(i).start_t) < 0.5/fs, 2);
            % Existing peak annotations are authoritative, including which
            % panel supplied the peak. Map identity only for GUI highlighting.
            selected(end+1, 1) = events(i); %#ok<AGROW>
            selected_candidates = selected_candidates | match;
            continue;
        else
            match = any(peaks >= events(i).start_t & peaks < events(i).end_t, 2);
        end
        if any(match)
            keep = keep | match;
            selected_candidates = selected_candidates | match;
        else
            % Missing/changed cycles must not silently erase an existing annotation.
            selected(end+1, 1) = events(i); %#ok<AGROW>
        end
    end
    selected = normalize_review_events([selected; candidates(keep)], fs);
end

