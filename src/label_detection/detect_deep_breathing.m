function [events, boundary_info] = detect_deep_breathing(data, resp_features, config)
% DETECT_DEEP_BREATHING Detect deep breathing.
%
% Syntax:
%   [events, boundary_info] = detect_deep_breathing(data, resp_features, config)
%
% Inputs:
%   data - Input physiological signal data.
%   resp_features - Respiratory-feature structure.
%   config - Pipeline configuration structure.
%
% Outputs:
%   events - Event structure array.
%   boundary_info - Event-boundary provenance structure.

    events = empty_events();
    N = size(data, 1);
    t_grid = resp_features.resp.time_sec;
    lungs = resp_features.resp.lungs;
    diaph = resp_features.resp.diaph;
    boundary_info = make_label_boundary_info('deep', ...
        'detect_deep_breathing', 'not_evaluated', empty_events(), ...
        empty_events(), NaN, '', [], [], []);

    lungs_mask = false(size(t_grid));
    if lungs.session_amplitude_available
        lungs_mask = lungs.deep_amplitude_mask;
    end
    diaph_mask = false(size(t_grid));
    if diaph.session_amplitude_available
        diaph_mask = diaph.deep_amplitude_mask;
    end

    if ~lungs.session_amplitude_available && ~diaph.session_amplitude_available
        fprintf('Skipping deep detection: no valid respiratory belt with usable breath amplitudes.\n');
        return;
    end

    [candidate_lungs, lungs_candidate_mask] = sustained_condition_to_events( ...
        lungs_mask, t_grid, config.fs, N, 0, ...
        'deep_breathing_lungs');
    [candidate_diaph, diaph_candidate_mask] = sustained_condition_to_events( ...
        diaph_mask, t_grid, config.fs, N, 0, ...
        'deep_breathing_diaph');
    [events_lungs, records_lungs, localized_lungs_events] = ...
        localize_confirmed_breath_events( ...
        candidate_lungs, lungs, N, config.fs, 'deep_breathing_lungs', ...
        'amplitude_ge', config.deep.amp_ratio_thr, NaN, ...
        config.deep.analysis_win_sec, config.deep.min_dur_sec, 'lungs');
    [events_diaph, records_diaph, localized_diaph_events] = ...
        localize_confirmed_breath_events( ...
        candidate_diaph, diaph, N, config.fs, 'deep_breathing_diaph', ...
        'amplitude_ge', config.deep.amp_ratio_thr, NaN, ...
        config.deep.analysis_win_sec, config.deep.min_dur_sec, 'diaph');
    events = merge_events({events_lungs, events_diaph});
    endpoint_mask = get_endpoint_mask(lungs, 'deep_amplitude_endpoint_mask', t_grid) | ...
        get_endpoint_mask(diaph, 'deep_amplitude_endpoint_mask', t_grid);
    localized_lungs = events_to_grid_mask(localized_lungs_events, t_grid);
    localized_diaph = events_to_grid_mask(localized_diaph_events, t_grid);
    final_mask = events_to_grid_mask(events, t_grid);
    boundary_info = make_label_boundary_info('deep', ...
        'detect_deep_breathing', 'confirmed_all_breath_window_midpoint_localization', ...
        [candidate_lungs; candidate_diaph], [events_lungs; events_diaph], ...
        NaN, 'breath_amplitude_ratio_session', endpoint_mask, ...
        lungs_candidate_mask | diaph_candidate_mask, ...
        localized_lungs | localized_diaph, final_mask);
    boundary_info.events = normalize_records([records_lungs; records_diaph]);
    boundary_info.boundary_uncertainty_sec = record_uncertainty(boundary_info.events);

    if config.deep.do_plot
        opts = struct( ...
            'figure_title', 'DEEP BREATHING', ...
            'event_name', 'Deep breathing', ...
            'lower_ratio', config.deep.amp_ratio_thr, ...
            'candidate_mask_lungs', lungs_candidate_mask, ...
            'candidate_mask_diaph', diaph_candidate_mask, ...
            'localized_mask_lungs', localized_lungs, ...
            'localized_mask_diaph', localized_diaph, ...
            'output_name', 'deep_breathing');
        plot_amplitude_state_diagnostic( ...
            resp_features, events_lungs, events_diaph, config, opts);
    end
end

function mask = get_endpoint_mask(belt, field, t_grid)
% GET_ENDPOINT_MASK Return endpoint mask.
%
% Syntax:
%   mask = get_endpoint_mask(belt, field, t_grid)
%
% Inputs:
%   belt - Respiratory-cycle or belt-evidence structure.
%   field - Input value `field`.
%   t_grid - Time coordinates in seconds.
%
% Outputs:
%   mask - Logical output mask.

    mask = false(size(t_grid));
    if isfield(belt, field), mask = logical(belt.(field)); end
end

function records = normalize_records(records)
% NORMALIZE_RECORDS Normalize records.
%
% Syntax:
%   records = normalize_records(records)
%
% Inputs:
%   records - Input value `records`.
%
% Outputs:
%   records - Computed output value `records`.

    for i = 1:numel(records)
        records(i).label = 'deep';
        records(i).detector = 'detect_deep_breathing';
    end
end

function value = record_uncertainty(records)
% RECORD_UNCERTAINTY Perform the record uncertainty operation.
%
% Syntax:
%   value = record_uncertainty(records)
%
% Inputs:
%   records - Input value `records`.
%
% Outputs:
%   value - Computed numeric value.

    if isempty(records), value = NaN; else, value = [records.uncertainty_sec]'; end
end
