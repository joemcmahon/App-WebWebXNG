# ABSTRACT: Mojolicious core module for WebWebXNG

package WebWebXNG;

=head1 NAME

WebWebXNG - core Mojo module for the WebWebXNG wiki

=head1 SYNOPSIS

   use Mojo::File qw(curfile);
   use lib curfile->dirname->sibling('lib')->to_string;
   use Mojolicious::Commands;

   # Start command line interface for application
   # Mojolicious::Commands->start_app('WebWebXNG');

=head1 DESCRIPTION

Base module; loads config, sets up routes, runs the server.

=cut

use Mojo::Base 'Mojolicious', -signatures;

use WebWebXNG::Routes;

# This method will run once at server start
sub startup ($self) {

  # Load configuration from config file
  my $config = $self->plugin('NotYAMLConfig');

  # Configure the application
  $self->secrets($config->{secrets});
  #$self->initialize_auth;

  # Router
  my $r = $self->routes;
  WebWebXNG::Routes->setup($r);
}

1;
