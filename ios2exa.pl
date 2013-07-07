#!/usr/bin/perl

#ios2exa - convert ios BGP Loc RIB to exabgp config

use strict;
use Getopt::Long::Descriptive;
use Net::Subnet;

my (%subnets, %peers);
my ($linecount, $prefix, $nexthop);

my ($opt, $usage) = describe_options(
	"$0 <arguments>",
	['asnum|a=i',	'AS Number of target / DUT (default 64511)'				],
	['cores|c=i',	'number of configuration per core files to create (default 1)'		],
	['debug|d',	'Debug mode'								],
	['file|f=s',	'filename containing output of IOS "show ip bgp" to parse'		],
	['holdtime|h=i','Hold timer (default 180 seconds)'					],
	['hintsubnets|i','Hint at which subnets can be used (overrides all other options)'	],
	['lines|l=i',	'number of lines in the input file to parse (default=unlimited)'	],
	['prefix|p=s',	'name to prefix output files with (default = exacfg)'			],
	['subnets|s=s@','multiple subnets <hostip>/<mask> of target/DUT (mandatory), this can and should be specified multiple times.'    ],
	['help|h',	'this help'								],
);

if ($opt->hintsubnets && -e $opt->file) {
}
elsif (($opt->help) || !( -e $opt->file )) {
	print($usage->text), exit;
}

my $as		= $opt->asnum	|| 64511;
my $cores 	= $opt->cores 	|| 1;
my $fileprefix 	= $opt->prefix 	|| 'exacfg';
my $holdtime	= $opt->holdtime|| 180;
my $lines 	= $opt->lines;
my $rfc1918 	= subnet_matcher qw(10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16);
my $rfc6666	= subnet_matcher qw(100::/64);

if ($opt->subnets && $opt->subnets->[0]) {
	foreach my $subnet (@{$opt->subnets}) {
		$subnets{$subnet} = $subnet;
	}
}
elsif ($opt->hintsubnets) {
}
else {
	die "No subnets specified\n";
}

