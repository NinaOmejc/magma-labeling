# Configuration

The main configuration file is:

```text
src/get_config_defaults.m
```

Only the most important settings are summarized here.

## Recording selection

```matlab
config.path_data_in
config.path_results_out
config.subjects
config.measurements
config.fs
config.data_columns
config.input_filename_pattern
```

## Recalculation and plotting

```matlab
config.overwrite_results
config.overwrite_features
config.make_figs_visible
config.verbosity
config.execution.mode
config.execution.selected_labels
```

Individual detector plots can additionally be controlled with the corresponding `do_plot` field.

The recording-level phenotype summary figure is controlled separately:

```matlab
config.PhenotypeSummary.do_plot = true;
config.PhenotypeSummary.show_reviewed = false;
```

By default it shows the automatic 22-feature numeric summary. Set
`show_reviewed` to `true` to add a reviewed column when a reviewed numeric
summary is present; automatic values are never substituted for reviewed values.

`config.verbosity = 1` prints concise progress, including important skip and
signal-availability messages. Set it to `2` for detailed pipeline-stage and
detector progress. Warnings and errors are always shown.

`config.execution.mode` is the sole switch for opening the unified final-label review:

```matlab
config.execution.mode = 'analyze';            % automatic analysis only
config.execution.mode = 'analyze_and_review'; % analyze, then review
config.execution.mode = 'review_only';        % load automatic results, then review
```

`config.execution.selected_labels = {}` keeps normal behavior. A non-empty
canonical subset, such as `{'irregular'}` or `{'irregular','slow'}`, computes
only those detectors. If a result already exists, the selected labels are
replaced and all non-selected automatic and reviewed annotations are preserved;
`overwrite_results` does not need to be enabled for this selective update. On a
new recording, unselected labels retain their canonical columns and are marked
unavailable with reason `not_computed`. Label selection is not valid with
`review_only`; review the saved merged result in a separate review-only run.

`review_only` requires an existing recording result. It loads the saved
automatic annotations and respiratory cycles without rerunning feature
extraction or detectors. Recording results use the filenames
`Sub<subject>_M<measurement>_results.mat` and
`Sub<subject>_M<measurement>_results.h5`; the respiratory-feature cache remains
`Sub<subject>_M<measurement>_features.mat`.

## Respiratory-cycle extraction

Preprocessing first aligns the diaphragm belt with the lung belt, then checks
their common orientation using a temporary average of the separately
standardized belts. Within each complete breath, time above the midpoint
between its peak and neighboring troughs measures whether high peaks are
narrow or broad. Narrow highs in at least 65% of breaths keep the orientation;
broad highs in at least 65% flip both belts. A 0.45–0.55 midpoint-dwell band
leaves near-symmetric shapes unchanged. The shared I:E ratio remains a
diagnostic; one usable belt falls back to its own I:E ratio. The settings are:

The relative correction flips the diaphragm when the median informative-window
correlation is at most `-0.65`, at least 80% of informative windows are
negative, and at least 60% of windows are informative.

```matlab
config.preprocessing.check_belt_polarity = true;
config.preprocessing.absolute_polarity.enabled = true;
config.preprocessing.absolute_polarity.ratio_lower = 0.90;
config.preprocessing.absolute_polarity.ratio_upper = 1.10;
config.preprocessing.absolute_polarity.majority_threshold = 0.65;
config.preprocessing.absolute_polarity.high_dwell_lower = 0.45;
config.preprocessing.absolute_polarity.high_dwell_upper = 0.55;
config.preprocessing.absolute_polarity.min_valid_breaths = 10;
```

The separate relative and absolute decisions are saved under
`config.preprocessing.belt_polarity_qc` and
`config.preprocessing.absolute_polarity_qc`. Final breath landmarks are
detected after both polarity steps, before manual review.

With `config.overwrite_features = false`, an existing compatible
`*_features.mat` keeps the respiratory signal orientation used when its peaks
and troughs were reviewed, even if the current polarity heuristic chooses a
different orientation. The current heuristic's QC is retained in
`config.preprocessing.computed_polarity_qc`. Set `overwrite_features = true`
for recordings whose polarity and landmarks should be recomputed and reviewed
again. An incompatible manually reviewed cache is never silently overwritten.

```matlab
config.resp.manual_control
config.resp.manual_window_sec
config.resp.min_peak_dist_sec
config.resp.min_peak_prom
config.resp.min_peak_height
config.resp.smooth_sec
config.resp.trough_method
config.resp.amp_method
```

`config.resp.amp_method` selects the canonical respiratory excursion used by downstream amplitude-dependent analyses:

```text
'expiratory'
'inspiratory'
'symmetric'
```

The primary analysis uses:

```matlab
config.resp.amp_method = 'expiratory';
```

Respiratory peaks are detected once and reused by all downstream labels.

Respiratory-cycle peak/trough review is a distinct upstream step controlled by
`config.resp.manual_control`, independent of `config.execution.mode`. Confirmed
cycles and their review provenance are saved in the respiratory-feature cache.
In the review GUI, red peaks can be added or removed. Existing blue trough dots
can be moved independently to another finite sample strictly between their two
surrounding peaks. Blue dots are editable trough landmarks; they are not
explicit hold boundaries. Each manual trough correction remains anchored to its
surrounding peak sample pair, so a later peak edit invalidates only corrections
whose pair changed.

## Session reference

```matlab
config.reference.pre_start_min  = 3;
config.reference.pre_end_min    = 6;

config.reference.post_start_min = 19;
config.reference.post_end_min   = 22;
```

Thus:

- M1/M3 use 3–6 min;
- M2/M4 use 19–22 min.

