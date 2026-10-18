function [analysis_data,analysis_cycles,state] = respiratory_artifact_view(data,cycles,config)
% RESPIRATORY_ARTIFACT_VIEW Disposable analysis copies; original data stay intact.
    N = size(data,1);
    state = respiratory_artifact_state(cycles,config,N);
    analysis_data = data; analysis_cycles = cycles;
    resolved = resolve_signal_channels(config);
    for name = {'lungs','diaph'}
        key = name{1}; idx = resolved.channels.([key '_idx']);
        if isempty(state.(key)), continue; end
        bad = false(N,1);
        for j = 1:size(state.(key),1), bad(state.(key)(j,1):state.(key)(j,2)) = true; end
        if ~isempty(idx), analysis_data(bad,idx) = NaN; end
        if ~isfield(cycles,key), continue; end
        belt = cycles.(key); masks = respiratory_artifact_masks(belt,N,config.fs);
        for field = {'amp','amp_exp','amp_insp','amp_sym'}
            if isfield(belt,field{1}) && numel(belt.(field{1})) == numel(masks.breath_valid)
                values = belt.(field{1}); values(~masks.breath_valid) = NaN; belt.(field{1}) = values;
            end
        end
        for field = {'ibi','rr_bpm'}
            if isfield(belt,field{1}) && numel(belt.(field{1})) == numel(masks.ibi_valid)
                values = belt.(field{1}); values(~masks.ibi_valid) = NaN; belt.(field{1}) = values;
            end
        end
        belt.artifact_valid_breath_mask = masks.breath_valid;
        belt.artifact_valid_ibi_mask = masks.ibi_valid;
        analysis_cycles.(key) = belt;
    end
end
