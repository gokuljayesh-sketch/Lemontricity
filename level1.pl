#!/usr/bin/perl
use strict;
use warnings;
use File::Spec;
use File::Path qw(make_path);

# ==============================================================================
# HACKATHON LEVEL 1: PARSE, EXTRACT & INVENTORY MODULE
# ==============================================================================

# Parse Directory Arguments
my $input_dir  = $ARGV[0] // 'inputs';
my $output_dir = $ARGV[1] // 'submit_here';

my $cts_file = File::Spec->catfile($input_dir, 'reports', 'pre_fix', 'cts.rpt');
my $sdc_file = File::Spec->catfile($input_dir, 'constraints', 'hack_top.sdc');

unless (-e $cts_file) {
    die "[-] ERROR: CTS report not found at '$cts_file'\n";
}

# Ensure Output Directory Exists
make_path($output_dir) unless -d $output_dir;
my $rpt_file = File::Spec->catfile($output_dir, 'level1_baseline.rpt');

# Data Structures
my $buffer_delay_ps = 0;
my %clocks_sdc;       # clock -> period_ns
my %clock_limits;    # clock -> { target_skew, max_tran, max_depth }
my %sinks;           # pin -> { clock, latency, depth, tran }
my %buffers;         # clock -> level -> count
my %clock_buffers;   # clock -> total buffer count
my $skipped_records = 0;

# --- 1. PARSE SDC FILE FOR CLOCK PERIODS ---
if (-e $sdc_file) {
    open(my $fh, '<', $sdc_file) or die "[-] ERROR: Cannot open $sdc_file: $!\n";
    while (my $line = <$fh>) {
        chomp($line);
        $line =~ s/#.*$//;
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '';

        # Example SDC: create_clock -name clk_core -period 2.0 [get_ports clk]
        if ($line =~ /create_clock\s+.*?-name\s+([\w_]+).*?-period\s+([\d\.]+)/i ||
            $line =~ /create_clock\s+.*?-period\s+([\d\.]+).*?-name\s+([\w_]+)/i) {
            my ($clk, $period) = ($1, $2);
            ($clk, $period) = ($2, $1) if $1 =~ /^[\d\.]+$/;
            $clocks_sdc{$clk} = $period + 0;
        }
    }
    close($fh);
}

# --- 2. PARSE PRE-FIX CTS REPORT ---
open(my $fh_cts, '<', $cts_file) or die "[-] ERROR: Cannot open $cts_file: $!\n";

while (my $line = <$fh_cts>) {
    chomp($line);
    $line =~ s/#.*$//;
    $line =~ s/^\s+|\s+$//g;
    next if $line eq '';

    # BUFFER_DELAY_PS <value>
    if ($line =~ /^BUFFER_DELAY_PS\s+([\d\.]+)/i) {
        $buffer_delay_ps = sprintf("%.2f", $1);
    }
    # CLOCK <name> TARGET_SKEW_PS <n> MAX_TRAN_PS <n> MAX_DEPTH <n>
    elsif ($line =~ /^CLOCK\s+(\S+)\s+TARGET_SKEW_PS\s+(\d+)\s+MAX_TRAN_PS\s+(\d+)\s+MAX_DEPTH\s+(\d+)/i) {
        my ($clk, $skew, $tran, $depth) = ($1, $2, $3, $4);
        $clock_limits{$clk} = {
            target_skew => $skew + 0,
            max_tran    => $tran + 0,
            max_depth   => $depth + 0,
        };
    }
    # SINK <pin> CLOCK <name> LATENCY_PS <n> DEPTH <n> TRAN_PS <n>
    elsif ($line =~ /^SINK\s+(\S+)\s+CLOCK\s+(\S+)\s+LATENCY_PS\s+(\d+)\s+DEPTH\s+(\d+)\s+TRAN_PS\s+(\d+)/i) {
        my ($pin, $clk, $lat, $depth, $tran) = ($1, $2, $3, $4, $5);
        $sinks{$pin} = {
            clock   => $clk,
            latency => $lat + 0,
            depth   => $depth + 0,
            tran    => $tran + 0,
        };
    }
    # BUFFER <name> CLOCK <name> LEVEL <n> FANOUT <n>
    elsif ($line =~ /^BUFFER\s+(\S+)\s+CLOCK\s+(\S+)\s+LEVEL\s+(\d+)\s+FANOUT\s+(\d+)/i) {
        my ($buf, $clk, $level, $fanout) = ($1, $2, $3, $4);
        $buffers{$clk}{$level}++;
        $clock_buffers{$clk}++;
    }
    else {
        $skipped_records++;
    }
}
close($fh_cts);

