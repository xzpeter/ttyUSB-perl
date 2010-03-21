package ttyUSB;

=pod
TODO
1.module name can be recognised by at cmd. For:
	LC6311: use AT+CGMR
	SIM4100: use ATI
=cut

use strict;
use threads;
use threads::shared;
use Data::Dumper;
use Time::HiRes qw( usleep );

use constant DEBUG => 1;

use constant AT_OK => 1;
use constant AT_ERR => 0;

use constant AT_STAT_IDLE => 0;
use constant AT_STAT_LISTEN => 1;
use constant AT_STAT_READY => 2;

use constant SMS_IDLE => 0;
use constant SMS_REQUEST => 1;
use constant SMS_READY => 2;

## $, = ', ';
## $\ = "\n";
$| = 1;

my $_at_status :shared = AT_STAT_IDLE;
my $_at_ok :shared = AT_ERR;
my $_at_cont :shared = "";

my $_sms_status :shared = SMS_IDLE;

sub new {
	my $class = shift;
	my %hash = @_;
	my $self = {};
	bless $self, $class or die "cannot bless in $class: $!";
	$self->{port} = $hash{port} || "/dev/ttyUSB5";
	$self->{type} = (uc $hash{type}) || "LC6311";
	$self->{retry} = $hash{retry} || 3;
	$self->open_port or die "cannot open port.";
	$self;
}

sub open_port {
	my $self = shift;
	die "port not initialized." unless defined $self->{port};
	open my $fh, "+<".$self->{port} or die "cannot open port: $!";
	$self->{fh} = $fh;
	1;
}

# fork a process listening to the port.
sub listen {
	my $self = shift;
	# if the port is not opened, open it.
	if (not defined $self->{fh}) {
		die "cannot open port." unless $self->open_port;
	}
	my $tid = threads->create( sub {
		my $fh = shift;
		while (defined (sysread $fh, my $s, 1024)) {
			# fill $_at_ok and $_at_cont
			print "<<< $s" if $s =~ /\S/ && DEBUG;
			if ($_at_status == AT_STAT_LISTEN) {
				$_at_cont .= $s; 
				if ($s =~ /OK/) { 
					$_at_ok = AT_OK; $_at_status = AT_STAT_READY; 
				}
				elsif ($s =~ /ERROR/) { 
					$_at_ok = AT_ERR; $_at_status = AT_STAT_READY;
				}
			}
			if ($_sms_status == SMS_REQUEST && $s =~ /> /) {
				$_sms_status = SMS_READY;
			}
		}
		die "sysread() returned 0 or error in listening thread: $!";
	}, $self->{fh});
	die "error in creating thread: $!" unless $tid;
	$self->{tid} = $tid;
	$tid->detach();
	1;
}

# such as: $self->write("AT+CREG?");
sub write {
	my $self = shift;
	# TOFIX: now only support scalar. it can be an array in the future.
	my $data = shift;
	my $fh = $self->{fh};
	return 1 if not defined $data;
	$data = $data."\r";
	print ">>> ".$data if DEBUG;
	print $fh $data;
}

# send a AT cmd, return after "OK"
sub cmd {
	my $self = shift;
	my $cmd = shift;
	return 1 if not defined $cmd;
	# clear flag
	$_at_ok = AT_ERR;
	$_at_status = AT_STAT_LISTEN;
	$_at_cont = "";
	$self->write($cmd) or die "cannot write() in cmd(): $!";
	# waiting for listening thread to receive "OK" or "ERROR"
## 	sleep 1 while $_at_status != AT_STAT_READY;
 	usleep 300 while $_at_status != AT_STAT_READY;
	$_at_status = AT_STAT_IDLE;
	$_at_ok;
}

sub dump {
	print Dumper(shift);
}

sub DESTROY {
}

# send a cmd array
sub cmd_array {
	my $self = shift;
	my @array = @_;
	foreach my $cmd (@array) {
		$self->cmd($cmd) or return 0;
	}
	1;
}

sub module_init_lc6311 {
	my $self = shift;
	my @init_arr = (
			'AT+CFUN=5',
			'AT+CFUN=1',
			'AT+COPS=0',
			'AT+CNMI=2,1,0,2,0',
## 			'AT+CPMS="ME","ME","ME"',
			'AT+CMMS=1',
			'AT+CMGF=1',
			'AT',
			'AT+CSMP=145,71,32,0',
			'AT+CSCS="GSM"'
			);
	$self->cmd_array(@init_arr);
}

sub module_init {
	my $self = shift;
	my $type = $self->{type};
	if ($type eq "LC6311") {
		$self->module_init_lc6311();
	} else {
		print "not supported now." if DEBUG;
		0; # not supported now.
	}
}

sub init {
	my $self = shift;
	while ($self->{retry}) {
		my $ret = $self->module_init();
		return 1 if $ret;
		$self->{retry}--;
	}
}

sub sendsms {
	my $self = shift;
	my $target = shift;
	my $data = shift;
	return 0 if not defined $target;
	$_sms_status = SMS_REQUEST;
	$self->write("AT+CMGS=\"$target\"");
	sleep 1 while $_sms_status != SMS_READY;
	$_sms_status = SMS_IDLE;
	# here, since rawdata must not be sent with end of "\r",
	# instead of $self->cmd(), I have to use a really ugly way to do this
	$_at_ok = AT_ERR;
	$_at_status = AT_STAT_LISTEN;
	$_at_cont = "";
	my $fh = $self->{fh};
	print $fh "$data\x1A";
	print "$data\r" if DEBUG; # show on STDOUT
	# waiting for listening thread to receive "OK" or "ERROR"
	sleep 1 while $_at_status != AT_STAT_READY;
	$_at_status = AT_STAT_IDLE;
	$_at_ok;
}

sub read_one_sms {
	my $self = shift;
	my $n = shift || 0;
	return 0 if ($n > 39 || $n < 0);
	$n = sprintf "%02d", $n;
	$self->cmd("AT^DMGR=$n") or return 0;
	my $result = $_at_cont;
	$result =~ s/\r\n//g;
	my @arr = $result =~ /"([^"]+)","([^"]+)",,"([^"]+)"(.*)$/;
	my $sms = {
		status => $arr[0],
		target => $arr[1],
		recvtime => $arr[2],
		content => $arr[3],
	};
	$sms;
}

sub readsms {
	my $self = shift;
	my $start = shift || 0;
	my $end = shift || 39;
	return 0 if $start =~ /\D/ || $end =~ /\D/;
	$start = 0 if $start < 0;
	$start = 39 if $start > 39;
	$end = $start if $end < $start;
	$end = 39 if $end > 39;
	foreach my $i ($start..$end) {
		my $sms = $self->read_one_sms($i);
		if ($sms) {
			return 0 unless $self->delete_one_sms($i);
			return $sms;
		}
	}
	0;
}

sub delete_one_sms {
	my $self = shift;
	my $i = shift || -1;
	return 0 if $i < 0 || $i > 39;
	my $cmd = sprintf "AT+CMGD=%02d", $i;
	$self->cmd($cmd);
}

sub clearsms {
	my $self = shift;
	for my $i (0..39) {
		$self->delete_one_sms($i);
	}
	1;
}

1;
