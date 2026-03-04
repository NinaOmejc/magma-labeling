
function tf = events_overlap_any(e, ev_list)
    tf = false;
    for k = 1:numel(ev_list)
        if ~(e.end_t < ev_list(k).start_t || e.start_t > ev_list(k).end_t)
            tf = true;
            return;
        end
    end
end
