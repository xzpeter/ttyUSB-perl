#!/usr/bin/perl -w
use strict;
use warnings;
use ttyUSB;

$, = ", ";
$\ = "\n";
$| = 1;

my $portn = shift || 0;
$portn = 5 if $portn =~ /\D/ || $portn < 0;
my $port = "/dev/ttyUSB$portn";

print "opening port $port...";

my $ttyUSB = ttyUSB->new( port => $port )
	or die "ttyUSB init failed.";
$ttyUSB->listen or die "listen failed.";
while (<>) {
	chomp;
	$ttyUSB->write($_);
}
