package WebWebXNG::LinkSyntax;
use Mojo::Base -base, -signatures;

# LinkPattern is the regular expression which matches page titles.
our $LinkWord    = "[A-Z][a-z]+";
our $LinkPattern = "(LinkWord){2,}";
our $TickedOrNot = "``$LinkPattern|$LinkPattern";

=head1 NAME

WebWebXNG::LinkSyntax - centralizes link syntax checking

=head1 DESCRIPTION

Centralizes the syntax checking of valid link names. Keeps us from having
to duplicate the regex that defines valid links all over the place.

=head1 METHODS

=head2 is_valid_linkname($purported_link)

Returns true if this string is a valid wiki linkword, false if not.

=cut

sub is_valid_linkname($word) {
  return $word =~ $LinkPattern;
}