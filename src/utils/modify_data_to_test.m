function data_modified = modify_data_to_test(data, fs, columns, trange_min, modification_type, to_plot)
%MODIFY_DATA_TO_TEST Modify selected signal columns in a chosen time range.
%
% Usage:
%   data_modified = modify_data_to_test(data, fs, columns, trange_min, modification_type, to_plot)
%
% Inputs:
%   data              - data matrix, samples x signals
%   fs                - sampling frequency in Hz
%   columns           - columns to modify, e.g. [5 6]
%   trange_min        - time range in minutes, e.g. [2 4]
%   modification_type - string, supports:
%                         'shallow_breathing'
%                         'irregular_breathing'
%                         'slow_breathing'
%                         'rapid_breathing'
%                         'respiratory_asynchrony'
%                         'desaturation'
%                         'apnea'
%                         'sigh'
%                         'periodic_breathing'
%   to_plot           - true/false
%
% Output:
%   data_modified     - same size as data, with selected columns modified
%
% Example:
%   data_mod = modify_data_to_test(data, config.new_fs, [5 6], [2 4], ...
%       'shallow_breathing', true);

    % -----------------------------
    % Basic checks
    % -----------------------------
    if nargin < 6
        to_plot = false;
    end

    if numel(trange_min) ~= 2
        error('trange_min must be a 2-element vector, e.g. [2 4].');
    end

    if trange_min(2) <= trange_min(1)
        error('trange_min end must be larger than start.');
    end

    if any(columns < 1) || any(columns > size(data, 2))
        error('One or more columns are outside the valid range of data columns.');
    end

    % -----------------------------
    % Time and mask
    % -----------------------------
    n_samples = size(data, 1);
    time_sec = (0:n_samples-1)' ./ fs;

    trange_start_sec = trange_min(1) * 60;
    trange_end_sec   = trange_min(2) * 60;

    trange_mask = time_sec >= trange_start_sec & time_sec <= trange_end_sec;

    if ~any(trange_mask)
        error('Selected time range does not overlap with data.');
    end

    % -----------------------------
    % Initialize output
    % -----------------------------
    data_modified = data;

    % -----------------------------
    % Modification type
    % -----------------------------
    switch lower(char(string(modification_type)))

        case 'shallow_breathing'
            % Keep amplitudes in the detector's shallow band:
            % config.ShB defaults to 0.65-0.80 of reference.
            data_modified = scale_selected_columns(data_modified, time_sec, trange_mask, columns, fs, 0.72);

        case 'irregular_breathing'
            data_modified = replace_respiration_with_variable_rate( ...
                data_modified, time_sec, trange_mask, columns, fs);

        case 'slow_breathing'
            data_modified = replace_respiration_with_fixed_rate( ...
                data_modified, time_sec, trange_mask, columns, fs, 9.5, 1.00);

        case 'rapid_breathing'
            data_modified = replace_respiration_with_fixed_rate( ...
                data_modified, time_sec, trange_mask, columns, fs, 22.0, 1.00);

        case 'respiratory_asynchrony'
            data_modified = replace_respiration_with_asynchrony( ...
                data_modified, time_sec, trange_mask, columns, fs);

        case 'desaturation'
            data_modified = apply_desaturation(data_modified, trange_mask, columns);

        case 'apnea'
            data_modified = flatten_selected_columns(data_modified, time_sec, trange_mask, columns, fs);

        case 'sigh'
            data_modified = inject_sigh_breath(data_modified, time_sec, trange_mask, columns, fs);

        case 'periodic_breathing'
            data_modified = replace_respiration_with_periodic_breathing( ...
                data_modified, time_sec, trange_mask, columns, fs);

        otherwise
            error(['Unknown modification_type: %s. Supported: shallow_breathing, ' ...
                'irregular_breathing, slow_breathing, rapid_breathing, ' ...
                'respiratory_asynchrony, desaturation, apnea, sigh, periodic_breathing.'], ...
                modification_type);
    end

    % -----------------------------
    % Optional plotting
    % -----------------------------
    if to_plot
        figure('Units', 'pixels', 'Position', near_fullscreen_figure_position());

        for i = 1:numel(columns)
            c = columns(i);

            subplot(numel(columns), 1, i)
            hold on

            plot(time_sec, data(:, c), 'DisplayName', 'Original')
            plot(time_sec, data_modified(:, c), 'DisplayName', 'Modified')

            xline(trange_start_sec, 'k--', 'Start')
            xline(trange_end_sec, 'k--', 'End')

            grid on
            xlabel('Time (s)')
            ylabel(sprintf('Column %d', c))

            title(sprintf('%s modification | column %d', modification_type, c), ...
                'Interpreter', 'none')

            legend('Location', 'best')
            hold off
        end
    end

