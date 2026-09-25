# Linux battery and power tools: research findings

Researched 2026-09-25. This is a tool-selection and measurement guide, not a benchmark result. Availability and exposed sensors depend on the machine, firmware, kernel, and driver; inspect each machine before choosing a metric.

## Choose the measurement boundary first

| Question | Best starting point | What the reading covers |
| --- | --- | --- |
| How much power does this laptop draw on battery? | Battery `energy_now` over a timed discharge, with `powerstat` or `upower` for live inspection | Energy leaving the battery, including the whole running system as seen by its battery gauge |
| Which CPU/package change helped? | RAPL `energy_uj` or `turbostat` | The named hardware energy domain, not necessarily the whole machine |
| Is the dedicated GPU staying active? | `nvidia-smi`, AMD GPU `hwmon`, or driver-specific telemetry | The GPU board or reported domain, subject to driver support |
| What draws at the AC outlet? | External, suitably calibrated wall power meter | Machine plus power-supply/charging losses and any attached loads on that outlet |
| Why is idle power high? | PowerTOP, CPU idle counters, `perf`, device runtime-PM state | Activity and possible causes; these are diagnostic clues, not additive wattmeters |

The [kernel power-supply interface](https://docs.kernel.org/power/power_supply_class.html) defines `energy_*` in µWh, `charge_*` in µAh, and `capacity` in percent. Do not use a percentage drop as a fine power meter, or mix charge and energy without voltage. Some hardware omits attributes. `power_now` is a momentary value when exposed; for a longer run, the change in `energy_now` is the more useful aggregate. The [powercap interface](https://docs.kernel.org/power/powercap/powercap.html) provides RAPL `energy_uj` and `max_energy_range_uj`; its domains can nest, so do not sum a package and its core subdomain. RAPL does not expose instantaneous power through this interface: derive mean watts from joules divided by elapsed seconds.

## Measurement and diagnosis tools

| Tool | Use and example | Limits and interpretation |
| --- | --- | --- |
| Battery sysfs: `/sys/class/power_supply/` | Discover the actual battery name; record `status`, `energy_now`, `energy_full`, `power_now` when present, and AC `online`. Preserve raw values and timestamps. [Kernel reference](https://docs.kernel.org/power/power_supply_class.html). | Battery-gauge update rate and resolution vary. Use a discharge interval long enough to produce a clear energy change. Do not assume the device is named `BAT0`. |
| `upower` | `upower -e`, then `upower -i DEVICE`; inspect energy, energy rate, and state. Useful for an initial inventory and desktop-visible values. [UPower CLI](https://upower.freedesktop.org/docs/upower.1.html), [device API](https://upower.freedesktop.org/docs/Device.html). | A convenient view of battery data, not an independent reference instrument. Confirm its sign and units before scripting. |
| `powerstat` | Repeated battery or RAPL power sampling with average, spread, CPU activity, and other context. Good for exploratory idle comparisons. [Project documentation](https://github.com/ColinIanKing/powerstat). | Check which source it selected. Its own RAPL example says those readings do not cover all hardware. Adjacent samples are correlated; compare repeated runs, not just sample count. |
| PowerTOP | `sudo powertop --html=powertop.html --time=60` for wakeups, idle states, devices, and tunable suggestions. `--csv` can aid later analysis. [Project README](https://github.com/fenrus75/powertop/blob/master/README.md). | Per-process/device watts are model estimates. Battery calibration can improve them, but can change brightness and exercise devices; run it outside benchmark trials. `--auto-tune` changes settings, so treat it as an intervention to test, not a baseline measurement. Reports may contain system details. |
| RAPL via powercap | Read a named zone's `energy_uj` before and after a workload; inspect `name` and `max_energy_range_uj`. [Kernel powercap guide](https://docs.kernel.org/power/powercap/powercap.html). | A counter can wrap. Choose an interval short enough to detect wraps or use a sampler that handles them. RAPL domains differ by processor and are not interchangeable with battery or wall power. |
| `turbostat` | On supported x86 systems, inspect frequency, CPU/package idle residency, temperature, and available RAPL power columns such as `PkgWatt`. [Kernel tool source](https://github.com/torvalds/linux/blob/master/tools/power/x86/turbostat/turbostat.c). | Useful for explaining a CPU result; reported fields vary by platform. Package watts are a component reading. |
| `perf` | `perf stat -a` can count CPU activity system-wide; `perf list` shows available events. Use tracepoints or sampled call stacks to identify work behind wakeups. [perf stat manual](https://www.man7.org/linux/man-pages/man1/perf-stat.1.html). | Event access may require privileges. Tracing adds overhead; do a short diagnostic capture separately from final energy trials. |
| GPU telemetry | NVIDIA: inspect `nvidia-smi` power draw and state. AMD: inspect supported `hwmon` `power1_average` and clocks. [NVIDIA guide](https://docs.nvidia.com/deploy/nvidia-smi/), [AMD kernel guide](https://docs.kernel.org/gpu/amdgpu/thermal.html). | NVIDIA board-power fields and AMD sensor coverage vary. On an AMD APU, the reported SoC power can include the CPU; do not add it to CPU package energy without checking overlap. |
| Sleep tools | Check `/sys/power/mem_sleep` to record `s2idle` versus `deep`; use [SleepGraph/pm-graph](https://github.com/intel/pm-graph/blob/master/README) for suspend/resume timelines and wake investigations. [Kernel sleep-state guide](https://docs.kernel.org/admin-guide/pm/sleep-states.html). | A suspend timeline diagnoses transition time, not sleep energy. For drain, compare battery energy before/after a long, timed suspend; account for the awake periods around it. |

An external meter helps validate AC input power, but its result is **not** battery discharge power. When charging, it also includes energy going into the battery; charger efficiency and external displays or peripherals change the boundary. Record the exact setup and meter model/calibration. This distinction follows from the battery and powercap measurement boundaries above.

## Controlled workloads and outcomes

| Tool | Role | What to record |
| --- | --- | --- |
| [stress-ng](https://github.com/ColinIanKing/stress-ng/blob/master/README.md) | Repeatable CPU, memory, or I/O stressors; fix worker count, method, and duration. Its `--metrics` output reports completed work; `--rapl` is available on supported x86 systems. | Work completed, elapsed time, energy, temperature, and whether all stressors passed. A synthetic load tests a component, not typical battery life. |
| [fio](https://github.com/axboe/fio/blob/master/HOWTO.rst) | Versioned job files for storage I/O patterns. | Job file, target device/file, bytes, throughput/latency, cache mode, energy, and drive temperature. Writes can alter data and SSD state; use a designated test file. |
| [hyperfine](https://github.com/sharkdp/hyperfine/blob/master/README.md) | Repeat command timings with warmups and export JSON or CSV. | Per-run time and setup. Pair with an energy logger: timing alone cannot show joules per task. |
| Real tasks | Browser session, video playback, software build, or a scripted daily workflow. | Exact content, network state, resolution/brightness, audio, completion criterion, elapsed time, and energy. This is the strongest check that a synthetic gain matters in use. |

For a fixed amount of work, compare **joules per completed task** and elapsed time as well as mean watts. For a fixed-duration activity such as video playback, compare watt-hours consumed over the same duration and quality settings. A lower watt value can still cost more total energy if the task runs longer.

## Tuning tools and surfaces to test

| Candidate | How to inspect or apply | Experimental rule |
| --- | --- | --- |
| Power Profiles Daemon | `powerprofilesctl list`, `get`, `set power-saver` where installed. [Project API](https://power-profiles-daemon-3v1n0-b70231ec1c573ac1bbe38f86440a681ab59.pages.freedesktop.org/gdbus-org.freedesktop.UPower.PowerProfiles.html). | Record the active profile and backend; profile names do not prove a saving. |
| TLP | `tlp-stat -s` for status, then test a documented profile or one setting. [TLP profiles](https://linrunner.de/tlp/settings/introduction.html), [usage](https://linrunner.de/tlp/usage/index.html). | Record effective settings and restore baseline after a trial. Battery charge thresholds concern battery longevity, not lower operating draw. [Battery-care reference](https://linrunner.de/tlp/settings/battery.html). |
| TuneD | `tuned-adm active`, `list`, `profile NAME`, `verify`. [Project README](https://github.com/redhat-performance/tuned/blob/master/README.md). | A profile changes multiple settings. Inspect its contents before attributing a result to one knob. TuneD's project documentation states it conflicts with some other power managers; avoid competing policy daemons during trials. |
| CPU frequency/energy preference | Inspect `/sys/devices/system/cpu/cpufreq/policy*/` for current driver, governor, limits, and supported energy preferences. [CPUFreq](https://docs.kernel.org/admin-guide/pm/cpufreq.html), [Intel P-State](https://docs.kernel.org/admin-guide/pm/intel_pstate.html). | Compare both idle and work-completion energy. A frequency cap can slow tasks enough to erase a power saving. |
| Device runtime PM and USB autosuspend | Inspect each device's `power/control`, `runtime_status`, and supported delay before a targeted change. [Runtime PM](https://docs.kernel.org/power/runtime_pm.html), [USB PM](https://docs.kernel.org/driver-api/usb/power-management.html). | Test device behavior, wake latency, and reconnects; a broad `powertop --auto-tune` result is only a hypothesis. |

## Suggested experiment protocol

1. **Inventory:** save machine model, CPU/GPU, battery health and capacity, firmware, kernel, distro, tool versions, available sensors, and active power manager. State whether the outcome is whole-machine battery energy, wall energy, or a named component domain.
2. **Fix conditions:** use the same power source, battery state-of-charge range, screen brightness and refresh rate, attached devices, radios/network, room temperature, and workload data. Let the machine settle after boot or profile changes. Record these values with each run.
3. **Establish baselines:** measure quiet idle and at least one fixed, realistic workload. Observe background jobs and CPU/GPU temperature; postpone runs disturbed by updates, thermal throttling, or unexpected activity.
4. **Take paired measurements:** record monotonic start/end times and raw energy counters. On battery, `E_Wh = (energy_start_µWh - energy_end_µWh) / 1,000,000`. Then `P_mean_W = E_Wh / duration_hours`. For RAPL, `E_J = delta_energy_µJ / 1,000,000` and `P_mean_W = E_J / duration_seconds`, after handling counter wrap. Keep a separate log of performance and correctness.
5. **Repeat and compare:** run at least three independent baseline and candidate trials when feasible, alternating order (for example A–B–B–A) to reduce time/temperature drift. Compare trial-level means or medians and their spread. Treat small differences near gauge resolution or natural run-to-run variation as inconclusive.
6. **Diagnose:** use PowerTOP, `turbostat`, `perf`, GPU telemetry, and runtime-PM state to explain a measured difference. Keep heavy tracing out of the primary comparison unless equally applied to both conditions.
7. **Change one thing:** save the original setting, apply one candidate, repeat the same workload, and check latency, throughput, device behavior, and sleep/wake behavior. Restore the setting before the next candidate. For a bundled profile, report it as a bundle.
8. **Report:** preserve raw time series and commands, tool versions, hardware context, each trial's energy/time/work, summary statistics, and rejected runs. State the measurement boundary and sensor limitations alongside every claimed saving.

This protocol is a proposed experimental method derived from the tools' stated measurement scopes and interfaces; it has not yet been validated on a specific machine.
