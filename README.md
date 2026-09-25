# Linux Power Lab

A reproducible workflow for measuring, analyzing, and improving battery life and power draw on Linux machines.

Record the hardware, kernel, power source, battery state, workload, and measurement tools for each run. Establish an idle and workload baseline, repeat measurements, then change one setting at a time and compare energy use, runtime, and performance. Keep raw readings and note sensor limits so results remain auditable.

The project will collect measurement procedures, analysis, and tested optimizations across machines.

## Development shell

Run `nix develop` to enter a shell with PowerTOP, powerstat, UPower, sensors, and hardware inventory tools. On x86-64 it also includes turbostat, perf, and Intel GPU tools. The Nushell script uses an existing `nu` installation. NVIDIA GPU readings use the host driver's `nvidia-smi`; the shell does not install a graphics driver. Some hardware counters still require root access.

## First script

Run `./scripts/power-now.nu` to show battery discharge or charging power when the battery exposes a rate. On AC, it can also report a one-second CPU package average if RAPL counters are readable. Battery charging and CPU package readings are not whole-machine AC draw; use an external meter for that measurement.

## Baseline report

Run `sudo ./scripts/measure-baseline.nu` from `nix develop`. The script requires sudo, makes no sudo calls of its own, and gives the new report to the user who invoked it. It writes a timestamped text report under `result/` with the kernel command line, exposed CPU idle states, a battery or CPU power snapshot, sensors, NVIDIA GPU data when available, a battery discharge run, RAPL domains, and turbostat. The battery run takes eight minutes and runs only if a battery is discharging at the start; the RAPL run takes one minute. `sudo ./scripts/measure-baseline.nu --quick` captures only the short snapshots.

The tools run in sequence, so their watts are not simultaneous measurements. In RAPL output, `core` is part of `pkg-0`; use `pkg-0` for CPU package power rather than adding those columns.
