#!/usr/bin/tclsh

proc audit_macro_inventory {data_text} {
    puts "--- H1.2 Macro Inventory ---"
    
    set total_count 0
    set total_area 0
    array set type_counts {}
    array set type_areas {}
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq ""} {continue}
        
        lassign $line inst type area
        
        incr total_count
        set total_area [expr {$total_area + $area}]
        
        if {[info exists type_counts($type)]} {
            incr type_counts($type)
            set type_areas($type) [expr {$type_areas($type) + $area}]
        } else {
            set type_counts($type) 1
            set type_areas($type) $area
        }
    }
    
    set largest_category ""
    set max_area 0
    foreach type [array names type_areas] {
        if {$type_areas($type) > $max_area} {
            set max_area $type_areas($type)
            set largest_category $type
        }
    }
    
    set unique_types [array size type_counts]
    puts "Total Unique Macro Types : $unique_types ([join [array names type_counts] {, }])"
    puts "Total Macro Count        : $total_count"
    puts "Total Cumulative Area    : $total_area"
    puts "Largest Macro Category   : $largest_category (Total Area: $max_area)"
    puts ""
}

# Dataset 2
set h1_2_data {
SRAM0 SRAM 12000
SRAM1 SRAM 12000
PLL0 PLL 4500
DSP0 DSP 8200
ROM0 ROM 6700
}

# Run the routine
audit_macro_inventory $h1_2_data