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

    my $db_object = $c->app->{_dbh};

    $c->app->plugin('authentication' => {
        autoload_user   => 1,
        wickedapp       => 'YouAreLogIn',
        load_user       => sub {
            my ($c, $user_key) = @_;
            my @user = $db_object->resultset('User')->search({
                id => $user_key
            });

            return \@user;
        },
        validate_user   => sub {
            my ($c, $username, $password) = @_;

            my $user_key = validate_user_login($db_object, $username, $password);

            if ( $user_key ) {
                $c->session(user => $user_key);
                return $user_key;
            }
            else {
                return undef;
            }
        },
    });

    my $auth_key = $c->authenticate($username, $password );

    if ( $auth_key )  {
        $c->flash( message => 'Logged in');
        return $c->redirect_to('/FrontPage');
    }
    else {
        $c->flash( error => 'Invalid credentials');
        $c->redirect_to('login');
    }
}

1;
