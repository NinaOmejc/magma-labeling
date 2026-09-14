function [is_normal, p_value, stats] = check_normality(x, varargin)
% CHECK_NORMALITY Test finite observations with Lilliefors, Jarque-Bera, or AD.
% x is flattened and requires at least eight finite values. Name-value options
% are Alpha, DoPlot, and Method. is_normal means the test did not reject at
% alpha; p_value is the test p-value. stats stores test name/statistic/critical
% value plus n, mean, std, skewness, kurtosis, alpha, p_value, and is_normal.

    alpha = 0.05;
    do_plot = false;
    method = 'lillie';

    % -----------------------------
    % Parse optional inputs
    % -----------------------------
    if mod(length(varargin), 2) ~= 0
        error('Optional arguments must be name-value pairs.');
    end

    for k = 1:2:length(varargin)
        switch lower(varargin{k})
            case 'alpha'
                alpha = varargin{k+1};

            case 'doplot'
                do_plot = varargin{k+1};

            case 'method'
                method = lower(varargin{k+1});

            otherwise
                error('Unknown option: %s', varargin{k});
        end
    end

    % -----------------------------
    % Clean input
    % -----------------------------
    x = x(:);
    x = x(isfinite(x));

    if numel(x) < 8
        error('Not enough finite data points to test normality.');
    end

    % -----------------------------
    % Normality test
    % -----------------------------
    switch method
        case 'lillie'
            warning_state = warning('off', 'all');
        
            [h, p_value, ksstat, critval] = lillietest(x, 'Alpha', alpha);
        
            warning(warning_state);
        
            stats.test = 'Lilliefors';
            stats.h = h;
            stats.ksstat = ksstat;
            stats.critval = critval;
        
            if p_value <= 0.001
                stats.p_string = '<= 0.001';
            else
                stats.p_string = sprintf('%.4g', p_value);
            end

        case 'jb'
            % Jarque-Bera test, based on skewness and kurtosis
            [h, p_value, jbstat, critval] = jbtest(x, alpha);

            stats.test = 'Jarque-Bera';
            stats.h = h;
            stats.jbstat = jbstat;
            stats.critval = critval;

        case 'ad'
            % Anderson-Darling test
            [h, p_value, adstat, critval] = adtest(x, 'Alpha', alpha);

            stats.test = 'Anderson-Darling';
            stats.h = h;
            stats.adstat = adstat;
            stats.critval = critval;

        otherwise
            error('Unknown method. Use ''lillie'', ''jb'', or ''ad''.');
    end

    % h = 0 means do not reject normality
    % h = 1 means reject normality
    is_normal = (h == 0);

    % -----------------------------
    % Additional descriptive stats
    % -----------------------------
    stats.n = numel(x);
    stats.mean = mean(x);
    stats.std = std(x);
    stats.skewness = skewness(x);
    stats.kurtosis = kurtosis(x);
    stats.alpha = alpha;
    stats.p_value = p_value;
    stats.is_normal = is_normal;

    % -----------------------------
    % Optional plot
    % -----------------------------
    if do_plot
        figure;
        hold on;

        histogram(x, 'Normalization', 'pdf');

        mu = mean(x);
        sigma = std(x);

        x_grid = linspace(min(x), max(x), 300);
        y_norm = normpdf(x_grid, mu, sigma);

        plot(x_grid, y_norm, 'LineWidth', 2);

        grid on;
        xlabel('Value');
        ylabel('Probability density');
        title(sprintf('%s normality test: p = %.4g, normal = %d', ...
            stats.test, p_value, is_normal));

        legend('Data histogram', 'Fitted normal distribution');

        hold off;
    end
end
