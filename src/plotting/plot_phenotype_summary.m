function fig = plot_phenotype_summary(phenotypes, config, review_history, recording_context)
% PLOT_PHENOTYPE_SUMMARY Render the final recording-level phenotype values.
%
% Inputs:
%   phenotypes - Completed phenotype bundle from build_recording_results.
%   config     - Pipeline settings supplying figure and output options.
%   review_history - Optional immutable rounds; each gets a numeric column.
%   recording_context - Optional recording-level reference QC and warning state.
%
% Output:
%   fig - Figure handle while plotting; empty after save_figure or when disabled.
%
% The figure presents existing numeric_summary values; recording QC is shared. It
% deliberately performs no phenotype, burden, overlap, or score calculation.

    if nargin < 4, recording_context = struct(); end
    fig = [];
    if nargin < 2 || isempty(config) || ...
            ~isfield(config, 'PhenotypeSummary') || ...
            ~isfield(config.PhenotypeSummary, 'do_plot') || ...
            ~config.PhenotypeSummary.do_plot
        return;
    end

    automatic = require_numeric_summary(phenotypes, 'automatic');
    schema = get_phenotype_feature_schema();

    if nargin < 3, review_history = struct([]); end
    [reviews, round_ids] = review_summaries(review_history);

    sections = phenotype_sections();
    feature_order = collect_feature_order(schema, sections);
    if ~isequal(feature_order, 1:schema.n_features)
        error('MAGMA:PhenotypeSummary:IncompleteLayout', ...
            'Phenotype-summary layout must contain every schema feature exactly once.');
    end

    n_groups = numel(sections{1}.groups); % Only literature profiles need group headings.
    n_rows = 1 + numel(sections) + n_groups + schema.n_features + 4;
    fig_height = max(780, 24 * n_rows);
    fig_width = 860 + 160 * numel(reviews);
    fig = figure( ...
        'Units', 'pixels', ...
        'Position', [60 40 fig_width fig_height], ...
        'Visible', config.make_figs_visible, ...
        'Color', 'w');
    ax = axes('Parent', fig, 'Position', [0.025 0.025 0.95 0.95]);
    hold(ax, 'on');
    axis(ax, 'off');
    xlim(ax, [0 1]);
    ylim(ax, [0 n_rows + 2.6]);
    set(ax, 'YDir', 'reverse');

    columns = table_columns(numel(reviews), fig_width);
    y = 0.65;
    text(ax, 0.5, y, sprintf( ...
        'Phenotype Summary | Subject %d | Measurement %d', ...
        config.subject, config.measure), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
        'FontSize', 14, 'Interpreter', 'none');

    y = y + 1.35;
    draw_header(ax, y, columns, round_ids);
    y = y + 1;

    for section_index = 1:numel(sections)
        section = sections{section_index};
        rectangle(ax, 'Position', [0.01 y - 0.42 0.98 0.84], ...
            'FaceColor', [0.90 0.92 0.94], 'EdgeColor', 'none');
        text(ax, 0.025, y, section.title, ...
            'FontWeight', 'bold', 'Interpreter', 'none');
        y = y + 1;

        for group_index = 1:numel(section.groups)
            group_key = section.groups{group_index};
            if section_index == 1
                text(ax, 0.035, y, phenotype_group_title(group_key), ...
                    'FontWeight', 'bold', 'Color', [0.12 0.20 0.28], ...
                    'Interpreter', 'none');
                line(ax, [0.03 0.98], [y + 0.43 y + 0.43], ...
                    'Color', [0.82 0.84 0.86], 'LineWidth', 0.6);
                y = y + 1;
            end

            if strcmp(group_key, 'forced_abdominal_expiration')
                text(ax, 0.055, y, 'Not assessable from current signals', ...
                    'Color', [0.40 0.40 0.40], 'FontAngle', 'italic', ...
                    'Interpreter', 'none');
                y = y + 1;
                continue;
            end

            feature_indices = find(strcmp(schema.phenotype_group, group_key));
            for feature_index = feature_indices
                draw_feature_row(ax, y, feature_index, schema, automatic, ...
                    reviews, columns);
                y = y + 1;
            end
        end
    end

    y = y + 0.4;
    text(ax, 0.025, y, sprintf('Reference QC | Thoracic: %s | Abdominal: %s', ...
        reference_quality_text(recording_context, 'lungs'), ...
        reference_quality_text(recording_context, 'diaph')), ...
        'Interpreter', 'none', 'FontSize', 9, 'Color', [0.35 0.35 0.35]);
    artifacts_pending = isfield(recording_context,'respiratory_artifact_state') && ...
        recording_context.respiratory_artifact_state.pending_reanalysis;
    if artifacts_pending || (isfield(recording_context,'recording_observations') && ...
            recording_context.recording_observations.pending_reanalysis)
        text(ax,0.5,1.3,'PENDING REANALYSIS: automatic results retain their original analysis evidence.', ...
            'HorizontalAlignment','center','Color',[0.75 0.2 0.05],'Interpreter','none');
    end
    hold(ax, 'off');
    figure(fig);
    save_figure(config, 'phenotype_summary');
    fig = [];
