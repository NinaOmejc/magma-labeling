function tf = has_reviewed_respiration_landmarks(cycles)
% HAS_REVIEWED_RESPIRATION_LANDMARKS Conservative protection for older metadata.
    tf = false;
    if ~isstruct(cycles) || ~isscalar(cycles), return; end
    if isfield(cycles,'provenance') && isstruct(cycles.provenance)
        p = cycles.provenance;
        for field = {'manual_review_performed','manual_edits_made'}
            if isfield(p,field{1}) && isequal(p.(field{1}),true), tf = true; return; end
        end
        if isfield(p,'review_status') && any(startsWith(string(p.review_status),'manual_reviewed'),'all')
            tf = true; return;
        end
    end
    for name = {'lungs','diaph'}
        if isfield(cycles,name{1}) && isfield(cycles.(name{1}),'trough_overrides') && ...
                ~isempty(cycles.(name{1}).trough_overrides)
            tf = true; return;
        end
    end
end
