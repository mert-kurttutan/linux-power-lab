#!/usr/bin/env nu

# Record a battery baseline and component readings in a timestamped text file.
const default_result_dir = path self ../result
const power_now = path self power-now.nu

def append-text [file: string, heading: string, body: string] {
    $"\n## ($heading) — (date now | format date '%Y-%m-%d %H:%M:%S %Z')\n($body)\n" | save --append --raw $file
}

def run-section [file: string, heading: string, command: closure] {
    let started = (date now | format date '%Y-%m-%d %H:%M:%S %Z')
    print $heading
    let result = (do $command | complete)
    let body = ([
        $"Started: ($started)"
        $"Exit code: ($result.exit_code)"
        ($result.stdout | str trim)
        ($result.stderr | str trim)
    ] | where { |line| $line != '' } | str join "\n")
    append-text $file $heading $body
}

def main [
    --output-dir: string = $default_result_dir
    --quick # Skip the eight-minute battery and one-minute RAPL runs.
] {
    let caller_uid = $env.SUDO_UID?
    let caller_gid = $env.SUDO_GID?
    if ((^id -u | str trim | into int) != 0) or $caller_uid == null or $caller_gid == null {
        error make {msg: 'Run this script with sudo: sudo ./scripts/measure-baseline.nu'}
    }

    let result_dir_existed = ($output_dir | path exists)
    mkdir $output_dir
    let owner = $"($caller_uid):($caller_gid)"
    if (not $result_dir_existed) or $output_dir == $default_result_dir {
        ^chown $owner $output_dir
    }
    let filename = $"(date now | format date '%Y-%m-%d_%H-%M-%S%.3f')-power.txt"
    let report = ($output_dir | path join $filename)
    if ($report | path exists) {
        error make {msg: $"Report already exists: ($report)"}
    }

    $"Linux power baseline\nCreated: (date now | format date '%Y-%m-%d %H:%M:%S %Z')\nMeasurements run in sequence; compare their timestamps before attributing power to a component.\nBattery watts describe discharge from the battery. RAPL package watts cover the CPU package, and RAPL core is already inside that package.\n" | save --raw $report
    ^chown $owner $report
    print $"Writing ($report)"

    run-section $report 'System' { ^uname -a }
    run-section $report 'Kernel command line' { ^cat /proc/cmdline }

    let idle_driver = (try { open /sys/devices/system/cpu/cpuidle/current_driver | str trim } catch { 'unavailable' })
    let max_cstate = (try { open /sys/module/intel_idle/parameters/max_cstate | str trim } catch { 'unavailable' })
    let states = (glob /sys/devices/system/cpu/cpu0/cpuidle/state*/name | sort | each { |path| open $path | str trim } | str join ', ')
    append-text $report 'CPU idle configuration' $"Driver: ($idle_driver)\nintel_idle.max_cstate: ($max_cstate)\nCPU 0 states: ($states)"

    let batteries = (glob /sys/class/power_supply/* | where { |device|
        (try { open ($device | path join type) | str trim } catch { '' }) == 'Battery'
    } | each { |device|
        {name: ($device | path basename), status: (try { open ($device | path join status) | str trim } catch { 'unknown' })}
    })
    let battery_lines = ($batteries | each { |battery| $"($battery.name): ($battery.status)" } | str join "\n")
    append-text $report 'Battery status at start' (if ($batteries | is-empty) { 'No battery detected' } else { $battery_lines })

    run-section $report 'Battery or CPU package now' { ^$power_now }

    let sensors = (which sensors | get -o 0.path)
    if $sensors != null {
        run-section $report 'Sensors' { ^$sensors }
    } else {
        append-text $report 'Sensors' 'sensors is unavailable'
    }

    let nvidia_smi = (which nvidia-smi | get -o 0.path)
    if $nvidia_smi != null {
        run-section $report 'NVIDIA GPU snapshot' {
            ^$nvidia_smi --query-gpu=timestamp,power.draw,utilization.gpu,temperature.gpu,pstate --format=csv
        }
    } else {
        append-text $report 'NVIDIA GPU snapshot' 'nvidia-smi is unavailable'
    }

    if not $quick {
        let powerstat = (which powerstat | get -o 0.path)
        if $powerstat != null {
            if not ($batteries | where status == 'Discharging' | is-empty) {
                run-section $report 'Battery discharge: 96 samples at 5-second intervals' {
                    ^$powerstat -d 0 5 96
                }
            } else {
                append-text $report 'Battery discharge' 'Skipped: no battery was discharging when the report started'
            }
            run-section $report 'RAPL domains: 12 samples at 5-second intervals' {
                ^$powerstat -RD 5 12
            }
        } else {
            append-text $report 'powerstat' 'powerstat is unavailable'
        }

        let turbostat = (which turbostat | get -o 0.path)
        if $turbostat != null {
            run-section $report 'CPU package and idle residency: 10 one-second samples' {
                ^$turbostat --quiet --Summary --interval 1 --num_iterations 10 --show 'PkgWatt,CorWatt,CPU%c1,CPU%c6,CPU%c7'
            }
        } else {
            append-text $report 'turbostat' 'turbostat is unavailable'
        }
    }

    print $"Report saved: ($report)"
}
