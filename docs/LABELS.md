# Label definitions

MAGMA detects elementary physiological patterns rather than clinical diagnoses.

Labels are independent and may overlap.

Unless explicitly literature-derived, thresholds below are operational research criteria.

| Label | Primary evidence | Primary condition |
|---|---|---|
| `shallow` | Belt excursion | $0.10 < A/A_{ref} \leq 0.80$, sustained ≥30 s |
| `deep` | Belt excursion | $A/A_{ref} \geq 1.20$, sustained ≥30 s |
| `slow` | Respiratory rate | ≤10 breaths/min, 60-s estimate, localized state ≥30 s |
| `rapid` | Respiratory rate | ≥20 breaths/min, 60-s estimate, localized state ≥30 s |
| `irregular` | IBI variability | 60-s $CV_{IBI} \geq 0.30$ |
| `apnea` | Very-low respiratory movement | ≤10% reference excursion for ≥10 s |
| `sigh` | Local breath excursion | Breath ≥2× centered 15-breath median |
| `periodic` | eAMI | eAMI ≥0.60 with sustained periodic modulation |
| `thoracic` | Relative thoracic/abdominal excursion | Normalized T/A ≥1.5 for ≥30 s |
| `async` | Thoracoabdominal phase offset | Reliable absolute phase offset ≥30° for sustained period |
| `desat` | SpO₂ | <90% or ≥3 percentage-point reference drop for ≥10 s |

## Shallow and deep breathing

Amplitude is measured relative to the belt-specific session reference.

The two belts are evaluated independently because their absolute amplitudes are not directly comparable.

## Slow and rapid breathing

Respiratory rate is estimated over 60-s windows and then localized using the reviewed respiratory cycles.

## Irregular breathing

The primary measure is the coefficient of variation of inter-breath intervals:

$$
CV_{IBI}
=
\frac{\mathrm{SD}(IBI)}
{\mathrm{mean}(IBI)}.
$$

Entropy and other nonlinear variability measures are not part of the current binary label.

## Apnea-like respiratory pauses

The label represents prolonged very-low respiratory movement.

Breath-amplitude evidence is preferred. Raw respiratory-belt excursion is used as a fallback when breath amplitudes cannot be evaluated.

When both belts are evaluable, both must support the event.

Because airflow is not measured directly, this label should be interpreted as an **apnea-like respiratory pause**, not confirmed obstructive or central apnea.

## Sigh

The primary method uses the Genecand-style local criterion:

$$
A_i
\geq
2\,
\operatorname{median}
(A_{i-7},\ldots,A_{i+7}).
$$

The same canonical belt amplitude selected by `config.resp.amp_method` is used by all sigh methods.

## Periodic breathing

The primary detector is the estimated amplitude modulation index (eAMI).

With the default eAMI primary selection, the Guyot demodulation/Matrix Pencil
implementation is retained as complementary evidence. It can instead supply
the final label through `config.periodic.primary_method = 'guyot'`.

MAGMA uses an adapted eAMI threshold of `0.60` and a configured Guyot
modulation-frequency band of `0.008–0.050 Hz`; these are tuned MAGMA settings,
not exact published thresholds. Guyot centered-window decisions represent the
nearest-center interval (boundaries halfway between adjacent centers) and are
never projected across the full 120-second analysis window. Sustained support
must still meet the configured 60-second minimum.

The output represents periodic or Cheyne–Stokes-like respiratory-effort modulation rather than a clinical diagnosis of Cheyne–Stokes respiration.

## Thoracic-dominant breathing

Thoracic and abdominal excursions are first normalized to their own session references.

The label is based on:

$$
\frac{T_{normalized}}
{A_{normalized}}
\geq 1.5.
$$

This describes relative thoracic dominance, not the absolute thoracic contribution to tidal volume.

## Respiratory asynchrony

The primary measure is thoracoabdominal phase offset.

Thoracic and abdominal signals are evaluated at one shared respiratory frequency. Reviewed breath timing guides the respiratory fundamental where available.

For local phase differences $\Delta\phi_j$,

$$
Z
=
\frac{1}{N}
\sum_j e^{i\Delta\phi_j}.
$$

The circular mean phase is:

$$
\bar{\phi}=\arg(Z),
$$

and phase consistency is:

$$
R=|Z|.
$$

Primary evidence requires:

- $|\bar{\phi}| \geq 30^\circ$;
- $R \geq 0.80$;
- at least 80% valid phase evidence;
- summary over five respiratory cycles;
- sustained support for the configured minimum duration.

A stable $180^\circ$ relationship therefore represents a large phase offset even though its phase consistency is high.

The older wavelet-coherence detector remains available as complementary evidence.

## Oxygen desaturation

A desaturation event is detected when:

$$
\mathrm{SpO}_2 < 90\%
$$

or

$$
\mathrm{SpO}_{2,ref}-\mathrm{SpO}_2
\geq 3
$$

percentage points for at least 10 s.

The absolute criterion does not require an available session reference.

Event diagnostics additionally store nadir, event depth, criterion support, and recovery information.
