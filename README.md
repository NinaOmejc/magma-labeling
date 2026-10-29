# MAGMA Physiological Event Labeling

MATLAB framework for extracting respiratory features and generating weak physiological labels from thoracic and abdominal respiratory belts and SpOâ‚‚ recordings.

The framework detects 11 elementary patterns:

`shallow`, `deep`, `slow`, `rapid`, `irregular`, `apnea`, `sigh`, `periodic`, `thoracic`, `async`, and `desat`.

Labels are independent and may overlap. They describe signal-derived physiological patterns rather than mutually exclusive clinical diagnoses.

MAGMA has two scientific output levels: Level 1 contains the time-resolved
labels and their supporting evidence; Level 2 contains recording-level
phenotypes and patterns. The five literature-based and six label-based Level-2
profiles are descriptive, may coexist, and are accompanied by a fixed 24-value
numeric summary.

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
3. SpOâ‚‚
4. Thoracic respiratory belt (`Resp-Lungs`)
5. Blood pressure
6. Abdominal respiratory belt (`Resp-Diaphragm`)

The default sampling frequency is 200 Hz.

At least one respiratory belt is required for respiratory analysis. Labels requiring both belts (`thoracic`, `async`) are unavailable when one belt is missing.

## Run

Edit:

```matlab
src/get_config_defaults.m
```

Then run:

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
7. saves MATLAB, HDF5, diagnostic, and group-level outputs.

The main recording outputs are
`Sub<subject>_M<measurement>_results.mat` and
`Sub<subject>_M<measurement>_results.h5`. The respiratory-feature cache keeps
the `_features.mat` suffix. MAT files contain one hierarchical `results` variable.
See [Outputs](docs/OUTPUTS.md) for the HDF5 v19
hierarchy and group-output filenames.

## Respiratory reference

Amplitude-dependent labels use a fixed recording-specific reference:

- M1/M3: 3â€“6 min
- M2/M4: 19â€“22 min

Respiratory-belt amplitudes are relative, not calibrated tidal volume. Thoracic and abdominal belts are therefore normalized independently.

Sigh detection defaults to `config.sigh.method = 'session_reference_2x'`:
the existing per-belt breath amplitude / session reference must be at least
`config.sigh.session_ratio_threshold` (default `2.0`). Missing references make
sigh evidence unavailable, with no local/global fallback. Reference QC flags
and respiratory artifact exclusions are preserved. The existing
`rolling_median_2x` alternative remains available; enable
`config.sigh.compare_methods` for fixed-versus-rolling counts and overlap.
See [Label definitions](docs/LABELS.md#sigh) for details.

## Manual review

Automatic annotations are always preserved.

Three optional review stages are available:

- respiratory peak/trough review;
- sigh review;
- final interval-label review.

Reviewed coverage is stored explicitly, so unreviewed data are not interpreted as manually confirmed negatives.
By default, `LabelEdit.review_automatically_accepted = {'desat','slow','rapid'}`
accepts valid automatic evidence without manual inspection. Set it to `{}` to
review all 11 assessable labels, including desaturation with an SpO2 panel.
See [manual review configuration](docs/CONFIGURATION.md#manual-review) for policy
refresh and saved-manual-review precedence. Current recording observations live
in results or the existing feature cache; legacy observation sidecars can be
reconciled without changing historical reviews (see [outputs](docs/OUTPUTS.md)).

In respiratory review, blue dots are editable trough landmarks between red
peaks. They are not explicit hold boundaries.

Respiratory review supports shared **Mark artifact** intervals that exclude both belts.
Use `config.resp.recheck_cached = true` to reopen saved reviewed landmarks.
See [Rechecking respiratory features](docs/RESPIRATORY_ARTIFACTS.md) for the
in-place atomic save, cancellation, reanalysis, and revision workflow.

## Tests

Run:

```matlab
results = run_all_tests();
```

See [Label definitions](docs/LABELS.md) for the physiological criteria and [Outputs](docs/OUTPUTS.md) for the saved data structure.
