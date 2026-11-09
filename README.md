# MAGMA Physiological Event Labeling

MATLAB framework for extracting respiratory features and generating weak physiological labels from thoracic and abdominal respiratory belts and SpO2 recordings.

The framework detects 11 elementary patterns:

`shallow`, `deep`, `slow`, `rapid`, `irregular`, `apnea`, `sigh`, `periodic`, `thoracic`, `async`, and `desat`.

Labels are independent and may overlap. They describe signal-derived physiological patterns rather than mutually exclusive clinical diagnoses.

MAGMA has two scientific output levels: Level 1 contains the time-resolved
labels and their supporting evidence; Level 2 contains five literature-based
profiles, six label-based patterns, and a thoracic-excursion assessment.
These are descriptive, may coexist, and have a fixed 24-value numeric summary.

## Documentation

- [Configuration](docs/CONFIGURATION.md)
- [Label definitions](docs/LABELS.md)
- [Phenotypes](docs/PHENOTYPES.md)
- [Outputs](docs/OUTPUTS.md)
- [MAT results hierarchy and field mapping](docs/RESULTS_SCHEMA.md)

## Input

Default signal order:

1. ECG1
2. ECG2
3. SpO2
4. Thoracic respiratory belt (`Resp-Lungs`)
5. Blood pressure
6. Abdominal respiratory belt (`Resp-Diaphragm`)

The default sampling frequency is 200 Hz.

At least one respiratory belt is required for respiratory analysis. Labels requiring both belts (`thoracic`, `async`) are unavailable when one belt is missing.

## Run

Edit paths, recording selection, and execution settings in `src/main_single.m`;
scientific defaults are in `src/get_config_defaults.m`. From the repository root:

```matlab
run('src/main_single.m')
```

The pipeline:

1. loads and preprocesses the recording;
2. extracts respiratory cycles;
3. optionally allows manual breath correction;
4. computes respiratory features and session references;
5. detects automatic physiological labels;
6. optionally allows manual label review;
7. saves MATLAB results and enabled HDF5 exports and diagnostic figures.

Recording results are saved as `Sub<subject>_M<measurement>_results.mat`,
containing one hierarchical `results` variable. Set `config.HDF5.enabled = true`
to also export `_results.h5` (schema v19); respiratory caches use `_features.mat`.
Run `src/main_group.m` separately for cohort summaries from saved results.
See [Outputs](docs/OUTPUTS.md) for file layouts and group-output filenames.

## Respiratory reference

Amplitude-dependent labels use a fixed recording-specific reference:

- M1/M3: 3-6 min
- M2/M4: 19-22 min; M2 ending before the reference starts uses its final 3 minutes, or all available data if shorter.

Respiratory-belt amplitudes are relative, not calibrated tidal volume. Thoracic and abdominal belts are therefore normalized independently.

Sigh defaults to `config.sigh.method = 'session_reference_2x'`: breath amplitude /
per-belt reference must reach `config.sigh.session_ratio_threshold` (`2.0`).
Missing references make sigh evidence unavailable. `rolling_median_2x` is optional;
`config.sigh.compare_methods` compares both. See [label details](docs/LABELS.md#sigh).

## Manual review

Automatic annotations are always preserved.

Two optional review stages are available:

- respiratory peak/trough review (`config.resp.manual_control`);
- label review, including discrete sigh peaks (`config.execution.mode`).

Reviewed coverage is stored explicitly, so unreviewed data are not interpreted as manually confirmed negatives.
By default, `LabelEdit.review_automatically_accepted = {'desat','slow','rapid'}`
accepts valid automatic evidence in `review` and `analyze_and_review` modes.
`analyze` does not create automatic acceptance or reviewed/comparison figures;
saved manual reviews remain available. Set the subset to `{}` to review all 11
assessable labels, including desaturation with an SpO2 panel.
See [manual review configuration](docs/CONFIGURATION.md#manual-review) for policy
refresh and saved-manual-review precedence. Recording observations are shared by
both editors and saved with results or features.

In respiratory review, blue dots are editable trough landmarks between red
peaks. They are not explicit hold boundaries.

The landmark and label review windows default to **Amplitude: Common max**.
Both respiratory plots use the same vertical limits, covering both full traces,
and equal plot heights for amplitude comparison. Click the toggle for
**Amplitude: Auto** and independent per-belt scaling. The selected mode stays
fixed while scrolling and switching labels; SpO2 keeps its own scale.

Respiratory review supports shared **Mark artifact** intervals that exclude both belts.
Use `config.resp.recheck_cached = true` to reopen saved reviewed landmarks.
See [Rechecking respiratory features](docs/RESPIRATORY_ARTIFACTS.md) for the
in-place atomic save, cancellation, reanalysis, and revision workflow.

## Tests

From the repository root:

```matlab
addpath('tests');
results = run_all_tests();
```
