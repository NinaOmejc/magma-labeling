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

The pipeline processes multi-channel physiological recordings and saves structured event annotations, label masks, diagnostic signals, features, and figures. Original label definitions are in `Labels.docx`.

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

4. Edit `src/get_config.m` to choose the `subjects` and `measurements` to process.
5. Edit `src/get_config.m` if paths, detector settings, plotting, or manual review options need to change.
6. Run:

```matlab
run('src/main_single.m')
```

`main_single.m` loops over the selected subjects and measurements, loads each recording, preprocesses the data, extracts respiration and SpO2 features, computes the respiratory and SpO2 references, runs all label detectors, builds the label mask, and saves outputs.

## Configuration

All main settings are defined in `src/get_config.m`.

Key parameters:

- `config.fs` - native and master sampling rate for all aligned signals (200 Hz for MAGMA recordings)
- `config.path_data_in` - input `.dat` file directory
- `config.path_results_out` - output directory
- `config.subjects` - subject identifiers to process
- `config.measurements` - measurement identifiers to process
- `config.data_columns` - input column names; at least one respiratory belt is required and SpO2 is optional
- `config.input_filename_pattern` - raw input filename pattern, with `{subject}` and `{measure}` placeholders
- `config.make_figs_visible` - show or hide figures during batch runs
- `config.overwrite_results` - recompute labels when a saved label file already exists

Each detector has its own settings block, for example `config.ShB`, `config.IrB`, `config.SlB`, `config.RaB`, `config.ReA`, `config.Des`, `config.Apn`, `config.Sig`, and `config.CSR`.

Preprocessing preserves the native sample count and alignment of every channel. It detrends only the configured respiratory belts. Respiratory-asynchrony analysis alone creates a temporary, anti-aliased 20 Hz representation controlled by `config.ReA.analysis_fs`; its results are mapped back to the 200 Hz master timeline.

`config.resp_ref` defines one fixed protocol/session amplitude reference independently for each usable belt. Measurements M1/M3 use reviewed breaths from minutes 2–7; M2/M4 use minutes 18–23. The session median normalizes amplitude-dependent shallow/deep and breath-amplitude apnea logic. Sigh detection intentionally uses the whole-record median because it is a global outlier detector.

`results.resp_ref` also retains whole-record values and early/late stability diagnostics. A step candidate, edge disagreement, or gradual/complex pattern is a descriptive `reference_quality` warning. The default action for every warning is **retain data, no correction**; warnings neither request manual correction nor automatically drift-correct the reference. A session reference becomes unavailable only when its belt lacks enough reviewed, finite positive breaths.

Respiratory belts are uncalibrated. Their raw amplitudes do not represent absolute tidal volume and are not safely comparable between subjects. A globally low-excursion recording can also look normal after within-record normalization, so amplitude ratios must be interpreted as within-record measures.

Plot behavior is controlled per module:

- `config.<module>.do_plot = true` generates and saves that module's diagnostic figure(s).
- `config.<module>.do_plot = false` skips generating/saving that module's diagnostic figure(s).

Manual review can be enabled at three levels:

- `config.resp.manual_control` - opens a breath peak editor before label detection. Edited peaks/troughs affect all downstream respiratory labels.
- `config.Sig.manual_control` - opens the sigh-specific breath-level editor for adding or removing sigh markers.
- `config.LabelEdit.manual_control` - opens the final event-interval editor after automatic detection and before the final label mask is saved. This editor handles `shallowB`, `irregB`, `slowB`, `rapidB`, `asyncB`, `desat`, `apnea`, and `CSR`; sigh is excluded because it has its own editor.

Final manual label edits are controlled by:

- `config.LabelEdit.apply_saved_edits` - reuse previously saved manual event edits on rerun, even if the GUI is disabled.
- `config.LabelEdit.save_edits` - save the edited per-label event intervals in a separate `*_manual_label_events.mat` file.
- `config.LabelEdit.rewrite_changed_figures` - after manual editing, overwrite only the label diagnostic images whose intervals changed; unchanged label images are left untouched.

## Input Data Format

Each recording is expected as a numeric `.dat` file whose columns match `config.data_columns`.
The default MAGMA configuration remains the original 6-column order:

