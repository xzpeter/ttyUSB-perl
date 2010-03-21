#!/usr/bin/perl -w
use strict;
use warnings;
use ttyUSB;
use Data::Dumper;

$, = ", ";
$\ = "\n";
$| = 1;

my $ttyUSB = ttyUSB->new( 
		port => "/dev/ttyUSB3", 
		type => "LC6311" ) 
	or die "ttyUSB init failed.";

$ttyUSB->listen() or die "listen failed.";

## $ttyUSB->init();
## $ttyUSB->sendsms("10086", "ye");
while (1) {
	my $sms = $ttyUSB->readsms();
	print Dumper $sms if $sms;
}
## my $cont = substr $sms->{content}, 0, 40;
## $ttyUSB->clearsms();
