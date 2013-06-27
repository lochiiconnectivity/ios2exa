#!/usr/bin/perl

#ios2exa - convert ios BGP Loc RIB to exabgp config

use strict;
use Getopt::Long::Descriptive;
use Net::Netmask;

my (%subnets, %peers);
my ($linecount, $prefix);

my ($opt, $usage) = describe_options(
	"$0 <arguments>",
	['asnum|a=i',	'AS Number of target / DUT (default 8426)'				],
	['cores|c=i',	'number of configuration per core files to create (default 1)'		],
	['file|f=s',	'filename containing output of IOS "show ip bgp" to parse'		],
	['holdtime|h=i','Hold timer (default 180 seconds)'					],
	['hintsubnets|i','Hint at which subnets can be used (overrides all other options)'	],
	['lines|l=i',	'number of lines in the input file to parse (default=unlimited)'	],
	['prefix|p=s',	'name to prefix output files with (default = exacfg)'			],
	['subnets|s=s@','comma seperated subnets <hostip>/<mask> of target/DUT (mandatory)'	],
	['help|h',	'this help'								],
);

if ($opt->hintsubnets && -e $opt->file) {
}
elsif (($opt->help) || !( -e $opt->file )) {
	print($usage->text), exit;
}

my $as		= $opt->asnum	|| 8426;
my $cores 	= $opt->cores 	|| 1;
my $fileprefix 	= $opt->prefix 	|| 'exacfg';
my $holdtime	= $opt->holdtime|| 180;
my $lines 	= $opt->lines;

if ($opt->subnets && $opt->subnets->[0]) {
	foreach my $subnet (@{$opt->subnets}) {
		if ($subnet=~m/(\d+\.\d+\.\d+\.\d+\/\d+)/) {
			my ($ip, $mask) = ($1, $2);
			$subnets{$ip} = new Net::Netmask($subnet);
		}
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
	my ($flags, $nexthop, $metric, $localpref, $weight, $path);
	if ($_=~m/^\*([>i]*)\s{0,2}(\d+\.\d+\.\d+\.\d+\/\d+|\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)\s{1,14}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s]+)/) {
		($flags, $prefix, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6, $7);
	}
	elsif ($_=~m/^\*([>i]*)\s{0,2}(\d+\.\d+\.\d+\.\d+\/\d+|\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)\s{1,}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s]+)/) {
		($flags, $prefix, $nexthop, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^\*([>i]*)\s+(\d+\.\d+\.\d+\.\d+)\s{1,15}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s]+)/) {
		($flags, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^\*([>i]*)\s+(\d+\.\d+\.\d+\.\d+)\s{1,18}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s]+)/) {
		($flags, $nexthop, $localpref, $weight, $path) = ($1, $2, $3, $4, $5);
	}
	elsif ($_=~m/^\*( i)\s{0,2}(\d+\.\d+\.\d+\.\d+\/\d+|\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)\s{1,14}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s]+)/) {
		($flags, $prefix, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6, $7);
	}
	elsif ($_=~m/^\*( i)\s{0,2}(\d+\.\d+\.\d+\.\d+\/\d+|\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)\s{1,}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s]+)/) {
		($flags, $prefix, $nexthop, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}
	elsif ($_=~m/^\*( i)\s+(\d+\.\d+\.\d+\.\d+)\s{1,15}(\d+)\s{4}(\d+)\s{1,}(\d+)\s{1}([0-9\(\)i\s]+)/) {
		($flags, $nexthop, $metric, $localpref, $weight, $path) = ($1, $2, $3, $4, $5, $6);
	}

	next unless ($nexthop);
	
	next if ($nexthop eq '80.168.0.25' || $nexthop eq '80.168.0.55' || $nexthop eq '10.255.255.10');

	next if ($path=~m/^\s+0\s/ || $path eq 'i');

	$path=~s/\(|\)| i//g;

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

	if ($opt->hintsubnets) {
		print "$nexthop\n";
		next NH;
	}

	my $neighbor;

	foreach my $sneighbor (keys %subnets) {
		if ($subnets{$sneighbor}->contains($nexthop)) {
			$neighbor = $sneighbor;
			$neighbor =~s/\/.*//g;
		}
	}	

	next NH unless ($neighbor);

	if ($filenum >= $cores) {
		$filenum = 1;
	}
	else {
		$filename++;
	}

	$filename = $fileprefix . ".$filenum";
	close ($filehandle) if ($filehandle);
	open ($filehandle, '>>', $filename ) || die "Can't open $!";
	print $filehandle "neighbor $neighbor {\n\trouter-id $nexthop;\n\tlocal-address $nexthop;\n\tlocal-as $peers{$nexthop}{'as'};\n\tpeer-as $as;\n\thold-time $holdtime;\n\tstatic {\n";
	foreach (@{$peers{$nexthop}{'static'}}) {
		print $filehandle "\t\t$_\n";
	}
	print $filehandle "\t}\n";
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
