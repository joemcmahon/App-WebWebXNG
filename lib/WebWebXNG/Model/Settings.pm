package WebWebXNG::Model::Settings;
use Mojo::Base 'WebWebXNG::Model', -signatures;
use Carp ();
use Crypt::Passphrase;

# We only ever have one settings record, and this is it.
has fixed_id => 1;

sub load($self) {
  my $sql = <<SQL;
    select * from settings where settings.id = ?;
  SQL
 return $self->sqlite->db
   ->query($sql, $self->fixed_id)
   ->rows;
}

sub save($self, $settings_hash) {
  my %old_settings = $self->load;

  # Get a local copy to ensure we don't modify the caller's copy,
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
);
