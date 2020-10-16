#!/usr/bin/perl

use strict;
use warnings;

while (<STDIN>) {
	chomp;
	my @words = split ",";

	@words = map { s/^'(.*)'$/$1/r } @words; # s/^'(.*)'$/$1/r is straight from perldoc (perlrequick)
	print join(",", @words), "\n";
}
