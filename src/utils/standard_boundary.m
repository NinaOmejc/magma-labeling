function info = standard_boundary(label, detector, events, method, uncertainty, source)
% STANDARD_BOUNDARY Create standard boundary-provenance metadata.
% Wraps final events as both candidate and localized events via
% make_label_boundary_info. label/detector/method/source are provenance text;
% uncertainty is seconds or NaN when no defensible scalar applies.

    info = make_label_boundary_info(label, detector, method, events, events, ...
        uncertainty, source, [], [], []);
    if isnan(uncertainty)
        info.temporal_resolution_note = ...
            'detector-specific timing; no unsupported scalar uncertainty assigned';
    else
        info.temporal_resolution_note = '';
    end
end
