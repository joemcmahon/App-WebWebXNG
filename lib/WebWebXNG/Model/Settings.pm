package WebWebXNG::Model::Settings;
use Mojo::Base -base, -signatures;
use Carp ();
use Crypt::Passphrase;

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
  my $sql = <<SQL;
    select * from settings where settings.id = ?;
SQL
 return $self->sqlite->db
   ->query($sql, $self->fixed_id)
   ->rows;
}

=head2 save($settings_hash)

Takes the supplied hash and puts it into the fixed database location,
using insert or update as appropriate.

=cut

sub save($self, $settings_hash) {
  my %old_settings = $self->load;

  # Make a local copy to ensure we don't modify the caller's copy,
  # then make sure we're going to store it under the fixed id.
  my %new_settings = %$settings_hash;
  $new_settings{id} = $self->fixed_id;

  if (keys %old_settings) {
    # We had settings, so merge the new and old ones, with the new
    # ones getting priority. Then update the existing record.
    %new_settings = (%new_settings, %old_settings);
    $self->sqlite->db->update('settings', \%new_settings);
  } else {
    # We didn't have any settings, so insert the supplied ones.
    # XXX: How do we check for a failed settings create?
    $self->sqlite->db->insert('settings', \%new_settings);
  }
}

1;
