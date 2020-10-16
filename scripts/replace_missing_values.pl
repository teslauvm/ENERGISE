#!/usr/bin/perl

use strict;
use warnings;

my $fill = "-999999";

while (<STDIN>) {
	chomp;
	my @words = split ",";

	@words = map { $_ ? $_ : $fill } @words;
	print join(",", @words), "\n";
}
