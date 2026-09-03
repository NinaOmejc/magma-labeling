function [label_available, reason] = compute_label_availability( ...
    label_names, phys_feat, spo2_feat, rea, apnea, sigh, csr)
% compute_label_availability
% Central recording-level scientific assessability for canonical labels.
% input_config only describes whether detector execution can be attempted;
% this function checks the evidence actually produced by that attempt.

    label_names = cellstr(string(label_names));
    label_available = false(1, numel(label_names));
    reason = repmat({'detector_analysis_failed'}, 1, numel(label_names));

    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;
    any_resp = lungs.available || diaph.available;
    session_amp = lungs.session_amplitude_available || ...
        diaph.session_amplitude_available;

    rate_slow = any_finite(lungs.rate_slow_window_bpm) || ...
        any_finite(diaph.rate_slow_window_bpm);
    rate_rapid = any_finite(lungs.rate_rapid_window_bpm) || ...
        any_finite(diaph.rate_rapid_window_bpm);
    irregular = any_finite(lungs.irregularity.cov) || ...
        any_finite(diaph.irregularity.cov);

    for i = 1:numel(label_names)
        name = label_names{i};
        switch name
            case {'shallow', 'deep'}
                [label_available(i), reason{i}] = amplitude_availability( ...
                    session_amp, any_resp);
            case 'irregular'
                [label_available(i), reason{i}] = respiratory_feature_availability( ...
                    irregular, any_resp);
            case 'slow'
                [label_available(i), reason{i}] = respiratory_feature_availability( ...
                    rate_slow, any_resp);
            case 'rapid'
                [label_available(i), reason{i}] = respiratory_feature_availability( ...
                    rate_rapid, any_resp);
            case 'async'
                label_available(i) = isstruct(rea) && ...
                    isfield(rea, 'valid_analysis') && logical(rea.valid_analysis);
                if label_available(i)
                    reason{i} = 'available';
                elseif isstruct(rea) && isfield(rea, 'skip_code') && ...
                        ismember(rea.skip_code, [1 2])
                    reason{i} = 'one_belt_only';
                else
                    reason{i} = 'respiratory_asynchrony_analysis_invalid';
                end
            case 'desat'
                label_available(i) = isfield(phys_feat, 'spo2') && ...
                    isfield(phys_feat.spo2, 'available') && ...
                    logical(phys_feat.spo2.available);
                if label_available(i)
                    reason{i} = 'available';
                elseif ~has_spo2_signal(spo2_feat)
                    reason{i} = 'missing_spo2';
                else
                    reason{i} = 'invalid_spo2';
                end
            case 'apnea'
                label_available(i) = diagnostic_available(apnea);
                if label_available(i)
                    reason{i} = 'available';
                elseif ~any_resp
                    reason{i} = 'no_respiratory_belt';
                else
                    reason{i} = 'insufficient_resp_features';
                end
            case 'sigh'
                label_available(i) = diagnostic_available(sigh);
                if label_available(i)
                    reason{i} = 'available';
                elseif ~any_resp
                    reason{i} = 'no_respiratory_belt';
                else
                    reason{i} = 'insufficient_resp_features';
                end
            case 'csr'
                label_available(i) = diagnostic_available(csr);
                if label_available(i)
                    reason{i} = 'available';
                elseif ~any_resp
                    reason{i} = 'no_respiratory_belt';
                else
                    reason{i} = 'insufficient_resp_features';
                end
            case 'thoracic'
                label_available(i) = ...
                    phys_feat.resp.thoracoabdominal_balance.available;
                if label_available(i)
                    reason{i} = 'available';
                elseif ~(lungs.available && diaph.available)
                    reason{i} = 'one_belt_only';
                elseif ~(lungs.session_amplitude_available && ...
                        diaph.session_amplitude_available)
                    reason{i} = 'no_session_reference';
                else
                    reason{i} = 'insufficient_thoracoabdominal_evidence';
                end
        end
    end
end

function [available, reason] = amplitude_availability(session_amp, any_resp)
    available = logical(session_amp);
    if available
        reason = 'available';
    elseif ~any_resp
        reason = 'no_respiratory_belt';
    else
        reason = 'no_session_reference';
    end
end

function [available, reason] = respiratory_feature_availability(evidence, any_resp)
    available = logical(evidence);
    if available
        reason = 'available';
    elseif ~any_resp
        reason = 'no_respiratory_belt';
    else
        reason = 'insufficient_resp_features';
    end
end

function tf = diagnostic_available(value)
    tf = isstruct(value) && isfield(value, 'available') && ...
        isscalar(value.available) && logical(value.available);
end

function tf = has_spo2_signal(spo2_feat)
    tf = isstruct(spo2_feat) && isfield(spo2_feat, 'idx_spo2') && ...
        ~isempty(spo2_feat.idx_spo2) && isfield(spo2_feat, 'spo2') && ...
        nnz(isfinite(spo2_feat.spo2)) >= 2;
end

function tf = any_finite(values)
    tf = any(isfinite(values(:)));
end
