# Configuration

MAGMA uses a two-level configuration so routine setup remains short while all
scientific defaults have one authoritative definition.

## Normal use

Edit `src/get_config.m` for input/output paths, recordings, execution options,
respiratory amplitude representation, explicit primary methods, and optional
manual review. It starts with the complete defaults and returns a fully
compatible configuration.

Configuration construction has no filesystem or GUI side effects. The shared
`run_magma(config)` runner creates the output directory and saves the final
caller-resolved configuration before processing any recording.

## Advanced/default settings

`src/get_config_defaults.m` contains every detector threshold, processing
window, duration criterion, reference setting, export option, and internal
default. Scientific thresholds normally should remain at their predefined
values unless the analysis is intentionally being modified.

Do not copy the full defaults into `get_config.m`; override only the small set
of settings that differs for the intended run.
