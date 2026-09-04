#!/usr/bin/tclsh

# ==============================================================================
# H5.1 – PHYSICAL DESIGN DASHBOARD
# ==============================================================================
proc generate_pd_dashboard {dir} {
    puts "--- H5.1 Physical Design Dashboard Report ---"
    puts [format "Consolidating stage reports from directory: %s/" $dir]
    puts ""
    
    set stages {
        "floorplan" "pd/floorplan.rpt"
        "place"     "pd/place.rpt"
        "cts"       "pd/cts.rpt"
        "route"     "pd/route.rpt"
    }
    
    puts [format "%-12s | %-22s | %-12s | %-15s | %-8s | %-8s" \
            "Stage" "Metric" "Spec Limit" "Measured Value" "Unit" "Status"]
    puts "---------------------------------------------------------------------------------------------------"
    
    dict for {stg file} $stages {
        if {![file exists $file]} {
            puts [format "%-12s | File %s missing" [string toupper $stg] $file]
            continue
        }
        set fp [open $file r]
        while {[gets $fp line] >= 0} {
            set line [string trim $line]
            if {$line eq "" || [string match "#*" $line]} {continue}
            
            # Format: METRIC_NAME SPEC_LIMIT VALUE UNIT STATUS
            lassign $line metric spec val unit status
            puts [format "%-12s | %-22s | %-12s | %-15s | %-8s | %-8s" \
                    [string toupper $stg] $metric $spec $val $unit $status]
        }
        close $fp
    }
    
    puts "---------------------------------------------------------------------------------------------------"
    puts ""
}

# Helper to generate test directory structure and files if missing
proc setup_h5_1_test_files {} {
    file mkdir "pd"
    if {![file exists "pd/floorplan.rpt"]} {
        set fp [open "pd/floorplan.rpt" w]
        puts $fp "Die_Utilization <=75.0 71.4 % PASS\nCore_Area N/A 1.25 mm^2 MET"
        close $fp
    }
    if {![file exists "pd/place.rpt"]} {
        set fp [open "pd/place.rpt" w]
        puts $fp "Std_Cell_Density <=80.0 78.2 % PASS\nPeak_Congestion <=85.0 81.0 % PASS"
        close $fp
    }
    if {![file exists "pd/cts.rpt"]} {
        set fp [open "pd/cts.rpt" w]
        puts $fp "Max_Latency <=0.800 0.620 ns PASS\nGlobal_Skew <=0.100 0.085 ns PASS"
        close $fp
    }
    if {![file exists "pd/route.rpt"]} {
        set fp [open "pd/route.rpt" w]
        puts $fp "Total_Wirelength N/A 3.15e6 units MET\nPost_Route_DRC 0 0 count PASS"
        close $fp
    }
}

setup_h5_1_test_files
generate_pd_dashboard "pd"