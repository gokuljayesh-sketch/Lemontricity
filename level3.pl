#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use List::Util qw(max min);

# Command-line input/output directories
my $input_dir  = $ARGV[0] || "inputs/";
my $output_dir = $ARGV[1] || "submit_here/";

$input_dir  =~ s{/*$}{/};
$output_dir =~ s{/*$}{/};

make_path($output_dir);

# File locations
my $sdc_file = "${input_dir}constraints/hack_top.sdc";
my $cts_file = "${input_dir}reports/pre_fix/cts.rpt";
my $rpt_file = "${output_dir}level3_priority.rpt";

# Fallback paths
if (! -e $cts_file && -e "${input_dir}cts.rpt") { $cts_file = "${input_dir}cts.rpt"; }
if (! -e $sdc_file && -e "${input_dir}hack_top.sdc") { $sdc_file = "${input_dir}hack_top.sdc"; }

# 1. Parse Constraints
my %target_skew_ps    = ();
my %target_latency_ps = ();
my $max_tran_ps       = 150.0;
my $max_depth         = 8;

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

# 2. Parse CTS Report Data
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

        if (defined $lat && defined $trn) {
            push @{$clocksdata{$clk}}, {
                type => $type,
                obj  => $obj,
                lat  => $lat + 0,
                trn  => $trn + 0,
                dep  => $dep + 0
            };
        }
    }
    close($cfh);
}

# 3. Analyze Clocks and Find Ranked Violations
my @violating_sinks = ();
my %depth_outlier_count = ();
my %depth_latencies = ();
my %clock_non_outliers = ();

my $worst_clock = "";
my $worst_clock_excess = -9999;
my $worst_clock_residual = 0;

foreach my $clk (sort keys %clocksdata) {
    my $t_skew = $target_skew_ps{$clk} // 250;
    my $t_lat  = $target_latency_ps{$clk} // 1000;
    my $sinks  = $clocksdata{$clk};

    my @all_lats = map { $_->{lat} } @$sinks;
    my $clk_max_lat = max(@all_lats);
    my $clk_min_lat = min(@all_lats);
    my $clk_skew = $clk_max_lat - $clk_min_lat;
    
    my $excess = $clk_skew - $t_skew;
    if ($excess > $worst_clock_excess) {
        $worst_clock_excess = $excess;
        $worst_clock = $clk;
    }

    foreach my $s (@$sinks) {
        my $dev = $s->{lat} - $t_lat;
        my $abs_dev = abs($dev);
        
        my $is_outlier = ($abs_dev > 100) ? 1 : 0;
        my $is_tran_viol = ($s->{trn} > $max_tran_ps) ? 1 : 0;
        my $is_depth_viol = ($s->{dep} > $max_depth) ? 1 : 0;

        if (!$is_outlier) {
            push @{$clock_non_outliers{$clk}}, $s->{lat};
        }

        if ($is_outlier || $is_tran_viol || $is_depth_viol) {
            my $impact = $abs_dev;
            my $score = $impact + (40 * $is_tran_viol) + (30 * $is_depth_viol);
            
            my @reasons = ();
            push @reasons, "Latency Outlier" if $is_outlier;
            push @reasons, "Tran Viol" if $is_tran_viol;
            push @reasons, "Depth Viol" if $is_depth_viol;
            my $reason = join(", ", @reasons);

            push @violating_sinks, {
                sink   => $s->{obj},
                clock  => $clk,
                score  => $score,
                impact => $impact,
                dev    => $dev,
                depth  => $s->{dep},
                tran   => int($s->{trn}),
                reason => $reason
            };
        }

        if ($is_outlier) {
            $depth_outlier_count{$s->{dep}}++;
            push @{$depth_latencies{$s->{dep}}}, $s->{lat};
        }
    }
}

if (exists $clock_non_outliers{$worst_clock} && @{$clock_non_outliers{$worst_clock}}) {
    my @non_out_lats = @{$clock_non_outliers{$worst_clock}};
    $worst_clock_residual = int(max(@non_out_lats) - min(@non_out_lats));
} else {
    $worst_clock_residual = 0;
}

# 4. Sort Violating Sinks
my @ranked_sinks = sort {
    $b->{score} <=> $a->{score} ||
    $b->{impact} <=> $a->{impact} ||
    $a->{sink} cmp $b->{sink}
} @violating_sinks;

my $dominant_depth = 0;
my $max_outliers_at_depth = -1;

foreach my $d (sort { $a <=> $b } keys %depth_outlier_count) {
    if ($depth_outlier_count{$d} > $max_outliers_at_depth) {
        $max_outliers_at_depth = $depth_outlier_count{$d};
        $dominant_depth = $d;
    }
}

# 5. Output Report Generation
open(my $out, '>', $rpt_file) or die "Cannot write to $rpt_file: $!";

my $rank = 1;
foreach my $rs (@ranked_sinks) {
    printf $out "RANK=%d SINK=%s CLOCK=%s SCORE=%.2f DEVIATION_PS=%.2f DEPTH=%d TRAN_PS=%d REASON=%s\n",
        $rank, $rs->{sink}, $rs->{clock}, $rs->{score}, $rs->{dev}, $rs->{depth}, $rs->{tran}, $rs->{reason};
    $rank++;
}
print $out "\n";

foreach my $d (sort { $a <=> $b } keys %depth_latencies) {
    my @lats = @{$depth_latencies{$d}};
    my $sum = 0;
    $sum += $_ foreach @lats;
    my $avg_lat = @lats ? ($sum / @lats) : 0;
    my $cnt = $depth_outlier_count{$d} // 0;

    printf $out "DEPTH_GROUP=%d OUTLIERS=%d AVG_LATENCY_PS=%.2f\n", $d, $cnt, $avg_lat;
}
print $out "\n";

print $out "WORST_CLOCK=$worst_clock\n";
print $out "WORST_CLOCK_EXCESS_PS=" . int($worst_clock_excess) . "\n";
print $out "DOMINANT_CAUSE_DEPTH=$dominant_depth\n";
print $out "RESIDUAL_SKEW_PS=$worst_clock_residual\n";
print $out "RANKED_SINKS=" . scalar(@ranked_sinks) . "\n";

close($out);