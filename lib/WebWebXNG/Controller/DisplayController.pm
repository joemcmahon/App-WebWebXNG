package WebWebXNG::Controller::DisplayController;
use Mojo::Base 'Mojolicious::Controller', -signatures;

=head1 NAME

WebWebXNG::Controller::DisplayController - actually display a page

=head1 METHODS

=head2 display($c)

Loads page name from C<page> in the stash, fetches the page content
from the page archive, and then renders the page template.

=cut

sub display ($c) {
  # Stash has the page name in 'page'.
  my $page = $c->app->stash('page');
  $page = "dummy page";

  # When the page archive is hooked up, we'll load the appropriate
  # page from it. Right now we just dummy it out.
  my $content;
  # XXX: fetch page content
  $content = "dummy page content";

  $c->render(
    template => 'page',
    error    => $c->flash('error'),
    content  => "Content for $page: $content",
  );
}

1;
