function [analysis_data,analysis_cycles,state] = respiratory_artifact_view(data,cycles,config)
% RESPIRATORY_ARTIFACT_VIEW Disposable analysis copies; original data stay intact.
    N = size(data,1);
    state = respiratory_artifact_state(cycles,config,N);
    analysis_data = data; analysis_cycles = migrate_respiratory_artifacts(cycles,N,state);
    resolved = resolve_signal_channels(config);
    bad = false(N,1);
    ranges = state.artifact_intervals_idx;
    analysis_cycles.artifact_intervals_idx = ranges;
    for j = 1:size(ranges,1), bad(ranges(j,1):ranges(j,2)) = true; end
    channels = [resolved.channels.lungs_idx resolved.channels.diaph_idx];
    analysis_data(bad,channels) = NaN;
    for name = {'lungs','diaph'}
        key = name{1};
        if isempty(ranges), continue; end
        if ~isfield(cycles,key), continue; end
        belt = analysis_cycles.(key);
        masks = respiratory_artifact_masks(belt,N,config.fs,ranges);
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
        % Derived analysis aliases support existing single-belt estimators.
        belt.artifact_intervals_idx = ranges;
        analysis_cycles.(key) = belt;
    end
end
