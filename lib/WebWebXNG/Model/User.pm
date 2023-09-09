package WebWebXNG::Model::User;
use Mojo::Base 'WebWebXNG::Model', -signatures;
use Carp ();
use Crypt::Passphrase;

sub add_user($self, $username, $first_name, $last_name, $password) {
  return $self
    ->sqlite
    ->db
    ->insert(
      'users',
      {
				name => $name,
        username => $username,
        first_name => $first_name,
        last_name => $last_name,
        password_hash => generate_password_hash($password),
      },
 )->last_insert_id;
}

sub set_user_verification($self, $username) {
  return $self->sqlite->db
    ->update('users',
      {verified => 1},
      {usename => $username},
    )->rows;
}

sub verified_user($self, $username) {
  my $sql = <<'  SQL';
    select verified from user
    where user.username = ?
  SQL
  return $self->sqlite->db
    ->query($sql, $username)->rows;
}

sub generate_password($password) {
    my $authenticator =  Crypt::Passphrase->new(
      encoder    => 'Argon2',
    );
    return $authenticator->hash_password($password);
}

sub validate_login($password) {
    my $sql = <<SQL;
      select password_hash from user
      where user.username = ?
    SQL

    # Usernames are unique, so there will be either 0 or 1 hit.
    my @users = $self->sqlite->db
      ->query($sql, $username)->rows;
    return 0 unless @users;


    my $authenticator =  Crypt::Passphrase->new(
      encoder    => 'Argon2',
    );
    return (
      $authenticator->verify_password($password, $users[0]) ? $user->id : 0
    );
}
