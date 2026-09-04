#!/usr/bin/tclsh

# Hardcoded sample dataset
set raw_data {
    D001 M2_SPACING 124
    D002 M3_WIDTH 32
    D003 VIA_ENCLOSURE 47
    D004 M4_SPACING 18
    D005 ANTENNA 9
}

set total_violations 0
set drc_records {}

# Process each line from the string variable
foreach line [split $raw_data "\n"] {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} { continue }

    set tokens [regexp -inline -all -- {\S+} $line]
    if {[llength $tokens] < 3} { continue }

    set err_id   [lindex $tokens 0]
    set category [lindex $tokens 1]
    set count    [expr {wide([lindex $tokens 2])}]

    incr total_violations $count
    lappend drc_records [list $category $count $err_id]
}

# Sorting procedure: Descending by violation count
proc sort_by_count {a b} {
    set count_a [lindex $a 1]
    set count_b [lindex $b 1]
    return [expr {$count_b - $count_a}]
}

set ranked_drc [lsort -command sort_by_count $drc_records]

# Identify dominant category
set top_record [lindex $ranked_drc 0]
set dominant_category [lindex $top_record 0]
set dominant_count    [lindex $top_record 1]
set dominant_pct      [expr {($dominant_count / double($total_violations)) * 100.0}]

# Print Sign-Off Summary Report
puts "=========================================================="
puts "                DRC VIOLATION SIGN-OFF ANALYSIS           "
puts "=========================================================="
puts [format "%-6s | %-18s | %-10s | %-10s" "RANK" "DRC CATEGORY" "COUNT" "PERCENTAGE"]
puts "----------------------------------------------------------"

set rank 1
foreach item $ranked_drc {
    set cat [lindex $item 0]
    set cnt [lindex $item 1]
    set pct [expr {($cnt / double($total_violations)) * 100.0}]
    
    puts [format "#%-5d | %-18s | %-10d | %-9.2f%%" $rank $cat $cnt $pct]
    incr rank
}

puts "=========================================================="
puts [format "Total DRC Violations    : %d" $total_violations]
puts [format "Dominant Violation Class: %s (%d violations, %.2f%%)" \
        $dominant_category $dominant_count $dominant_pct]
puts "=========================================================="