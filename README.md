# MAGMA – Physiological Event Labeling Pipeline

MATLAB-based physiological signal processing pipeline for detecting respiratory dysfunction events, including:

- Apnea  
- Slow breathing (Bradypnea)  
- Rapid breathing (Tachypnea)  
- Shallow breathing  
- Irregular breathing  
- Respiratory asynchrony (TO DO)
- Desaturation (SpO₂)  
- Sigh  

The pipeline processes multi-channel physiological recordings and produces structured event annotations. Full label definitions: **`Labels.docx`**.

---

## Download / setup

Clone with Git:

```bash
git clone https://github.com/NinaOmejc/magma-labeling.git
cd magma-labeling
```

Or download ZIP on GitHub: **Code → Download ZIP**, then extract.

---

## Run the pipeline

1. Open MATLAB.
2. Set the repository root as your working directory.
3. Add the `src/` folder to the MATLAB path:

```matlab
addpath(genpath(fullfile(pwd, 'src')));
```

4. Configuration

All settings are defined in: `src/get_config.m`. See below.

5. Run

Call `main.m`. It loops over subjects/conditions, loads data, extracts respiration + SpO₂ features, runs all detectors, merges events, builds a time mask, and saves outputs.

---

## Configuration

All settings are defined in:

- `src/get_config.m`

Key parameters:

- `config.fs` — sampling rate (e.g., 200 Hz)
- `config.path_data_in` — input data directory
- `config.path_results_out` — output directory
- `config.data_columns` — expected 6-channel format (order matters)
- `config.save_plots` — each label has it's own plot, which you can turn on/off
- `config.make_figs_visible` — figures are set to be invisible and to close to speed up the code

---

## Input data format

Each recording is expected as a `.dat` file, where each column represents one signal. Rows are time samples; the sampling rate must match `config.fs`.

---

## Outputs

For each subject/condition, a folder is created, e.g.:

```
results/
  Sub42_Cond1/
    Sub42_Cond1_labels_results.mat
    Sub42_Cond1_raw_data.png
    Sub42_Cond1_apnea.png
    Sub42_Cond1_desaturation.png
    ...
```

A typical saved struct contains:

```matlab
results.subject   = config.subject;    % Subject identifier (e.g., 42)
results.condition = config.condition;  % Experimental condition identifier (1: pre, 2: post)
results.events    = sub_events;        % *Struct array of detected events* (type + timing)
results.mask      = label_mask;        % Sample-level logical mask [N x L] (samples × labels); useful for ML applications
results.baseline  = baseline;          % Baseline reference values (e.g., SpO₂, respiratory amplitudes)
results.config    = config;            % Full configuration used for this run (for reproducibility)
```

### Figures

Multiple diagnostic figures may be created per recording (example):

- `*_raw_data`
- `*_lungs`, `*_diaph`
- `*_shallow_breathing`
- `*_slow_breathing`
- `*_rapid_breathing`
- `*_apnea`
- `*_desaturation`
- `*_sigh`
---

### Event struct format

Each event contains:

- `type`
- `start_idx`, `end_idx` (sample indices)
- `start_t`, `end_t` (seconds)

---

## License

MIT License
