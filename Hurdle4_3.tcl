#!/usr/bin/tclsh

# ==============================================================================
# H4.3 – PRE/POST ROUTE COMPARATOR
# ==============================================================================
proc compare_pre_post_route {data_text} {
    puts "--- H4.3 Pre/Post Route Comparator Report ---"
    puts ""
    
    puts [format "%-12s | %-12s | %-12s | %-14s | %-20s | %-12s | %-10s" \
            "Metric" "Pre-Route" "Post-Route" "Delta (Diff)" "% Degradation" "Impact" "Severity"]
    puts "-------------------------------------------------------------------------------------------------------------------"
    
    set lines [split $data_text "\n"]
    foreach line $lines {
        set line [string trim $line]
        if {$line eq "" || [string match "#" $line] || [string match "METRIC" $line]} {continue}
        
        # Format: METRIC PRE_ROUTE POST_ROUTE
        lassign $line metric pre post
        
        set pre_val [expr {double($pre)}]
        set post_val [expr {double($post)}]
        set delta [expr {$post_val - $pre_val}]
        
        # Determine directional degradation:
        # - Slack metrics (WNS, TNS): Higher/More positive is better (Negative delta = Degradation)
        # - Physical metrics (WIRELENGTH, DRC, POWER): Lower is better (Positive delta = Degradation)
        set is_slack_metric [expr {$metric eq "WNS" || $metric eq "TNS"}]
        
        set pct_str "N/A"
        if {$pre_val != 0.0} {
            if {$is_slack_metric} {
                # Percentage increase in negative slack/violation
                set pct [expr {(abs($delta) / abs($pre_val)) * 100.0}]
            } else {
                set pct [expr {($delta / abs($pre_val)) * 100.0}]
            }
            set pct_str [format "%+.2f%%" $pct]
        } elseif {$metric eq "DRC" && $post_val > 0} {
            set pct_str [format "N/A (+%d New)" [expr {int($post_val)}]]
        }
        
        # Impact Classification
        set impact "NO CHANGE"
        set severity "LOW"
        
        if {$is_slack_metric} {
            if {$delta < 0} {
                set impact "DEGRADED"
                set severity [expr {$metric eq "TNS" ? "CRITICAL" : "HIGH"}]
            } elseif {$delta > 0} {
                set impact "IMPROVED"
                set severity "NONE"
            }
        } else {
            if {$delta > 0} {
                set impact "DEGRADED"
                if {$metric eq "DRC"} {
                    set severity "CRITICAL"
                } elseif {$metric eq "WIRELENGTH"} {
                    set severity "MODERATE"
                } else {
                    set severity "MINOR"
                }
            } elseif {$delta < 0} {
                set impact "IMPROVED"
                set severity "NONE"
            }
        }
        
        puts [format "%-12s | %-12.2f | %-12.2f | %-+14.2f | %-20s | %-12s | %-10s" \
                $metric $pre_val $post_val $delta $pct_str $impact $severity]
    }
    
    puts "-------------------------------------------------------------------------------------------------------------------"
    puts ""
}

# Level 4 Dataset 3
set h4_3_data {
METRIC PRE_ROUTE POST_ROUTE
WNS -0.04 -0.18
TNS -1.2 -12.5
WIRELENGTH 2800000 3210000
DRC 0 148
POWER 126.4 131.8
}

# Run Hurdle 4.3
compare_pre_post_route $h4_3_data