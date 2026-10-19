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
config.exclude_recordings = [3 1; 3 2; 23 1]; % [] to exclude none
config.fs
config.data_columns
config.input_filename_pattern
```

`exclude_recordings` is an N-by-2 matrix of `[subject, measurement]` pairs.
Both recording analysis and group analysis omit matching pairs; other measurements
for the subject remain eligible. IDs must be finite integers: subject >= 0
(0 is allowed for synthetic recordings), measurement in 1:4. Invalid lists
raise `MAGMA:Config:InvalidExcludedRecordings` before recording data is loaded.
The default lists explicitly cover M1-M4 for the previously excluded subjects.
`config.problems.missing_lung_belt` remains a separate signal-availability setting.

The two manual editors also offer **Minimal or absent thoracic excursion**. Use this recording-level observation when the belt is present but
reliable thoracic breaths cannot be extracted. It does not edit
`config.problems.missing_lung_belt` or create a new label. Its saved state is shared
by subject **and** measurement. The selector offers **Not assessed**, **Not observed**,
and **Observed**, initialized from the saved status. Accepting peak/trough or label
review with the selector untouched preserves `not_assessed`; only an explicit
selection records a negative or positive assessment. Cancel/X does not commit it. A technically missing belt disables the selector
and does not create a negative assessment.
`config.LabelEdit.reviewer_role` supplies the observation's reviewer provenance
in either editor. See [the observation schema and reanalysis workflow](OUTPUTS.md#recording-level-thoracic-observation)
for pending-output handling after a late annotation. The two associated numeric
phenotype features are documented in [PHENOTYPES.md](PHENOTYPES.md#thoracic-excursion-phenotype-and-rhythmicity).

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
```

The single `phenotype_summary.png` shows Automatic and automatically adds
Review 1, Review 2, etc. from saved per-round phenotype snapshots, in round
order. It is refreshed after successful review in both review-only and combined
analysis/review runs. There is no separate reviewed-figure switch or filename.
Legacy rounds without stored phenotype values show Not computed; their values
are not reconstructed or substituted from the latest round.

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
broad highs in at least 65% flip both belts. A 0.45Ã¢â‚¬â€œ0.55 midpoint-dwell band
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

