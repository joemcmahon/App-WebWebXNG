#ABSTRACT: A Perl wiki with some useful bells and whistles

package App::WebWebXNG;

=head1 SYNOPSIS

    # Handwaving the initialization, which will be needed...
    use App::WebWebXNG;
    my $wiki = App::WebWebXNG->new();
    $wiki->run;

=head1 DESCRIPTION

C<App::WebWebXNG> is a minimal wiki implemented in Perl. It concentrates on
providing easy-to-use access control over media types. This version is a
port of the original WebWebX from 1998 to a modern Perl stack. It is hoped
that this will, over time, provide a useful basic wiki that can be deployed
easily pretty much anywhere Perl can be installed.

=cut


use 5.38.0;
use Mojo::Base 'Mojolicious', -signatures;

=head1 CLASS METHODS

=head2 startup

Mojo-required method to set up routes. This replaces WebWebX's
router hash.

=cut

# Stubbing all the functions to start.
sub startup ($self) {
  $self->routes->get('/SearchRefs')->to("dev#hello");    #HandleSearch
  $self->routes->get('/ViewPage')->to("dev#hello");      #HandleView
  $self->routes->get('/ShowDiffs')->to("dev#hello");     #HandleDiffs
  $self->routes->get('/EditLinks')->to("dev#hello");     #HandleLinks
  $self->routes->get('/EditLink')->to("dev#hello");      #HandleEditLink
  $self->routes->get('/EditPage')->to("dev#hello");      #HandleEdit
  $self->routes->get('/RestorePage')->to("dev#hello");   #HandleRestore
  $self->routes->get('/PurgePage')->to("dev#hello");     #HandlePurge
  $self->routes->get('/PageProps')->to("dev#hello");     #HandleProperties
  $self->routes->get('/PageInfo')->to("dev#hello");      #HandleInfo
  $self->routes->get('/RenamePage')->to("dev#hello");    #HandleRename
  $self->routes->get('/DeletePage')->to("dev#hello");    #HandleDelete
  $self->routes->get('/MailNotify')->to("dev#hello");    #HandleMail
  $self->routes->get('/EditMail')->to("dev#hello");      #HandleEditMail
  $self->routes->get('/RecentChanges')->to("dev#hello"); #HandleRecentChanges
  $self->routes->get('/SetAdminData')->to("dev#hello");  #EditAdminRecord
  $self->routes->get('/UnlockFile')->to("dev#hello");    #UnlockFile
  $self->routes->get('/ManageUsers')->to("dev#hello");   #ManageUsers
  $self->routes->get('/UserPWChange')->to("dev#hello");  #UserPWChange
  $self->routes->get('/GlobalPurge')->to("dev#hello");   #HandleGlobalPurge
}

if (caller) {
  app->start;
}
