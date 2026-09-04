#!/usr/bin/tclsh

# ==============================================================================
# H2.3 – ROUTING LENGTH STATISTICS BY LAYER
# ==============================================================================
proc calculate_layer_wirelength_stats {data_text} {
    puts "--- H2.3 Routing Length Statistics Report ---"
    puts ""
    
    set total_nets 0
    set total_wirelength 0
    set max_wirelength 0
    set max_net ""
    set max_layer ""
    
    array set layer_totals {}
    array set layer_counts {}
    array set layer_nets {}
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        
        # Format: net_id layer length
        lassign $line net layer length
        
        incr total_nets
        set total_wirelength [expr {$total_wirelength + $length}]
        
        # Track longest net overall
        if {$length > $max_wirelength} {
            set max_wirelength $length
            set max_net $net
            set max_layer $layer
        }
        
        # Accumulate metrics per layer
        if {[info exists layer_totals($layer)]} {
            set layer_totals($layer) [expr {$layer_totals($layer) + $length}]
            incr layer_counts($layer)
            lappend layer_nets($layer) "$net ($length)"
        } else {
            set layer_totals($layer) $length
            set layer_counts($layer) 1
            set layer_nets($layer) [list "$net ($length)"]
        }
    }
    
    puts [format "%-8s | %-10s | %-25s | %-30s" "Layer" "Net Count" "Total Wire Length (units)" "Contributed Nets"]
    puts "-----------------------------------------------------------------------------------"
    
    foreach layer [lsort [array names layer_totals]] {
        set nets_str [join $layer_nets($layer) ", "]
        puts [format "%-8s | %-10d | %-25d | %-30s" \
                $layer $layer_counts($layer) $layer_totals($layer) $nets_str]
    }
    
    set avg_wirelength [expr {$total_nets > 0 ? double($total_wirelength) / $total_nets : 0.0}]
    
    puts "-----------------------------------------------------------------------------------"
    puts [format "Total Wire Length   : %d units" $total_wirelength]
    puts [format "Average Wire Length : %.2f units" $avg_wirelength]
    puts [format "Longest Net         : %s on layer %s with wire length of %d units" \
            $max_net $max_layer $max_wirelength]
    puts ""
}

# Level 2 Dataset 3
set h2_3_data {
N1 M2 125
N2 M3 420
N3 M4 870
N4 M2 95
N5 M5 1200
N6 M3 315
}

# Run Hurdle 2.3
calculate_layer_wirelength_stats $h2_3_data