package WebWebXNG::Routes;
use v5.38;
use feature qw(signatures);

=head1 NAME

WebWebXNG::Routes - centralized route setup for WebWebXNG

=head1 SYNOPSIS

   use WebWebXNG::Routes;

    my $r = $self->routes;
    WebWebXNG::Routes->setup($r);

=head1 DESCRIPTION

Defines the routes for WebWebXNG. If there's a better static config way to do this,
we'll switch that in for this.

=head1 CLASS METHODS

=head2 setup($routes)

Adds the app's routes to the route object.

=cut

sub setup ($class, $r) {

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
