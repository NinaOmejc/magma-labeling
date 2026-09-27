function fig = plot_phenotype_summary(phenotypes, config)
% PLOT_PHENOTYPE_SUMMARY Render the final recording-level phenotype values.
%
% Inputs:
%   phenotypes - Completed phenotype bundle from build_recording_results.
%   config     - Pipeline settings supplying figure and output options.
%
% Output:
%   fig - Figure handle while plotting; empty after save_figure or when disabled.
%
% The figure is a presentation of existing numeric_summary values only. It
% deliberately performs no phenotype, burden, overlap, or score calculation.

    fig = [];
    if nargin < 2 || isempty(config) || ...
            ~isfield(config, 'PhenotypeSummary') || ...
            ~isfield(config.PhenotypeSummary, 'do_plot') || ...
            ~config.PhenotypeSummary.do_plot
        return;
    end

    automatic = require_numeric_summary(phenotypes, 'automatic');
    schema = get_phenotype_feature_schema();

    show_reviewed = isfield(config.PhenotypeSummary, 'show_reviewed') && ...
        config.PhenotypeSummary.show_reviewed;
    reviewed = [];
    if show_reviewed && isfield(phenotypes, 'reviewed') && ...
            isstruct(phenotypes.reviewed) && ...
            isfield(phenotypes.reviewed, 'numeric_summary')
        reviewed = require_numeric_summary(phenotypes, 'reviewed');
    end

    sections = phenotype_sections();
    feature_order = collect_feature_order(schema, sections);
    if ~isequal(feature_order, 1:schema.n_features)
        error('MAGMA:PhenotypeSummary:IncompleteLayout', ...
            'Phenotype-summary layout must contain every schema feature exactly once.');
    end

    n_groups = sum(cellfun(@(item) numel(item.groups), sections));
    n_rows = 1 + numel(sections) + n_groups + schema.n_features + 1;
    fig_height = max(900, 32 * n_rows);
    fig = figure( ...
        'Units', 'pixels', ...
        'Position', [60 40 1500 fig_height], ...
        'Visible', config.make_figs_visible, ...
        'Color', 'w');
    ax = axes('Parent', fig, 'Position', [0.025 0.025 0.95 0.95]);
    hold(ax, 'on');
    axis(ax, 'off');
    xlim(ax, [0 1]);
    ylim(ax, [0 n_rows + 2.6]);
    set(ax, 'YDir', 'reverse');

    has_reviewed = ~isempty(reviewed);
    columns = table_columns(has_reviewed);
    y = 0.65;
    text(ax, 0.5, y, sprintf( ...
        'Phenotype Summary | Subject %d | Measurement %d', ...
        config.subject, config.measure), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
        'FontSize', 14, 'Interpreter', 'none');

    y = y + 1.35;
    draw_header(ax, y, columns, has_reviewed);
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
            text(ax, 0.035, y, phenotype_group_title(group_key), ...
                'FontWeight', 'bold', 'Color', [0.12 0.20 0.28], ...
                'Interpreter', 'none');
            line(ax, [0.03 0.98], [y + 0.43 y + 0.43], ...
                'Color', [0.82 0.84 0.86], 'LineWidth', 0.6);
            y = y + 1;

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
                    reviewed, columns, has_reviewed);
                y = y + 1;
            end
        end
    end

    hold(ax, 'off');
    figure(fig);
    save_figure(config, 'phenotype_summary');
    fig = [];
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
    summary = phenotypes.(layer_name).numeric_summary;
    validate_compact_phenotype_features(summary);
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
                'desaturation'}})};
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

function columns = table_columns(has_reviewed)
% TABLE_COLUMNS Resolve stable table positions for one or two value layers.

    columns = struct();
    columns.feature = 0.055;
    columns.unit = 0.66;
    if has_reviewed
        columns.automatic = 0.82;
        columns.reviewed = 0.94;
    else
        columns.automatic = 0.91;
        columns.reviewed = NaN;
    end
end

function draw_header(ax, y, columns, has_reviewed)
% DRAW_HEADER Render table column names.

    line(ax, [0.03 0.98], [y + 0.43 y + 0.43], ...
        'Color', [0.45 0.48 0.50], 'LineWidth', 1.0);
    text(ax, columns.feature, y, 'Measure', 'FontWeight', 'bold');
    text(ax, columns.unit, y, 'Unit', ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    text(ax, columns.automatic, y, 'Automatic', ...
        'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    if has_reviewed
        text(ax, columns.reviewed, y, 'Reviewed', ...
            'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    end
end

function draw_feature_row(ax, y, index, schema, automatic, reviewed, columns, has_reviewed)
% DRAW_FEATURE_ROW Render existing values without rescaling or imputation.

    text(ax, columns.feature, y, schema.display_name{index}, ...
        'Interpreter', 'none');
    text(ax, columns.unit, y, display_unit(schema.units{index}), ...
        'HorizontalAlignment', 'center', 'Color', [0.35 0.35 0.35], ...
        'Interpreter', 'none');
    text(ax, columns.automatic, y, display_value(automatic, index), ...
        'HorizontalAlignment', 'right', 'Interpreter', 'none');
    if has_reviewed
        text(ax, columns.reviewed, y, display_value(reviewed, index), ...
            'HorizontalAlignment', 'right', 'Interpreter', 'none');
    end
end

function value_text = display_value(summary, index)
% DISPLAY_VALUE Preserve explicit unavailable versus available-zero states.

    if ~summary.available(index)
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
