#!/usr/bin/perl

# check_multiprocs.pl
# Do a nagios check_proc on multiple processes 
#
# Syntax: check_multiprocs.pl -w l:h -c l:h proc1,w=l:h,c=l:h proc2 ...

# check_multiprocs - spawn nagios check_procs for multiple processes
# Rob Wolfram <propdf@hamal.nl>
#
# Changelog
# v. 0.9   - RSW - First working version.
# v. 0.9.5 - RSW - added the possibility for an argument check

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;

Getopt::Long::Configure('gnu_getopt',
                        'prefix_pattern=(--|-)',
                        'pass_through');

my ($warn,$crit,$cmd)=('1:','0:','/usr/lib64/nagios/plugins/check_procs');
my ($warntext,$crittext,$exitcode)=('','',0);
my ($conf,$quiet,$help,$options);
my @proclst=();
my %cwarn=();
my %ccrit=();
my %dasha=();

GetOptions('warn|w=s' => \$warn,
           'crit|c=s' => \$crit,
           'cmd|C=s'  => \$cmd,
           'conf|f=s' => \$conf,
           'quiet|q'  => \$quiet,
           'help|h'   => \$help,
           'options|o' => \$options,
          );

pod2usage(-verbose => 1) if $options;
pod2usage(-verbose => 2) if $help;

die "Command $cmd is not executable\n" if (not -x $cmd);

