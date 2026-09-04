#!/usr/bin/tclsh

# ==============================================================================
# H4.2 – DRIVER SIZING & FANOUT HOTSPOT REMEDIATION
# ==============================================================================
proc remediate_driver_and_fanout {data_text {max_tran_limit 150.0} {avg_fanout_limit 20}} {
    puts "--- H4.2 Driver Sizing & Fanout Hotspot Report ---"
    puts [format "Max Transition Limit: %.1f ps | Fanout Hotspot Threshold: > %d" $max_tran_limit [expr {int($avg_fanout_limit * 1.5)}]]
    
    set total_objects 0
    set upsize_count 0
    set split_count 0
    set fanout_threshold [expr {$avg_fanout_limit * 1.5}]
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {continue}
        
        # Format: type object_name clock transition_ps fanout
        lassign $line type obj clk tran fan
        
        incr total_objects
        
        # Check transition violation
        if {$tran > $max_tran_limit} {
            incr upsize_count
            puts [format "⚡ UPSIZE DRIVER  | Sink: %-10s | Clock: %-10s | Tran: %5.1f ps (Limit: %.1f ps)" $obj $clk $tran $max_tran_limit]
        }
        
        # Check fanout hotspot violation
        if {$type eq "BUFFER" && $fan > $fanout_threshold} {
            incr split_count
            puts [format "🔀 SPLIT BUFFER   | Buffer: %-8s | Clock: %-10s | Fanout: %2d (Threshold: %.0f)" $obj $clk $fan $fanout_threshold]
        }
    }
    
    puts "----------------------------------------------------------------------------------------"
    puts [format "Total Objects Scanned   : %d" $total_objects]
    puts [format "UPSIZE_DRIVER Actions   : %d" $upsize_count]
    puts [format "SPLIT_BUFFER Actions    : %d" $split_count]
    puts ""
}

# Dataset 2
set h4_2_data {
SINK   U100/CK CLK_CORE 165.4 1
SINK   U101/CK CLK_CORE 142.1 1
BUFFER BUF1    CLK_CORE 110.0 38
SINK   U200/CK CLK_PERI 188.0 1
BUFFER BUF2    CLK_PERI 105.0 12
}

# Run Hurdle 4.2
remediate_driver_and_fanout $h4_2_data 150.0 20