package WebWebXNG::Model::Settings;
use Mojo::Base -base, -signatures;
use Carp ();
use Crypt::Passphrase;

has sqlite => sub { die "SQLite database must be supplied" };

=head1 NAME

WebWebXNG::Model::Settings - support functions for wiki settings

=head1 SYNOPSIS

    use WebWebXNG::Model::Settings;
    my $settings = WebWebXNG::Model::Settings->new;
    my $setting_values = $settings->load;
    ...
    $setting_values->{$some_key} = $new_value;
    $settings->save($setting_values);

=head1 DESCRIPTION

Centralizes the loading/saving of the wiki's global settings, formerly
done by hardcoding everything into globals. It was 25 years ago, don't judge.

Prevents multiple sets of settings by hardcoding an ID and always using that
one record to store the data.

=cut

# We only ever have one settings record, and this is it.
has fixed_id => 1;

=head1 METHODS

=head2 load()

Loads the current values of the settings and returns them as a hash.

=cut

sub load($self) {
  my $contents = $self->_read;
  if (not defined $contents) {
    # Insert record at fixed id, forcing defaults.
    my $contents = {
      id => $self->fixed_id,
      data_dir => "",
      lock_dir => "",
    };
    $self->sqlite->db->insert('settings', $contents);
    return $self->_read;
  }
  return $contents;
}

sub _read($self) {
  my $sql = <<SQL;
    select * from settings where settings.id = ?;
SQL
  return $self->sqlite->db
    ->query($sql, $self->fixed_id)
    ->hash;
}

=head2 save($settings_hash)

Takes the supplied hash and puts it into the fixed database location,
using insert or update as appropriate.

=cut

sub save($self, $settings_hash) {
  my $new_settings = $settings_hash;
  # Don't allow multiple sets of settings. We'll update by the fixed ID
  # anyway, so we don't care if there was an ID here.
  delete $new_settings->{id};
  foreach my $k (keys %$new_settings) {
    $self->sqlite->db->update('settings', {$k => $new_settings->{$k}}, {id => $self->fixed_id});
  }
  return $self->_read;
}

1;
