package WebWebXNG::Controller::Example;
use Mojo::Base 'Mojolicious::Controller', -signatures;

# This action will render a template
=head1 INSTANCE METHODS

=head2 welcome

Renders the dummy page for development.

=cut

sub welcome ($self) {

  # Render template "example/welcome.html.ep" with message
  $self->render(msg => 'Welcome to the Mojolicious real-time web framework!');
}

1;