end

function quality = reference_quality_text(recording_context, belt_name)
% REFERENCE_QUALITY_TEXT Display saved QC categories without reclassifying them.

    quality = 'Unavailable';
    if ~isfield(recording_context, 'resp_ref') || ...
            ~isfield(recording_context.resp_ref, belt_name) || ...
            ~isfield(recording_context.resp_ref.(belt_name), 'reference_quality')
        return;
    end
    saved_quality = char(string(recording_context.resp_ref.(belt_name).reference_quality));
    if ~isempty(saved_quality)
        quality = strrep(saved_quality, '_', ' ');
    end
end

function summary = require_numeric_summary(phenotypes, layer_name)
% REQUIRE_NUMERIC_SUMMARY Return one validated, already-computed layer.

    if ~isstruct(phenotypes) || ~isscalar(phenotypes) || ...
            ~isfield(phenotypes, layer_name) || ...
            ~isstruct(phenotypes.(layer_name)) || ...
            ~isfield(phenotypes.(layer_name), 'numeric_summary')
        error('MAGMA:PhenotypeSummary:MissingNumericSummary', ...
            'phenotypes.%s.numeric_summary is required.', layer_name);
    end
    summary = align_phenotype_numeric_summary(phenotypes.(layer_name).numeric_summary);
end

function sections = phenotype_sections()
% PHENOTYPE_SECTIONS Define clinician-facing section and profile order.

    sections = { ...
        struct( ...
            'title', 'Literature-based breathing-pattern phenotypes', ...
            'groups', {{ ...
                'hyperventilation_like', ...
                'periodic_deep_sighing', ...
                'thoracic_dominant_breathing', ...
                'thoracoabdominal_asynchrony', ...
                'forced_abdominal_expiration'}}), ...
        struct( ...
            'title', 'Label-based respiratory pattern profiles', ...
            'groups', {{ ...
                'apneic_breathing', ...
                'periodic_breathing', ...
                'shallow_breathing', ...
                'slow_breathing', ...
                'irregular_breathing', ...
                'desaturation'}}), ...
        struct('title','Minimal or absent thoracic excursion', ...
            'groups',{{'minimal_thoracic_excursion'}})};
end

function feature_order = collect_feature_order(schema, sections)
% COLLECT_FEATURE_ORDER Verify that grouping preserves the schema contract.

    feature_order = [];
    for section_index = 1:numel(sections)
        groups = sections{section_index}.groups;
        for group_index = 1:numel(groups)
            group_key = groups{group_index};
            if strcmp(group_key, 'forced_abdominal_expiration')
                continue;
            end
            feature_order = [feature_order, ... %#ok<AGROW>
                find(strcmp(schema.phenotype_group, group_key))];
        end
    end
end

function [reviews, round_ids] = review_summaries(history)
% REVIEW_SUMMARIES Read snapshots in round order without recomputing history.

    reviews = {};
    round_ids = [];
    if isempty(history), return; end
    [round_ids, order] = sort([history.round_id]);
    reviews = cell(1, numel(order));
    for i = 1:numel(order)
        entry = history(order(i));
        if isfield(entry, 'phenotype_numeric_summary_reviewed') && ...
                ~isempty(entry.phenotype_numeric_summary_reviewed)
            reviews{i} = entry.phenotype_numeric_summary_reviewed;
        elseif isfield(entry, 'phenotypes_reviewed') && ~isempty(entry.phenotypes_reviewed)
            reviews{i} = entry.phenotypes_reviewed.numeric_summary;
        end
        if ~isempty(reviews{i}), reviews{i} = align_phenotype_numeric_summary(reviews{i}); end
    end
