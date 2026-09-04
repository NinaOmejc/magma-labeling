function info = standard_boundary(label, detector, events, method, uncertainty, source)
% STANDARD_BOUNDARY Create standard boundary-provenance metadata.
%
% Syntax:
%   info = standard_boundary(label, detector, events, method, uncertainty, source)
%
% Inputs:
%   label - Label identifier or label metadata.
%   detector - Input value `detector`.
%   events - Event structure data.
%   method - Input value `method`.
%   uncertainty - Input value `uncertainty`.
%   source - Input value `source`.
%
% Outputs:
%   info - Computed summary or metadata structure.

    info = make_label_boundary_info(label, detector, method, events, events, ...
        uncertainty, source, [], [], []);
    if isnan(uncertainty)
        info.temporal_resolution_note = ...
            'detector-specific timing; no unsupported scalar uncertainty assigned';
    else
        info.temporal_resolution_note = '';
    end
end
