function [signals_normality, normality_stats] = check_normalities(sigs, config)
%CHECK_NORMALITIES Check normality of multiple signal fields and optionally plot.
%
% Inputs:
%   sigs   - struct containing fields such as x0, peak_val, trough_val, amp, ibi_s, rr_bpm
%   config - config struct, optional fields:
%       config.normality.do_plot = true/false
%       config.normality.alpha   = 0.05
%       config.normality.method  = 'lillie', 'ad', or 'jb'
%
% Outputs:
%   signals_normality - logical vector, true if field is approximately normal
%   normality_stats   - struct with p-values and descriptive stats per field

    % -----------------------------
    % Defaults
    % -----------------------------

    if ~sigs.ok 
        return
    end
    
    col_names = {'x0', 'peak_val', 'trough_val', 'amp', 'ibi', 'rr_bpm'};

    do_plot = true;
    alpha = 0.05;
    method = 'lillie';

    % if nargin >= 2 && isfield(config, 'normality')
    %     if isfield(config.normality, 'do_plot')
    %         do_plot = config.normality.do_plot;
    %     end
    %     if isfield(config.normality, 'alpha')
    %         alpha = config.normality.alpha;
    %     end
    %     if isfield(config.normality, 'method')
    %         method = config.normality.method;
    %     end
    % end

    % -----------------------------
    % Allocate outputs
    % -----------------------------
    n_cols = length(col_names);

    signals_normality = false(1, n_cols);
    normality_stats = struct();

    % -----------------------------
    % Optional figure
    % -----------------------------
    if do_plot
        figure('Units', 'pixels', 'Position', [100 100 1400 800], 'Visible', config.make_figs_visible);
        tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    end

    % -----------------------------
    % Loop over fields
    % -----------------------------
    for i = 1:n_cols
        sig_name = col_names{i};

        if ~isfield(sigs, sig_name)
            warning('Field "%s" not found in sigs. Skipping.', sig_name);

            normality_stats.(sig_name).is_normal = false;
            normality_stats.(sig_name).p_value = NaN;
            normality_stats.(sig_name).n = 0;
            normality_stats.(sig_name).message = 'Field missing';

            if do_plot
                nexttile;
                title(sprintf('%s missing', sig_name), 'Interpreter', 'none');
                axis off;
            end

            continue
        end

        sig = sigs.(sig_name);
        sig = sig(:);
        sig = sig(isfinite(sig));

        if numel(sig) < 8
            warning('Field "%s" has fewer than 8 finite values. Skipping.', sig_name);

            normality_stats.(sig_name).is_normal = false;
            normality_stats.(sig_name).p_value = NaN;
            normality_stats.(sig_name).n = numel(sig);
            normality_stats.(sig_name).message = 'Too few finite values';

            if do_plot
                nexttile;
                title(sprintf('%s: too few values', sig_name), 'Interpreter', 'none');
                axis off;
            end

            continue
        end

        % Run normality test without plotting
        [sig_is_normal, p_value, stats] = check_normality(sig, ...
            'DoPlot', false, ...
            'Alpha', alpha, ...
            'Method', method);

        signals_normality(i) = sig_is_normal;
        normality_stats.(sig_name) = stats;

        % -----------------------------
        % Plot in wrapper
        % -----------------------------
        if do_plot
            nexttile;
            hold on;

            histogram(sig, 'Normalization', 'pdf');

            mu = mean(sig, 'omitnan');
            sigma = std(sig, 'omitnan');

            if isfinite(mu) && isfinite(sigma) && sigma > 0
                x_grid = linspace(min(sig), max(sig), 300);
                y_norm = normpdf(x_grid, mu, sigma);
                plot(x_grid, y_norm, 'LineWidth', 2);
            end

            grid on;
            xlabel(sig_name, 'Interpreter', 'none');
            ylabel('PDF');

            title(sprintf('%s | p = %.3g | normal = %d', ...
                sig_name, p_value, sig_is_normal), ...
                'Interpreter', 'none');

            legend('Data', 'Normal fit', 'Location', 'best');
            hold off;
        end
    end

    % Optional global title
    if do_plot
        sgtitle(sprintf('Normality check using %s test, alpha = %.3g', ...
            method, alpha), ...
            'Interpreter', 'none');

        save_figure(config, ['normality_test_' sigs.basename])
    end
end