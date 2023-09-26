package WebWebXNG::Model::User;
use 5.38.0;

use Mojo::Base -base, -signatures;
use Carp ();
use Crypt::Passphrase;

use constant MINIMUM_PASSWORD_LENGTH => 10;

has sqlite => sub { die "SQLite database must be supplied" };

=head1 NAME

WebWebXNG::Model::User - user model methods

=head1 SYNOPSIS

    $app->add_user("UserName", "User", "Name", "theCodeOnMyLuggage"");
    $app->set_user_verification($username);
    print "$username is verified" if $app->verified_user($username);
    print "$username can log in"  if $app->validate_login($username, $password);

=head1 DESCRIPTION

WebWebXNG::Model::User adds the necessary methods to manage users in the database.
This is a minimal set of functions; we'll need some more, like password validation
and removing users (especially removing non-validated users).

=head1 METHODS

=cut

# _read is a utility used across many of the methods. It
# allows us to get around Mojo's limitation of a single
# primary key for each table in SQLite.
#
# It finds the user by username and returns a hash of the
# values for that user.
sub _read($self, $username) {
  my $sql = <<SQL;
    select * from users
    where users.username = ?
SQL
  return $self->sqlite->db
    ->query($sql, $username)
    ->hash // {};
}

=head2 exists($username)

Returns true if the user exists, false if not.

=cut

sub exists($self, $username) {
  return $self->_read($username)->{id};
}

=head2 add($username, $first, $last, $email, $password)

Adds a new user to the database. User's password hash is generated, and the user
is marked as "not validated"; this prevents random yoyos from registering.

Should return a status and an error, Go-style; currently just returns an ID
(success) or undef (failure).

=cut

sub add($self, $username, $first_name, $last_name, $email, $password) {
  # TODO: ban list for emails!
  return if $self->exists($username);

  # Minimal validation. All of the supplied fields have to be there
  # and be non-null.
  for my $field ($username, $first_name, $last_name, $email) {
    return unless $field;
  }
  return unless $self->_password_is_reasonable($password);

  # Insert if this user does not exist.
  return $self
    ->sqlite
    ->db
    ->insert(
      'users',
      {
        username => $username,
        first_name => $first_name,
        last_name => $last_name,
        password_hash => _hash_password($password),
        email => $email,
        verified => 0,
      },
 )->last_insert_id;
}

=head2 set_verified($username)

Turn on the verification flag for a user. Should be used
in concert with someother authentication mechanism (e.g.,
"enter the code from the email we sent you").

=cut

sub set_verified($self, $username) {
  my $id = $self->exists($username);
  return unless $id;

  return $self->sqlite->db
    ->update('users',
      {verified => 1},
      {id => $id},
    )->rows;
}

=head2 is_verified($username)

Returns true if the user is verified, false if not.

=cut

sub is_verified($self, $username) {
  my $id = $self->exists($username);
  return unless $id;

  my $sql = <<SQL;
  select * from users
  where id = ?
    and verified = 1;
SQL
  return $self->sqlite->db
    ->query($sql, $id)->hash;
}

=head2 validate_login($username, $password)

Returns true if the user can login with this password,
false if not. Note that we also check that the user is
verified and do not permit a login if they're not.

=cut

sub validate_login($self, $username, $password) {
  my $user = $self->_read($username);
  return unless $user->{verified};

  my $authenticator =  Crypt::Passphrase->new(
    encoder    => 'Argon2',
  );
  return (
    $authenticator->verify_password($password, $user->{password_hash}) ? $user->{id} : 0
  );
}

# Create a password hash to be stored in the user record.
sub _hash_password($password) {
    my $authenticator =  Crypt::Passphrase->new(
      encoder    => 'Argon2',
    );
    return $authenticator->hash_password($password);
}

# Returns true if the password meets our minimum requirements.
# XXX: We might want to put some or all of these in settings.
#      Though if we do, someone will turn everything off and
#      then be upset when their database fills up with craziness.
sub _password_is_reasonable($self, $p) {
  return unless length($p) > MINIMUM_PASSWORD_LENGTH;
  return unless $p =~ /\d/ # at least one digit
            and $p =~ /[[:upper:]]/ # at least one upper-case char
            and $p =~ /[[:lower:]]/ # at least one lower-case char
            and $p =~ /[^[:alnum:]]/ # at least one special
          ;
}

1;


