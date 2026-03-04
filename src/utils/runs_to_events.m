
function ev = runs_to_events(cond, fs_like, min_sec, label)
    cond = cond(:) ~= 0;
    d = diff([false; cond; false]);
    st = find(d==1);
    en = find(d==-1)-1;

    ev = empty_events();
    for i = 1:numel(st)
        dur = (en(i)-st(i)+1)/fs_like;
        if dur >= min_sec
            ev(end+1,1) = struct( ...
                'type', label, ...
                'start_idx', st(i), ...
                'end_idx', en(i), ...
                'start_t', (st(i)-1)/fs_like, ...
                'end_t',   (en(i)-1)/fs_like );
        end
    end
end