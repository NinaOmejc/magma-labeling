# MAGMA Physiological Event Labeling Pipeline

MATLAB-based physiological signal processing pipeline for detecting respiratory dysfunction events in single-subject recordings.

Detected labels include:

- Shallow breathing
- Irregular breathing
- Slow breathing (bradypnea)
- Rapid breathing (tachypnea)
- Respiratory asynchrony
- Desaturation (SpO2)
- Apnea
- Sigh
- Cheyne-Stokes-like / periodic breathing

The pipeline processes multi-channel physiological recordings and saves structured event annotations, label masks, diagnostic signals, features, and figures. Original label definitions are in `Labels.docx`; label 9 is implemented in `config.CSR` and `detect_periodic_breathing.m`.

## Download And Setup

Clone with Git:

```bash
git clone https://github.com/NinaOmejc/magma-labeling.git
cd magma-labeling
```

Or download the ZIP from GitHub with **Code > Download ZIP**, then extract it.

## Run Single-Subject Analysis

1. Open MATLAB.
2. Set the repository root as your working directory.
3. Add `src/` to the MATLAB path:

```matlab
addpath(genpath(fullfile(pwd, 'src')));
```

4. Edit `src/main_single.m` to choose the `subjects` and `measurements` to process.
5. Edit `src/get_config.m` if paths or detector settings need to change.
6. Run:

```matlab
run('src/main_single.m')
```

`main_single.m` loops over the selected subjects and measurements, loads each recording, preprocesses the data, extracts respiration and SpO2 features, computes baselines, runs all label detectors, builds the label mask, and saves outputs.

## Configuration

All main settings are defined in `src/get_config.m`.

Key parameters:

- `config.fs` - raw sampling rate, usually 200 Hz
- `config.new_fs` - sampling rate after preprocessing
- `config.path_data_in` - input `.dat` file directory
- `config.path_results_out` - output directory
- `config.data_columns` - expected 6-channel column order
- `config.save_plots` - save detector and diagnostic figures
- `config.make_figs_visible` - show or hide figures during batch runs
- `config.overwrite_results` - recompute labels when a saved label file already exists

Each detector has its own settings block, for example `config.ShB`, `config.IrB`, `config.SlB`, `config.RaB`, `config.ReA`, `config.Des`, `config.Apn`, `config.Sig`, and `config.CSR`.

## Input Data Format

Each recording is expected as a `.dat` file with 6 columns:

1. ECG1
2. ECG2
3. SpO2
4. Resp-Lungs
5. Blood Pressure
6. Resp-Diaphragm

Rows are time samples. The raw sampling rate must match `config.fs`.

The expected filename pattern is:

```text
ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub<subject>_Pom<measure>_DeTr_Norm.dat
```

For example:

```text
ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub42_Pom1_DeTr_Norm.dat
```

## Outputs

For each subject and measurement, the pipeline creates one output folder:

```text
<config.path_results_out>/
  Sub42_M1/
    Sub42_M1_labels.mat
    Sub42_M1_raw_data.png
    Sub42_M1_label_mask.png
    Sub42_M1_rapid_breathing.png
    Sub42_M1_slow_breathing.png
    Sub42_M1_desaturation.png
    ...
```

A saved label file contains fields like:

```matlab
results.subject            = config.subject;      % Subject identifier
results.measure            = config.measure;      % Measurement identifier
results.events             = sub_events;          % Detected event struct array
results.mask               = label_mask;          % Sample-level label mask [N x labels]
results.label_names        = label_names;         % Label names matching mask columns
results.resp_feat          = resp_feat;           % Respiratory features for lungs and diaphragm
results.spo2_feat          = spo2_feat;           % SpO2 features and desaturation candidates
results.diagnostic_signals = diagnostic_signals;  % Continuous detector-adjacent signals
results.baseline           = baseline;            % Static and rolling baseline references
results.config             = config;              % Full configuration used for this run
```

`results.measure` is the only saved measurement identifier.

## Artificial Test Signals

To generate nine artificial one-label datasets from source recording Sub1/M1 and validate the detector output, run:

```matlab
run('src/main_test_signals.m')
```

This creates ignored local files under `test_data/` named as `Sub0_Pom1` through `Sub0_Pom9`. Measurements map to labels in order: `ShB`, `IrB`, `SlB`, `RaB`, `ReA`, `Des`, `Apn`, `Sig`, and `CSR`. Results are saved under `results/test_signals/`. The script errors if a measurement misses its expected label and reports any additional canonical labels so detector weaknesses remain visible.

## Event Struct Format

Each event contains:

- `type` - one of the main labels: `ShB`, `IrB`, `SlB`, `RaB`, `ReA`, `Des`, `Apn`, `Sig`, `CSR`
- `subtype` - optional modifier, for example `shallow`, `deep`, or `desat`
- `desat` - true when the event is associated with desaturation
- `depth` - `shallow`, `deep`, or empty when not applicable
- `start_idx`, `end_idx` - sample indices
- `start_t`, `end_t` - event times in seconds

Rapid breathing remains `type = 'RaB'` in the main mask. Its variants are stored in `subtype`, so a rapid-deep episode is represented as `type = 'RaB'`, `subtype = 'deep'`.

## License

MIT License
