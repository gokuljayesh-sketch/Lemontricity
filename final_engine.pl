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
my $sdc_file       = "${input_dir}constraints/hack_top.sdc";
my $pre_cts_file   = "${input_dir}reports/pre_fix/cts.rpt";
my $post_cts_file  = "${input_dir}reports/post_fix/cts.rpt";
my $plan_file      = "${output_dir}fix_plan.txt";
my $rpt_file       = "${output_dir}final_report.rpt";
my $summary_file   = "${output_dir}machine_summary.txt";

# Fallbacks
if (! -e $pre_cts_file && -e "${input_dir}cts.rpt") { $pre_cts_file = "${input_dir}cts.rpt"; }
if (! -e $post_cts_file && -e "${input_dir}post_cts.rpt") { $post_cts_file = "${input_dir}post_cts.rpt"; }
if (! -e $sdc_file && -e "${input_dir}hack_top.sdc") { $sdc_file = "${input_dir}hack_top.sdc"; }

# 1. Parse Constraints
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

# Subroutine to parse CTS reports
sub parse_cts {
    my ($file) = @_;
    my %data = ();
    return %data unless (-e $file);

    open(my $fh, '<', $file) or die "Cannot open $file: $!";
    while (my $line = <$fh>) {
        chomp($line);
        next if ($line =~ /^\s*#/ || $line =~ /^\s*$/);

        my $type = ($line =~ /^(SINK|OBJECT|BUFFER)/i) ? uc($1) : "SINK";
        my $obj  = ($line =~ /(?:SINK|OBJECT|BUFFER)\s+(\S+)/i) ? $1 : "UNKNOWN";
        my $clk  = ($line =~ /CLOCK\s+(\S+)/i) ? $1 : "sys_clk";
        my $lat  = ($line =~ /LATENCY_PS\s+([\d\.\-]+)/i) ? $1 : undef;
        my $dep  = ($line =~ /DEPTH\s+(\d+)/i) ? $1 : 0;
        my $trn  = ($line =~ /TRAN_PS\s+([\d\.]+)/i) ? $1 : undef;

        if (defined $lat && defined $trn) {
            $data{$clk}{$obj} = {
                type => $type,
                lat  => $lat + 0,
                trn  => $trn + 0,
                dep  => $dep + 0
            };
        }
    }
    close($fh);
    return %data;
}

my %pre_data  = parse_cts($pre_cts_file);
my %post_data = parse_cts($post_cts_file);

# 2. Analyze Pre and Post Metrics
my (%pre_skew, %post_skew, %pre_tran_viols, %post_tran_viols, %pre_dep_viols, %post_dep_viols);
my (%pre_sinks, %post_sinks);

foreach my $clk (keys %pre_data) {
    my @lats = map { $_->{lat} } values %{$pre_data{$clk}};
    $pre_skew{$clk} = @lats ? int(max(@lats) - min(@lats)) : 0;
    $pre_tran_viols{$clk} = grep { $_->{trn} > $max_tran_ps } values %{$pre_data{$clk}};
    $pre_dep_viols{$clk}  = grep { $_->{dep} > $max_depth } values %{$pre_data{$clk}};
    $pre_sinks{$_} = 1 foreach keys %{$pre_data{$clk}};
}

foreach my $clk (keys %post_data) {
    my @lats = map { $_->{lat} } values %{$post_data{$clk}};
    $post_skew{$clk} = @lats ? int(max(@lats) - min(@lats)) : 0;
    $post_tran_viols{$clk} = grep { $_->{trn} > $max_tran_ps } values %{$post_data{$clk}};
    $post_dep_viols{$clk}  = grep { $_->{dep} > $max_depth } values %{$post_data{$clk}};
    $post_sinks{$_} = 1 foreach keys %{$post_data{$clk}};
}

# Sink Loss/Gain Audit
my $sinks_lost  = grep { !$post_sinks{$_} } keys %pre_sinks;
my $sinks_added = grep { !$pre_sinks{$_} } keys %post_sinks;

# 3. Read Fix Plan & Compute Accuracy
my $total_actions = 0;
my $accurate_actions = 0;

if (-e $plan_file) {
    open(my $pfh, '<', $plan_file) or die "Cannot open $plan_file: $!";
    while (my $line = <$pfh>) {
        chomp($line);
        next if $line =~ /^\s*$/;
        my ($clk, $sink, $action, $st_str, $b_str, $t_str) = split(/\s+/, $line);
        next unless defined $sink && defined $t_str;

        my ($target_ps) = $t_str =~ /=(\d+)/;
        $total_actions++;

        if (exists $post_data{$clk}{$sink}) {
            my $achieved_lat = $post_data{$clk}{$sink}->{lat};
            if (abs($achieved_lat - $target_ps) <= $buffer_delay_ps) {
                $accurate_actions++;
            }
        }
    }
    close($pfh);
}

my $plan_accuracy_pct = $total_actions ? sprintf("%.2f", ($accurate_actions / $total_actions) * 100) : "100.00";

# 4. Generate Final Consolidated Report
open(my $out, '>', $rpt_file) or die "Cannot write to $rpt_file: $!";

print $out "=== BEFORE ===\n";
foreach my $clk (sort keys %pre_data) {
    my $outliers = grep { abs($_->{lat} - ($target_latency_ps{$clk} // 1000)) > 100 } values %{$pre_data{$clk}};
    printf $out "CLOCK=%s SKEW_PS=%d OUTLIERS=%d TRAN_VIOLS=%d DEPTH_VIOLS=%d\n",
        $clk, $pre_skew{$clk}, $outliers, ($pre_tran_viols{$clk}//0), ($pre_dep_viols{$clk}//0);
}
print $out "\n";

print $out "=== DETECTED ISSUES ===\n";
foreach my $clk (sort keys %pre_data) {
    my $t_lat = $target_latency_ps{$clk} // 1000;
    foreach my $s (sort keys %{$pre_data{$clk}}) {
        my $item = $pre_data{$clk}{$s};
        if (abs($item->{lat} - $t_lat) > 100 || $item->{trn} > $max_tran_ps || $item->{dep} > $max_depth) {
            printf $out "VIOLATION SINK=%s CLOCK=%s LATENCY_PS=%.2f TRAN_PS=%.2f DEPTH=%d\n",
                $s, $clk, $item->{lat}, $item->{trn}, $item->{dep};
        }
    }
}
print $out "\n";

print $out "=== CORRECTION / RECOMMENDATION ===\n";
if (-e $plan_file) {
    open(my $pfh, '<', $plan_file);
    while (<$pfh>) { print $out $_; }
    close($pfh);
}
print $out "\n";

print $out "=== AFTER ===\n";
foreach my $clk (sort keys %post_data) {
    printf $out "CLOCK=%s SKEW_PS=%d TRAN_VIOLS=%d DEPTH_VIOLS=%d\n",
        $clk, $post_skew{$clk}, ($post_tran_viols{$clk}//0), ($post_dep_viols{$clk}//0);
}
print $out "\n";

print $out "=== CLOSURE ===\n";
my $overall_closure = "PASS";
my $tot_pre_skew = 0;
my $tot_post_skew = 0;
my $tot_pre_tran = 0; my $tot_post_tran = 0;
my $tot_pre_dep  = 0; my $tot_post_dep  = 0;

foreach my $clk (sort keys %pre_data) {
    my $t_skew = $target_skew_ps{$clk} // 250;
    my $p_skew = $post_skew{$clk} // $pre_skew{$clk};
    my $status = ($p_skew <= $t_skew) ? "PASS" : "FAIL";
    $overall_closure = "FAIL" if $status eq "FAIL";

    printf $out "CLOCK=%s SKEW_BEFORE_PS=%d SKEW_AFTER_PS=%d TARGET_SKEW_PS=%d STATUS=%s\n",
        $clk, $pre_skew{$clk}, $p_skew, $t_skew, $status;

    $tot_pre_skew  += $pre_skew{$clk};
    $tot_post_skew += $p_skew;
    $tot_pre_tran  += ($pre_tran_viols{$clk} // 0);
    $tot_post_tran += ($post_tran_viols{$clk} // 0);
    $tot_pre_dep   += ($pre_dep_viols{$clk} // 0);
    $tot_post_dep  += ($post_dep_viols{$clk} // 0);
}

my $imp_pct = $tot_pre_skew ? sprintf("%.2f", (($tot_pre_skew - $tot_post_skew) / $tot_pre_skew) * 100) : "0.00";
if ($sinks_lost > 0 || $sinks_added > 0) { $overall_closure = "FAIL"; }

printf $out "TRAN_VIOLATIONS_BEFORE=%d  TRAN_VIOLATIONS_AFTER=%d\n", $tot_pre_tran, $tot_post_tran;
printf $out "DEPTH_VIOLATIONS_BEFORE=%d  DEPTH_VIOLATIONS_AFTER=%d\n", $tot_pre_dep, $tot_post_dep;
printf $out "SINKS_LOST=%d  SINKS_ADDED=%d\n", $sinks_lost, $sinks_added;
print $out "PLAN_ACCURACY_PERCENT=$plan_accuracy_pct\n";
print $out "IMPROVEMENT_PERCENT=$imp_pct\n";
print $out "BEFORE_STATUS=" . (($tot_pre_tran || $tot_pre_dep) ? "FAIL" : "PASS") . "\n";
print $out "AFTER_STATUS=" . (($tot_post_tran || $tot_post_dep) ? "FAIL" : "PASS") . "\n";
print $out "CLOSURE=$overall_closure\n";
close($out);

# 5. Write Machine Summary
open(my $ms, '>', $summary_file) or die "Cannot write to $summary_file: $!";
print $ms "CLOSURE=$overall_closure\n";
print $ms "IMPROVEMENT_PERCENT=$imp_pct\n";
print $ms "PLAN_ACCURACY_PERCENT=$plan_accuracy_pct\n";
print $ms "SINKS_LOST=$sinks_lost\n";
print $ms "SINKS_ADDED=$sinks_added\n";
close($ms);