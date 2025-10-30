# --------------------------------------------------------------------
# Write_reports.tcl
# Generates summary report: clocks, Fmax, slack, critical warnings,
# And known Vivado warnings
# Usage: set stage "<synth|place|route|final>"; source write_reports.tcl
# --------------------------------------------------------------------

if {![info exists stage]} {
    set stage "final"
}

# Report directory
set report_dir "../build/reports_${stage}"
file mkdir $report_dir
set summary_file "${report_dir}/summary.rpt"
set timing_file "$report_dir/timing_summary.rpt"

# Vivado timing report
report_timing_summary -file  $timing_file -quiet

# --------------------------------------------------------------------
# Known Vivado warnings (non-critical)
# --------------------------------------------------------------------
set warning_patterns {
    {Route 35-328}
    {Timing Violation}
    {Synth 8-3295}
    {DRC PDCN-1569}
}

# --------------------------------------------------------------------
# Utility procs
# --------------------------------------------------------------------
proc report_violated_paths {fp timing_file} {
    if {![file exists $timing_file]} { return }

    set fh [open $timing_file r]
    set rpt_data [read $fh]
    close $fh

    set hints {
        setup "Check pipeline/register placement"
        hold  "Check clock skew or add delay buffers"
    }

    puts $fp ""
    puts $fp "-- Violated Timing Paths (Slack < 0) --"
    puts $fp "Signal (Endpoint)        | Clock        | Type  | Slack (ns) | Hint"
    puts $fp "--------------------------------------------------------------------------"

    foreach line [split $rpt_data "\n"] {
        # Match lines with slack < 0, e.g.:
        # "Path Type: setup, Slack: -0.521, Endpoint: u_eth/u_mac/rx_data_reg, Clock: rgmii_rx_clk"
        if {[regexp {Path Type:\s*(\S+),\s*Slack:\s*(-?\d+\.\d+),\s*Endpoint:\s*(\S+),\s*Clock:\s*(\S+)} $line -> type slack endp clk]} {
            if {[expr {$slack < 0.0}]} {
                set hint [dict get $hints $type]
                puts $fp [format "%-24s | %-11s | %-5s | %-10s | %s" $endp $clk $type $slack $hint]
            }
        }
    }

    puts $fp "--------------------------------------------------------------------------"
}


# Get timing numbers per clock (WNS, TNS, WHS, THS)
proc get_timing_per_clock {clk_name} {
    global timing_file
    set rpt_file $timing_file
    if {![file exists $rpt_file]} {
        return [list WNS "N/A" TNS "N/A" WHS "N/A" THS "N/A"]
    }
    set fh [open $rpt_file r]
    set rpt_data [read $fh]
    close $fh

    # Initialize defaults
    array set timing {
        WNS "N/A"
        TNS "N/A"
        WHS "N/A"
        THS "N/A"
    }

    # --- 1) Search Path Group tables ---
    foreach line [split $rpt_data "\n"] {
        if {[regexp {^\s*\S+\s+(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)} $line -> from_clk to_clk wns tns]} {
            if {$from_clk eq $clk_name || $to_clk eq $clk_name} {
                set timing(WNS) $wns
                set timing(TNS) $tns
            }
        }
    }

    # --- 2) Search final clock summary ---
    foreach line [split $rpt_data "\n"] {
        if {[regexp "^\\s*$clk_name\\s+(-?\\d+\\.\\d+)\\s+(-?\\d+\\.\\d+).*?(-?\\d+\\.\\d+)\\s+(-?\\d+\\.\\d+)" $line -> wns tns whs ths]} {
            set timing(WNS) $wns
            set timing(TNS) $tns
            set timing(WHS) $whs
            set timing(THS) $ths
        }
    }

    return [array get timing]
}

# Top N critical warnings/errors
proc get_top_messages {N} {
    set out {}
    if {[llength [info commands get_messages]] > 0} {
        set msgs [get_messages -severity {CRITICAL_WARNING ERROR FATAL}]
        set count 0
        foreach m $msgs {
            if {$count >= $N} {break}
            lappend out [get_property MSG_STRING $m]
            incr count
        }
    } elseif {[file exists vivado.log]} {
        set fh [open vivado.log r]
        set lines [split [read $fh] "\n"]
        close $fh
        set filtered {}
        foreach l $lines {
            if {[regexp {^(CRITICAL WARNING:|ERROR:|FATAL:)} $l]} {
                lappend filtered $l
            }
        }
        set out [lrange $filtered 0 [expr {$N-1}]]
    }
    return $out
}

# Parse clockInfo.txt for additional clocks
proc parse_clockinfo {fname} {
    set clocks {}
    if {[file exists $fname]} {
        set fh [open $fname r]
        set lines [split [read $fh] "\n"]
        close $fh
        foreach l $lines {
            if {[regexp {^Clock \d+: ([^ ]+)} $l -> clkname]} {
                lappend clocks $clkname
            }
        }
    }
    return $clocks
}

# Extract known Vivado warnings from vivado.log
proc get_known_warnings {patterns} {
    set out {}
    if {[file exists vivado.log]} {
        set fh [open vivado.log r]
        set lines [split [read $fh] "\n"]
        close $fh
        foreach l $lines {
            # Skip comment lines starting with ##
            if {[string match "# #*" $l]} { continue }
            foreach pat $patterns {
                if {[regexp $pat $l]} {
                    lappend out $l
                    break   ;# Avoid duplicating if multiple patterns match
                }
            }
        }
    }
    return $out
}

