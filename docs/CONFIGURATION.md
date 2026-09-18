# Configuration

The main configuration file is:

```text
src/get_config.m
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
```

Individual detector plots can additionally be controlled with the corresponding `do_plot` field.

`config.verbosity = 1` prints concise progress, including important skip and
signal-availability messages. Set it to `2` for detailed pipeline-stage and
detector progress. Warnings and errors are always shown.

## Respiratory-cycle extraction

```matlab
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

Respiratory-cycle review:

```matlab
config.resp.manual_control
```

Sigh review:

```matlab
config.sigh.manual_control
```

Final interval review:

```matlab
config.LabelEdit.manual_control
config.LabelEdit.apply_saved_edits
config.LabelEdit.save_edits
config.LabelEdit.start_from
config.LabelEdit.reviewer_role
```

Automatic and manually reviewed annotations remain separate.
