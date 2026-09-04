#!/usr/bin/tclsh

# ==============================================================================
# H2.2 – CONGESTION ANALYZER (HOTSPOTS & DOMINANCE)
# ==============================================================================
proc analyze_congestion_and_dominance {data_text {threshold 85}} {
    puts "--- H2.2 Congestion Analyzer Report ---"
    puts "Hotspot Threshold Limit: > ${threshold}% Utilization"
    puts ""
    
    set total_regions 0
    set hotspot_count 0
    set total_h_util 0.0
    set total_v_util 0.0
    
    puts [format "%-10s | %-20s | %-18s | %-10s | %-18s" \
            "Region ID" "Horizontal Util (%)" "Vertical Util (%)" "Status" "Dominant Direction"]
    puts "-----------------------------------------------------------------------------------"
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        
        # Format: REGION R1 H_UTIL=72 V_UTIL=68
        if {[regexp {REGION\s+(\S+)\s+H_UTIL=(\d+)\s+V_UTIL=(\d+)} $line -> region h_util v_util]} {
            incr total_regions
            set total_h_util [expr {$total_h_util + $h_util}]
            set total_v_util [expr {$total_v_util + $v_util}]
            
            set status "NORMAL"
            if {$h_util > $threshold || $v_util > $threshold} {
                set status "HOTSPOT"
                incr hotspot_count
            }
            
            if {$h_util > $v_util} {
                set dominant "Horizontal"
            } elseif {$v_util > $h_util} {
                set dominant "Vertical"
            } else {
                set dominant "Balanced"
            }
            
            puts [format "%-10s | %-20d | %-18d | %-10s | %-18s" \
                    $region $h_util $v_util $status $dominant]
        }
    }
    
    if {$total_regions == 0} {
        puts "Error: No valid region dataset found."
        return
    }
    
    set avg_h [expr {$total_h_util / double($total_regions)}]
    set avg_v [expr {$total_v_util / double($total_regions)}]
    
    if {$avg_h > $avg_v} {
        set global_dominance "Horizontal Routing"
    } elseif {$avg_v > $avg_h} {
        set global_dominance "Vertical Routing"
    } else {
        set global_dominance "Balanced Routing"
    }
    
    puts "-----------------------------------------------------------------------------------"
    puts [format "Hotspots Detected             : %d" $hotspot_count]
    puts [format "Average Horizontal Utilization : %.2f%%" $avg_h]
    puts [format "Average Vertical Utilization   : %.2f%%" $avg_v]
    puts [format "Global Routing Dominance       : %s" $global_dominance]
    puts ""
}

# Level 2 Dataset 2
set h2_2_data {
REGION R1 H_UTIL=72 V_UTIL=68
REGION R2 H_UTIL=94 V_UTIL=89
REGION R3 H_UTIL=81 V_UTIL=96
REGION R4 H_UTIL=63 V_UTIL=59
}

# Run Hurdle 2.2
analyze_congestion_and_dominance $h2_2_data 85