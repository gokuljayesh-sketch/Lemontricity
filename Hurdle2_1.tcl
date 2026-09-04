proc analyze_fanout {data_text {high_thresh 100} {crit_thresh 500}} {
    puts "--- H2.1 High-Fanout Analysis ---"
    
    set critical_nets {}

    foreach line [split $data_text "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} continue

        lassign $line net fanout

        if {$fanout >= $crit_thresh} {
            set category "CRITICAL"
            lappend critical_nets [list $net $fanout]
        } elseif {$fanout >= $high_thresh} {
            set category "HIGH"
        } else {
            set category "NORMAL"
        }

        puts [format "Net: %-10s | Fanout: %-5d | Status: %s" $net $fanout $category]
    }

    # Rank critical nets in descending order
    puts "\n--- Critical Nets Ranking ---"
    set sorted_critical [lsort -integer -decreasing -index 1 $critical_nets]
    
    set rank 1
    foreach item $sorted_critical {
        lassign $item net fanout
        puts [format "Rank %d: %-10s (Fanout: %d)" $rank $net $fanout]
        incr rank
    }
}

# --- Execution for H2.1 ---
set h21_data {
clk 1248
reset_n 682
scan_en 910
enable 42
interrupt 103
alu_sel 18
}

analyze_fanout $h21_data 100 500