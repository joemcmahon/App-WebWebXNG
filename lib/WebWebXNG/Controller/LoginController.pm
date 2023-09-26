package WebWebXNG::Controller::LoginController;
use Mojo::Base 'Mojolicious::Controller', -signatures;

=head1 NAME

WebWebXNG::Controller::LoginController - handle the login process

=head1 METHODS

=head2 index($c)

Redirects a bare invocation to the login page.

=cut

sub index ($c) {
    $c->render(
        template => 'login',
        error    => $c->flash('error')
    );
}

=head2 user_login($c)

Actually perform the login process.

=cut

sub user_login($c) {
    my $username = $c->param('username');                               # From the form
    my $password = $c->param('password');                               # From the form

    my $user_key = $c->app->users->validate_login($username, $password);
    if ($user_key) {
      $c->session(user => $user_key);
      $c->flash( message => 'Logged in');
      return $c->redirect_to('/FrontPage');
    }
    else {
        $c->flash( error => 'Login failed. (Are you validated?)');
        $c->redirect_to('login');
    }
}

1;
