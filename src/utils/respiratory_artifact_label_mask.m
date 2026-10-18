function mask = respiratory_artifact_label_mask(features,labels,N,config,diagnostics)
% RESPIRATORY_ARTIFACT_LABEL_MASK Technical assessability, separate from labels.
% Single-belt labels retain the other usable belt. Cross-belt labels require
% simultaneous valid evidence. Existing estimator windows determine gap guards.
    if nargin < 5, diagnostics = struct(); end
    mask = true(N,numel(labels));
    if ~isfield(features,'respiratory_artifact_state'), return; end
    state = features.respiratory_artifact_state;
    if isempty(state.lungs) && isempty(state.diaph), return; end
    resolved = resolve_signal_channels(config);
    for j = 1:numel(labels)
        label = labels{j};
        if strcmp(label,'desat'), continue; end
        before = 0; after = 0; field = 'available';
        switch label
            case {'shallow','deep','thoracic'}, field = 'session_amplitude_available';
            case 'sigh', field = 'amplitude_available';
        end
        switch label
            case 'slow', after = features.rate_windows_sec.slow;
            case 'rapid', after = features.rate_windows_sec.rapid;
            case 'irregular', after = get_config_value(config,'irregular','analysis_win_sec',60);
            case 'apnea', after = get_config_value(config,'apnea','min_dur_sec',10);
            case 'thoracic', after = features.thoracoabdominal_balance.analysis_window_sec;
            case 'periodic'
                after = get_config_value(config.periodic,'guyot','window_sec',120)/2;
                if strcmp(get_config_value(config,'periodic','primary_method','eami'),'eami')
                    after = get_config_value(config.periodic,'eami','energy_win_sec',60)/2;
                end
                before = after;
        end
        valid = false(N,2);
        keys = {'lungs','diaph'};
        for b = 1:2
            key = keys{b}; belt = features.(key);
            usable = isfield(belt,field) && belt.(field);
            if strcmp(label,'async')
                usable = ~isempty(resolved.channels.([key '_idx'])); % primary valid mask supplies raw phase usability
            elseif strcmp(label,'apnea') && isfield(diagnostics,'apnea')
                d = diagnostics.apnea;
                if isfield(d,'raw_excursion') && isfield(d.raw_excursion,key)
                    usable = belt.session_amplitude_available || d.raw_excursion.(key).valid;
                end
            elseif strcmp(label,'periodic') && isfield(diagnostics,'periodic')
                d = diagnostics.periodic;
                method = get_config_value(config,'periodic','primary_method','eami');
                if isfield(d,method) && isfield(d.(method),key), usable = d.(method).(key).available; end
            elseif strcmp(label,'sigh') && isfield(diagnostics,'sigh') && isfield(diagnostics.sigh,key)
                usable = diagnostics.sigh.(key).available;
            end
            if b == 1 && (is_lung_belt_ignored(config) || minimal_thoracic_excursion(config)), usable = false; end
            if ~usable, continue; end
            valid(:,b) = true;
            ranges = state.([key '_evidence']);
            if strcmp(label,'sigh') && ~isempty(ranges)
                % A centered baseline uses the configured number of original
                % breath positions, including invalid positions at the gap.
                t = belt.peak_t(:); half = floor(get_config_value(config,'sigh','rolling_window_breaths',15)/2);
                if strcmp(get_config_value(config,'sigh','method','rolling_median_2x'),'rolling_median_2x')
                    for k = 1:size(ranges,1)
                        left = find(t*config.fs+1 <= ranges(k,1),1,'last');
                        right = find(t*config.fs+1 >= ranges(k,2),1,'first');
                        if ~isempty(left), ranges(k,1) = min(ranges(k,1),round(t(max(1,left-half))*config.fs)+1); end
                        if ~isempty(right), ranges(k,2) = max(ranges(k,2),round(t(min(numel(t),right+half))*config.fs)+1); end
                    end
                elseif strcmp(get_config_value(config,'sigh','method','rolling_median_2x'),'legacy_60s')
                    after = get_config_value(config,'sigh','legacy_prev_win_sec',60);
                end
            end
            for k = 1:size(ranges,1)
                first = max(1,ranges(k,1)-ceil(before*config.fs));
                last = min(N,ranges(k,2)+ceil(after*config.fs));
                valid(first:last,b) = false;
            end
        end
        if ismember(label,{'thoracic','async'}), mask(:,j) = all(valid,2);
        else, mask(:,j) = any(valid,2); end
    end
end