1. ECG1
2. ECG2
3. SpO2
4. Resp-Lungs
5. Blood Pressure
6. Resp-Diaphragm

Rows are time samples and columns are signals. The raw sampling rate must match `config.fs`.

For external data, `config.data_columns` can also list only the available signals, for example:

```matlab
config.data_columns = {'SpO2', 'Resp-Lungs', 'Resp-Diaphragm'};
config.data_columns = {'Resp-Lungs', 'Resp-Diaphragm'};
config.data_columns = {'Resp', 'SpO2'};
config.data_columns = {'Resp'};
```

Accepted respiratory aliases include `Resp-Lungs`, `Lungs`, `Thorax`, `Chest`, `Resp-Diaphragm`, `Diaphragm`, `Abdomen`, `Resp`, `RespiratoryBelt`, and `Respiration`.
Accepted oxygen-saturation aliases include `SpO2`, `SpO₂`, `Spo2`, `SaO2`, and `OxygenSaturation`.
If only one belt is present, one-belt respiratory labels still run and respiratory asynchrony is skipped. If SpO2 is absent, desaturation detection and desaturation modifiers are skipped.

The loader resolves available channels from `config.data_columns` and records the resolved channel configuration in `results.input_config`. This allows the same pipeline and plotting/manual-review interfaces to run on the full MAGMA signal set as well as smaller external files with only the available respiratory and/or SpO2 channels.

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
    Sub42_M1_manual_label_events.mat
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
results.resp_ref           = resp_ref;            % Fixed session/global respiratory references and descriptive QC
results.spo2_feat          = spo2_feat;           % SpO2 features and desaturation candidates
results.diagnostic_signals = diagnostic_signals;  % Continuous detector-adjacent signals
results.manual_label_edit  = manual_label_edit;   % Manual edit metadata and changed label list
results.rewritten_manual_label_figures = rewritten_manual_label_figures; % Figures rewritten after manual interval edits
results.baseline           = baseline;            % Static SpO2 and label-specific baseline interval
results.input_config       = config.input_config; % Resolved channels and skipped/running labels
results.config             = config;              % Full configuration used for this run
```

`results.events` and `results.mask` already include accepted manual edits. The separate `Sub*_M*_manual_label_events.mat` file stores the edited per-label event sets before final merging/normalization, so the same human edits can be reused on rerun and compared against newly detected automatic events.

`results.measure` is the saved measurement identifier.

## Group-Level Measure Comparability

`build_group_label_table` writes `group_analysis/group_measure_comparability.csv` alongside the group summary. Interpret group outputs in three classes:

- Absolute/comparable across subjects: respiratory rate (bpm), event durations/fractions, SpO2, and timing measures.
- Within-record normalized: belt amplitude ratios, shallow/deep excursion measures, and the whole-record/session amplitude ratio.
- Not safely comparable across subjects: raw belt amplitude or raw session/global belt reference values.

## Artificial Test Signals

To generate nine artificial one-label datasets from source recording Sub1/M1 and validate the detector output, run:

```matlab
run('src/main_test_signals.m')
```

This creates ignored local files under `test_data/` named as `Sub0_Pom1` through `Sub0_Pom9`. Measurements map to labels in order: `shallowB`, `irregB`, `slowB`, `rapidB`, `asyncB`, `desat`, `apnea`, `sigh`, and `CSR`. Results are saved under `results/test_signals/`. The script errors if a measurement misses its expected label and reports any additional canonical labels so detector weaknesses remain visible.

## Event Struct Format

Each event contains:

- `type` - one of the main labels: `shallowB`, `irregB`, `slowB`, `rapidB`, `asyncB`, `desat`, `apnea`, `sigh`, `CSR`
- `subtype` - optional modifier, for example `shallow`, `deep`, or `desat`
- `desat` - true when the event is associated with desaturation
- `depth` - `shallow`, `deep`, or empty when not applicable
- `start_idx`, `end_idx` - sample indices
- `start_t`, `end_t` - event times in seconds

Rapid breathing remains `type = 'rapidB'` in the main mask. Its variants are stored in `subtype`, so a rapid-deep episode is represented as `type = 'rapidB'`, `subtype = 'deep'`.
Older short event names such as `RaB`, `Apn`, or `Sig` are still accepted by the normalization helper, but new outputs use the longer canonical names.

## License

MIT License
