#ABSTRACT: A Perl wiki with some useful bells and whistles

package App::WebWebXNG;

=head1 SYNOPSIS

    # Handwaving the initialization, which will be needed...
    use App::WebWebXNG;
    my $wiki = App::WebWebXNG->new();
    $wiki->run;

=head1 DESCRIPTION

C<App::WebWebXNG> is a minimal wiki implemented in Perl. It concentrates on
providing easy-to-use access control over media types. This version is a
port of the original WebWebX from 1998 to a modern Perl stack. It is hoped
that this will, over time, provide a useful basic wiki that can be deployed
easily pretty much anywhere Perl can be installed.

=cut


use 5.38.0;
use Mojo::Base 'Mojolicious', -signatures;

=head1 CLASS METHODS

=head2 run

Called to launch the application.

=cut

sub run {
}

run unless caller();
