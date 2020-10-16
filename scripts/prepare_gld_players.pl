#!/usr/bin/perl

use strict;
use warnings;

require "$ENV{HOME}/now/ENERGISE/scripts/ipga_pearls.pl";
our %UC;

my ($COI, $NOA, $SMI) = parse_argv(@ARGV);

open(my $f_lnode, "<", "lnode.csv") || die "$!";
my $head = <$f_lnode>;

# $f_lnode column IDs (0-indexed):
my $iLN = 0; # load number
my $iNN = 1; # node number
my $iPH = 2; # phases
my $iKW = 3; # kW

my %A = (A=>0, B=>1, C=>2);

my @lnode;		    # processed contents of ./lnode.csv
my @kWdrive = (0., 0., 0.); # EPRI_DRIVE-derived ckt-total kW consumed per phase
my @kW;

while (<$f_lnode>) {
	chomp;
	my @words = split ",";

	my @phases = split '', $words[$iPH]; # e.g., 'a', 'c'
	my $numphs = $#phases+1;

	@kW = (0., 0., 0.);
	foreach (@phases) {
		$kW[$A{$_}]       = $words[$iKW]/$numphs;
		$kWdrive[$A{$_}] += $kW[$A{$_}];
	}

	push @lnode, [$words[$iLN], $words[$iNN], $words[$iPH], $kW[$A{A}], $kW[$A{B}], $kW[$A{C}], 0];
}
close($f_lnode);

open(my $f_noa, ">", "noa.csv") || die "$!";
print $f_noa "load_number,number_of_5kW_arrays\n";

my $kWdrive_sum = $kWdrive[0] + $kWdrive[1] + $kWdrive[2];

foreach my $load (@lnode) {
	my $kW_sum = 0;

	foreach my $i (0..2) {
		$kW_sum          += $load->[$iKW+$i];
		$load->[$iKW+$i] /= $kWdrive[$i]; # for each CC, per phase, normalize the kW consumed by the ckt-total value
	}

	if ($NOA) {
		$load->[$iKW+3] = sprintf("%.0f", $kW_sum/$kWdrive_sum*$NOA);
		print $f_noa "$load->[$iLN],$load->[$iKW+3]\n";
	}
}
close($f_noa);


$head = <STDIN>;	        # SCADA data for the parent bank of $COI
chomp $head;
my @cnames = split ",", $head;	# column names
my $NC     = $#cnames;		# number of columns

my $N = 3+($COI-1)*5;           # time,bnk_{kW,beta}; ckt1_{kW,asum,fr1,fr2,fr3}; ... panel_output_kW (for a 5 kW solar array)

my %kWscada;	                # SCADA-derived ckt-wide kW time series (per phase)

while (<STDIN>) {
	chomp;
	my @words = split ",";

	if ($words[1] ne "NA") {
		$kWscada{$words[0]} = [
			$words[$N]*$words[$N+2], # demand (kW): phase 1
			$words[$N]*$words[$N+3], #                    2
			$words[$N]*$words[$N+4], #                    3
			$words[$NC],             # solar: phase 1+2+3
			$words[2]                # bank beta
		];
	}
}

my @T = (sort keys %kWscada);

foreach my $load (@lnode) {
	my $ln = $load->[$iLN];
	my $nn = $load->[$iNN];

	my @phases = split '', $load->[$iPH];

	# demand:
	my $D;
	foreach my $phase (@phases) {
		open(my $player, ">", "d_${ln}_${phase}_${nn}.csv") || die "$!";
		# the fraction of demand for NodeID=nn and phase $phase:
		my $fraction = $load->[$iKW+$A{$phase}];
		if ($fraction) {
			foreach my $t (@T) {
				$D->{$t}->[$A{$phase}] = $fraction * $kWscada{$t}->[$A{$phase}] * $UC{kilo};
				printf $player "%s,%-.0f%+.0fj\n", $t, $D->{$t}->[$A{$phase}], $kWscada{$t}->[4] * $D->{$t}->[$A{$phase}];
			}
		} else {
			foreach my $t (@T) {
				$D->{$t}->[$A{$phase}] = 0;
				printf $player "$t,0+0j\n";
			}
		}
		close($player);
	}

	# solar:
	if ($NOA) {
		foreach my $phase (@phases) {
			open(my $player, ">", "s_${ln}_${phase}_${nn}.csv") || die "$!";
			foreach my $t (@T) {
				my $denominator = $D->{$t}->[0] + $D->{$t}->[1] + $D->{$t}->[2];

				my $beta;
				if ($SMI) {
					$beta = $kWscada{$t}->[4];
				} else {
					$beta = 0;
				}
				# allocate the instantaneous solar output per phase in proportion to demand:
				if ($denominator) {
					my $S = ($D->{$t}->[$A{$phase}]/$denominator) * $load->[$iKW+3] * $kWscada{$t}->[3] * $UC{kilo};
					my $P = $S / sqrt(1+$beta^2);
					my $Q = $P * $beta;
					printf $player "%s,%-.0f%+.0fj\n", $t, $P, $Q;
				} else {
					printf $player "$t,0+0j\n";
				}
			}
			close($player);
		}
	}
}

sub parse_argv {
	my ($COI, $NOA, $SMI);

	while (my $arg = shift) {
		if ($arg eq '-c') {
			# circuit of interest:
			$COI = shift;
		} elsif ($arg eq '-n') {
			# number of (5kW solar) arrays
			$NOA = shift;
		}
		elsif ($arg eq '-s') {
			# "smart" inverters?
			$SMI = 1;
		}
	}

	if (!$COI) {
		$COI = 1;
	}
	if (!$NOA) {
		$NOA = 0;
	}
	if (!$SMI) {
		$SMI = 0;
	}

	return($COI, $NOA, $SMI);
}

# ~/now/ENERGISE/scripts/prepare_gld_players.pl -c 1 -n 1751 2> .err.log < ~/now/ENERGISE/data/demand_and_solar_allendale_bank239_minutely_aug_2016_week1.csv
# ~/now/ENERGISE/scripts/prepare_gld_players.pl -c 1 -n 1079 2> .err.log < ~/now/ENERGISE/data/demand_and_solar_allendale_bank139_minutely_aug_2016_week1.csv
# ~/now/ENERGISE/scripts/prepare_gld_players.pl -c 2 -n 2648 2> .err.log < ~/now/ENERGISE/data/demand_and_solar_allendale_bank239_minutely_aug_2016_week1.csv
