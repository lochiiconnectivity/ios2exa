ios2exa
=======

Converts Cisco IOS IPv4 BGP LOC Rib dumps to exabgp for lab scenarios

Usage:

./ios2exa.pl <arguments>
	-a --asnum         AS Number of target / DUT (default 64511)
	-c --cores         number of configuration per core files to create
	                   (default 1)
	-d --debug         Debug mode
	-f --file          filename containing output of IOS "show ip bgp" to
	                   parse
	-h --holdtime      Hold timer (default 180 seconds)
	-i --hintsubnets   Hint at which subnets can be used (overrides all
	                   other options)
	-l --lines         number of lines in the input file to parse
	                   (default=unlimited)
	-p --prefix        name to prefix output files with (default = exacfg)
	-s --subnets       multiple subnets <hostip>/<mask> of target/DUT (mandatory)
	                   this can and should be specified multiple times.
	-h --help          this help



First, you must obtain the output of "show ip bgp" and optionally "show bgp ipv6 unicast"
from a Cisco IOS based system. Both of these should be concatenated and placed in a file
to which we point ios2exa. 

Here is an example using script(1) to create a file, called example.txt:

$ script example.txt
Script started, file is example.txt
$ ssh router -l cisco
cisco@router's password: 

router>terminal length 0
router>show ip bgp 
<snip>
router>show bgp ipv6 unicast
<snip>
router>exit
Connection to router closed.
$ exit
exit
Script done, file is example.txt


Now ios2exa can be invoked on this file, the important parameters are thus:

-a <asnum> = your AS number

-f <file> = this is the name of the file you just generated (example.txt in this example)

-s <subnets> = ip addresses with their subnet masks for which to generate peers 


in our example, the router 'router' is in AS64496 , and peers at an IXP , using the address
192.0.2.100 in 192.0.2.0/24.

We want exabgp to simulate all peers on this IXP that we peer with.

We would invoke ios2exa thusly:

./ios2exa.pl -a 64496 -f example.txt -s 192.0.2.100/24

This will generate a file, exacfg.1 which will contain simulations of all neighbors and 
their prefixes and some NLRI (mainly just AS_PATH)

If you would like to run mutliple exabgp processes (for instance, to run on machines
with multiple cores), the -c flag will help you split the configs up into a number
of files, one to be run on each core. 

For example, on an 8 core machine, to generate 8 exabgp configuration files:

./ios2exa.pl -a 64496 -c 8 -f example.txt -s 192.0.2.100/24

exabgp can then be used to create 8 independant single core processes

./exabgp exacfg.1 exacfg.2 exacfg.3 exacfg.4 exacfg.5 exacfg.6 exacfg.7 exacfg.8


