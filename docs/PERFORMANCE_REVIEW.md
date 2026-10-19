# Observation defaults and focused performance review

Reviewed `main` at `48db13a` (matching fetched `origin/main`). Changes are local;
no real recording cache/result was written and no cohort was run.

Both GUIs now select the saved observation from **Not assessed / Not observed /
Observed**. Accepting an ordinary landmark or label review without changing
this selector preserves `not_assessed`, its NaN clinician value, revision,
timestamp and pending state. Explicit negative/positive assessments remain
0/1. Returning to Not assessed is also explicit and retains the existing
revision, history, rollback and pending-reanalysis machinery. The observation
storage schema and 24-feature phenotype schema are unchanged.

## Ranked performance findings

Ranks combine source inspection with one synthetic recording benchmark. Output
and disk costs depend strongly on figure size, filesystem and export settings;
this is not a measured ranking for the clinician's machine.

| Rank | Area | Finding / cost | Action |
| --- | --- | --- | --- |
| 1 | Diagnostic figures and output I/O | Full-resolution traces, repeated graphics-object searches/layout, rendering and PNG compression can dominate. `save_figure` wrote the **same FIG twice** when `plot_format='fig'` and the stem selected a sidecar. HDF5, when enabled, creates many separate datasets and can add substantial I/O. | Removed only the duplicate FIG write. PNG resolution, sidecar policy for PNG, figure contents and error reporting remain unchanged. |
| 2 | Asynchrony wavelets | On the synthetic recording, phase offset took **0.925 s** and legacy coherence **0.908 s**. `detect_respiratory_asynchrony` always computes legacy coherence and also computes phase when requested by the primary/comparison settings. Together this can mean four belt transforms per recording/block. | Left unchanged. The methods use different normalization, frequency ranges, edge handling and summaries; their transforms are not safely interchangeable. |
| 3 | Feature-cache and metadata I/O | Normal load reads the full cache; recheck additionally copies/verifies it, commits it, and reloads it. Full-run completion loads and rewrites the cache even if its pending state was already false. Observation reads repeatedly inspect MAT/HDF5 mirrors; saving/publishing updates several files. Network/sync folders can amplify these costs. | Ranked from source, **not timed on real files**. Kept consistency checks, backups, transactions and publication unchanged. A later no-op completion fast path must prove that both compact and cycle metadata are already current. |
| 4 | eAMI | **0.298 s**. Two belts use overlapping centered energy windows (301 samples at the current 60-s/5-Hz defaults), repeatedly computing finite checks, local means and energies. Butterworth setup and resampling ratios also repeat between belts/finite regions. | Left unchanged. Replacing centered energy with moving sums/variance can change rounding, invalid-window handling and decisions near a threshold; no such substitution was made. |
| 5 | Guyot | **0.204 s** in the stage benchmark. A 900-s recording produces 66 windows per usable belt at the current 120-s/90%-overlap settings. Each eligible window uses an economy SVD, eigenvalues and amplitude fitting. | Used built-in `hankel` for the two sample matrices. Their entries are identical to the original column loop. SVD, model order, fitting, classification and temporal projection are unchanged. |
| 6 | Q23 | **0.109 s** in the stage benchmark. Each 120-s/50%-overlap window formerly rebuilt abdominal IBI/frequency arrays, quality bounds, resampling factors, Hamming windows and Welch parameters. Artifact-window checks repeated scalar setup; complete traces still called interpolation with an empty query. | Hoisted invariant setup and batch-computed artifact-window validity. Retained per-window detrending, FIR resampling, `pwelch`, integration and quality tests. Interpolation still runs for actual gaps. |

Other repeated work: `respiratory_artifact_state`/`respiratory_artifact_view`
rebuild sample/breath/IBI masks in reference extraction, feature construction,
dispatch and individual methods. This is especially worth profiling with many
marked intervals. It was left unchanged: a shared cache would need to account
for recording identity, sample grid, actual landmarks/intervals, artifact and
observation revisions, and preprocessing/configuration differences.

`run_magma` can also preprocess and load features a second time after an
observation revision changes. This is intentional polarity/feature alignment.
The default fix prevents an untouched unassessed dropdown from needlessly
causing that path; explicit observation changes retain it.

## Measured optimizations and numerical checks

MATLAB **R2025a / PCWIN64**, synthetic 900-s recording at 200 Hz, 180,000 samples,
two amplitude-modulated respiratory belts. Before/after timings below are
medians of nine alternating warm runs, using copies of the original functions
from `48db13a`.

