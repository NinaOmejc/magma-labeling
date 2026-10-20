# MAGMA dysfunctional-breathing phenotypes

MAGMA separates two analysis levels:

1. **Level 1 â€” time-resolved physiological labels and evidence.** Labels,
   events, assessability masks, breath evidence, and detector diagnostics.
2. **Level 2 â€” recording-level phenotype and respiratory-pattern evidence.**
   Detailed profiles and a fixed 24-value numeric summary are provided for
   automatic and reviewed annotation layers.

Level 2 contains three groups:

- **Literature-based dysfunctional-breathing phenotypes:**
  hyperventilation-like respiratory pattern, periodic deep sighing,
  thoracic-dominant breathing, forced abdominal expiration, and
  thoraco-abdominal asynchrony.
- **Additional MAGMA label-derived respiratory patterns:** apneic breathing,
  periodic breathing, shallow breathing, slow breathing, irregular breathing,
  and desaturation.
- **Recording-level minimal or absent thoracic excursion:** independent spectral
  rhythmicity and clinician assessment, with separate provenance.

A phenotype is **not one number**, no binary clinical diagnosis is produced,
and the twelve recording-level profiles are not mutually exclusive. The detailed
Level-2 evidence contains more information than the fixed numeric summary.

## Five literature-based phenotypes

| Literature-based phenotype | Selected summary measures | Availability condition |
|---|---:|---|
| Hyperventilation-like respiratory pattern | 5 | rapid or deep evidence is available |
| Periodic deep sighing | 5 | sigh and irregular evidence are available |
| Thoracic-dominant breathing | 3 | the two-belt thoracic profile is available |
| Forced abdominal expiration | 0 | unavailable with the current signals |
| Thoraco-abdominal asynchrony | 3 | the two-belt asynchrony profile is available |

Every detailed phenotype contains only `name`, `available`,
`signal_derived_measures`, `limitations`, and `source_provenance`. `available`
means that sufficient MAGMA signal support exists to compute the profile for
this recording. It does not mean that the phenotype is present or that a
clinical diagnosis has been established.

```text
available != phenotype present
available != clinical diagnosis
```

### Hyperventilation-like respiratory pattern

MAGMA intentionally does not use the term *hyperventilation syndrome*.
Respiratory belts can show rapid/deep breathing but cannot establish that
ventilation is excessive relative to metabolic demand.

The five selected numeric-summary measures are:

1. rapid-breathing fraction of rapid-assessable time;
2. deep-breathing fraction of deep-assessable time;
3. rapid/deep overlap duration divided by time where both labels are jointly
   assessable;
4. the median of available per-belt recording-scope respiratory-rate medians;
5. the median of available per-belt recording-scope normalized breath-excursion
   medians.

Rate and excursion medians use the full relevant layer-specific assessable
scope, not only samples already labeled rapid or deep. The detailed Level-2 evidence
also retains directional overlap fractions, overlap event summaries,
event-conditioned medians, and belt-specific values.

### Periodic deep sighing

Periodic deep sighing describes the recurrence and organization of sighs. It
is distinct from the Level-1 `periodic` label, which describes waxing/waning
respiratory effort.

The five selected numeric-summary measures are:

1. coverage-aware sigh frequency per 15 minutes;
2. maximum sigh count in a continuously assessable 15-minute interval;
3. irregular-breathing fraction of irregular-assessable time;
4. fraction of assessable canonical sigh events whose midpoint occurs in an
   irregular-positive state;
5. median of available per-belt recording-scope ordinary IBI CoV medians.

The 15-minute maximum is unavailable when no continuous assessable 15-minute
interval exists. For reviewed evidence, unreviewed gaps are never counted as
reviewed negatives. The event-level sigh/irregular feature is distinct from
the sample-duration overlap metric, which remains in the detailed Level-2 evidence.

### Thoracic-dominant breathing

Each uncalibrated respiratory belt is normalized to its own session reference.
The result describes relative thoracic-versus-abdominal change, not an absolute
rib-cage contribution to tidal volume.

The three selected numeric-summary measures are thoracic-dominant fraction, the recording-scope
median normalized thoracic-to-abdominal excursion ratio, and median event
duration. If the detector is assessable and has zero events, the summary event
duration is 0 seconds. If the detector is unavailable, it remains `NaN`.

### Forced abdominal expiration

