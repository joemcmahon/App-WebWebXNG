package WebWebXNG::Controller::RegistrationController;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Try::Tiny;
use WebWebXNG::Model::User;
use WebWebXNG::LinkSyntax qw(is_valid_linkname);
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

sub user_registration($c) {

  my %fields = (
    first_name    => $c->param('firstName'),
    last_name     => $c->param('lastName'),
    username      => $c->param('username'),
    password      => $c->param('password'),
    confirm_pwd   => $c->param('confirm_password'),
    email         => $c->param("email"),
    confirm_email => $c->param("confirm_email"),
  );
  my($message) = fields_are_missing(%fields);
  if ($message) {
    $c->flash(error => $message);
    $c->redirect_to('register');
  }

  my ($username, $name_status) = build_username(%fields);
  my $user = $c->app->users->exists($username);
  if ($user) {
    $c->flash( error => "Username '$username' already exists.");
    $c->redirect_to('register');
  }

  # All fields present, user doesn't exist. Add the new user.
  my $added = $c->app->users->add(
    $fields{username},
    $fields{first_name},
    $fields{last_name},
    $fields{email},
    $fields{password}
  );
  if (!$added) {
    $c->flash( error => "Failed to add your username. We'll check the error and get back to you.");
    $c->redirect_to('register');
  };

  $c->flash( message => $name_status);
  $c->redirect_to('register');
}

=head2 fields_are_missing(%fields)

Field validation for the input fields. This code simply verifies that
we have the fields that we need and that they are properly consistent.
It does not do any database checking.

Returns undef if the fields are complete and consistent, or an error
message diagnosing the problem(s) if not.

=cut

sub fields_are_missing(%fields) {
  my @missing;
  push @missing, 'first name' if !$fields{first_name};
  push @missing, 'last name' if !$fields{last_name};
  push @missing, 'password' if ! $fields{password};
  push @missing, 'password confirmation' if ! $fields{confirm_pwd};
  push @missing, 'email' if ! $fields{email};
  push @missing, 'email confirmation' if ! $fields{verify};
  my $message;
  if (@missing) {
    my $are = "are";
    my $fields = "fields";
    if (@missing > 2) {
      my $final = pop @missing;
      my $start = join ', ', @missing;
      $message = ucfirst("$start, and $final");
    } elsif (@missing == 2) {
      $message = ucfirst(join " and ", @missing);
    } elsif (@missing) {
      $message = "@missing";
      $are = "is";
      $fields = "field";
    }
    return ucfirst $message;
  }
  # Make sure validation fields were supplied and accurate.
  if ($fields{email} ne $fields{verify}) {
    $message = 'Email and email verification must match.';
  }
  if ($fields{password} ne $fields{confirm_pwd}) {
    $message = 'Password and password confirmation must match.';
  }
  return $message;
}

=head2 build_username(%fields)

Takes the field inputs from the registration form and tries multiple
options to build a valid username for the user.

=over

=item 1 If a username was supplied and is a valid wiki link name, use it.

=item 2 If no username was supplied, try first name plus last name, as is.

=item 3 If this fails, try lowercasing both names and uppercasing the first character of each.

=item 4 If this fails, try converting the input to ASCII.

=back

The caller is responsible for letting the user know if the generated
username is a duplicate and indicating how to proceed. This function
just tries to build something that can be used.

=cut

sub build_username(%fields) {
  # Create the username if none was supplied. It needs to be a valid wikiname.
  my $name_is_valid = 0;
  my $name_status = "";

  # Eliminate any spaces or non-alpha characters.
  my $username = $fields{username};
  my $first_name = $fields{first_name};
  $first_name =~ s/\s+//g;
  $first_name =~ s/[[:digit:]]//g;
  my $last_name = $fields{last_name};
  $last_name =~ s/\s+//g;
  $last_name =~ s/[[:digit:]]//g;

  #  1. If the new user supplied a username,
  #     see if it meets the wikiname standard.
  $name_is_valid = is_valid_linkname($username);
  $name_status = "Using chosen username '$username'";

  # The following chain of unlesses is okay, because as
  # soon as the name is valid, we skip all the rest of them.
  # It could be rewritten "if (not $name_is_valid)" but
  # this reads more like an English description of the
  # choices we make.

  #  2. If there is no username, try the concatenation of first
  #     and last as is.
  unless ($name_is_valid) {
    $username = $first_name . $last_name;
    $name_is_valid = is_valid_linkname($username);
    $name_status = "Using username '$username'";
  }
  #  3. If that doesn't work, force the two names into
  #      the wikiname standard.
  #     XXX: We do have a user rename function,
  #         so this is less draconian than it looks.
  unless ($name_is_valid) {
    $username = ucfirst(lc($first_name)) . ucfirst(lc($last_name));
    $name_is_valid = is_valid_linkname($username);
    $name_status = "Using username '$username'";
  }
  # 4. If THAT doesn't work, then the user's name
  #    probably contains non-ASCII characters. Apologize
  #    for our ASCII-centrism and generate a name.
  #    XXX: Same here. If someone doesn't like the ASCIIfication,
  #         we can rename their account later.
  unless ($name_is_valid) {
    $first_name = ucfirst(lc(unidecode($first_name)));
    $first_name =~ s/\s(.)/uc($1)/ge;
    $last_name = ucfirst(lc(unidecode($last_name)));
    $last_name =~ s/\s(.)/uc($1)/ge;

    $username = ucfirst(lc(unidecode($first_name)))
              . ucfirst(lc(unidecode($last_name)));
    $username =~ s/\s//g;
    $name_status = "Unfortunately our wiki is ASCII-centric, so we've done our best to translate your name to ASCII. Using username '$username'";
  }
  return $username, $name_status . " Check your email for the validation link.";
}
1;
