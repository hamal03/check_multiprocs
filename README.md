# check_multiprocs
#### Combine multiple "check_procs" nagios checks

This script combines multiple checks of the Nagios "check_procs" plugin.
The process names to check can be specified either by a configuration file
or on the command line, but at least one process name must be specified.
The number of processes for "CRITICAL" and "WARNING" levels can be
specified globally or per process name. script is written in perl and depends
on the availability of the "check_procs" plugin. Use the "--help" option
for the complete man page.
