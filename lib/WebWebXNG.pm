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
use Mojo::SQLite;

# The default page loaded if no page is given.
has front_page => 'FrontPage';

# This method will run once at server start
sub startup ($self) {

  # Load configuration from config file
  my $config = $self->plugin('NotYAMLConfig');

  # Merge settings from environment into config.
  $config = $self->_merge_from_env($config);

  # Configure the application
  $self->secrets($config->{secrets});
  my @failure_reasons = $self->_validate_config($config);
  die qq(Config failed: @{[join "\n", @failure_reasons]})
    if @failure_reasons;

  # Set up database and models
  my $sqlite_file = $config->{sqlite_file};
  $self->helper(
    sqlite => sub { state $sql = Mojo::SQLite->new($sqlite_file) }
  );
  $self->helper(
    users => sub { state $users = WebWebXNG::Model::Users->new(sqlite => $self->sqlite) }
  );
  $self->helper(
    settings => sub { state $settings = WebWebXNG::Model::Settings->new(sqlite => $self->sqlite) }
  );

  # Migrate to latest version if necessary
  my $path = $self->home->child('schema', 'db.schema');
  $self->sqlite->auto_migrate(1)->migrations->name('users')->from_file($path);
  $self->sqlite->auto_migrate(1)->migrations->name('settings')->from_file($path);

  # Router
  my $r = $self->routes;

  # Registration routes for user/password.
  # XXX: OAuth would be nice too.
  $r->get('/register')->to(
    controller => 'RegistrationController',
    action     => 'register'
  );
  $r->post('/register')->to(
    controller => 'RegistrationController',
    action     => 'user_registration'
  );

  # Login routes for user/password.
  $r->get('/login')->to(
    controller => 'LoginController',
    action     => 'index',
  );
  $r->post('/login')->to(
    controller => 'LoginController',
    action     => 'user_login'
  );

  # Add WebWebXNG stub routes. These will be implemented and tested one
  # at a time to ensure the page loads and renders as expected.
  $r->get('/search')->to("Example#welcome");           #HandleSearch
  $r->get('/view/:page')->to("Example#welcome");       #HandleView
  $r->get('/diffs/:page')->to("Example#welcome");      #HandleDiffs
  $r->get('/edit_links/:page')->to("Example#welcome"); #HandleLinks
  $r->get('/edit_link')->to("Example#welcome");        #HandleEditLink
  $r->get('/edit/:page')->to("Example#welcome");       #HandleEdit
  $r->get('/restore/:page')->to("Example#welcome");    #HandleRestore
  $r->get('/purge/:page')->to("Example#welcome");      #HandlePurge
  $r->get('/props/:page')->to("Example#welcome");      #HandleProperties
  $r->get('/info/:page')->to("Example#welcome");       #HandleInfo
  $r->get('/rename/:page')->to("Example#welcome");     #HandleRename
  $r->get('/delete/:page')->to("Example#welcome");     #HandleDelete
  $r->get('/notify')->to("Example#welcome");           #HandleMail
  $r->get('/notify/edit')->to("Example#welcome");      #HandleEditMail
  $r->get('/changes')->to("Example#welcome");          #HandleRecentChanges
  $r->get('/admin')->to("Example#welcome");            #EditAdminRecord
  $r->get('/unlock/:page')->to("Example#welcome");     #UnlockFile
  $r->get('/manage_users')->to("Example#welcome");     #ManageUsers
  $r->get('/password')->to("Example#welcome");         #UserPWChange
  $r->get('/purge/global')->to("Example#welcome");     #HandleGlobalPurge

  # All of these are probably also going to need POST endpoints as well.
  # Adding only the GETs for now. This enables us to pass the tests and
  # adds placeholders for the stuff we need to actually implement.

  # Named page with no explicit route opens that page.
  # Pages should all be in CamelCase form, so they won't conflict with
  # the other routes.
  $r->get('/:page')->to(
    controller => 'DisplayController',
    action     => 'display',
    # Page is already set by the route match.
  );

  # Root URL opens default front page.
  # Uses the same controller as the named-page route, but adds the
  # proper default page to the stash.
  $r->get('/')->to(
    controller => 'DisplayController',
    action     => 'display',
    page       => $self->front_page,
  );


}

sub _merge_from_env($self, $config) {
  my @keys = qw(sqlite_file);
  for my $key (@keys) {
    $config->{$key} = $ENV{uc($key)};
  }
  return $config;
}

sub _validate_config($self, $config) {
  my @reasons = ();
  push @reasons, "No database path supplied" unless $config->{sqlite_file};
  return @reasons;
}

1;