end

function columns = table_columns(n_reviews, fig_width)
% TABLE_COLUMNS Keep label/value spacing stable as review columns are added.

    columns = struct();
    columns.feature = 0.045;
    columns.values = (700 + 160 * (0:n_reviews)) / fig_width;
end

function draw_header(ax, y, columns, round_ids)
% DRAW_HEADER Render table column names.

    line(ax, [0.03 0.98], [y + 0.43 y + 0.43], ...
        'Color', [0.45 0.48 0.50], 'LineWidth', 1.0);
    text(ax, columns.feature, y, 'Measure', 'FontWeight', 'bold');
    headers = [{'Automatic'}, arrayfun(@(id) sprintf('Review %d', id), ...
        round_ids, 'UniformOutput', false)];
    for i = 1:numel(headers)
        text(ax, columns.values(i), y, headers{i}, ...
            'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    end
end

function draw_feature_row(ax, y, index, schema, automatic, reviews, columns)
% DRAW_FEATURE_ROW Render existing values without rescaling or imputation.

    label = schema.display_name{index};
    if strcmp(schema.feature_role{index}, 'label_based')
        label = [phenotype_group_title(schema.phenotype_group{index}) ' burden'];
    end
    text(ax, columns.feature, y, sprintf('%s (%s)', label, display_unit(schema.units{index})), ...
        'Interpreter', 'none');
    summaries = [{automatic}, reviews];
    for i = 1:numel(summaries)
        [value_text, value_color] = display_value(summaries{i}, index);
        if index == 23 && i > 1 && ~isempty(summaries{i}) && summaries{i}.available(index)
            value_text = 'Recording QC'; value_color = [0.35 0.35 0.35];
        elseif index == 24
            value_text = 'Not assessed';
            if ~isempty(summaries{i}) && summaries{i}.available(index)
                value_text = 'Not observed (0)';
                if summaries{i}.values(index) == 1, value_text = 'Observed (1)'; end
            end
        end
        text(ax, columns.values(i), y, value_text, ...
            'HorizontalAlignment', 'right', 'Color', value_color, ...
            'Interpreter', 'none');
    end
end

function [value_text, value_color] = display_value(summary, index)
% DISPLAY_VALUE Distinguish not computed, unavailable, and measured values.

    value_color = [0 0 0];
    if isempty(summary) || strcmp(summary.missing_reason{index}, 'not_computed')
        value_text = 'Not computed';
        value_color = [0.45 0.45 0.45];
    elseif ~summary.available(index)
        value_text = 'Unavailable';
    else
        value_text = sprintf('%.2f', summary.values(index));
    end
end

function unit_text = display_unit(schema_unit)
% DISPLAY_UNIT Convert schema unit tokens to compact display text.

    switch schema_unit
        case 'breaths_per_min'
            unit_text = 'breaths/min';
        case 'events_per_15_min'
            unit_text = 'events/15 min';
        otherwise
            unit_text = strrep(schema_unit, '_', ' ');
    end
end

function title_text = phenotype_group_title(group_key)
% PHENOTYPE_GROUP_TITLE Map schema group identifiers to readable headings.

    switch group_key
        case 'hyperventilation_like'
            title_text = 'Hyperventilation-like respiratory pattern';
        case 'periodic_deep_sighing'
            title_text = 'Periodic deep sighing';
        case 'thoracic_dominant_breathing'
            title_text = 'Thoracic-dominant breathing';
        case 'thoracoabdominal_asynchrony'
            title_text = 'Thoraco-abdominal asynchrony';
        case 'minimal_thoracic_excursion'
            title_text = 'Minimal or absent thoracic excursion';
        case 'forced_abdominal_expiration'
            title_text = 'Forced abdominal expiration';
        case 'apneic_breathing'
            title_text = 'Apneic breathing';
        case 'periodic_breathing'
            title_text = 'Periodic breathing';
        case 'shallow_breathing'
            title_text = 'Shallow breathing';
        case 'slow_breathing'
            title_text = 'Slow breathing';
        case 'irregular_breathing'
            title_text = 'Irregular breathing';
        case 'desaturation'
            title_text = 'Desaturation';
        otherwise
            error('MAGMA:PhenotypeSummary:UnknownGroup', ...
                'No display heading is defined for phenotype group "%s".', group_key);
    end
end
