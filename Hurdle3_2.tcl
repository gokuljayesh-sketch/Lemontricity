#!/usr/bin/tclsh

# ==============================================================================
# H3.2 – IR-DROP ANALYZER
# ==============================================================================
proc analyze_ir_drop {data_text {max_drop_pct_limit 5.0}} {
    puts "--- H3.2 IR-Drop Analyzer Report ---"
    puts [format "Configured Max IR-Drop Limit: %.2f%% VDD" $max_drop_pct_limit]
    puts ""
    
    set total_regions 0
    set violations 0
    set worst_region ""
    set worst_drop_v 0.0
    set worst_drop_pct 0.0
    
    puts [format "%-10s | %-13s | %-12s | %-17s | %-19s | %-10s | %-10s" \
            "Region ID" "Nominal VDD" "Actual VDD" "Absolute Drop (V)" "Percentage Drop (%)" "Limit (%)" "Status"]
    puts "---------------------------------------------------------------------------------------------------"
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        
        # Format: region v_nominal v_actual
        lassign $line region v_nom v_act
        
        incr total_regions
        
        set abs_drop [expr {$v_nom - $v_act}]
        set pct_drop [expr {($abs_drop / $v_nom) * 100.0}]
        
        set status "PASS"
        if {$pct_drop > $max_drop_pct_limit} {
            set status "VIOLATION"
            incr violations
        }
        
        if {$abs_drop > $worst_drop_v} {
            set worst_drop_v $abs_drop
            set worst_drop_pct $pct_drop
            set worst_region $region
        }
        
        puts [format "%-10s | %-13.3f | %-12.3f | %-17.3f | %-18.2f%% | %-9.1f%% | %-10s" \
                $region $v_nom $v_act $abs_drop $pct_drop $max_drop_pct_limit $status]
    }
    
    puts "---------------------------------------------------------------------------------------------------"
    puts [format "Total Regions Scanned     : %d" $total_regions]
    puts [format "IR-Drop Violations (>%.1f%%) : %d" $max_drop_pct_limit $violations]
    puts [format "Worst IR-Drop Region      : %s (%.3f V / %.2f%% VDD)" $worst_region $worst_drop_v $worst_drop_pct]
    puts ""
}

# Level 3 Dataset 2
set h3_2_data {
R1 0.900 0.872
R2 0.900 0.841
R3 0.900 0.883
R4 0.900 0.812
R5 0.900 0.865
}

# Run Hurdle 3.2 with 5.0% threshold
analyze_ir_drop $h3_2_data 5.0