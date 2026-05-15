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
%   modification_type - string, currently supports:
%                         'shallow_breathing'
%   to_plot           - true/false
%
% Output:
%   data_modified     - same size as data, with selected columns modified
%
% Example:
%   data_mod = modify_data_to_test(data, config.fs, [5 6], [2 4], ...
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
    switch lower(modification_type)

        case 'shallow_breathing'
            % Reduce oscillation amplitude by 50% around local center.
            %
            % This preserves local baseline but makes the selected segment
            % shallower.

            amplitude_scale = 0.25;

            for i = 1:numel(columns)
                c = columns(i);

                sig = data(:, c);
                sig_modified = sig;

                local_center = mean(sig(trange_mask), 'omitnan');

                if ~isfinite(local_center)
                    warning('Column %d has invalid local center. Skipping.', c);
                    continue
                end

                sig_modified(trange_mask) = local_center + ...
                    amplitude_scale * (sig(trange_mask) - local_center);

                data_modified(:, c) = sig_modified;
            end

        otherwise
            error('Unknown modification_type: %s. Currently supported: ''shallow_breathing''.', ...
                modification_type);
    end

    % -----------------------------
    % Optional plotting
    % -----------------------------
    if to_plot
        figure('Units', 'pixels', 'Position', [100 100 1200 300*numel(columns)]);

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