Forced abdominal expiration remains one of the five literature-based phenotypes,
but the current signals cannot establish active abdominal-muscle recruitment.
It contributes no numeric-summary measure. Thoracic dominance or belt excursion is not
used as a surrogate. Future assessment would require clinical annotation or
more direct muscular/mechanical evidence.

### Thoraco-abdominal asynchrony

The three selected numeric-summary measures are asynchrony fraction, recording-scope median
absolute phase offset over reliable finite phase evidence, and median event
duration. As for thoracic dominance, an assessable detector with zero events
has a summary event duration of 0 seconds; unavailable evidence remains `NaN`.

The detailed Level-2 evidence retains event counts, maximum durations, phase consistency,
frequency-selection evidence, method comparison, reference quality, polarity
metadata, coherence diagnostics, skip codes, and other QC fields. These fields
are not part of the fixed numeric summary.

## Six label-based respiratory patterns

The additional MAGMA label-based profiles are apneic breathing, periodic
breathing, shallow breathing, slow breathing, irregular breathing, and
desaturation. Each reuses its corresponding Level-1 label without introducing
a new detector or definition.

### Irregular breathing

- **Origin:** Label-based
- **Feature:** Irregular-breathing burden
- **Description:** Irregular-breathing duration divided by
  irregular-assessable duration.
- **Clinician-readable interpretation:** Proportion of assessable recording
  time classified as irregular breathing based on excessive breath-to-breath
  timing variability.
- **Units:** fraction

Irregular breathing may occur independently of recurrent sighing and is
therefore exposed as its own label-based profile. The same irregular burden
also remains a characteristic of the literature-based periodic-deep-sighing
profile. This intentional reuse represents two different interpretations of
the same established Level-1 evidence. Recent breathing-pattern-disorder
literature also recognizes irregular breathing as a clinically recognizable
abnormal breathing pattern; MAGMA nevertheless reports a signal-derived
pattern rather than a diagnosis.

## Fixed recording-level numeric summary

The phenotype summary schema is the sole authority for names, order, units,
roles, display names, and source descriptions. The public `numeric_summary`
structure contains 24 selected numeric measures derived from the Level-2
phenotype and respiratory-pattern evidence.

| # | Feature name | Units |
|---:|---|---|
| 1 | `db_hyperventilation_rapid_fraction` | fraction |
| 2 | `db_hyperventilation_deep_fraction` | fraction |
| 3 | `db_hyperventilation_rapid_deep_overlap_fraction` | fraction |
| 4 | `db_hyperventilation_median_rr_bpm` | breaths_per_min |
| 5 | `db_hyperventilation_median_relative_excursion` | ratio |
| 6 | `db_periodic_deep_sighing_sighs_per_15_min` | events_per_15_min |
| 7 | `db_periodic_deep_sighing_max_sighs_15_min` | events_per_15_min |
| 8 | `db_periodic_deep_sighing_irregular_fraction` | fraction |
| 9 | `db_periodic_deep_sighing_sigh_irregular_overlap_fraction` | fraction |
| 10 | `db_periodic_deep_sighing_median_ibi_cov` | dimensionless |
| 11 | `db_thoracic_dominant_fraction` | fraction |
| 12 | `db_thoracic_dominant_median_ta_ratio` | ratio |
| 13 | `db_thoracic_dominant_median_event_duration_sec` | seconds |
| 14 | `db_asynchrony_fraction` | fraction |
| 15 | `db_asynchrony_median_abs_phase_deg` | degrees |
| 16 | `db_asynchrony_median_event_duration_sec` | seconds |
| 17 | `pattern_apnea_fraction` | fraction |
| 18 | `pattern_periodic_fraction` | fraction |
| 19 | `pattern_shallow_fraction` | fraction |
| 20 | `pattern_slow_fraction` | fraction |
| 21 | `pattern_irregular_fraction` | fraction |
| 22 | `pattern_desaturation_fraction` | fraction |
| 23 | `thoracic_respiratory_rhythmicity` | dimensionless (0-1) |
| 24 | `minimal_thoracic_excursion_clinician` | binary_assessment (0/1/NaN) |

The first 16 variables represent the literature-based phenotypes; positions 17-22
are the unchanged additional label-based respiratory-pattern burdens. Positions
23-24 belong to the new recording-level thoracic-excursion phenotype. Forced abdominal
expiration contributes zero variables.

