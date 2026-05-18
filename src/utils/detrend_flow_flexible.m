function [output, trend] = detrend_flow_flexible(t_series, config)
%DETREND_FLOW_FLEXIBLE Detrend vector or matrix time series over time
%intervals or using high pass filter.
%

    % -----------------------------
    % Defaults
    % -----------------------------
    method = 'hpfilter';
    sampl_freq = 200;
    highpass_cutoff = 0.01;   % Hz
    filter_order    = 4;
    hp_edge_pad_sec = 100;    % seconds
    window_l        = 90;     % seconds
    do_plot         = false;
    signals = {'Resp-Lungs', 'Resp-Diaphragm'};


    if isfield(config, 'fs'), sampl_freq = config.fs; end
    if isfield(config, 'detrend')
        if isfield(config.detrend, 'method'), method = config.detrend.method; end
        if isfield(config.detrend, 'highpass_cutoff'), highpass_cutoff = config.detrend.highpass_cutoff; end
        if isfield(config.detrend, 'filter_order'), filter_order = config.detrend.filter_order; end
        if isfield(config.detrend, 'hp_edge_pad_sec'), hp_edge_pad_sec = config.detrend.hp_edge_pad_sec; end
        if isfield(config.detrend, 'signals'), signals = config.detrend.signals; end
        if isfield(config.detrend, 'window_length'), window_l = config.detrend.window_length; end
        if isfield(config.detrend, 'do_plot'), do_plot = config.detrend.do_plot; end
    end

    % -----------------------------
    % Input shape handling
    % -----------------------------
    input_was_row_vector = isrow(t_series) && isvector(t_series);

    if isvector(t_series)
        time = [];
        data = t_series(:);   % work as column
    else
        signal_cols = find(ismember(config.data_columns, signals));
        time = [];
        data = t_series(:, signal_cols);
    end

    [n_samples, n_signals] = size(data);

    output_data = zeros(n_samples, n_signals);
    trend_data  = zeros(n_samples, n_signals);

    % -----------------------------
    % Detrend each signal column separately
    % -----------------------------
    switch lower(method)

        case 'hpfilter'
            nyquist = sampl_freq / 2;

            if highpass_cutoff <= 0
                error('HighpassCutoff must be positive.');
            end

            if highpass_cutoff >= nyquist
                error('HighpassCutoff must be smaller than Nyquist frequency.');
            end

            Wn = highpass_cutoff / nyquist;

            [b, a] = butter(filter_order, Wn, 'high');

            for c = 1:n_signals
                x = data(:, c);
                if all(isnan(x))
                    output_data(:, c) = x;
                    trend_data(:, c)  = x;
                else
                    y = highpass_with_reflect_padding(x, b, a, sampl_freq, highpass_cutoff, hp_edge_pad_sec);
                    output_data(:, c) = y;
                    trend_data(:, c)  = x - y;
                end
            end

        case 'moving_detrend'
            for c = 1:n_signals
                x = data(:, c);

                [y, tr, ~] = detrend_flow(x, sampl_freq, window_l);

                output_data(:, c) = y(:);
                trend_data(:, c)  = tr(:);
            end

        otherwise
            error('Unknown method. Use ''hpfilter'' or ''moving_detrend''.');
    end

    % -----------------------------
    % Reinsert detrended columns into full-size matrices
    % -----------------------------
    if isvector(t_series)
        output = output_data;
        trend  = trend_data;
    
        % Preserve row-vector orientation for vector input
        if input_was_row_vector
            output = output';
            trend  = trend';
        end
    else
        output = t_series;              % full original matrix
        trend  = nan(size(t_series));    % trend only exists for detrended columns
    
        output(:, signal_cols) = output_data;
        trend(:, signal_cols)  = trend_data;
    end

    % -----------------------------
    % Optional plotting
    % -----------------------------
    if do_plot
        if isempty(time)
            t = (0:n_samples-1)' ./ sampl_freq;
        else
            t = time;
        end

        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);

        for c = 1:n_signals
            original_col_idx = signal_cols(c);

            subplot(n_signals, 1, c);

            plot(t, data(:, c), 'DisplayName', 'Original');
            hold on;
            plot(t, output_data(:, c), 'DisplayName', 'Detrended');
            plot(t, trend_data(:, c), 'DisplayName', 'Estimated trend');
            hold off;

            grid on;
            xlabel('Time');
            ylabel(sprintf('Signal %d', original_col_idx));

            if c == 1
                title(sprintf('Detrending using %s', method), 'Interpreter', 'none');
            end

            if c == 1
                legend;
            end
        end
        save_figure(config, 'data_detrend_comparison_in_time')

        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);

        for c = 1:n_signals
            original_col_idx = signal_cols(c);

            subplot(n_signals, 1, c);
            hold on, 
            histogram(data(:, c), 100)
            histogram(output_data(:, c), 100)   
            hold off

            xlabel('Amplitude');
            ylabel(sprintf('Signal %d', original_col_idx));

            if c == 1
                title(sprintf('Detrending using %s', method), 'Interpreter', 'none');
            end

            if c == 1
                legend;
            end
        end
        save_figure(config, 'data_detrend_comparison_in_amplitude')
        
    end
end

function y = highpass_with_reflect_padding(x, b, a, fs, cutoff_hz, pad_sec_cfg)
% Apply zero-phase high-pass filtering with reflected edge padding.
% This reduces endpoint ringing artifacts from filtfilt.

    x = x(:);
    n = numel(x);
    y = nan(size(x));

    valid = isfinite(x);
    if nnz(valid) < 3
        return;
    end

    % Fill NaNs temporarily so filtfilt can run.
    xv = fillmissing(x, 'linear', 'EndValues', 'nearest');

    if isempty(pad_sec_cfg) || ~isfinite(pad_sec_cfg) || pad_sec_cfg <= 0
        % Roughly one cutoff period by default (bounded).
        pad_sec = min(120, max(10, 1 / max(cutoff_hz, eps)));
    else
        pad_sec = pad_sec_cfg;
    end

    base_guard = 3 * (max(numel(a), numel(b)) - 1);
    pad_len = max(base_guard, round(pad_sec * fs));
    pad_len = min(pad_len, floor((n - 1) / 2));

    if pad_len < 1
        y = filtfilt(b, a, xv);
        y(~valid) = NaN;
        return;
    end

    left_pad = xv(pad_len+1:-1:2);
    right_pad = xv(end-1:-1:end-pad_len);
    xp = [left_pad; xv; right_pad];

    yp = filtfilt(b, a, xp);
    y = yp(pad_len+1:pad_len+n);
    y(~valid) = NaN;
end
