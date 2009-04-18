# A Perl/DBI collectd plugin for recording samples into a relational
# datanase. Currently only Postgres has been tested.
#
# Written by Bob Cotton <bob.cotton@gmail.com>
#
# This is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free
# Software Foundation; only version 2 of the License is applicable.

# Notes:
# Depends on Perl DBI and 
# A sample perl plugin config may look like this:
#
# <Plugin perl>
#     IncludeDir "<path to this file>"
#     LoadPlugin DBStore
#     <Plugin DBStore>
#         DBIDriver "Pg"
#         DatabaseHost "dbhost"
#         DatabasePort "5432"
#         DatabaseName "metrics_database"
#         DatabaseUser "metrics"
#         DatabasePassword "secret"
#      </Plugin>
# </Plugin>
package Collectd::Plugin::DBStore;
use strict;
use warnings;

use Collectd qw( :all );
use DBI;
use POSIX qw(strftime);

plugin_register (TYPE_INIT, 'DBStore', 'dbstore_init');
plugin_register (TYPE_CONFIG, 'DBStore', 'dbstore_config');
plugin_register (TYPE_WRITE, 'DBStore', 'dbstore_write');

my $dbh;
my $dbi_driver;
my $db_host;
my $db_port;
my $db_name;
my $db_user;
my $db_password;

sub dbstore_init
{
  if (!defined $dbi_driver) {
    plugin_log (LOG_ERR, "DBStore: No DBIDriver configured.");
    return 0;
  }

  if (!defined $db_host) {
    plugin_log (LOG_ERR, "DBStore: No DatabaseHost configured");
    return 0;
  }

  if (!defined $db_port) {
    plugin_log (LOG_ERR, "DBStore: No DatabasePort configured");
    return 0;
  }

  if (!defined $db_name) {
    plugin_log (LOG_ERR, "DBStore: No DatabaseName configured");
    return 0;
  }

  if (!defined $db_user) {
    plugin_log (LOG_ERR, "DBStore: No DatabaseUser configured");
    return 0;
  }

  if (!defined $db_password) {
    plugin_log (LOG_ERR, "DBStore: No DatabasePassword configured");
    return 0;
  }
  return 1;
}

sub dbstore_config
{
  my $config = shift;
  my $count = scalar(@{$config->{'children'}});
  for (my $i = 0; $i < $count; $i++) {
    my $key = $config->{'children'}[$i]->{'key'} || "";
    my $value = $config->{'children'}[$i]->{'values'}[0];
    if ($key eq "DatabaseHost") { $db_host = $value }
    elsif ($key eq "DatabasePort") { $db_port = $value }
    elsif ($key eq "DatabaseName") { $db_name = $value }
    elsif ($key eq "DatabaseUser") { $db_user = $value }
    elsif ($key eq "DatabasePassword") { $db_password = $value }
    elsif ($key eq "DBIDriver") { $dbi_driver = $value }
  }
  return 1;
}

sub dbstore_write
  {
    my $type = shift;
    my $ds   = shift;
    my $vl   = shift;
    my $return;

    if (scalar (@$ds) != scalar (@{$vl->{'values'}})) {
      plugin_log (LOG_WARNING, "DS number does not match values length");
      return;
    }

    my $dbh = DBI->connect("dbi:$dbi_driver:dbname=$db_name;host=$db_host;port=$db_port;",
                           "$db_user", "$db_password");
    unless(defined $dbh) {
      plugin_log(LOG_ERR, "DBStore: could not connect to database " . DBI->errstr);
      return 0;
    }
    
    my $stmt = $dbh->prepare("select insert_metric(?::timestamp, ?, ?, ?, ?, ?, ?, ?, ?)");
    unless(defined $stmt) {
      plugin_log(LOG_ERR, "DBStore: could not prepare statement " . $dbh->errstr);
      return 0;
    }
    
    my $timestamp = strftime("%G-%m-%d %H:%M:%S", localtime($vl->{'time'}));
    for (my $i = 0; $i < scalar (@$ds); ++$i) {
      $return = $stmt->execute($timestamp,
                               $vl->{'values'}->[$i],
                               $vl->{'host'},
                               @{$ds}[$i]->{'type'} == 1 ? 'GUAGE' : 'COUNTER',
                               $vl->{'plugin'},
                               $vl->{'plugin_instance'},
                               $type,
                               @{$ds}[$i]->{'name'},
                               $vl->{'type_instance'});
      if($return < 1) {
        plugin_log(LOG_ERR, "DBStore: insert failed: ". $dbh->errstr);
        $dbh->disconnect();        
        return 0;
      }
      $stmt->finish();
    }
    $dbh->disconnect();
    return 1;
  }
return 1;