end

function data_out = scale_selected_columns(data_in, time_sec, mask, columns, fs, scale)
    data_out = data_in;
    for i = 1:numel(columns)
        c = columns(i);
        sig = data_out(:, c);
        [center, ~] = local_center_and_amp(sig, mask);
        replacement = sig;
        replacement(mask) = center + scale * (sig(mask) - center);
        data_out(:, c) = blend_masked_segment(sig, replacement, time_sec, mask, fs, 2.0);
    end
end

function data_out = replace_respiration_with_fixed_rate(data_in, time_sec, mask, columns, fs, bpm, amp_scale)
    data_out = data_in;
    phase_offsets = linspace(0, 0.12, max(1, numel(columns)));
    t0 = time_sec(find(mask, 1, 'first'));

    for i = 1:numel(columns)
        c = columns(i);
        sig = data_out(:, c);
        [center, amp] = local_center_and_amp(sig, mask);
        phase = 2 * pi * (bpm / 60) * (time_sec - t0) + phase_offsets(i);
        replacement = sig;
        replacement(mask) = center + amp_scale * amp * sin(phase(mask));
        data_out(:, c) = blend_masked_segment(sig, replacement, time_sec, mask, fs, 2.0);
    end
end

function data_out = replace_respiration_with_variable_rate(data_in, time_sec, mask, columns, fs)
    data_out = data_in;
    t0 = time_sec(find(mask, 1, 'first'));
    local_t = time_sec - t0;
    bpm = 15 + 8 * sin(2 * pi * local_t / 37) + 5 * sin(2 * pi * local_t / 17);
    bpm = min(max(bpm, 6.5), 28.0);
    phase = 2 * pi * cumsum(bpm / 60) / fs;

    for i = 1:numel(columns)
        c = columns(i);
        sig = data_out(:, c);
        [center, amp] = local_center_and_amp(sig, mask);
        replacement = sig;
        replacement(mask) = center + amp * sin(phase(mask) + 0.10 * (i - 1));
        data_out(:, c) = blend_masked_segment(sig, replacement, time_sec, mask, fs, 2.0);
    end
end

function data_out = replace_respiration_with_asynchrony(data_in, time_sec, mask, columns, fs)
    data_out = data_in;
    if numel(columns) < 2
        error('respiratory_asynchrony requires two respiration columns, e.g. [4 6].');
    end

    t0 = time_sec(find(mask, 1, 'first'));
    local_t = time_sec - t0;

    c_lungs = columns(1);
    c_diaph = columns(2);
    [center_l, amp_l] = local_center_and_amp(data_out(:, c_lungs), mask);
    [center_d, amp_d] = local_center_and_amp(data_out(:, c_diaph), mask);

    lungs = data_out(:, c_lungs);
    diaph = data_out(:, c_diaph);
    repl_lungs = lungs;
    repl_diaph = diaph;

    phase_lungs = 2 * pi * (12 / 60) * local_t;
    phase_drift = 1.3 * (1 - cos(2 * pi * local_t / 120));
    phase_diaph = phase_lungs + phase_drift;

    repl_lungs(mask) = center_l + amp_l * sin(phase_lungs(mask));
    repl_diaph(mask) = center_d + amp_d * sin(phase_diaph(mask));

    data_out(:, c_lungs) = blend_masked_segment(lungs, repl_lungs, time_sec, mask, fs, 2.0);
    data_out(:, c_diaph) = blend_masked_segment(diaph, repl_diaph, time_sec, mask, fs, 2.0);
end

