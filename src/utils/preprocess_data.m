function [output, config, trend] = preprocess_data(t_series, config)
% preprocess_data
% Detrend configured signal columns, then resample all channels to
% config.new_fs.

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
        signal_cols = 1;
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

    [output, trend, config] = resample_preprocessed_data(output, trend, config, sampl_freq);
end

function [data_out, trend_out, config] = resample_preprocessed_data(data_in, trend_in, config, input_fs)
% Resample the full preprocessed data matrix and update config.new_fs/times.

    target_fs = input_fs;
    if isfield(config, 'new_fs') && ~isempty(config.new_fs)
        target_fs = config.new_fs;
    end

    if ~isfinite(target_fs) || target_fs <= 0
        error('config.new_fs must be a positive finite sampling rate.');
    end

    if target_fs > input_fs
        error('config.new_fs must be <= config.fs for downsampling.');
    end

    config.raw_fs = input_fs;
    config.preprocessing.original_fs = input_fs;
    config.preprocessing.new_fs = target_fs;

    if abs(target_fs - input_fs) <= max(eps(input_fs), eps(target_fs))
        data_out = data_in;
        trend_out = trend_in;
    else
        data_was_row_vector = isrow(data_in) && isvector(data_in);
        trend_was_row_vector = isrow(trend_in) && isvector(trend_in);

        data_resample_in = data_in;
        trend_resample_in = trend_in;
        if isvector(data_in)
            data_resample_in = data_in(:);
        end
        if isvector(trend_in)
            trend_resample_in = trend_in(:);
        end

        data_out = resample_matrix(data_resample_in, input_fs, target_fs);
        trend_out = resample_matrix(trend_resample_in, input_fs, target_fs);

        if data_was_row_vector
            data_out = data_out';
        end
        if trend_was_row_vector
            trend_out = trend_out';
        end
    end

    config.new_fs = target_fs;
    if isvector(data_out)
        n_samples = numel(data_out);
    else
        n_samples = size(data_out, 1);
    end
    config.times = (0:n_samples-1) / config.new_fs;
end

function y = resample_matrix(x, fs_in, fs_out)
% Resample columns while tolerating all-NaN trend columns.

    if isempty(x)
        y = x;
        return;
    end

    [p, q] = rat(fs_out / fs_in, 1e-12);
    y = [];

    for c = 1:size(x, 2)
        xc = x(:, c);
        valid = isfinite(xc);

        if any(valid)
            x_fill = xc;
            if ~all(valid)
                x_fill = fillmissing(x_fill, 'linear', 'EndValues', 'nearest');
            end
            yc = resample(x_fill, p, q);

            if ~all(valid)
                missing_mask = resample(double(~valid), p, q) > 0.01;
                yc(missing_mask) = NaN;
            end
        else
            yc = nan(size(resample(zeros(size(xc)), p, q)));
        end

        if isempty(y)
            y = nan(numel(yc), size(x, 2));
        end
        y(:, c) = yc;
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
