#!/usr/bin/perl

use strict;
use warnings;

my $file = $ARGV[0] || die "ARGV[0]: csv file";

open(my $fi, "<", "$file") || die "$!";

my $head = <$fi>;
print $head;
chomp $head;

my @cnames = split ",", $head;	# column names
shift @cnames;			# remove the index column
my $NAs = join(",", map {"NA"} @cnames); # there must be a better way of accomplishing this...

my %row;
while (<$fi>) {
	chomp;
	my @words = split ",";
	$row{$words[0]} = $_; # words[0] is the index column -- timestamp herein
}
close($fi);

while (<STDIN>) {		# list of timestamps
	chomp;

	my ($t, $z) = ($_ =~ /(\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d)(.*)/); # "2010-08-03 22:30:00 EST" -> $t = "2010-08-03 22:30:00"

	if (exists $row{$t}) {
		print "$row{$t}\n";
	} else {
		print "$t,$NAs\n";
	}
}


# ~/iPGA/utils/process_scada_data.pl allendale_bank239_scada.csv | tee tmp.csv
# ./infill.pl tmp.csv < masterlist_of_times.txt                  | tee my_allendale_bank239_scada.csv