The interval is never automatically moved to a different part of the recording.

## Label-specific configuration

Each detector has its own configuration section:

```matlab
config.shallow
config.deep
config.slow
config.rapid
config.irregular
config.apnea
config.sigh
config.periodic
config.thoracic
config.async
config.desat
```

See [LABELS.md](LABELS.md) for the primary conditions.

## Primary literature-based methods

### Sigh

```matlab
config.sigh.method = 'rolling_median_2x';
```

The primary sigh criterion compares each breath with a centered 15-breath local median.

### Periodic breathing

```matlab
config.periodic.primary_method = 'eami';
```

The Guyot method is retained as a secondary comparison.

The tuned periodic settings are MAGMA adaptations rather than exact published
thresholds:

```matlab
config.periodic.eami.threshold = 0.60;
config.periodic.guyot.fm_band_hz = [0.008 0.050];
```

Guyot uses centered 120-second windows with 80% overlap. Each classification
represents its nearest-center interval (about 24 seconds per center step), not
the full analysis window, before the 60-second persistence rule is applied.

### Respiratory asynchrony

For the final analysis:

```matlab
config.async.primary_method = 'wavelet_phase_offset';
config.async.compare_methods = true;
config.async.plot_legacy_coherence = false;
```

The older wavelet-coherence method remains available as complementary evidence.
Its respiratory-band comparison subplot is hidden by default and can be added
at the bottom of the diagnostic figure independently of `compare_methods`.

Important phase-offset settings include:

```matlab
config.async.phase_offset.angle_threshold_deg = 30;
config.async.phase_offset.summary_cycles = 5;
config.async.phase_offset.min_resultant_length = 0.80;
config.async.phase_offset.min_valid_fraction = 0.80;

config.async.phase_offset.frequency_min_hz = 0.052;
config.async.phase_offset.frequency_max_hz = 0.60;
```

Reviewed breath timing guides selection of the shared respiratory fundamental when available. Joint thoracic/abdominal wavelet magnitude is used within the allowed neighborhood or as a fallback.

Sensor polarity is fixed by configuration/acquisition and must never be optimized separately for each recording.

Missing-data blocks are not bridged during phase analysis.

## Manual review

The unified 11-label reviewer is enabled only when:

```matlab
ismember(config.execution.mode, {'analyze_and_review', 'review_only'})
```

Sighs are edited in the same reviewer and snap to respiratory breaths. There
are no separate sigh/final-label manual-control, apply-saved, or save-review
switches. Review
rounds are always appended to the persistent history file and record the
automatic `source_analysis_id` they derive from. Settings that remain:

```matlab
config.LabelEdit.start_from
config.LabelEdit.reviewer_role
```

For example, a clinician can review the frozen automatic analysis with:

```matlab
config.execution.mode = 'review_only';
config.LabelEdit.start_from = 'automatic';
config.LabelEdit.reviewer_role = 'clinician';
```

Automatic and manually reviewed annotations remain separate.

## Saved-result cohort analysis

`run('src/main_group.m')` uses `config.group` and reads saved
`*_results.mat` files only. To override the defaults, define `config`
before calling `run`:

```matlab
config = get_config_defaults();
config.group.subjects = [];             % discover all saved subject IDs
config.group.measurements = [1 2];      % M1 and M2
config.group.exclude_subjects = config.remove_subjects;
config.group.control_subjects = [];     % optional metadata
config.group.patient_subjects = [];     % optional metadata
config.group.paired_measurements = [1 2];
config.group.plot_layer = 'automatic';   % or 'reviewed'
config.group.plot_label_histograms = true;
config.group.plot_stratified_histograms = true;
run('src/main_group.m');
```

Set `subjects` to numeric IDs for a subset. Empty `subjects` discovers
all saved IDs; exclusions still apply. `measurements` can be any distinct
subset of 1–4. Set `paired_measurements` to two distinct values in 1–4,
such as `[3 4]` or `[1 3]`, and include both in `measurements`.
Pairs match by subject ID. Subjects without both recordings remain in the
`group_details.xlsx` Paired_changes sheet with an invalid-pair flag. Missing control/patient metadata are
reported as `Unknown`; group membership is never inferred from IDs.

When both explicit group lists are empty, `main_group.m` looks for
`ML_database_WORK_IN_PROGRESS_20Sep26_MG.xlsx` two directories above
`config.path_results_out`. It reads only `Questionnaire` columns
`Sub_code` and `grp`: 0 means Control (healthy control) and 1 means
Patient, as defined by the workbook dictionary. Matching uses the numeric
subject ID in `Sub_code`; unmatched subjects stay `Unknown`.
Explicit `control_subjects`/`patient_subjects` lists take precedence.
Set `config.group.metadata_file` to a specific workbook path to override
discovery, or to `''` to disable it. Group-specific histograms are generated
when Control or Patient subjects are present.

M1 is before rehabilitation and before exercise/stress; M2 is before
rehabilitation and after exercise/stress. M3 and M4 are the analogous
before/after exercise recordings after rehabilitation. The default M1 to M2
difference does not estimate rehabilitation effectiveness.

Group tables are consolidated in `group_summary.xlsx` and `group_details.xlsx`.
Only `group_label_burden_histograms_automatic` plots are generated, including
the Control, Patient, and combined variants when metadata are present. Set
the two remaining plot switches to false for tables only. `plot_layer` selects
the descriptive and paired table layer; selecting `reviewed` generates tables
without plots. The diagnostic overview and other descriptive plots have been
removed. See [OUTPUTS.md](OUTPUTS.md) for the worksheet layout.
