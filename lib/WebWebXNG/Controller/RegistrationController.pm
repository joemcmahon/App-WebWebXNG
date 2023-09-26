package WebWebXNG::Controller::RegistrationController;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Try::Tiny;
use WebWebXNG::Model::User;
use Text::Unidecode;

=head1 NAME

WebWebXNG::Controller::RegistrationController - handle user registration

=head1 METHODS

=head2 register

Displays the registration form.

=cut

sub register($c) {
  $c->render(
    template => 'register',
    error    => $c->flash('error'),
    message  => $c->flash('message')
  );
}

=head2 user_registration($c)

Actually register the user in the database. Reports any errors.

=cut
sub user_registration {
  my $c = shift;

  my $username = $c->param('username');
  my $password = $c->param('password');
  my $confirm_password = $c->param('confirm_password');
  my $first_name = $c->param('firstName');
  my $middle_name = $c->param('middleName');
  my $last_name = $c->param('lastName');
  my $email = $c->param("email");
  my $verify = $c->param("email_verify");

  my @missing = '';
  push @missing, 'email' if ! $email;
  push @missing, 'email verification' if ! $verify;
  push @missing, 'password' if ! $password;
  push @missing, 'password confirmation' if ! $confirm_password;
  push @missing, 'first name' if !$first_name;
  push @missing, 'last name' if !$last_name;
  if (@missing) {
    my $final = pop @missing;
    my $start = join ', ', @missing;
    my $missing = ucfirst("$start, and $final");
    $c->flash(error => "$missing fields are missing and are required.");
    $c->redirect_to('register');
  }

  # Make sure validation fields were supplied and accurate.
  if ($email ne $verify) {
    $c->flash(error => "Email and email verification must match.");
    $c->redirect_to('register');
  }
  if ($password ne $confirm_password) {
      $c->flash(error => 'Password and password confirmation must match.');
      $c->redirect_to('register');
  }

  # Create the username if none was supplied. It needs to be a valid wikiname.
  my $name_is_valid = 0;
  my $name_status = "";

  #  1. If the new user supplied a username, see if it meets the wikiname standard.
  my $checker = WebWebXNG::LinkSyntax->new;
  $name_is_valid = $checker->is_valid_linkname($username);
  $name_status = "Using chosen username '$username'";

  #  2. If they did not, try the concatenation of first and last as is.
  unless ($name_is_valid) {
    $username = $first_name . $last_name;
    $name_is_valid = $checker->is_valid_linkname($username);
    $name_status = "Using username '$username'";
  }
  #  3. If that doesn't work, force the two names into the wikiname standard.
  #     XXX: We do have a user rename in there somewhere, so this is less draconian
  #          than it looks.
  unless ($name_is_valid) {
    $username = ucfirst(lc($first_name)) . ucfirst(lc($last_name));
    $name_is_valid = $checker->is_valid_linkname($username);
    $name_status = "Using username '$username'";
  }
  # 4. If THAT doesn't work, then the user's name probably contains non-ASCII
  #    characters. Apologize for our ASCII-centrism and generate a name.
  unless ($name_is_valid) {
    $username = unidecode($first_name.$last_name);
    $name_status = "Unfortunately our wiki is ASCII-centric, and we've done our best to translate your name to ASCII. Using username '$username'";
  }

  my $user = $c->app->users->exists($username);
  if ($user) {
    $c->flash( error => "Username '$username' already exists.");
    $c->redirect_to('register');
  }

  # All fields present, user doesn't exist. Add the new user.
  my $added = $c->app->users->add($username, $first_name, $last_name, $email, $password);
  if (!$added) {
    $c->flash( error => 'Failed to add your username. Please use the contact form to tell us about it.');
    $c->redirect_to('register');
  };

  $c->flash( message => 'Your username has been created. Please check your email for the validation link.');
  $c->redirect_to('register');
}

1;
