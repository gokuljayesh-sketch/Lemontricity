#!/usr/bin/tclsh

# ==============================================================================
# H3.3 – CTS QUALITY CHECKER
# ==============================================================================
proc check_cts_quality {data_text {max_slew_limit 0.100}} {
    puts "--- H3.3 CTS Quality Checker Report ---"
    puts [format "Configured Max Slew Limit: %.3f ns" $max_slew_limit]
    puts ""
    
    set total_sinks 0
    set slew_violations 0
    
    set min_latency 999999.0
    set max_latency 0.0
    set min_sink ""
    set max_sink ""
    
    puts [format "%-10s | %-18s | %-20s | %-15s | %-10s" \
            "Sink Name" "Clock Latency (ns)" "Transition Slew (ns)" "Slew Limit (ns)" "Slew Status"]
    puts "-----------------------------------------------------------------------------------"
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        
        # Parse format: SINK1 LATENCY=0.480 SLEW=0.082
        if {[regexp {(\S+)\s+LATENCY=(\S+)\s+SLEW=(\S+)} $line -> sink lat slew]} {
            incr total_sinks
            
            # Latency bounds
            if {$lat < $min_latency} {
                set min_latency $lat
                set min_sink $sink
            }
            if {$lat > $max_latency} {
                set max_latency $lat
                set max_sink $sink
            }
            
            # Slew check
            set status "PASS"
            if {$slew > $max_slew_limit} {
                set status "VIOLATION"
                incr slew_violations
            }
            
            puts [format "%-10s | %-18.3f | %-20.3f | %-15.3f | %-10s" \
                    $sink $lat $slew $max_slew_limit $status]
        }
    }
    
    if {$total_sinks == 0} {
        puts "Error: No valid CTS sink data found."
        return
    }
    
    set global_skew [expr {$max_latency - $min_latency}]
    
    puts "-----------------------------------------------------------------------------------"
    puts [format "Total Sinks Analyzed : %d" $total_sinks]
    puts [format "Minimum Clock Latency: %.3f ns (at %s)" $min_latency $min_sink]
    puts [format "Maximum Clock Latency: %.3f ns (at %s)" $max_latency $max_sink]
    puts [format "Global Clock Skew    : %.3f ns (%.1f ps)" $global_skew [expr {$global_skew * 1000.0}]]
    puts [format "Slew Violations Count: %d" $slew_violations]
    puts ""
}

# Level 3 Dataset 3
set h3_3_data {
SINK1 LATENCY=0.480 SLEW=0.082
SINK2 LATENCY=0.525 SLEW=0.094
SINK3 LATENCY=0.465 SLEW=0.076
SINK4 LATENCY=0.590 SLEW=0.128
}

# Run Hurdle 3.3 with 0.100 ns max slew limit
check_cts_quality $h3_3_data 0.100