# Group sinks by clock
my %clk_sinks;
foreach my $pin (keys %sinks) {
    my $clk = $sinks{$pin}{clock};
    push @{ $clk_sinks{$clk} }, $sinks{$pin};
}

# Derive global list of clocks
my %all_clocks = map { $_ => 1 } (keys %clock_limits, keys %clk_sinks, keys %clocks_sdc);
my @sorted_clocks = sort keys %all_clocks;

my $total_sinks_cnt = scalar(keys %sinks);
my $total_bufs_cnt  = 0;
foreach my $c (keys %clock_buffers) { $total_bufs_cnt += $clock_buffers{$c}; }

# --- 3. WRITE LEVEL 1 REPORT ---
open(my $out, '>', $rpt_file) or die "[-] ERROR: Cannot write report to $rpt_file: $!\n";

print $out "BATCH=03\n";
print $out "INPUT_STATUS=PASS\n";
print $out "BUFFER_DELAY_PS=$buffer_delay_ps\n";
print $out "CLOCKS=" . scalar(@sorted_clocks) . "\n";
print $out "TOTAL_SINKS=$total_sinks_cnt\n";
print $out "TOTAL_BUFFERS=$total_bufs_cnt\n";
print $out "SKIPPED_RECORDS=$skipped_records\n\n";
print $out "# one block per clock, clocks in lexical order\n";

foreach my $clk (@sorted_clocks) {
    my $period = sprintf("%.2f", $clocks_sdc{$clk} // 0.00);
    my $sink_list = $clk_sinks{$clk} // [];
    my $num_sinks = scalar(@$sink_list);

    my ($lat_min, $lat_max, $lat_mean, $lat_median) = (0, 0, "0.0", 0);
    my ($depth_min, $depth_max) = (0, 0);
    my ($tran_min, $tran_max)   = (0, 0);

    if ($num_sinks > 0) {
        my @lats   = sort { $a <=> $b } map { $_->{latency} } @$sink_list;
        my @depths = sort { $a <=> $b } map { $_->{depth} } @$sink_list;
        my @trans  = sort { $a <=> $b } map { $_->{tran} } @$sink_list;

        $lat_min = $lats[0];
        $lat_max = $lats[-1];

        my $sum = 0;
        $sum += $_ foreach @lats;
        $lat_mean = sprintf("%.1f", $sum / $num_sinks);

        # Median logic according to prompt specifications
        if ($num_sinks % 2 == 1) {
            $lat_median = $lats[int($num_sinks / 2)];
        } else {
            my $mid1 = $lats[($num_sinks / 2) - 1];
            my $mid2 = $lats[$num_sinks / 2];
            $lat_median = int((($mid1 + $mid2) / 2) + 0.5);
        }

        $depth_min = $depths[0];
        $depth_max = $depths[-1];
        $tran_min  = $trans[0];
        $tran_max  = $trans[-1];
    }

    my $buf_count = $clock_buffers{$clk} // 0;
    my $num_levels = $buffers{$clk} ? scalar(keys %{ $buffers{$clk} }) : 0;

    print $out "CLOCK=$clk PERIOD_NS=$period SINKS=$num_sinks LAT_MIN_PS=$lat_min LAT_MAX_PS=$lat_max LAT_MEAN_PS=$lat_mean LAT_MEDIAN_PS=$lat_median\n";
    print $out "CLOCK=$clk DEPTH_MIN=$depth_min DEPTH_MAX=$depth_max TRAN_MIN_PS=$tran_min TRAN_MAX_PS=$tran_max BUFFERS=$buf_count LEVELS=$num_levels\n";
}

close($out);
print "[+] Level 1 complete! Baseline report written to: $rpt_file\n";