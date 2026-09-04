#!/usr/bin/tclsh

# ==============================================================================
# H5.2 – PD OPTIMIZATION ADVISOR (FILE-BASED INTEGRATION)
# ==============================================================================

# Procedure to parse threshold limits configuration file
proc load_limits_config {cfg_filepath} {
    array set limits {}
    if {![file exists $cfg_filepath]} {
        puts "Error: Configuration file '$cfg_filepath' not found."
        return [array get limits]
    }
    
    set fp [open $cfg_filepath r]
    while {[gets $fp line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        
        # Parse format: KEY VALUE (e.g. MAX_UTIL 80)
        lassign $line key val
        set limits($key) $val
    }
    close $fp
    return [array get limits]
}

# Core analysis procedure comparing metrics against limits.cfg
proc run_pd_optimization_advisor {cfg_file metrics_file} {
    puts "--- H5.2 PD Optimization Advisor Report ---"
    puts [format "Configuration File: %s" $cfg_file]
    puts [format "Metrics File      : %s" $metrics_file]
    puts ""
    
    # 1. Load limits from cfg file
    array set limits [load_limits_config $cfg_file]
    if {[array size limits] == 0} {
        puts "Error: Unable to load threshold limits."
        return
    }
    
    # 2. Parse measured design metrics file
    if {![file exists $metrics_file]} {
        puts "Error: Design metrics file '$metrics_file' not found."
        return
    }
    
    set recommendations {}
    set fp [open $metrics_file r]
    
    while {[gets $fp line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        
        # Parse format: PARAMETER MEASURED_VALUE
        lassign $line param val
        
        # Compare measured metrics against limits.cfg thresholds
        switch -exact -- $param {
            "WNS" {
                set target 0.00
                if {$val < $target} {
                    set diff [expr {$val - $target}]
                    # Priority 1: Critical Timing Slack
                    lappend recommendations [list 1 "CRITICAL" "Timing" "MIN_WNS_NS" \
                        [format "%.3f ns" $val] [format "%.3f ns" $target] [format "%.3f ns" $diff] \
                        "Buffer Insertion & Gate Sizing on Critical Paths"]
                }
            }
            "IR_DROP_PCT" {
                set limit [expr {[info exists limits(MAX_IR_DROP_PCT)] ? $limits(MAX_IR_DROP_PCT) : 8.0}]
                if {$val > $limit} {
                    set diff [expr {$val - $limit}]
                    # Priority 2: Power / IR Drop
                    lappend recommendations [list 2 "HIGH" "Power / IR" "MAX_IR_DROP_PCT" \
                        [format "%.2f%%" $val] [format "%.2f%%" $limit] [format "+%.2f%%" $diff] \
                        "Reinforce Power Grid Mesh & Add Decap Cells"]
                }
            }
            "CLOCK_SKEW" {
                set limit [expr {[info exists limits(MAX_SKEW_NS)] ? $limits(MAX_SKEW_NS) : 0.10}]
                if {$val > $limit} {
                    set diff [expr {$val - $limit}]
                    # Priority 3: CTS Skew
                    lappend recommendations [list 3 "HIGH" "CTS Skew" "MAX_SKEW_NS" \
                        [format "%.3f ns" $val] [format "%.3f ns" $limit] [format "+%.3f ns" $diff] \
                        "Re-balance Clock Tree Buffers & Apply Shielding"]
                }
            }
            "UTILIZATION" {
                set limit [expr {[info exists limits(MAX_UTIL)] ? $limits(MAX_UTIL) : 80.0}]
                if {$val > $limit} {
                    set diff [expr {$val - $limit}]
                    # Priority 4: Placement Density
                    lappend recommendations [list 4 "MEDIUM" "Placement" "MAX_UTIL" \
                        [format "%.2f%%" $val] [format "%.2f%%" $limit] [format "+%.2f%%" $diff] \
                        "Spread Standard Cells to Low-Density Regions"]
                }
            }
            "CONGESTION" {
                set limit [expr {[info exists limits(MAX_CONGESTION)] ? $limits(MAX_CONGESTION) : 85.0}]
                if {$val > $limit} {
                    set diff [expr {$val - $limit}]
                    # Priority 5: Routing Congestion
                    lappend recommendations [list 5 "MEDIUM" "Routing" "MAX_CONGESTION" \
                        [format "%.2f%%" $val] [format "%.2f%%" $limit] [format "+%.2f%%" $diff] \
                        "Apply Local Placement Blockages & Cell Spreading"]
                } else {
                    set diff [expr {$val - $limit}]
                    lappend recommendations [list 6 "PASS" "Congestion" "MAX_CONGESTION" \
                        [format "%.2f%%" $val] [format "%.2f%%" $limit] [format "%.2f%%" $diff] \
                        "Within Spec - Monitor Routing Track Usage"]
                }
            }
        }
    }
    close $fp
    
    # 3. Sort recommendations by severity rank
    set sorted_recs [lsort -integer -index 0 $recommendations]
    
    puts [format "%-6s | %-10s | %-12s | %-18s | %-15s | %-12s | %-14s | %-42s" \
            "Rank" "Severity" "Category" "Config Key" "Measured" "Spec Limit" "Excess" "Recommended Optimization Action"]
    puts "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
    
    foreach item $sorted_recs {
        lassign $item rank sev cat key meas lim diff act
        puts [format "%-6d | %-10s | %-12s | %-18s | %-15s | %-12s | %-14s | %-42s" \
                $rank $sev $cat $key $meas $lim $diff $act]
    }
    
    puts "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
    puts ""
}

# Helper procedure to generate test environment files matching screenshot
proc setup_h5_2_environment {} {
    # Generate limits.cfg matching screenshot exactly
    set fp [open "limits.cfg" w]
    puts $fp "MAX_UTIL 80"
    puts $fp "MAX_CONGESTION 85"
    puts $fp "MAX_IR_DROP_PCT 8"
    puts $fp "MAX_SKEW_NS 0.10"
    close $fp

    # Generate design metrics report
    set fp [open "design_metrics.rpt" w]
    puts $fp "WNS -0.120"
    puts $fp "IR_DROP_PCT 9.80"
    puts $fp "CLOCK_SKEW 0.145"
    puts $fp "UTILIZATION 84.50"
    puts $fp "CONGESTION 82.00"
    close $fp
}

# Execute
setup_h5_2_environment
run_pd_optimization_advisor "limits.cfg" "design_metrics.rpt"