if ($conf) {
    open my $CONFFILE, "<", $conf or die "Cannot read $conf\n";
    while (<$CONFFILE>) {
        my $line=$_;
        chomp $line;
        next if (/^\s*(#.*)$/);
        $line =~ s/#.*//;
        $line =~ s/^\s*(\S.*\S)\s*$/$1/;
        my @pargs=split(',',$line);
        my $pname=shift(@pargs);
        $pname =~ s/^\s*(\S.*?)\s*$/$1/;
        if ($pname =~ /^\//) {
            $pname =~ s!^/-a/!!;
            $dasha{$pname}=1;
        }
        push @proclst, $pname if (not grep {$_ eq $pname} @proclst);
        for my $arg (@pargs) {
            $arg =~ s/^\s*(\S.*?)\s*$/$1/;
            if ($arg =~ /^w\s*=\s*(.*)/) {
                $cwarn{$pname}=$1;
            }
            elsif ($arg =~ /^c\s*=\s*(.*)/) {
                $ccrit{$pname}=$1;
            }
            else {
                print STDERR "Argument error: $arg\n" if not $quiet;
            }
        }
        $cwarn{$pname}=$warn if (not exists $cwarn{$pname});
        $ccrit{$pname}=$crit if (not exists $ccrit{$pname});
    }
}

for my $proc (@ARGV) {
    my @pargs=split(',',$proc);
    my $pname=shift(@pargs);
    if ($pname =~ /^\//) {
        $pname =~ s!^/-a/!!;
        $dasha{$pname}=1;
    }
    $dasha{$pname}=1 if ($pname =~ /^\//);
    my $pwarn=(exists $cwarn{$pname})?$cwarn{$pname}:$warn;
    my $pcrit=(exists $ccrit{$pname})?$ccrit{$pname}:$crit;
    for my $arg (@pargs) {
        $arg =~ s/^\s*(\S.*?)\s*$/$1/;
        if ($arg =~ /^w\s*=\s*(.*)/) {
            $pwarn=$1;
        }
        elsif ($arg =~ /^c\s*=\s*(.*)/) {
            $pcrit=$1;
        }
    }
    push @proclst, $pname if (not grep {$_ eq $pname} @proclst);
    $cwarn{$pname}=$pwarn;
    $ccrit{$pname}=$pcrit;
}

die "No process names specified\n" if (not scalar @proclst);

for my $proc (@proclst) {
    my @args=($cmd,"-w",$cwarn{$proc},"-c",$ccrit{$proc});
    push @args, (exists $dasha{$proc})?"-a":"-C";
    push @args, $proc;
    my $result=&Backticks(@args);
    chomp $result;
    if ($result =~ /^PROCS CRITICAL:/) {
        # Critical
        $exitcode=2;
        $result =~ s/^PROCS CRITICAL: //;
        $crittext.=", " if $crittext ne '';
        $crittext.=$result;
    }
    elsif ($result =~ /^PROCS WARNING:/) {
        $exitcode = 1 if (not $exitcode);
        $result =~ s/^PROCS WARNING: //;
        $warntext.=", " if $warntext ne '';
        $warntext.=$result;
    }
}

my $rettext="MULTIPROCS ";
if ($exitcode == 2) {
    $rettext.="CRITICAL: ".$crittext."\n";
}
elsif ($exitcode == 1) {
    $rettext.="WARNING: ".$warntext."\n";
}
else {
    $rettext.="OK: All named processes OK\n";
}
print $rettext;
exit $exitcode;


sub Backticks {
    my @arr=@_;
    my ($result,$pid, $CHILD);
    if ($pid = open ($CHILD,"-|")) {
        local $/;
        return <$CHILD>;
    }
    else {
        if ( ! defined $pid ) {
            exit $! if ($quiet);
            die "Cannot fork.\n";
        }
        if ( ! -x $arr[0] ) {
            exit $! if ($quiet);
            die "Cannot execute $arr[0]\n";
        }
        exec @arr;
    }
}

__END__

=head1 NAME

check_multiprocs.pl - combine multiple "check_procs" nagios checks 

=head1 SYNOPSIS

B<check_multiprocs.pl> [B<-f>|B<--conf> I<filename>] 
[B<-w>|B<--warn> I<low:high>] [B<-c>|B<--crit> I<low:high>] 
[B<-C>|B<--cmd> I</path/to/check_procs>] [B<-q>|B<--quiet>]
[I<process1[,w|c=low:high ...]> I<process2[,w|c=low:high ...]> I<...>

B<checkprocs.pl> B<-h>|B<--help>

B<checkprocs.pl> B<-o>|B<--options>

=head1 DESCRIPTION

This program combines multiple checks of the Nagios "check_procs" plugin.  The
process names to check can be specified either by a configuration file or on the
command line, but at least one process name must be specified. The number of
processes for "CRITICAL" and "WARNING" levels can be specified globally or per
process name (see CONFIGURATION) and default to "WARNING" if one or more named
processes do not run and "OK" otherwise. The program exits with a single line of
text and an exit value of 0 if the exit state is "OK", a value of 1 if the exit
state is "WARNING" and a value of 2 if the exit is "CRITICAL".

=head1 OPTIONS

=over 4

=item B<-f, --conf> I<filename>

Read I<"filename"> for process names to check. Processes on the command line are
added to the list of processes and "WARNING" or "CRITICAL" specifications on the
command line for the same process name override the specifications in this file.
See CONFIGURATION below for the syntax of this file and the specifications. The
first non-option argument on the command line indicates the start of command
line provided process names, optionally with "WARNING" or "CRITICAL"
specifications.  Both this argument as well as process names on the command line
are optional but at at least one process name must be specified by either means.

=item B<-w, --warn> I<low:high>

Override the global value for the number of running processes per named process
that should run for the program not to enter the "WARNING" state. See the
CONFIGURATION section below for the syntax. The default is that 0 running
processes for one or more named processes will cause a "WARNING" state. This
argument is optional.

=item B<-c, --crit> I<low:high>

Override the global value for the number of running processes per named process
that should run for the program not to enter the "CRITICAL" state. See the
CONFIGURATION section below for the syntax. The default is that the program does
not enter a "CRITICAL" state. If for a program both "WARNING" and "CRITICAL"
values apply, the "CRITICAL" value will take precedence. This argument is
optional.

=item B<-C>|B<--cmd> I</path/to/check_procs>

Override the default path to the I<check_procs> Nagios plugin. The default path
is set to I</usr/lib64/nagios/plugins/check_procs>. The plugin is a dependency
to this program. This argument is optional.

=item B<-q|--quiet>

Suppress non-fatal error output.

=item B<-h, --help>

Print the manpage.

=item B<-o, --options>

Print a short help, consisting of Usage and Options.

=back

=head1 CONFIGURATION

Either in a file (specified by the I<--conf> argument) or on the command line
(following all option arguments), one or more process names need to be passed
for which the number of running processes will be tallied. Along with the
process name the values for which a "WARNING" or "CRITICAL" state is rendered
can be specified but the specification is optional. Without it, the global
values apply.

Process names are checked on the base name of the command (the I<"-C"> flag for
I<check_proc>). If a process name starts with the slash (/) character, it is 
considered as part of the arguments to the command and the I<check_proc> flag
I<"-a"> is used instead. If you want to check on a process argument that does
not start with a leading slash, prepend the "process name" (in this case,
argument name) with the text "I</-a/>" (without quotes). This will be stripped
from the name and the rest will be considered an argument check.

Just like in the I<check_procs> plugin, the specifications take the format of
I<low:high> where both I<low> and I<high> denote a number of processes and
either one can be omitted but not both. The default value for "WARNING" is I<1:>
which means that if there is no running process with the specified name, a
"WARNING" is generated. The default value for "CRITICAL" is I<0:> which means
that it's not possible to generate that result for the specified process (there
should be at least 0 processes with the given name for the process not to be in
a "CRITICAL" state). The global values can be overridden with the I<--warn> and
I<--crit> arguments respectively.

If the values should be overridden for a specific process name in the
configuration file or on the command line, separate the process name and one or
both overrides with commas.  The process name should be first, and the overrides
should take the form of I<w=low:high> for "WARNING" overrides or I<c=low:high>
for "CRITICAL" overrides. E.g.:

I<sendmail,c=1:,w=3:50>

means that if no sendmail process runs, a "CRITICAL" is generated but if at
least one runs, but less than three or more than 50, a "WARNING" is generated.

If the process names are passed on the command line, multiple names should be
separate arguments (i.e., they should be separated with white space). If
override values are specified with the process name, care should be taken that
the name and its overrides are passed as a single argument.

If the process names (and optionally their overrides) are passed in the
configuration file, each process (along with its overrides) should be on a
separate line. Blanc lines and everything following a hash character (I<#>) in
the file are ignored.

=head2 CAVEAT

If this check is spawned via the NRPE agent on a Linux system with SELinux
enabled, and the configuration file is used, make sure that the nrpe process can
read the file. E.g. on a RHEL or CentOS system, if you place the file in
/etc/nagios it will get the context type "nagios_etc_t" assigned to it.
Processes with context type "nrpe_t" cannot read files with context type
"nagios_etc_t", the context type should instead be set to "nrpe_etc_t".

=head1 AUTHOR

Rob S. Wolfram E<lt>propdf@hamal.nlE<gt>

=head1 LICENSE

This program is licensed according to the GNU General Public License (GPL)
Version 2. A copy of the license text can be obtained from
E<lt>http://www.gnu.org/licenses/gpl.htmlE<gt> or by mailing the author. In
short it means that there are no restrictions on its use, but distributing the
program or derivative works is only allowed according to the terms of the GPL.

=cut

