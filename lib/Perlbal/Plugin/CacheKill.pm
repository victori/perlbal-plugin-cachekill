package Perlbal::Plugin::CacheKill;

use Perlbal;
use strict;
use warnings;

#
# Add $self->{service}->run_hook('modify_response_headers', $self);
# To sub handle_response in BackendHTTP after Content-Length is set.
# bless check
#if(ref($self->{service})  &&  UNIVERSAL::can($self->{service},'can')) {
#  $self->{service}->run_hook('modify_response_headers', $self);
#}
# LOAD CacheKill
# SET plugins        = cachekill

sub load {
    my $class = shift;
    Perlbal::register_global_hook('manage_command.cache_kill', \&cachekill_config);
    return 1;
}

sub unload {
    my $class = shift;
    return 1;
}

sub cachekill_config {
  my $mc = shift->parse(qr/^cache_kill\s+(?:(\w+)\s+)?(\S+)\s*=\s*(.*)$/,"usage: cache_kill [<service>] codes = <404,500,501>");
  my ($svcname,$cmd,$result) = $mc->args;
  
  unless ($svcname ||= $mc->{ctx}{last_created}) {
      return $mc->err("No service name in context from CREATE SERVICE <name> or USE <service_name>");
  }

  my $ss = Perlbal->service($svcname);
  return $mc->err("Non-existent service '$svcname'") unless $ss;

  if($result =~ /,/) {
    $ss->{extra_config}->{cache_kill} = [split(/,/,$result)];
  } else {
    $ss->{extra_config}->{cache_kill} = [$result];
  }
  
  Perlbal::log('info','Configured Perlbal::Plugin::CacheKill');
  
  return $mc->ok;
}

# called when we're being added to a service
sub register {
    my ( $class, $svc ) = @_;

    my $modify_response_headers_hook = sub {
        my Perlbal::BackendHTTP $be  = shift;
        my Perlbal::HTTPHeaders $hds = $be->{res_headers};
        my Perlbal::Service $svc     = $be->{service};
        return 0 unless defined $hds && defined $svc;
        
        foreach (@{$svc->{extra_config}->{cache_kill}}) {
          if($hds->response_code eq $_) {
            $hds->header( 'Cache-Control', 'no-cache, max-age=0, must-revalidate' );
            last;
          }
        }
        
        return 0;
    };

    $svc->register_hook( 'CacheKill', 'modify_response_headers', $modify_response_headers_hook );
    return 1;
}

# called when we're no longer active on a service
sub unregister {
    my ( $class, $svc ) = @_;
    $svc->unregister_hooks('CacheKill');
    $svc->unregister_setters('CacheKill');
    return 1;
}

1;

=head1 NAME

Perlbal::Plugin::CacheKill - Deny caching on certain response codes

=head1 SYNOPSIS

This plugin provides Perlbal the ability to deny caching on certain response codes. This plugin was made to sit between the application servers and squid. Squid 2.7 lacks the ACL ability to deny caching on response codes, Perlbal::Plugin::CacheKill takes care of appending No-Cache headers on specific response codes.

Configuration as follows:

  See sample/perlbal.conf
  
  -- Required Configuration Options
  
  cache_kill codes = <404,500,501,502,503>
    - Define the codes for perlbal to deny caching to. 

=head1 MANAGEMENT COMMANDS

  cache_kill <service name> codes = 500,501,502

=head1 AUTHOR

  Victor Igumnov, C<< <victori at fabulously40.com> >>

=cut