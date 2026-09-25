#!/usr/bin/env nu

# Show battery power flow and, when available, a CPU-package estimate.
def read-number [path: string] {
    if not ($path | path exists) { return null }
    try { open $path | str trim | into int } catch { null }
}

def battery-watts [device: string] {
    let power = (read-number ($device | path join power_now))
    if $power != null { return (($power | math abs) / 1000000) }

    let current = (read-number ($device | path join current_now))
    let voltage = (read-number ($device | path join voltage_now))
    if $current != null and $voltage != null {
        return ((($current | math abs) * $voltage) / 1000000000000)
    }
    null
}

def main [] {
    let batteries = (glob /sys/class/power_supply/* | where { |device|
        (try { open ($device | path join type) | str trim } catch { '' }) == 'Battery'
    })

    let discharging = ($batteries | where { |device|
        (try { open ($device | path join status) | str trim } catch { '' }) == 'Discharging'
    })

    if not ($discharging | is-empty) {
        let readings = ($discharging | each { |device|
            {name: ($device | path basename), watts: (battery-watts $device)}
        })

        if ($readings | where watts == null | is-empty) {
            let watts = ($readings | get watts | math sum | math round --precision 2)
            let names = ($readings | get name | str join ', ')
            print $"Battery discharge: ($watts) W [($names)]"
            return
        }
    }

    let charging = ($batteries | where { |device|
        (try { open ($device | path join status) | str trim } catch { '' }) == 'Charging'
    })
    mut measured_charge = false
    if not ($charging | is-empty) {
        let readings = ($charging | each { |device|
            {name: ($device | path basename), watts: (battery-watts $device)}
        })
        if ($readings | where watts == null | is-empty) {
            let watts = ($readings | get watts | math sum | math round --precision 2)
            let names = ($readings | get name | str join ', ')
            print $"Battery charging: ($watts) W into [($names)]; this is not machine power draw"
            $measured_charge = true
        }
    }

    # Select one interface per CPU package; RAPL package and subdomain
    # counters overlap, and the MMIO interface can duplicate the main one.
    for prefix in ['intel-rapl:' 'amd-rapl:' 'intel-rapl-mmio:'] {
        let zones = (glob /sys/class/powercap/* | where { |zone|
            let name = ($zone | path basename)
            ($name | str starts-with $prefix) and (($name | split row ':' | length) == 2)
        })
        if ($zones | is-empty) { continue }

        let started = (date now)
        let first = ($zones | each { |zone|
            {path: $zone, energy: (read-number ($zone | path join energy_uj)), range: (read-number ($zone | path join max_energy_range_uj))}
        })
        if not ($first | where energy == null or range == null | is-empty) { continue }

        sleep 1sec
        let second = ($first | each { |zone|
            $zone | insert final_energy (read-number ($zone.path | path join energy_uj))
        })
        if not ($second | where final_energy == null | is-empty) { continue }

        let seconds = ((date now) - $started) / 1sec
        let joules = ($second | each { |zone|
            let delta = if $zone.final_energy >= $zone.energy {
                $zone.final_energy - $zone.energy
            } else {
                $zone.range - $zone.energy + $zone.final_energy
            }
            $delta / 1000000
        } | math sum)
        let watts = ($joules / $seconds | math round --precision 2)
        let elapsed = ($seconds | math round --precision 2)
        print $"CPU package power: ($watts) W; RAPL average over ($elapsed) s; not whole-machine draw"
        return
    }

    if $measured_charge {
        print 'Whole-machine AC draw is unavailable from these sensors; use an external power meter.'
        return
    }
    if not ($discharging | is-empty) {
        print --stderr 'A battery is discharging, but it exposes no readable power_now or current_now + voltage_now values.'
    } else if not ($charging | is-empty) {
        print --stderr 'A battery is charging, but it exposes no readable power_now or current_now + voltage_now values.'
    } else {
        let states = ($batteries | each { |device|
            let status = (try { open ($device | path join status) | str trim } catch { 'unknown' })
            $"($device | path basename): ($status)"
        } | str join ', ')
        print --stderr $"Battery status: ($states). No charge or discharge rate to report. Whole-machine AC draw needs an external meter; CPU RAPL counters, if present, may require sudo."
    }
    exit 1
}
