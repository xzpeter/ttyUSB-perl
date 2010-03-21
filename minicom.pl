#!/usr/bin/perl -w
use strict;
use warnings;
use ttyUSB;

$, = ", ";
$\ = "\n";
$| = 1;

my $port = shift || "/dev/ttyUSB3";

my $ttyUSB = ttyUSB->new( port => $port )
	or die "ttyUSB init failed.";
$ttyUSB->listen or die "listen failed.";
while (<>) {
	chomp;
	$ttyUSB->write($_);
}