open (FH, '<', $opt->file) || die "Can't open $!";
while (<FH>) {
	last if ($opt->lines && $linecount>=$opt->lines);
	chop;
	chop;
	my ($matched, $flags, $metric, $localpref, $weight, $path);
	if ($_=~m/^\*([>i]*)\s{0,2}(\d+\.\d+\.\d+\.\d+\/\d+|\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s{1,14}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s\?]+)/) {
		$matched = 'A';
		print "A. F=$1, P=$2, N=$3, M=$4, L=$5, W=$6, P=$7\n" if ($opt->debug);
		($flags, $prefix, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6, $7);
	}
	elsif ($_=~m/^\*([>i]*)\s{0,2}(\d+\.\d+\.\d+\.\d+\/\d+|\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s{1,}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s\?]+)/) {
		$matched = 'B';
		print "B. F=$1, P=$2, N=$3, L=$4, W=$5, P=$6\n" if ($opt->debug);
		($flags, $prefix, $nexthop, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^\*([>i]*)\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s{1,15}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s\?]+)/) {
		$matched = 'C';
		print "C. F=$1, N=$2, M=$3, L=$4, W=$5, P=$6\n" if ($opt->debug);
		($flags, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^\*([>i]*)\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s{1,18}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s\?]+)/) {
		$matched = 'D';
		print "D. F=$1, N=$2, L=$3, W=$4, P=$5\n" if ($opt->debug);
		($flags, $nexthop, $localpref, $weight, $path) = ($1, $2, $3, $4, $5);
	}
	elsif ($_=~m/^\*( i)\s{0,2}(\d+\.\d+\.\d+\.\d+\/\d+|\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s{1,14}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s\?]+)/) {
		$matched = 'E';
		print "E. F=$1, P=$2, N=$3, M=$4, L=$5, W=$6, P=$7\n" if ($opt->debug);
		($flags, $prefix, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6, $7);
	}
	elsif ($_=~m/^\*( i)\s{0,2}(\d+\.\d+\.\d+\.\d+\/\d+|\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s{1,}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s\?]+)/) {
		$matched = 'F';
		print "F. F=$1, P=$2, N=$3, L=$4, W=$5, P=$6\n" if ($opt->debug);
		($flags, $prefix, $nexthop, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^\*( i)\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s{1,15}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s\?]+)/) {
		$matched = 'G';
		print "G. F=$1, N=$2, M=$3, L=$4, W=$5, P=$6\n" if ($opt->debug);
		($flags, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^[\*>]+\s+([0-9a-fA-F:\/]{5,})\s+([0-9a-fA-F:]{5,})/) {
		$matched = 'H';
		print "H. P=$1, N=$2\n" if ($opt->debug);
		($prefix, $nexthop) = ($1, $2);
	}
	elsif ($_=~m/(\d+\.\d+\.\d+\.\d+\/\d+|[0-9a-fA-F:]{5,}\/\d+)$/) {
		$matched = 'I';
		print "I. P=$1\n" if ($opt->debug);
		$prefix = $1;
		$nexthop = undef;
	}
	elsif ($_=~m/^[\*> ]*([0-9a-fA-F:]{5,})$/) {
		$matched = 'J';
		print "J. N=$1\n" if ($opt->debug);
		$nexthop = $1;
	}
	elsif ($_=~m/^([>i]*)\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s{1,14}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s\?]+)/) {
		$matched = 'K';
		print "K. F=$1, N=$2, M=$3, L=$4, W=$5, P=$6\n" if ($opt->debug);
		($flags, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^\*( i)\s+(\d+\.\d+\.\d+\.\d+|[0-9a-fA-F:\/]{5,})\s+(\d+)\s+(\d+)\s+(\d+)\s+([0-9\(\)i\s\?]+)/) {
		$matched = 'L';
		print "L. F=$1, N=$2, M=$3, L=$4, W=$5, P=$6\n" if ($opt->debug);
		($flags, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^\s+([0-9a-fA-F:]{5,})\s+(\d+)\s+(\d+)\s+(\d+)\s+([0-9\(\)i\s\?]+)/) {
		$matched = 'M';
		print "M. N=$1, M=$2, L=$3, W=$4, P=$5\n" if ($opt->debug);
		($nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5);
	}
	elsif ($_=~m/^\s+(\d+)\s+(\d+)\s+(\d+)\s+([0-9\(\)i\s\?]+)/) {
		$matched = 'N';
		print "N. M=$1, L=$2, W=$3, P=$4\n" if ($opt->debug);
		($metric, $localpref, $weight, $path) = ($1, $2, $3, $4);
	}
	elsif ($_=~m/^\s+\s+(\d+)\s+(\d+)\s+([0-9\(\)i\s\?]+)/) {
		$matched = 'O';
		print "O. L=$1, W=$2, P=$3\n" if ($opt->debug);
		($localpref, $weight, $path) = ($1, $2, $3, $4);
	}
	elsif ($_=~m/h|r|\*d /) {
		$matched = 'HRD';
	}
	else {
		$matched = 'U';
		print "U. Unknown (line = $_)\n" if ($opt->debug);
	}

	next unless ($nexthop);
	next unless ($path);
	
	next if ( $rfc1918->($nexthop) || $rfc6666->($nexthop) );

	next if ($path=~m/^\s+0\s/ || $path eq 'i');

	$path=~s/\(|\)| i//g;
	$path=~s/\?//g;

	if (!$peers{$nexthop}{'as'} && $path=~m/^(\d+)\s*/) {
		$peers{$nexthop}{'as'} = $1;
	}
	elsif (!$peers{$nexthop}{'as'}) {
		next;
	}

	$prefix = &maskify($prefix) unless ($prefix=~m/\//);

	push (@{$peers{$nexthop}{'static'}}, "route $prefix next-hop $nexthop as-path [ $path ];");

	$linecount++;
}
close (FH);


my $filenum = 1;
my ($filehandle, $filename, $nexthopcount);

NH:
foreach my $nexthop (keys %peers) {

	my $rid 	= ($nexthop=~m/:/) ? '0.0.0.1' 		: $nexthop;
	my $family	= ($nexthop=~m/:/) ? 'ipv6 unicast' 	: 'ipv4 unicast';
	my $efamily 	= ($nexthop=~m/:/) ? 'inet6 unicast' 	: 'inet4 unicast';

	if ($opt->hintsubnets) {
		print "$nexthop\n";
		next NH;
	}

	my $neighbor;

	foreach my $sneighbor (keys %subnets) {
		if (subnet_matcher($subnets{$sneighbor})->(($nexthop))) {
			$neighbor = $sneighbor;
			$neighbor =~s/\/.*//g;
		}
	}	

	next NH unless ($neighbor);

	if ($filenum >= ($cores-1)) {
		$filenum = 1;
	}
	else {
		$filenum++;
	}

	$filename = $fileprefix . ".$filenum";
	close ($filehandle) if ($filehandle);
	open ($filehandle, '>>', $filename ) || die "Can't open $!";
	print $filehandle "neighbor $neighbor {\n\trouter-id $rid;\n\tlocal-address $nexthop;\n\tlocal-as $peers{$nexthop}{'as'};\n\tpeer-as $as;\n\thold-time $holdtime;\n\tfamily {\n\t\t$efamily;\n\t}\n\tstatic {\n";
	foreach (@{$peers{$nexthop}{'static'}}) {
		print $filehandle "\t\t$_\n";
	}
	print $filehandle "\t}\n}\n";
	$nexthopcount++;	
}
close ($filehandle) if ($filehandle);
exit;

sub maskify { 
        my $ip = shift;
        return unless ($ip);
        if ($ip=~m/^(\d+)\.\d+\.\d+\.\d+$/) {
                my $octet = $1;
                my $mask;
                if ($octet < 128) {
                        $mask = 8;
                }
                elsif ($octet < 192) {
                        $mask = 16;
                }
                else {
                        $mask = 24;
                }
                return $ip . '/' . $mask;
        }
        else {
                return $ip;
        }
}
