# MAGMA Physiological Event Labeling

MATLAB framework for extracting respiratory features and generating weak physiological labels from thoracic and abdominal respiratory belts and SpO₂ recordings.

The framework detects 11 elementary patterns:

`shallow`, `deep`, `slow`, `rapid`, `irregular`, `apnea`, `sigh`, `periodic`, `thoracic`, `async`, and `desat`.

Labels are independent and may overlap. They describe signal-derived physiological patterns rather than mutually exclusive clinical diagnoses.

## Documentation

- [Configuration](docs/CONFIGURATION.md)
- [Label definitions](docs/LABELS.md)
- [Outputs](docs/OUTPUTS.md)

## Input

Default signal order:

1. ECG1
2. ECG2
3. SpO₂
4. Thoracic respiratory belt (`Resp-Lungs`)
5. Blood pressure
6. Abdominal respiratory belt (`Resp-Diaphragm`)

The default sampling frequency is 200 Hz.

At least one respiratory belt is required for respiratory analysis. Labels requiring both belts (`thoracic`, `async`) are unavailable when one belt is missing.

## Run

Edit:

```matlab
src/get_config.m
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

## Respiratory reference

Amplitude-dependent labels use a fixed recording-specific reference:

- M1/M3: 3–6 min
- M2/M4: 19–22 min

Respiratory-belt amplitudes are relative, not calibrated tidal volume. Thoracic and abdominal belts are therefore normalized independently.

## Manual review

Automatic annotations are always preserved.

Three optional review stages are available:

- respiratory peak/trough review;
- sigh review;
- final interval-label review.

Reviewed coverage is stored explicitly, so unreviewed data are not interpreted as manually confirmed negatives.

## Tests

Run:

```matlab
results = run_all_tests();
```

See [Label definitions](docs/LABELS.md) for the physiological criteria and [Outputs](docs/OUTPUTS.md) for the saved data structure.
