#!/usr/bin/tclsh

proc check_placement_coordinates {core_width core_height data_text} {
    puts "--- H1.3 Placement Coordinate Checker ---"
    puts "Core Boundary limits: 0 to $core_width (X), 0 to $core_height (Y)"
    
    set violations 0
    
    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq ""} {continue}
        
        lassign $line obj x y
        
        set out_of_bounds 0
        set reasons {}
        
        if {$x < 0 || $x > $core_width} {
            set out_of_bounds 1
            lappend reasons "X ($x) out of range"
        }
        if {$y < 0 || $y > $core_height} {
            set out_of_bounds 1
            lappend reasons "Y ($y) out of range"
        }
        
        if {$out_of_bounds} {
            incr violations
            puts "❌ WARNING: Object '$obj' is out-of-bounds at ($x, $y) -> Reason: [join $reasons {, }]"
        }
    }
    
    if {$violations == 0} {
        puts "✅ Success: All coordinates are within physical core limits."
    } else {
        puts "Total out-of-bound objects identified: $violations"
    }
    puts ""
}

# Dataset 3
set h1_3_data {
U1 10 20
U2 120 340
U3 510 210
U4 240 480
U5 -10 75
}

# Run the routine
check_placement_coordinates 500 500 $h1_3_data