- M1/M3 use 3Ã¢â‚¬â€œ6 min;
- M2/M4 use 19Ã¢â‚¬â€œ22 min.

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
config.sigh.method = 'session_reference_2x';
config.sigh.session_ratio_threshold = 2.0;
config.sigh.compare_methods = false;
```

The default classifies a breath when its existing per-belt
`amp_ratio_session >= session_ratio_threshold`. It requires a valid fixed
session reference and `session_amplitude_available`; unavailable evidence is
not a negative classification and never triggers a local/global fallback.
Reference QC flags remain visible in diagnostics. Canonical amplitudes still
follow `config.resp.amp_method`.

For methodological comparison, select `config.sigh.method = 'rolling_median_2x'`
to use the existing centered 15-breath median instead. Its separate threshold
remains `config.sigh.rolling_ratio_threshold = 2.0`. Setting
`config.sigh.compare_methods = true` reports fixed-session versus rolling counts
and overlap on jointly evaluable, artifact-clean breaths and overlays the
other method in ratio plots. The fixed method excludes contaminated breath
support without the rolling method's extra centered-window artifact guard.

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
config.exclude_recordings = [23 1];     % omit M1 only; M2 remains eligible
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
subset of 1Ã¢â‚¬â€œ4. Set `paired_measurements` to two distinct values in 1Ã¢â‚¬â€œ4,
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

## Portable machine-local paths

`get_config_defaults.m` initializes both roots with the author's Windows paths.
`main_single.m` calls it and **overwrites both roots again**. Setting `config`
in the workspace before running `main_single.m` therefore does not override
its settings. No path inference happens later in `run_magma`.

Keep a personal launcher outside the repository, using the public runner:

```matlab
repo = 'C:\path\to\magma-labeling'; % this computer's checkout
addpath(genpath(fullfile(repo, 'src')));
config = get_config_defaults();
config.path_data_in = fullfile('C:\', 'MAGMA data', 'raw');
config.path_results_out = fullfile('C:\', 'MAGMA data', 'results');
config.subjects = 21;       % choose the intended recording(s)
config.measurements = 1;
% Copy your intended scientific, plotting, execution and review settings here.
run_magma(config);
```

On macOS/Linux, use an appropriate absolute root, for example
`fullfile('/home', 'user', 'MAGMA data', 'results')`. Paths may be character
vectors or string scalars. Use an explicitly chosen local folder while
investigating; never copy another collaborator's drive letters blindly.
This launcher avoids editing or inheriting somebody else's machine paths.
It does not require a different execution mode or disabling any plots.

## PNG export investigation and diagnostic

### Source trace and established findings

1. `get_config_defaults` initializes `path_results_out`; `main_single` replaces
   it. Direct callers such as `example/demo.m` can also override it.
2. `run_magma` checks/creates that root and saves `analysis_configuration.mat`
   **before** iterating over recordings or adding `subject` and `measure`.
3. `load_raw_data` derives `sub_results_path` as
   `fullfile(config.path_results_out, ['Sub' num2str(subject) '_M' num2str(measure)])`.
   This always replaces any preexisting `sub_results_path`. Input loading uses
   `fullfile` too. Feature caches and recording results share this subfolder.
4. `run_selected_label_detectors` calls shallow detection first when selected.
   `detect_shallow_breathing` passes the fixed ASCII stem `shallow_breathing`
   to `plot_amplitude_state_diagnostic`. It creates four tiled panels with
   full-length raw belts, scatter points, support patches and outside legends.
5. `save_figure` builds `Sub%d_M%d_shallow_breathing.png` with `fullfile`, checks
   the parent folder, then calls `exportgraphics(fig, fullpath, 'Resolution', dpi)`.
   PNG and 150 DPI are the defaults. An explicit fourth argument overrides
   the destination; it is not used by shallow detection. Configured figure
   width/height override screen-based sizing. This stem does not request a
   `.fig` sidecar. The figure closes after a successful export.

Before this patch, output-folder `mkdir` results were unchecked and no write
probe was performed. A failure could surface later as an unhelpful export
error. Also, `[config.path_results_out filesep ...]` and the equivalent input
join work with character vectors but create a string array for a string
scalar root. This was reproduced on R2025a: a 1-by-3 string array, versus one
path from `fullfile`. That bug would usually fail before label detection;
it is **not established as the clinician's cause**.

The patch uses `fullfile` for those two joins, verifies directory creation
and an actual temporary write before root/recording output and figure saving,
and adds the destination and parent to export exceptions while retaining the
original exception as a cause. Missing plot directories now raise an error.
Plot naming, DPI and exporter remain unchanged. Detection, preprocessing,
review annotations, MAT save calls and HDF5 export are unchanged.

A successful configuration MAT save establishes access to the **root at that
time**, not the recording subdirectory, a particular PNG, or the native PNG
writer. If earlier PNGs in that same recording folder succeeded, a persistent
root/path failure becomes less likely. Check their actual timestamps.

Unproven causes include recording-folder ACLs; an existing PNG locked or
read-only; a target occupied by a directory; interrupted network/mapped-drive
access; synchronization/security software; path length or native filename
encoding; and a figure-specific export/resource problem. Hardcoded paths
alone do not prove any of these. Screen size, total plotted samples and DPI
can make the shallow figure more demanding on a different machine.

### Run the standalone diagnostic on both computers

Send **only `src/diagnose_png_export.m`** to the clinician if convenient. It
has no dependencies on MAGMA, raw data, toolboxes, or the full analysis.
Put it in MATLAB's current folder or add its containing folder to the path.
Use the configuration snapshot from the failing run and the actual failing
subject/measurement (21 and 1 below are examples):

```matlab
saved = load('C:\actual\results\analysis_configuration.mat', 'config');
subject = 21; measurement = 1; % replace with the failing recording IDs
% tempname produces a fresh log path, so an earlier report is not overwritten.
logfile = [tempname '.txt'];
diary(logfile);
report = diagnose_png_export(saved.config, subject, measurement);
diary off;
fprintf('Diagnostic log: %s\n', logfile);
```

Do not run `main_single` to obtain the configuration. If the snapshot is
unavailable, supply a struct with the **exact** results root from the failing
run, and its `plot_dpi` if configured:

```matlab
config = struct('path_results_out', 'C:\actual\results');
report = diagnose_png_export(config, 21, 1);
```

On the working computer, use its own output root and the same recording IDs
and export settings. Compare the two logs: exact MATLAB release/build
(R2025a versus R2025b as well as update/build), OS, renderer/device/details,
DPI, resolved folders, target existence/open status, path lengths/Unicode,
and each simple/four-panel output/temp result and exception. If available,
also note which earlier PNGs were successfully saved by the failed run.

The diagnostic prints the exact production destination but never exports to
it. An existing target is inspected with `fileattrib` and opened `r+` then
closed **without writing or truncating**. Fresh PNG probe stems have the same
length as the production stem; failures also try a shorter fresh name.
Folder probes check creation, writing and closing a small file. All probe
files and newly created empty directories are removed, including on export
failure; cleanup problems are printed. The caller's diary log is retained.
Synthetic figures are hidden, at 640x360 and 1000x700 pixels. PNG validity is
checked with `imfinfo`. No global renderer or execution setting is changed.

If the original failed figure remains open, optionally test it directly:

```matlab
failed_figure = get(groot, 'CurrentFigure'); % select the actual failed figure
report = diagnose_png_export(saved.config, subject, measurement, failed_figure);
```

This is optional; it exports that figure to fresh names in both locations,
leaves it open, and requires no rerun. It may take longer for a large figure.
The small synthetic test alone cannot rule out a problem with the real figure.

| Observation | Interpretation and next step |
| --- | --- |
| A: invalid path, a path component is a file, unresolved drive/share | Correct that machine's configured absolute root; check actual drive/share availability. |
| B: folder creation or temporary write/close fails | Read the recorded mkdir/fopen error; choose or grant access to the intended output folder. Attribute flags alone are not a write test. |
| C: target exists and `r+` fails, while fresh exports pass | Target-specific access/lock/read-only problem. Check its attributes and applications/sync using it. An `r+` success cannot exclude transient or exporter-specific locking. |
| Output export fails but identical temp export passes | Destination-specific/native file-opening issue. Compare short-name retry; repeat using a short, local ASCII output root to isolate length/encoding/network/sync. Spaces and Unicode alone are not evidence of a defect. |
| D: simple PNG fails even in a folder with a successful write probe in `tempdir` | Exporter/environment or native path handling needs investigation. Capture the full exception; repeat with a short local ASCII root if tempdir itself has a complex path. This does not by itself identify the GPU. |
| E: simple passes but four-panel or retained figure fails | Figure/layout/size/resource-dependent candidate. Compare both locations, figure dimensions, object counts, DPI and graphics details. Only the retained figure tests the real figure's complexity. |
| Everything passes | Failure not reproduced. A transient lock/access change or actual-figure problem remains possible; do not claim a path or compatibility cause. |

Both computers reportedly use MATLAB 2025, so a missing export API is not the
leading explanation. MathWorks documents `exportgraphics` as introduced in
[R2020a](https://www.mathworks.com/help/matlab/ref/exportgraphics.html).
The diagnostic records older-release missing-function exceptions too, without
adding a production fallback. It queries
[rendererinfo](https://www.mathworks.com/help/matlab/ref/rendererinfo.html)
using an axes argument, supported before the no-argument form.
A `print`/other compatibility fallback should only be proposed after a
repeatable exporter-specific failure, with matching DPI, naming, crop,
background and layout checked. None is currently justified.

Remaining clinician evidence: the diagnostic log, the original complete
exception if it differs, exact failing subject/measurement and target path,
whether the location is local/mapped/UNC/OneDrive or otherwise synchronized,
and whether that PNG already existed or was open in another program. No raw
physiological data is needed. A read-only or intermittent cause needs an
appropriate local access correction; the patch cannot repair ACLs or locks.

Lightweight developer validation (no full pipeline):

```matlab
addpath(genpath('src'));
results = runtests('tests/unit/test_png_export.m');
assertSuccess(results);
```

## Rechecking respiratory features

`config.resp.recheck_cached = false` reuses compatible caches as before. Set it
to `true` with `overwrite_results=true`, `overwrite_features=false`, analyze
mode, and `execution.selected_labels={}` to reopen existing saved landmarks
and artifact intervals. Reviewed validates and atomically replaces the original
cache without creating a persistent backup. Cancel skips that recording without
replacing the cache. Existing backup folders are left untouched.
See [the recheck workflow](RESPIRATORY_ARTIFACTS.md).
