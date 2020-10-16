#!/usr/bin/perl

use strict;
use warnings;

$ARGV[0] || die "ARGV[0]: SCADA (bank) file";

require "$ENV{HOME}/now/ENERGISE/scripts/ipga_pearls.pl";

open(my $f_scada, "<", "$ARGV[0]") || die "$!";

# $f_scada column IDs (0-indexed):
my $iDT   = 1;			# Date-Time
my $iBA1  = 5;			# Bank Amps-Phase 1
my $iBA2  = $iBA1+1;		# Bank Amps-Phase 2
my $iBA3  = $iBA1+2;		# Bank Amps-Phase 3
my $iBKW  = 8;			# Bank KW
my $iBPF  = 11;			# Bank_PF
my $iCkt1 = 12;			# Circuit #1

my $head = <$f_scada>;
chomp $head;
my @cnames = split ",", $head;	# column names

my $nckt = ($#cnames-$iCkt1+1)/4; # number of circuits

print "time,bnk_kW,bnk_beta";
print ",ckt${_}_kW,ckt${_}_asum,ckt${_}_fr1,ckt${_}_fr2,ckt${_}_fr3" foreach (1..$nckt);
print "\n";

while (<$f_scada>) {
	chomp;
	my @words = split ",";

	my $ignore;
	foreach (@words) {
		if (!$_ || $_ eq "0") {
			$ignore = 1;
			last;
		}
	}

	if (!$ignore) {		
		my $bnk_asum = $words[$iBA1]+$words[$iBA2]+$words[$iBA3]; # asum: amps sum
		my $bnk_beta = sqrt($words[$iBPF]**(-2)-1); # =Q/P

		printf "%s,%.0f,%.3f", format_time_oru($words[$iDT]), $words[$iBKW], $bnk_beta;

		my $i = $iCkt1;

		foreach (1..$nckt) {
			my $ckt_asum = $words[$i+1]+$words[$i+2]+$words[$i+3];

			my $ckt_fr1 = $words[$i+1]/$ckt_asum; # fr: fraction
			my $ckt_fr2 = $words[$i+2]/$ckt_asum;
			my $ckt_fr3 = $words[$i+3]/$ckt_asum;

			printf ",%.0f,%.1f,%.3f,%.3f,%.3f",
			($ckt_asum/$bnk_asum)*$words[$iBKW],
			$ckt_asum,
			$ckt_fr1, $ckt_fr2, $ckt_fr3;

			$i += 4; # there are 4 columns per circuit (name, amps_phase_1, amps_phase_2, amps_phase_3)
		}
		print "\n";
	}
}
close($f_scada);
