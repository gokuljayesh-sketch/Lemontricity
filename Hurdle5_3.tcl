#!/usr/bin/tclsh

# ==============================================================================
# H5.3 – PHYSICAL SIGN-OFF ASSISTANT (FILE DISCOVERY & ERROR RECOVERY)
# ==============================================================================

# Parse configuration file for limits
proc load_signoff_limits {cfg_path} {
    array set limits {
        MAX_DRC 0
        MAX_IR_DROP_PCT 8.0
        MAX_EM_RATIO 1.00
        MIN_SETUP_WNS 0.00
        MIN_HOLD_WNS 0.00
    }
    
    if {![file exists $cfg_path]} {
        puts "Warning: Limits file '$cfg_path' not found. Using defaults."
        return [array get limits]
    }
    
    set fp [open $cfg_path r]
    while {[gets $fp line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        lassign $line key val
        if {$key ne "" && $val ne ""} {
            set limits($key) $val
        }
    }
    close $fp
    return [array get limits]
}

# Core Sign-Off Assistant Engine
proc run_signoff_assistant {signoff_dir} {
    puts "--- H5.3 Physical Sign-Off Assistant Report ---"
    puts [format "Scanning Directory: %s/" $signoff_dir]
    puts ""
    
    # 1. Load limits configuration
    set cfg_file [file join $signoff_dir "limits.cfg"]
    array set limits [load_signoff_limits $cfg_file]
    
    # Expected report files
    set rpt_files [list \
        "drc.rpt"    "DRC" \
        "ir.rpt"     "IR" \
        "em.rpt"     "EM" \
        "timing.rpt" "TIMING" \
    ]
    
    puts "DATA INTEGRITY & MALFORMED DATA AUDIT:"
    puts [format "%-22s | %-12s | %-20s | %-10s | %-12s | %-16s | %-25s" \
            "Report File" "Status" "Format Audit" "Total Lines" "Valid Records" "Malformed Records" "Audit Action"]
    puts "----------------------------------------------------------------------------------------------------------------------------------------"
    
    # Data tracking
    set max_drc 0
    set max_ir 0.0
    set max_em 0.0
    set setup_wns 999.0
    set hold_wns 999.0
    
    set total_malformed 0
    
    foreach {rel_path domain} $rpt_files {
        set full_path [file join $signoff_dir $rel_path]
        
        if {![file exists $full_path]} {
            puts [format "%-22s | %-12s | %-20s | %-10s | %-12s | %-16s | %-25s" \
                    $rel_path "MISSING" "CRITICAL ERROR" "0" "0" "0" "File Missing"]
            continue
        }
        
        set fp [open $full_path r]
        set line_count 0
        set valid_cnt 0
        set malformed_cnt 0
        
        while {[gets $fp line] >= 0} {
            incr line_count
            set line [string trim $line]
            if {$line eq "" || [string match "#*" $line]} {continue}
            
            # Robust parsing & malformed data detection
            set tokens [split $line]
            # Remove empty tokens from multiple spaces
            set clean_tokens {}
            foreach t $tokens { if {$t ne ""} { lappend clean_tokens $t } }
            
            if {[llength $clean_tokens] < 2} {
                incr malformed_cnt
                incr total_malformed
                continue
            }
            
            lassign $clean_tokens key val
            # Strip non-numeric artifacts for value parsing
            set clean_val [string trimright $val "%xns"]
            
            # Validate numerical integrity
            if {![string is double -strict $clean_val]} {
                incr malformed_cnt
                incr total_malformed
                continue
            }
            
            incr valid_cnt
            
            # Populate domain metrics
            switch -exact -- $domain {
                "DRC" {
                    if {$clean_val > $max_drc} { set max_drc [expr {int($clean_val)}] }
                }
                "IR" {
                    if {$clean_val > $max_ir} { set max_ir $clean_val }
                }
                "EM" {
                    if {$clean_val > $max_em} { set max_em $clean_val }
                }
                "TIMING" {
                    if {$key eq "SETUP_WNS" || $key eq "WNS"} {
                        set setup_wns $clean_val
                    } elseif {$key eq "HOLD_WNS"} {
                        set hold_wns $clean_val
                    }
                }
            }
        }
        close $fp
        
        set fmt_audit "CLEAN"
        set action "Parsed Successfully"
        if {$malformed_cnt > 0} {
            set fmt_audit "MALFORMED DETECTED"
            set action [format "Skipped %d Bad Line(s)" $malformed_cnt]
        }
        
        puts [format "%-22s | %-12s | %-20s | %-10d | %-12d | %-16d | %-25s" \
                [file join $signoff_dir $rel_path] "FOUND" $fmt_audit $line_count $valid_cnt $malformed_cnt $action]
    }
    
    puts "----------------------------------------------------------------------------------------------------------------------------------------"
    puts ""
    
    # 2. Evaluate Sign-Off Criteria
    puts "PHYSICAL SIGN-OFF VERIFICATION MATRIX:"
    puts [format "%-24s | %-24s | %-22s | %-16s | %-12s" \
            "Verification Domain" "Configured Spec Limit" "Measured Peak / Worst" "Violation Count" "Domain Status"]
    puts "------------------------------------------------------------------------------------------------------------------------"
    
    set overall_pass 1
    
    # DRC Check
    set drc_limit $limits(MAX_DRC)
    set drc_status [expr {$max_drc <= $drc_limit ? "PASS" : "FAIL"}]
    if {$drc_status eq "FAIL"} { set overall_pass 0 }
    puts [format "%-24s | %-24s | %-22s | %-16d | %-12s" \
            "DRC Violations" [format "MAX_DRC = %d" $drc_limit] [format "%d Violations" $max_drc] [expr {$max_drc > $drc_limit ? $max_drc : 0}] $drc_status]
            
    # IR Check
    set ir_limit $limits(MAX_IR_DROP_PCT)
    set ir_status [expr {$max_ir <= $ir_limit ? "PASS" : "FAIL"}]
    if {$ir_status eq "FAIL"} { set overall_pass 0 }
    puts [format "%-24s | %-24s | %-22s | %-16d | %-12s" \
            "IR-Drop (%% VDD)" [format "MAX_IR_DROP_PCT = %.1f%%" $ir_limit] [format "%.2f%%" $max_ir] [expr {$max_ir > $ir_limit ? 1 : 0}] $ir_status]
            
    # EM Check
    set em_limit $limits(MAX_EM_RATIO)
    set em_status [expr {$max_em <= $em_limit ? "PASS" : "FAIL"}]
    if {$em_status eq "FAIL"} { set overall_pass 0 }
    puts [format "%-24s | %-24s | %-22s | %-16d | %-12s" \
            "EM Current Ratio" [format "MAX_EM_RATIO = %.2fx" $em_limit] [format "%.2fx" $max_em] [expr {$max_em > $em_limit ? 1 : 0}] $em_status]
            
    # Setup Timing Check
    set setup_limit $limits(MIN_SETUP_WNS)
    set setup_status [expr {$setup_wns >= $setup_limit ? "PASS" : "FAIL"}]
    if {$setup_status eq "FAIL"} { set overall_pass 0 }
    puts [format "%-24s | %-24s | %-22s | %-16d | %-12s" \
            "Setup Timing (WNS)" [format "MIN_SETUP_WNS = %.2f ns" $setup_limit] [format "%+.3f ns" $setup_wns] [expr {$setup_wns < $setup_limit ? 1 : 0}] $setup_status]
            
    # Hold Timing Check
    set hold_limit $limits(MIN_HOLD_WNS)
    set hold_status [expr {$hold_wns >= $hold_limit ? "PASS" : "FAIL"}]
    if {$hold_status eq "FAIL"} { set overall_pass 0 }
    puts [format "%-24s | %-24s | %-22s | %-16d | %-12s" \
            "Hold Timing (WNS)" [format "MIN_HOLD_WNS = %.2f ns" $hold_limit] [format "%+.3f ns" $hold_wns] [expr {$hold_wns < $hold_limit ? 1 : 0}] $hold_status]
            
    puts "------------------------------------------------------------------------------------------------------------------------"
    
    set final_status [expr {$overall_pass ? "CLEAN SIGN-OFF (PASSED)" : "TAPE-OUT REJECTED (VIOLATIONS DETECTED)"}]
    puts [format "OVERALL TAPE-OUT STATUS : %s" $final_status]
    if {$total_malformed > 0} {
        puts [format "DATA INTEGRITY WARNING : %d malformed line(s) filtered out during execution." $total_malformed]
    }
    puts ""
}

# Helper to construct sample signoff directory & reports matching prompt files
proc setup_h5_3_environment {} {
    file mkdir "signoff"
    
    # limits.cfg
    set fp [open "signoff/limits.cfg" w]
    puts $fp "MAX_DRC 0\nMAX_IR_DROP_PCT 8.0\nMAX_EM_RATIO 1.00\nMIN_SETUP_WNS 0.00\nMIN_HOLD_WNS 0.00"
    close $fp
    
    # drc.rpt
    set fp [open "signoff/drc.rpt" w]
    puts $fp "# Physical Sign-off DRC Report\nTOTAL_DRC 0\nGEOMETRY_DRC 0"
    close $fp
    
    # ir.rpt (with intentional malformed line for integrity test)
    set fp [open "signoff/ir.rpt" w]
    puts $fp "# Power Grid IR Drop Report\nREGION_R1 4.2%\nREGION_R2 6.4%\nCORRUPTED_RECORD_INVALID_ENTRY_TEST\nREGION_R3 3.1%"
    close $fp
    
    # em.rpt
    set fp [open "signoff/em.rpt" w]
    puts $fp "# Electromigration Report\nMAX_SIGNAL_EM 0.88\nPOWER_GRID_EM 0.75"
    close $fp
    
    # timing.rpt
    set fp [open "signoff/timing.rpt" w]
    puts $fp "# Timing Sign-off Report\nSETUP_WNS 0.015\nHOLD_WNS 0.008"
    close $fp
}

# Execute
setup_h5_3_environment
run_signoff_assistant "signoff"