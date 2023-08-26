use 5.38.0;

package App::WebWebXNG::Controller::Dev;

=head1 NAME

App::WebWebXNG::Controller::Dev - development controller

=head1 DESCRIPTION

This is a Mojolicious controller class that's here solely for
development. It contains no code actually used in the application.

=cut

use Mojo::Base 'Mojolicious::Controller', -signatures;

sub helloi ($self) {
  $self->render(text => 'Hello world!');
}
