#!/usr/bin/perl

###  check_rundeck.pl

# Nagios plugin for checking Rundeck scheduled job execution status.  
# Written by Espen Blikstad

##############################################################################
# prologue
use strict;
use warnings;

use XML::Simple;
use LWP::UserAgent;

use Nagios::Monitoring::Plugin ;

use vars qw($VERSION $PROGNAME  $verbose $warn $critical $timeout $result);
$VERSION = '1.0';

# get the base name of this script for use in the examples
use File::Basename;
$PROGNAME = basename($0);


##############################################################################
# define and get the command line options.
#   see the command line option guidelines at 
#   https://nagios-plugins.org/doc/guidelines.html#PLUGOPTIONS


# Instantiate Nagios::Monitoring::Plugin object (the 'usage' parameter is mandatory)
my $p = Nagios::Monitoring::Plugin->new(
    usage => "Usage: %s -H <hostname>
    -t|--token=<token>
    -p|--project=<project>
    [ -a|--api=<version> ]", 
    version => $VERSION,
    blurb => 'Nagios Plugin for Rundeck.', 

	extra => "
This is a Nagios monitoring plugin for Rundeck. The plugin works with
the Rundeck Web API. This plugin reports last execution status of
every scheduled job within a Rundeck project.");


# Define and document the valid command line options
# usage, help, version, timeout and verbose are defined by default.


$p->add_arg(
	spec => 'hostname|H=s',
        help => '-H, --hostname=STRING\n',
        #desc => 'Hostname of the Rundeck instance to connect to',
	required => 1,
);

$p->add_arg(
	spec => 'token|t=s',
        help => '-t, --token=STRING\n',
        #desc => 'API token used for authentication',
	required => 1,
);

$p->add_arg(
	spec => 'api|a=s',
        help => '-a, --api=INTEGER\n',
        #desc => 'API version to use',
	required => 0,
        default => 18,
);

$p->add_arg(
	spec => 'project|p=s',
        help => '-p, --project=STRING\n',
        #desc => 'Rundeck project to check jobs in',
	required => 1,
);



# Parse arguments and process standard ones (e.g. usage, help, version)
$p->getopts;


# perform sanity checking on command line options
#if ( (defined $p->opts->result) && ($p->opts->result < 0 || $p->opts->result > 20) )  {
#    $p->nagios_die( " invalid number supplied for the -r option " );
#}
#
#unless ( defined $p->opts->warning || defined $p->opts->critical ) {
#	$p->nagios_die( " you didn't supply a threshold argument " );
#}


##############################################################################
# check stuff.

my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
my $xml = new XML::Simple;

my $host = $p->opts->hostname;
my $api_version = $p->opts->api;
my $api_token = $p->opts->token;
my $project = $p->opts->project;

# Return all scheduled jobs in the specified project
my $response = $ua->get("https://$host/api/$api_version/project/$project/jobs?scheduledFilter=true&authtoken=$api_token");
if(!$response->is_success) {
   $p->nagios_die("Could not retrieve jobs");
}

my $jobs = $xml->XMLin($response->decoded_content);

# Counter for job status
my $jobs_succeeded = 0;
my $jobs_failed = 0;
my $jobs_aborted = 0;
my $jobs_no = 0;
my @failed_jobs;

foreach my $job (keys %{ $jobs->{'job'} }) {
   my $id = $jobs->{job}{$job}{id};
   # Get the last execution of the specified job
   my $response = $ua->get("https://$host/api/$api_version/project/$project/executions?jobIdListFilter=$id\&max=1&authtoken=$api_token");
   my $executions = $xml->XMLin($response->decoded_content);
   if($response->is_success && $executions->{count} && $jobs->{job}{$job}{scheduleEnabled} eq "true") {

      if($executions->{execution}{status} eq "succeeded") {
         $jobs_succeeded++;
      }
      if($executions->{execution}{status} eq "failed") {
         $jobs_failed++;
         push(@failed_jobs, $executions->{execution}{job}{group} . "/" . $job);
         #print Dumper($execution);

      }
      #print $job . $executions->{execution}{status} ;
      #print "\n";
   }
   else {
      $jobs_no++;   
   }
}

my $msg = "$jobs_succeeded jobs succeeded, $jobs_failed jobs failed and $jobs_aborted jobs aborted\n";
my @sorted_jobs = sort { lc($a) cmp lc($b) } @failed_jobs;
foreach my $job (@sorted_jobs) {
   $msg = $msg . "'" . $job . "'" . " failed.\n";
}


if($jobs_failed) {
   $p->nagios_exit(CRITICAL, $msg);
} elsif($jobs_aborted) {
   $p->nagios_exit(WARNING, $msg);
} else {
   $p->nagios_exit(OK, $msg);
}