| Calculation | Before | After | Improvement |
| --- | ---: | ---: | ---: |
| Q23 | 0.0930 s | 0.0826 s | 11.2% less time (1.13x) |
| Full two-belt Guyot | 0.1959 s | 0.1754 s | 10.4% less time (1.12x) |

The separate five-stage benchmark above uses three repetitions, includes the
first call in its median, and has different warm-up/timing noise. Its numbers
should not be substituted into the paired before/after calculation. Neither
measurement is an end-to-end MAGMA speedup estimate.

Complete outputs were compared using `isequaln`: **54 Q23 cases**, **56 Matrix
Pencil cases**, and **3 full Guyot cases**, all identical. Cases include sampling
rates 5, 10, 20, 128, 199.5 and 200 Hz, finite/short-gap/long-gap traces, flat or
small signals, spikes, marked artifacts, invalid inputs and rank-deficient
modulation. Source signals, landmarks and artifact ranges were not changed.

A temporary synthetic FIG test confirmed two saves became one (profiled cold
calls: 3.33 s versus 2.31 s; not a stable benchmark estimate). Reopened FIG
numeric line data and exported PNG pixels were exactly equal; PNG-sidecar
saving still ran once. No existing numerical operation was replaced to reduce
helper count, and no thresholds, label definitions or phenotype features changed.

Validation also passed 25 focused tests covering unchanged GUI acceptance,
explicit three-state reversal, revisions/rollback, cache cancellation and
reopening, phenotype mapping, Matrix Pencil and PNG export errors. Syntax and
`git diff --check` passed. Sub33_M1's real cache/results SHA-256 values remained
unchanged. No full-cohort test was run.

## Minimal benchmark on one recording

`example/benchmark_one_recording.m` accepts the original **preprocessed** sample
matrix, saved cycles and analysis config. It never calls `run_magma`, feature
extraction, GUI review, cache writers or result exporters. It returns a table;
it does not save it. An unavailable/skipped method is not a useful speed test.

```matlab
addpath(genpath('src')); addpath('example');
saved = load(resultFile, 'config', 'resp_cycles', 'analysis_recording_observations');
cfg = saved.config;
if isfield(saved, 'analysis_recording_observations')
    cfg.recording_observations = saved.analysis_recording_observations;
end
% data = the corresponding original preprocessed N-by-Nchannel matrix.
timings = benchmark_one_recording(data, saved.resp_cycles, cfg, 3);
```

If a native preprocessed HDF5 export exists, it can be read without running the
pipeline:

```matlab
data = h5read(hdf5File, '/signals/preprocessed');
```

Use its stored sampling rate/column order with `cfg`. Exports stored as single
precision are suitable for timing, but not for proving bitwise equality with
the original double-precision analysis. Smoothed `resp_cycles.*.x0` traces are
not a substitute for the original preprocessed matrix.

For function-level profiling on just that recording:

```matlab
profile on;
benchmark_one_recording(data, saved.resp_cycles, cfg, 1);
profile off;
profile viewer;
```

Optional cache I/O measurement uses a read-only load and an isolated temporary
copy; it does not invoke the live cache updater:

```matlab
tic; payload = load(featureCacheFile); load_seconds = toc;
benchDir = tempname; mkdir(benchDir);
assert(startsWith(benchDir,tempdir) && ~strcmp(benchDir,tempdir));
cleanup = onCleanup(@() rmdir(benchDir,'s'));
tic; atomic_save_mat(fullfile(benchDir,'cache_copy.mat'),payload); save_seconds = toc;
clear cleanup;
```

Optional diagnostic timing retains the saved numerical settings and redirects
all figure outputs to a fresh temporary directory. This evaluates only one
saved-evidence detector/plot; it does not save or replace recording labels:

```matlab
savedEvidence = load(resultFile, 'resp_features');
benchDir = tempname; mkdir(benchDir);
assert(startsWith(benchDir,tempdir) && ~strcmp(benchDir,tempdir));
cleanup = onCleanup(@() rmdir(benchDir,'s'));
plotCfg = cfg; plotCfg.sub_results_path = benchDir;
plotCfg.make_figs_visible = 'off'; plotCfg.shallow.do_plot = true;
tic; [~,~] = detect_shallow_breathing(data,savedEvidence.resp_features,plotCfg);
figure_and_detector_seconds = toc;
clear cleanup;
```

Keep file reads, warm/cold compute, figures and writes as separate measurements.
No optimization removes the requested diagnostic plots, comparison evidence,
or integrity checks.