# --------------------------------------------------------------------
# Clock information
# --------------------------------------------------------------------
set clk_aliases [list \
    clk_200_p    clk_200_p \
    clk_200_n    clk_200_p \
    rgmii_rx_clk rgmii_rx_clk \
    rgmii_tx_clk rgmii_tx_clk \
    fabric_clk   fabric_clk \
    gtx_clk90    gtx_clk90 \
]
#fabric_clk   clk_out1_clk_wiz_0 \
#gtx_clk90    clk_out2_clk_wiz_0 \

set script_dir [file dirname [info script]]
set clockinfo_file "${script_dir}/clockInfo.txt"
set clockinfo_clocks [parse_clockinfo $clockinfo_file]

# --------------------------------------------------------------------
# Generate summary report
# --------------------------------------------------------------------
set fp [open $summary_file w]
puts $fp "---------------------------------------------------------------"
puts $fp "| Clock           | Fmax (MHz) | Slack (ns) | Status           |"
puts $fp "---------------------------------------------------------------"

foreach {alias actual} $clk_aliases {
    set fmax "N/A"
    set slack "N/A"
    set status "MISSING"

    set clk_obj [get_clocks -quiet $actual]
    if {[llength $clk_obj] > 0} {
        if {![catch {get_property PERIOD $clk_obj} period]} {
            set fmax [format "%.2f" [expr {1000.0 / $period}]]

            # Use new timing extractor
            array set results [get_timing_per_clock $actual]
            set slack $results(WNS)

            if {$slack ne "N/A"} {
                if {[expr {$slack < 0.0}]} {
                    set status "FAIL (slack)"
                } else {
                    set status "PASS"
                }
            } else {
                set status "PASS"
            }
        }
    } elseif {[lsearch -exact $clockinfo_clocks $alias] >= 0 || \
              [lsearch -exact $clockinfo_clocks $actual] >= 0} {
        set status "UNUSED"
    }

    if {$alias ne $actual && $status ni {"MISSING" "UNUSED"}} {
        set status "$status (alias)"
    }

    puts $fp [format "| %-15s | %-10s | %-10s | %-15s |" \
        $alias $fmax $slack $status]
}

puts $fp "---------------------------------------------------------------"
puts $fp ""

# --------------------------------------------------------------------
# Top 10 critical warnings/errors
# --------------------------------------------------------------------
puts $fp "-- Top 10 Critical Warnings / Errors --"
puts $fp "Count | Message"
puts $fp "-------------------------------"
set msgs [get_top_messages 10]
set idx 1
foreach m $msgs {
    puts $fp [format "%-5d | %s" $idx $m]
    incr idx
}

# --------------------------------------------------------------------
# Known Vivado warnings (non-critical)
# --------------------------------------------------------------------
puts $fp ""
puts $fp "-- Other Known Warnings --"
puts $fp "Count | Message"
puts $fp "-------------------------------"
set known_warnings [get_known_warnings $warning_patterns]
set idx 1
foreach w $known_warnings {
    puts $fp [format "%-5d | %s" $idx $w]
    incr idx
}

# --------------------------------------------------------------------
# Global Timing Closure Summary
# --------------------------------------------------------------------
puts $fp ""
puts $fp "-- Global Timing Closure Summary --"
set rpt_file $timing_file
if {[file exists $rpt_file]} {
    set fh [open $rpt_file r]
    set rpt_data [read $fh]
    close $fh

    set WNS "N/A"
    set TNS "N/A"
    set WHS "N/A"
    set THS "N/A"

    foreach line [split $rpt_data "\n"] {
        if {[regexp {WNS:\s+(-?\d+\.\d+)} $line -> v]} { set WNS $v }
        if {[regexp {TNS:\s+(-?\d+\.\d+)} $line -> v]} { set TNS $v }
        if {[regexp {WHS:\s+(-?\d+\.\d+)} $line -> v]} { set WHS $v }
        if {[regexp {THS:\s+(-?\d+\.\d+)} $line -> v]} { set THS $v }
    }

    puts $fp [format "WNS = %s ns   | TNS = %s ns" $WNS $TNS]
    puts $fp [format "WHS = %s ns   | THS = %s ns" $WHS $THS]
    puts $fp ""

    if {$WNS ne "N/A" && $WNS < 0} {
        puts $fp "Negative WNS: tighten constraints, check critical path placement, consider pipelining."
    } elseif {$TNS ne "N/A" && $TNS < 0} {
        puts $fp "Negative TNS: multiple paths failing, review floorplanning or timing exceptions."
    } elseif {$WHS ne "N/A" && $WHS < 0} {
        puts $fp "Negative WHS: hold violation, add delay buffers or fix skew."
    } elseif {$THS ne "N/A" && $THS < 0} {
        puts $fp "Negative THS: widespread hold issues, check clocking and placement."
    } else {
        puts $fp "All major timing checks pass."
    }
}
# Append violated paths table
report_violated_paths $fp $timing_file

close $fp
puts "Report generated: $summary_file"