function data_out = apply_desaturation(data_in, mask, columns)
    data_out = data_in;
    for i = 1:numel(columns)
        c = columns(i);
        sig = data_out(:, c);
        local_base = median(sig(~mask), 'omitnan');
        if ~isfinite(local_base)
            local_base = median(sig, 'omitnan');
        end
        if ~isfinite(local_base)
            local_base = 97;
        end
        sig(mask) = min(local_base - 5, 88);
        data_out(:, c) = sig;
    end
end

function data_out = flatten_selected_columns(data_in, time_sec, mask, columns, fs)
    data_out = data_in;
    for i = 1:numel(columns)
        c = columns(i);
        sig = data_out(:, c);
        [center, amp] = local_center_and_amp(sig, mask);
        replacement = sig;
        replacement(mask) = center + 0.01 * amp * sin(2 * pi * 0.2 * time_sec(mask));
        data_out(:, c) = blend_masked_segment(sig, replacement, time_sec, mask, fs, 1.0);
    end
end

function data_out = inject_sigh_breath(data_in, time_sec, mask, columns, fs)
    data_out = data_in;
    event_t = mean(time_sec(mask), 'omitnan');
    sigma_sec = 0.9;

    for i = 1:numel(columns)
        c = columns(i);
        sig = data_out(:, c);
        [~, amp] = local_center_and_amp(sig, mask);
        sigh = 3.5 * amp * exp(-0.5 * ((time_sec - event_t) / sigma_sec) .^ 2);
        replacement = sig + sigh;
        data_out(:, c) = blend_masked_segment(sig, replacement, time_sec, mask, fs, 0.5);
    end
end

function data_out = replace_respiration_with_periodic_breathing(data_in, time_sec, mask, columns, fs)
    data_out = data_in;
    t0 = time_sec(find(mask, 1, 'first'));
    local_t = time_sec - t0;
    cycle_sec = 50;
    bpm = 12;

    envelope = 0.35 + 0.95 * 0.5 .* (1 - cos(2 * pi * local_t / cycle_sec));
    phase_offsets = linspace(0, 0.10, max(1, numel(columns)));

    for i = 1:numel(columns)
        c = columns(i);
        sig = data_out(:, c);
        [center, amp] = local_center_and_amp(sig, mask);
        phase = 2 * pi * (bpm / 60) * local_t + phase_offsets(i);
        replacement = sig;
        replacement(mask) = center + amp * envelope(mask) .* sin(phase(mask));
        data_out(:, c) = blend_masked_segment(sig, replacement, time_sec, mask, fs, 2.0);
    end
end

function [center, amp] = local_center_and_amp(sig, mask)
    segment = sig(mask);
    center = median(segment, 'omitnan');
    if ~isfinite(center)
        center = median(sig, 'omitnan');
    end
    if ~isfinite(center)
        center = 0;
    end

    finite_segment = segment(isfinite(segment));
    if numel(finite_segment) >= 5
        amp = 0.5 * (prctile(finite_segment, 95) - prctile(finite_segment, 5));
    else
        amp = std(sig, 'omitnan');
    end
    if ~isfinite(amp) || amp <= 0
        amp = 1;
    end
end

function sig_out = blend_masked_segment(sig, replacement, time_sec, mask, fs, fade_sec)
    sig_out = sig;
    idx = find(mask);
    if isempty(idx)
        return;
    end

    weights = ones(numel(idx), 1);
    fade_n = min(round(fade_sec * fs), floor(numel(idx) / 2));
    if fade_n > 1
        fade_in = linspace(0, 1, fade_n)';
        weights(1:fade_n) = fade_in;
        weights(end-fade_n+1:end) = flipud(fade_in);
    end

    sig_out(idx) = (1 - weights) .* sig(idx) + weights .* replacement(idx);

    % Keep the exact requested segment boundaries from being ambiguous in
    % plots when the selected range has non-integer sample limits.
    if numel(idx) > 1
        sig_out(time_sec < time_sec(idx(1)) | time_sec > time_sec(idx(end))) = ...
            sig(time_sec < time_sec(idx(1)) | time_sec > time_sec(idx(end)));
    end
end
