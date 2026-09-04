#!/usr/bin/tclsh

# ==============================================================================
# H4.1 – PLACEMENT QOR SCORER
# ==============================================================================
proc score_placement_qor {data_text} {
    puts "--- H4.1 Placement QoR Scorer Report ---"
    puts ""
    
    set runs {}
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        
        # Format: RUN_A UTIL=72 CONG=81 WNS=-0.05 WL=2.8e6
        if {[regexp {(\S+)\s+UTIL=(\S+)\s+CONG=(\S+)\s+WNS=(\S+)\s+WL=(\S+)} $line -> run util cong wns wl]} {
            set util_val [expr {double($util)}]
            set cong_val [expr {double($cong)}]
            set wns_val  [expr {double($wns)}]
            set wl_val   [expr {double($wl)}]
            
            # Composite QoR Scoring Formulation
            set score [expr {100.0 - (0.3 * $cong_val) - (0.2 * $util_val) + (100.0 * $wns_val) - (0.00001 * $wl_val)}]
            
            lappend runs [list $run $util_val $cong_val $wns_val $wl_val $score]
        }
    }
    
    if {[llength $runs] == 0} {
        puts "Error: No valid placement data found."
        return
    }
    
    # Sort candidates by composite score descending
    set sorted_runs [lsort -real -decreasing -index 5 $runs]
    
    puts [format "%-6s | %-10s | %-12s | %-12s | %-10s | %-12s | %-10s | %-20s" \
            "Rank" "Run ID" "Util (%)" "Cong (%)" "WNS (ns)" "Wirelength" "QoR Score" "Status"]
    puts "-------------------------------------------------------------------------------------------------------------------"
    
    set rank 1
    foreach item $sorted_runs {
        lassign $item run util cong wns wl score
        
        set status "ACCEPTABLE"
        if {$rank == 1} {
            set status "OPTIMAL (WINNER)"
        } elseif {$wns < -0.10} {
            set status "REJECTED (TIMING)"
        }
        
        puts [format "%-6d | %-10s | %-12.1f | %-12.1f | %-10.2f | %-12.2e | %-10.2f | %-20s" \
                $rank $run $util $cong $wns $wl $score $status]
        incr rank
    }
    
    set best_run [lindex [lindex $sorted_runs 0] 0]
    set best_score [lindex [lindex $sorted_runs 0] 5]
    
    puts "-------------------------------------------------------------------------------------------------------------------"
    puts [format "Top Candidate Selected : %s (Composite QoR Score: %.2f)" $best_run $best_score]
    puts ""
}

# Level 4 Dataset 1
set h4_1_data {
RUN_A UTIL=72 CONG=81 WNS=-0.05 WL=2.8e6
RUN_B UTIL=76 CONG=88 WNS=0.02 WL=2.9e6
RUN_C UTIL=69 CONG=74 WNS=-0.11 WL=2.6e6
}

# Run Hurdle 4.1
score_placement_qor $h4_1_data