Deep breathing, rapid breathing, and sighing remain fully available at Level 1
and contribute to the literature-based phenotypes without separate Level-2
profiles. Irregular breathing intentionally contributes to periodic deep
sighing and also appears as an independent label-based Level-2 profile.

## Thoracic excursion phenotype and rhythmicity

The new phenotype is **Minimal or absent thoracic excursion**. Its two features
are independent descriptions, not a thresholded diagnosis or an asynchrony subtype.

`thoracic_respiratory_rhythmicity` is the median of valid-window ratios

```text
Q = thoracic Welch power within f_AB +/- max(0.03 Hz, 0.20*f_AB)
    / thoracic Welch power over 0.05-2 Hz
```

Both integration bands are clipped to 0.05-2 Hz. Windows are 120 s with 50%
overlap. The abdominal frequency reference is the median reciprocal interval
between existing abdominal peaks, using their authoritative sample indices.
Reviewed peaks are used when available; no new peaks are detected for this metric.
Each window requires at least six eligible intervals (0.5-20 s), 70% reference
time coverage, 80% valid intervals and relative frequency IQR <= 0.5.

Signals are local copies of the existing preprocessed thoracic and abdominal
traces. Each needs 95% finite coverage, with no gap longer than 1 s. Only shorter
gaps are interpolated. Constant signals and numerical flatlines after detrending
are unavailable. Obvious transients exceeding 20 robust MAD standard deviations
reject the window; rejection counts/reasons are retained. These are transparent
signal-QC heuristics, not clinical classification criteria. Remaining artifacts
can still influence the index. Thoracic data are locally linearly detrended,
FIR anti-aliased to min(native fs, 10 Hz), and analyzed with 40-s Hamming Welch
segments with 50% overlap. PSD integrals interpolate at band edges. Q is bounded
to [0,1]; the saved value is the median of valid Q windows.

High Q means concentrated respiratory-frequency content. It does not measure
calibrated rib-cage excursion, tidal volume, or a validated probability of minimal
excursion. Low Q can reflect irregular breathing, coupling problems, noise or
artifacts. No amplitude comparison between independently normalized belts and no
binary threshold is applied. Even a very small coherent thoracic oscillation can
have high Q. No thoracic peaks are required, including when extraction is suppressed.

