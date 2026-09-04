#!/usr/bin/tclsh

proc calculate_utilization {data_text} {
    puts "--- H1.1 Utilization Report ---"
    
    set core_area 0
    set std_cell_area 0
    set macro_area 0
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq ""} {continue}
        
        lassign $line key value
        if {$key eq "CORE_AREA"}      { set core_area $value }
        if {$key eq "STD_CELL_AREA"}  { set std_cell_area $value }
        if {$key eq "MACRO_AREA"}     { set macro_area $value }
    }
    
    if {$core_area == 0} {
        puts "Error: Core area cannot be zero."
        return
    }
    
    set std_cell_util [expr {($std_cell_area / double($core_area)) * 100}]
    set macro_util    [expr {($macro_area / double($core_area)) * 100}]
    set overall_util  [expr {(($std_cell_area + $macro_area) / double($core_area)) * 100}]
    
    puts [format "Standard-Cell Utilization : %.2f%%" $std_cell_util]
    puts [format "Macro Utilization         : %.2f%%" $macro_util]
    puts [format "Overall Used-Area         : %.2f%%" $overall_util]
    puts ""
}

# Dataset 1
set h1_1_data {
CORE_AREA 500000
STD_CELL_AREA 315000
MACRO_AREA 85000
}

# Run the routine
calculate_utilization $h1_1_data