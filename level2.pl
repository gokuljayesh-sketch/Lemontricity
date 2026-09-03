#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);

my $input_dir  = $ARGV[0] || "inputs/";
my $output_dir = $ARGV[1] || "submit_here/";

$input_dir  =~ s{/*$}{/};
$output_dir =~ s{/*$}{/};

make_path($output_dir);

my $sdc_file = "${input_dir}constraints/hack_top.sdc";
my $cts_file = "${input_dir}reports/pre_fix/cts.rpt";
my $rpt_file = "${output_dir}level2_violations.rpt";

if (! -e $cts_file && -e "${input_dir}cts.rpt") { $cts_file = "${input_dir}cts.rpt"; }
if (! -e $sdc_file && -e "${input_dir}hack_top.sdc") { $sdc_file = "${input_dir}hack_top.sdc"; }

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

open(my $out, '>', $rpt_file) or die "Cannot write to $rpt_file: $!";

my $total_violations = 0;
my $critical_count   = 0;
my $major_count      = 0;
my $minor_count      = 0;
my %clock_statuses   = ();

foreach my $clk (sort keys %clocksdata) {
    my $t_skew = $target_skew_ps{$clk} // 250;
    my $t_lat  = $target_latency_ps{$clk} // 1000;
    
    my $sinks = $clocksdata{$clk};
    my $min_lat = 999999;
    my $max_lat = -999999;
    my $outliers_count = 0;
    my $has_other_violation = 0;

    my $total_fanout = 0;
    my $buf_count    = 0;
    foreach my $s (@$sinks) {
        if ($s->{type} eq "BUFFER" || $s->{fan} > 0) {
            $total_fanout += $s->{fan};
            $buf_count++;
        }
    }
    my $avg_fanout = ($buf_count > 0) ? ($total_fanout / $buf_count) : 0;
    my $fanout_limit = ($avg_fanout > 0) ? ($avg_fanout * 1.5) : 20.0;

    foreach my $s (@$sinks) {
        $min_lat = $s->{lat} if $s->{lat} < $min_lat;
        $max_lat = $s->{lat} if $s->{lat} > $max_lat;

        # 1. TRAN_VIOLATION
        if ($s->{trn} > $max_tran_ps) {
            my $meas = sprintf("%.2f", $s->{trn});
            my $lim  = sprintf("%.2f", $max_tran_ps);
            my $marg = sprintf("%.2f", $s->{trn} - $max_tran_ps);
            print $out "VIOLATION TYPE=TRAN_VIOLATION OBJECT=$s->{obj} CLOCK=$clk MEASURED=$meas LIMIT=$lim MARGIN=$marg SEVERITY=MAJOR\n";
            $total_violations++;
            $major_count++;
            $has_other_violation = 1;
        }

        # 2. DEPTH_VIOLATION
        if ($s->{dep} > $max_depth) {
            my $meas = sprintf("%.2f", $s->{dep});
            my $lim  = sprintf("%.2f", $max_depth);
            my $marg = sprintf("%.2f", $s->{dep} - $max_depth);
            print $out "VIOLATION TYPE=DEPTH_VIOLATION OBJECT=$s->{obj} CLOCK=$clk MEASURED=$meas LIMIT=$lim MARGIN=$marg SEVERITY=MINOR\n";
            $total_violations++;
            $minor_count++;
            $has_other_violation = 1;
        }

        # 3. LATENCY_OUTLIER
        my $dev = $s->{lat} - $t_lat;
        if (abs($dev) > 100) {
            $outliers_count++;
            my $meas = sprintf("%+.2f", $dev);
            my $marg = sprintf("%.2f", abs($dev) - 100.0);
            print $out "VIOLATION TYPE=LATENCY_OUTLIER OBJECT=$s->{obj} CLOCK=$clk MEASURED=$meas LIMIT=100.00 MARGIN=$marg SEVERITY=MINOR\n";
            $total_violations++;
            $minor_count++;
            $has_other_violation = 1;
        }

        # 4. FANOUT_HOTSPOT
        if ($s->{fan} > 0 && $s->{fan} > $fanout_limit) {
            my $meas = sprintf("%.2f", $s->{fan});
            my $lim  = sprintf("%.2f", $fanout_limit);
            my $marg = sprintf("%.2f", $s->{fan} - $fanout_limit);
            print $out "VIOLATION TYPE=FANOUT_HOTSPOT OBJECT=$s->{obj} CLOCK=$clk MEASURED=$meas LIMIT=$lim MARGIN=$marg SEVERITY=MINOR\n";
            $total_violations++;
            $minor_count++;
            $has_other_violation = 1;
        }
    }

    my $skew_ps = ($min_lat < 999999) ? int($max_lat - $min_lat) : 0;
    my $skew_percent = sprintf("%.2f", ($t_skew > 0) ? ($skew_ps / $t_skew) * 100 : 0);

    my $status = "PASS";
    if ($skew_ps > $t_skew) {
        $status = "FAIL";
        my $meas = sprintf("%.2f", $skew_ps);
        my $lim  = sprintf("%.2f", $t_skew);
        my $marg = sprintf("%.2f", $skew_ps - $t_skew);
        print $out "VIOLATION TYPE=SKEW_VIOLATION OBJECT=$clk CLOCK=$clk MEASURED=$meas LIMIT=$lim MARGIN=$marg SEVERITY=CRITICAL\n";
        $total_violations++;
        $critical_count++;
    } elsif ($has_other_violation) {
        $status = "WARNING";
    }

    $clock_statuses{$clk} = $status;
    print $out "CLOCK=$clk SKEW_PS=$skew_ps TARGET_SKEW_PS=$t_skew SKEW_PERCENT=$skew_percent TARGET_LATENCY_PS=$t_lat OUTLIERS=$outliers_count STATUS=$status\n\n";
}

my $baseline_status = "PASS";
foreach my $st (values %clock_statuses) {
    if ($st eq "FAIL") {
        $baseline_status = "FAIL";
        last;
    } elsif ($st eq "WARNING") {
        $baseline_status = "WARNING";
    }
}

print $out "TOTAL_VIOLATIONS=$total_violations\n";
print $out "CRITICAL_COUNT=$critical_count MAJOR_COUNT=$major_count MINOR_COUNT=$minor_count\n";
print $out "BASELINE_STATUS=$baseline_status\n";

close($out);
print "Report updated successfully.\n";