This is an exploratory MAGMA adaptation motivated by periodic/nonperiodic RIP
assessment in [Robles-Rubio et al. (2020)](https://doi.org/10.1371/journal.pone.0238402).
Their AUREA nonperiodic-power algorithm is different; the present ratio is not
their published exact metric and has no claimed clinical validation.

`minimal_thoracic_excursion_clinician` reuses the authoritative observation:
`observed=1`, explicitly `not_observed=0`, and `not_assessed=NaN`. Both GUIs
offer Not assessed / Not observed / Observed and preserve the saved status
unless explicitly changed. Accepting a peak/trough or label review alone does
not assess thoracic excursion or increment its observation revision. Explicit
changes retain timestamp, reviewer role, source, revision, and reanalysis handling.
Cancel/X leaves metadata unchanged. Set `config.LabelEdit.reviewer_role = 'clinician'` for a
clinician's session. Legacy/never-assessed records and disabled controls for a
technically missing belt do not silently become assessed negatives.

The method/version, parameters, reference provenance, observation revision,
availability, missing reason, total/valid window counts, valid-window fraction,
and valid time coverage are saved in `respiratory_signal_qc.thoracic`.
Technical absence returns NaN with `thoracic_belt_technically_missing` or
`thoracic_channel_missing`. Insufficient abdominal reference, flatline, finite
coverage and transient-artifact failures have separate reasons. Zero remains a
finite, available concentration value, never a missing-sensor marker.

With `config.PhenotypeSummary.do_plot`, full analyses also save
`Sub<subject>_M<measurement>_thoracic_rhythmicity_diagnostic.png`. Its three
panels show both preprocessed belts in the same valid 120-s window, their Welch
spectral shapes, and individual window concentrations with recording medians
on a common 0-1 scale. The representative window has thoracic Q23 closest to
the recording median. Signal units and numerical ticks are retained; absolute
amplitudes between belts are not calibrated against each other. Each PSD is
divided by its own total 0.05-2 Hz power, removing absolute power information.
Both concentrations use the same validated abdominal frequency and Q23 band.
The abdominal concentration is transient plotting evidence only; it is not
saved as a phenotype feature. Window counts/coverage and clinician observation
status are shown separately. Without a valid Q23 window, the figure explains
the missing reason and shows available signal evidence without a score.

These two features are recording-scoped independently of manual label coverage.
Automatic feature 24 uses `analysis_recording_observations`; Review N uses that
round's saved observation. The same saved signal QC supplies feature 23 in both
matrices, with scope/provenance explicit. The figure shows its value once and
identifies review entries as Recording QC. Label-only review never recomputes the
spectral value. Current results require all 24 features; old 22-feature results
must be regenerated from reviewed feature caches without overwriting those
features. A pending-reanalysis banner keeps
old automatic values distinguishable from a newer clinician assessment.

## Safe reanalysis with reviewed feature preservation

Close both editors. Load your normal base configuration and keep its native
sampling/channel/amplitude settings. Before any batch rerun, copy and verify the
selected recordings' MAT originals to a **fresh backup directory outside their
recording folders**:

```matlab
manifest = backup_recording_mat_files(config, backup_directory);
assert(all([manifest.verified]));
config.execution.mode = 'analyze';
config.execution.selected_labels = {};
config.overwrite_results = true;
config.overwrite_features = false;
```

The backup contains feature caches, authoritative MAT results, review checkpoints,
observation sidecars and a manifest. Each copy is loaded and compared against its
original to verify restoration. Retain this backup after reanalysis.

First use a copy of the config with `subjects=33` and `measurements=1`. Compare
both belts' saved `peak_idx`, `trough_idx`, `trough_overrides` (when present),
and complete belt structs against the verified backup before expanding the
subject list. An isolated output copy is recommended for this first real-recording
check. Do not combine this operation with new manual landmark editing. A valid
reviewed cache is reused during full and selected reruns. Incompatible reviewed
metadata or landmarks raise an error before repair/re-extraction; restore a
compatible backup or resolve the incompatibility explicitly. Thoracic suppression
retains landmark history and only gates active evidence.

The new metric performs no feature-cache I/O. Targeted tests cover a complete
synthetic full-analysis rerun, backup restoration, unchanged reviewed belt structs,
technical/physiological distinctions, cancellation, current review histories, MAT/group
and HDF5 consistency. No real cohort or batch reanalysis is run by these tests.

## Availability, zero, and coverage

All fractions use assessable time as their denominator. For each numeric-summary
feature MAGMA stores the value, an availability flag, coverage fraction, and a
missing reason.

```text
unavailable != negative
```

A finite zero is a valid available negative. Missing or unusable signal
evidence remains `NaN` with `available=false`; it is never silently converted
to zero. The numeric summaries are raw and unscaled. MAGMA performs no
cross-subject normalization, imputation, or transformation of these outputs.

## Automatic and reviewed summaries

The automatic and reviewed layers are always separate:

- **automatic** uses the full physiologically assessable recording;
- **reviewed** label-derived features (1-22) use only explicitly reviewed *and*
  physiologically assessable regions. Features 23-24 retain their independent
  recording-level scopes described above.

Recording-scope rate, excursion, CoV, balance, and phase medians obey the same
layer scope. A reviewed median therefore never incorporates an unreviewed
region, and automatic/reviewed values are never silently mixed in one row.

## Detailed Level-2 evidence and Level-1 crosswalk

The full archive preserves useful burden, event, overlap, belt-specific,
method-comparison, availability, QC, and provenance evidence. It also preserves
event-conditioned continuous summaries alongside the recording-scope summaries
selected for the fixed numeric summary.

| Level-1 evidence | Level-2 use |
|---|---|
| `rapid`, `deep`, rapid/deep overlap | Hyperventilation-like pattern |
| `sigh`, `irregular`, sigh/irregular overlap | Periodic deep sighing |
| `thoracic` and normalized belt balance | Thoracic-dominant breathing |
| `async` and reliable phase evidence | Thoraco-abdominal asynchrony |
| `irregular` | Periodic deep sighing and independent Irregular breathing profile |
| `apnea`, `periodic`, `shallow`, `slow`, `desat` | Additional label-based burdens |

## Scientific interpretation limitations

Nijmegen Questionnaire, ETCO2/capnography, CPET/ergospirometry, and other clinical
variables remain external to the original signal-derived 22 measures. The recording-level thoracic observation is the explicit exception:
it is included as feature 24 with distinct clinician provenance. Those other
clinical variables are not pipeline inputs and are not stored as placeholders. Relevant scientific
caveats are expressed only through each profile's `limitations` field.
