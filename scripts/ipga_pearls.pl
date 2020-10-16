use strict;
use warnings;

# unit conversion:
our %UC = (
	micro => 1.000e-6,
	milli => 1.000e-3,
	centi => 1.000e-1,
	kilo  => 1.000e+3,
	Mega  => 1.000e+6,
	Giga  => 1.000e+9
);

# find unique elements in a list:
# inspired by findUnique() at
# https://sourceforge.net/p/gridlab-d/code/HEAD/tree/Taxonomy_Feeders/PopulationScript/ConversionScripts/Cyme_to_GridLabD.txt
sub unique_elements {
	my (@a) = @_;
	my %h;
	return(grep { !$h{$_}++ } @a); # isn't Perl awesome?
}

# find the intersection of two lists:
# inspired by the answer given by "chromatic" at
# http://www.perlmonks.org/?node_id=2461
sub intersection_of {
	my ($a, $b) = @_;
	my %c = map { $_ => 1 } @$a;
	return(grep { $c{$_}  } @$b);
}

# compute the mean of a list of numbers:
sub mean_of {
	my (@numbers) = @_;
	my ($sum, $n);
	foreach (@numbers) {
		if ($_ =~ /\d+/) {
			$sum += $_;
			$n   += 1;
		}
	}
	return($sum/$n) if ($n);
}

# format ORU (ConEd) timestamps:
sub format_time_oru {
	my ($timestamp) = @_;	# e.g., 1/1/16 1:00 AM
	my ($month, $day, $year, $hour, $minute, $meridiem) = ($timestamp =~ /(\d+)\/(\d+)\/(\d\d)\s(\d+):(\d\d)\s(\D+)/);
	if ($meridiem eq "PM" && $hour != 12) {
		$hour += 12;
	} elsif ($meridiem eq "AM" && $hour == 12) {
		$hour = 0;
	}
	return(sprintf("20%02d-%02d-%02d %02d:%02d:00", $year, $month, $day, $hour, $minute)); # 2016-01-01 01:00:00
}

1; # to "require" this file in another, a truthy value needs to be returned
