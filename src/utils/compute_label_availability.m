function [label_available, reason] = compute_label_availability( ...
    label_names, resp_features, diagnostics_Des, rea, apnea, sigh, csr)
% COMPUTE_LABEL_AVAILABILITY Compute label availability.
%
% Syntax:
%   [label_available, reason] = compute_label_availability(label_names, resp_features, diagnostics_Des, rea, apnea, sigh, csr)
%
% Inputs:
%   label_names - Label identifier or label metadata.
%   resp_features - Respiratory-feature structure.
%   diagnostics_Des - Detector diagnostic data.
%   rea - Input value `rea`.
%   apnea - Input value `apnea`.
%   sigh - Input value `sigh`.
%   csr - Input value `csr`.
%
% Outputs:
%   label_available - Logical availability result.
%   reason - Output text or identifier.

    label_names = cellstr(string(label_names));
    label_available = false(1, numel(label_names));
    reason = repmat({'detector_analysis_failed'}, 1, numel(label_names));

    lungs = resp_features.resp.lungs;
    diaph = resp_features.resp.diaph;
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
                label_available(i) = isstruct(diagnostics_Des) && ...
                    isfield(diagnostics_Des, 'detection_available') && ...
                    logical(diagnostics_Des.detection_available);
                if label_available(i)
                    reason{i} = 'available';
                elseif ~has_spo2_signal(diagnostics_Des)
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
                    resp_features.resp.thoracoabdominal_balance.available;
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
% AMPLITUDE_AVAILABILITY Perform the amplitude availability operation.
%
% Syntax:
%   [available, reason] = amplitude_availability(session_amp, any_resp)
%
% Inputs:
%   session_amp - Input value `session_amp`.
%   any_resp - Input value `any_resp`.
%
% Outputs:
%   available - Logical availability result.
%   reason - Output text or identifier.

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
% RESPIRATORY_FEATURE_AVAILABILITY Perform the respiratory feature availability operation.
%
% Syntax:
%   [available, reason] = respiratory_feature_availability(evidence, any_resp)
%
% Inputs:
%   evidence - Input value `evidence`.
%   any_resp - Input value `any_resp`.
%
% Outputs:
%   available - Logical availability result.
%   reason - Output text or identifier.

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
% DIAGNOSTIC_AVAILABLE Perform the diagnostic available operation.
%
% Syntax:
%   tf = diagnostic_available(value)
%
% Inputs:
%   value - Input value `value`.
%
% Outputs:
%   tf - Computed output value `tf`.

    tf = isstruct(value) && isfield(value, 'available') && ...
        isscalar(value.available) && logical(value.available);
end

function tf = has_spo2_signal(diagnostics_Des)
% HAS_SPO2_SIGNAL Determine whether spo2 signal.
%
% Syntax:
%   tf = has_spo2_signal(diagnostics_Des)
%
% Inputs:
%   diagnostics_Des - Detector diagnostic data.
%
% Outputs:
%   tf - Computed output value `tf`.

    tf = isstruct(diagnostics_Des) && ...
        isfield(diagnostics_Des, 'signal_available') && ...
        logical(diagnostics_Des.signal_available);
end

function tf = any_finite(values)
% ANY_FINITE Perform the any finite operation.
%
% Syntax:
%   tf = any_finite(values)
%
% Inputs:
%   values - Input value `values`.
%
% Outputs:
%   tf - Computed output value `tf`.

    tf = any(isfinite(values(:)));
end
