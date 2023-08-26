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

# This method will run once at server start
sub startup ($self) {

  # Load configuration from config file
  my $config = $self->plugin('NotYAMLConfig');

  # Configure the application
  $self->secrets($config->{secrets});

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to('Example#welcome');

  # Add WebWebXNG stub routes.
  $r->get('/SearchRefs')->to("Example#welcome");    #HandleSearch
  $r->get('/ViewPage')->to("Example#welcome");      #HandleView
  $r->get('/ShowDiffs')->to("Example#welcome");     #HandleDiffs
  $r->get('/EditLinks')->to("Example#welcome");     #HandleLinks
  $r->get('/EditLink')->to("Example#welcome");      #HandleEditLink
  $r->get('/EditPage')->to("Example#welcome");      #HandleEdit
  $r->get('/RestorePage')->to("Example#welcome");   #HandleRestore
  $r->get('/PurgePage')->to("Example#welcome");     #HandlePurge
  $r->get('/PageProps')->to("Example#welcome");     #HandleProperties
  $r->get('/PageInfo')->to("Example#welcome");      #HandleInfo
  $r->get('/RenamePage')->to("Example#welcome");    #HandleRename
  $r->get('/DeletePage')->to("Example#welcome");    #HandleDelete
  $r->get('/MailNotify')->to("Example#welcome");    #HandleMail
  $r->get('/EditMail')->to("Example#welcome");      #HandleEditMail
  $r->get('/RecentChanges')->to("Example#welcome"); #HandleRecentChanges
  $r->get('/SetAdminData')->to("Example#welcome");  #EditAdminRecord
  $r->get('/UnlockFile')->to("Example#welcome");    #UnlockFile
  $r->get('/ManageUsers')->to("Example#welcome");   #ManageUsers
  $r->get('/UserPWChange')->to("Example#welcome");  #UserPWChange
  $r->get('/GlobalPurge')->to("Example#welcome");   #HandleGlobalPurge

  # All of these are probably also going to need POST endpoints as well.
  # Adding only the GETs for now. This enables us to pass the tests and
  # adds placeholders for the stuff we need to actually implement.
}

1;
