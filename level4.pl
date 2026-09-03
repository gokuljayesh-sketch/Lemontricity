#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use List::Util qw(max min);
use POSIX qw(ceil);

my $input_dir  = $ARGV[0] || "inputs/";
my $output_dir = $ARGV[1] || "submit_here/";

$input_dir  =~ s{/*$}{/};
$output_dir =~ s{/*$}{/};

make_path($output_dir);

my $sdc_file       = "${input_dir}constraints/hack_top.sdc";
my $cts_file       = "${input_dir}reports/pre_fix/cts.rpt";
my $rpt_file       = "${output_dir}level4_fix_plan.rpt";
my $fix_plan_file  = "${output_dir}fix_plan.txt";

if (! -e $cts_file && -e "${input_dir}cts.rpt") { $cts_file = "${input_dir}cts.rpt"; }
if (! -e $sdc_file && -e "${input_dir}hack_top.sdc") { $sdc_file = "${input_dir}hack_top.sdc"; }

my %target_skew_ps    = ();
my %target_latency_ps = ();
my $max_tran_ps       = 150.0;
my $max_depth         = 8;
my $buffer_delay_ps   = 30.0;

if (-e $sdc_file) {
    open(my $sfh, '<', $sdc_file) or die "Cannot open $sdc_file: $!";
    while (my $line = <$sfh>) {
        chomp($line);
        if ($line =~ /set_clock_uncertainty\s+([\d\.]+)\s+\[get_clocks\s+([^\n\]]+)\]/) {
            my ($val, $clk) = ($1, $2);
            $target_skew_ps{$clk} = ($val < 5) ? int($val * 1000) : int($val);
        }
        elsif ($line =~ /set_clock_latency\s+([\d\.]+)\s+\[get_clocks\s+([^\n\]]+)\]/) {
            my ($val, $clk) = ($1, $2);
            $target_latency_ps{$clk} = ($val < 5) ? int($val * 1000) : int($val);
        }
    }
    close($sfh);
}

my %clocksdata = ();

if (-e $cts_file) {
    open(my $cfh, '<', $cts_file) or die "Cannot open $cts_file: $!";
    while (my $line = <$cfh>) {
        chomp($line);
        next if ($line =~ /^\s*#/ || $line =~ /^\s*$/);

        my $type = ($line =~ /^(SINK|OBJECT|BUFFER)/i) ? uc($1) : "SINK";
        my $obj  = ($line =~ /(?:SINK|OBJECT|BUFFER)\s+(\S+)/i) ? $1 : "UNKNOWN";
        my $clk  = ($line =~ /CLOCK\s+(\S+)/i) ? $1 : "sys_clk";
        my $lat  = ($line =~ /LATENCY_PS\s+([\d\.\-]+)/i) ? $1 : undef;
        my $dep  = ($line =~ /DEPTH\s+(\d+)/i) ? $1 : 0;
        my $trn  = ($line =~ /TRAN_PS\s+([\d\.]+)/i) ? $1 : undef;
        my $fan  = ($line =~ /FANOUT\s+(\d+)/i) ? $1 : 0;

        if (defined $lat && defined $trn) {
            push @{$clocksdata{$clk}}, {
                type => $type,
                obj  => $obj,
                lat  => $lat + 0,
                trn  => $trn + 0,
                dep  => $dep + 0,
                fan  => $fan + 0
            };
        }
    }
    close($cfh);
}

my @fix_actions = ();
my %predicted_sinks_lat = ();
my $buffers_inserted = 0;
my $buffers_removed  = 0;
my $expected_violations_after = 0;

foreach my $clk (sort keys %clocksdata) {
    my $t_skew = $target_skew_ps{$clk} // 250;
    my $t_lat  = $target_latency_ps{$clk} // 1000;
    my $sinks  = $clocksdata{$clk};

    my $total_fanout = 0;
    my $buf_count = 0;
    foreach my $s (@$sinks) {
        if ($s->{type} eq "BUFFER") {
            $total_fanout += $s->{fan};
            $buf_count++;
        }
    }
    my $avg_fanout = ($buf_count > 0) ? ceil($total_fanout / $buf_count) : 20;

    foreach my $s (@$sinks) {
        my $before_lat = int($s->{lat});
        my $dev        = $s->{lat} - $t_lat;
        my $abs_dev    = abs($dev);
        my $predicted_lat = $s->{lat};

        if ($abs_dev > 100) {
            my $delta = $t_lat - $s->{lat};
            my $stages = ceil(abs($delta) / $buffer_delay_ps);
            $stages = 1 if $stages < 1;

            my $action = "";
            if ($delta > 0) {
                $action = "INSERT_BUFFER";
                $buffers_inserted += $stages;
                $predicted_lat = $s->{lat} + ($stages * $buffer_delay_ps);
            } else {
                $action = "REMOVE_BUFFER";
                $buffers_removed += $stages;
                $predicted_lat = $s->{lat} - ($stages * $buffer_delay_ps);
            }

            push @fix_actions, {
                sink      => $s->{obj},
                clock     => $clk,
                action    => $action,
                stages    => $stages,
                before_ps => $before_lat,
                target_ps => int($t_lat),
                reason    => "Latency Outlier Fix ($action $stages stages)"
            };
        }

        if ($s->{trn} > $max_tran_ps) {
            push @fix_actions, {
                sink      => $s->{obj},
                clock     => $clk,
                action    => "UPSIZE_DRIVER",
                stages    => 1,
                before_ps => int($s->{trn}),
                target_ps => int($max_tran_ps),
                reason    => "Transition Violation Fix"
            };
        }

        if ($s->{dep} > $max_depth) {
            push @fix_actions, {
                sink      => $s->{obj},
                clock     => $clk,
                action    => "RESTRUCTURE_BRANCH",
                stages    => ($s->{dep} - $max_depth),
                before_ps => $s->{dep},
                target_ps => $max_depth,
                reason    => "Depth Violation Fix"
            };
        }

        if ($s->{type} eq "BUFFER" && $s->{fan} > ($avg_fanout * 1.5)) {
            push @fix_actions, {
                sink      => $s->{obj},
                clock     => $clk,
                action    => "SPLIT_BUFFER",
                stages    => 2,
                before_ps => $s->{fan},
                target_ps => $avg_fanout,
                reason    => "Fanout Hotspot Fix"
            };
        }

        push @{$predicted_sinks_lat{$clk}}, $predicted_lat;
    }
}

my @sorted_actions = sort {
    $a->{clock} cmp $b->{clock} ||
    $a->{sink} cmp $b->{sink}
} @fix_actions;

open(my $fh_plan, '>', $fix_plan_file) or die "Cannot write to $fix_plan_file: $!";
foreach my $act (@sorted_actions) {
    print $fh_plan "$act->{clock} $act->{sink} $act->{action} STAGES=$act->{stages} BEFORE_PS=$act->{before_ps} TARGET_PS=$act->{target_ps}\n";
}
close($fh_plan);

open(my $out, '>', $rpt_file) or die "Cannot write to $rpt_file: $!";

foreach my $act (@sorted_actions) {
    printf $out "FIX SINK=%s CLOCK=%s ACTION=%s STAGES=%d BEFORE_PS=%d TARGET_PS=%d REASON=%s\n",
        $act->{sink}, $act->{clock}, $act->{action}, $act->{stages}, $act->{before_ps}, $act->{target_ps}, $act->{reason};
}
print $out "\n";

foreach my $clk (sort keys %clocksdata) {
    my $t_skew = $target_skew_ps{$clk} // 250;
    
    my @orig_lats = map { $_->{lat} } @{$clocksdata{$clk}};
    my $skew_before = int(max(@orig_lats) - min(@orig_lats));

    my @pred_lats = @{$predicted_sinks_lat{$clk}};
    my $pred_skew = int(max(@pred_lats) - min(@pred_lats));

    my $status = ($pred_skew <= $t_skew) ? "PASS" : "FAIL";
    if ($status eq "FAIL") { $expected_violations_after++; }

    printf $out "CLOCK=%s SKEW_BEFORE_PS=%d PREDICTED_SKEW_PS=%d TARGET_SKEW_PS=%d EXPECTED_STATUS=%s\n",
        $clk, $skew_before, $pred_skew, $t_skew, $status;
}
print $out "\n";

print $out "TOTAL_ACTIONS=" . scalar(@sorted_actions) . "\n";
print $out "BUFFERS_INSERTED=$buffers_inserted\n";
print $out "BUFFERS_REMOVED=$buffers_removed\n";
print $out "EXPECTED_VIOLATIONS_AFTER=$expected_violations_after\n";

close($out);
