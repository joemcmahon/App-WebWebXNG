package Storable;
use Carp;

=head1 NAME

Storable -- manage storable objects

=head1 DESCRIPTION

A pretty good way to "flatten" most objects into scalars,
for ultimate storage into a DBM-like database.  The following 
objects may be flattened:

=over

=item *

The undefined value.

=item *

Simple scalars.

=item *

Reference to unblessed arrays, whose elements are themselves storable objects.

=item *

References (blessed or unblessed) to hashes, whose keys are printable 
scalars, and whose instance variables are themselves storable objects.

=back

Classes which wish to have their objects be storable may inherit 
from this class to use the OO-flavored interface; namely, the
flatten() instance method, and the inflate() class method (which
is essentially a constructor).

=head1 SYNOPSIS

You can use it in a non-OO way...

    # Flatten an object:
    my $fluffy = ['nice', 'and', 'fluffy'];
    my $flat = IU::Storable->flatten($fluffy);
    
    # Inflate it again (note that we pass in a reference for efficiency):
    my $fluffy = IU::Storable->inflate(\$flat);

Or you can inherit from it...

    package Stuff;
    @ISA = qw(IU::Storable);
    ... 
    my $flat = $fluffy->flatten;
    my $fluffy = Stuff->inflate(\$flat);

=head1 WARNING

Storable objects may *not* contain circular reference chains: that is, 
they cannot contain references to objects which refer back to themselves.
Circular reference chains will result in an infinite loop.

=head1 NOTES

Flattening of objects is recursive.  It reduces objects to streams
which use the special 2-byte sequence:

      [ \001 | depth ]

as separators.  The depth (0-255) indicates the nestedness of the
object.  If we represent the depth-n separator as [n], here's how
flattening at depth n works:

      undef                '-'
      scalar "FOO"         '$'   [n]  'F'  'O'  'O' 
      array of 3 elems     '@'   [n]  val1  [n]  val2  [n]  val3
      hash of 2 elems    'HASH'  [n]  key1  [n]  val1  [n]  key2  [n]  val2
      blessed hash        Class  [n]  key1  [n]  val1  [n]  key2  [n]  val2

=head1 VERSION

$Id: Storable.pm,v 1.1 1999/01/15 16:33:40 joe Exp joe $

=cut

use strict;

#------------------------------------------------------------
#
# UTILITIES
#
#------------------------------------------------------------

#------------------------------------------------------------
# flatten_it OBJECT,DEPTH,FLATREF
#------------------------------------------------------------
# I<Utility>.  Turn OBJECT into a scalar, adding it into FLATREF.

sub flatten_it {
    my ($o, $depth, $flatref) = @_;

    # Figure out the separator(s):
    my $SEP = pack("cc", 1, $depth);

    # Flatten, based on the reference type:
    my $oref = ref($o);
    if (!defined($o)) {            # undef
	$$flatref .= '-';
    }
    elsif (!defined($oref) || ($oref eq '')) {  # assume scalar
	$$flatref .= "\$$SEP$o";
    }
    elsif ($oref eq 'ARRAY') {     # unblessed array ref
	my $value;

	$$flatref .= '@';
	foreach $value (@$o) {
	    $$flatref .= $SEP;	    
	    flatten_it($value, $depth+1, $flatref);
	}
    }
    else {                         # assume blessed hash ref
	my ($key, $value);

	$$flatref .= $oref;
	while (($key, $value) = each %$o) {
	    defined($value) || next;
	    $$flatref .= "$SEP$key$SEP";
	    flatten_it($value, $depth+1, $flatref);
	}
    }
    1;
}

#------------------------------------------------------------
# inflate_it FLATREF,DEPTH
#------------------------------------------------------------
# Turn scalar ref back into an object.

sub inflate_it {
    my ($flatref, $depth) = @_;    # used to separate values
    my $o;    

    # Explode and get the type.  Note the efficiency hack. :-P
    my @exploded;
    if (!$depth)        { @exploded = split(/\001\000/, $$flatref) }
    elsif ($depth == 1) { @exploded = split(/\001\001/, $$flatref) }
    elsif ($depth == 2) { @exploded = split(/\001\002/, $$flatref) }
    elsif ($depth == 3) { @exploded = split(/\001\003/, $$flatref) }
    else {
	my $SEP = pack("cc", 1, $depth);
	@exploded = split(/$SEP/, $$flatref);
    }    
    my $otype = shift @exploded;

    # Inflate, based on type:
    if ($otype eq '-') {        # undef
	return undef;
    }
    elsif ($otype eq '$') {     # scalar
        return $exploded[0];
    }
    elsif ($otype eq '@') {     # array
        my $flatvalue;
        my @o = ();

        while (@exploded) {
            $flatvalue = shift(@exploded);
            push(@o, inflate_it(\$flatvalue, $depth+1));
        }
        return \@o;
    }
    else {                      # hash
        my ($key, $flatvalue);    
        my $o = {};

        while (@exploded) {
            $key       = shift(@exploded);
            $flatvalue = shift(@exploded);
            $o->{$key} = inflate_it(\$flatvalue, $depth+1);
        }
        bless $o, $otype;
        return $o;
    }
    undef;
}



#------------------------------------------------------------
#
# PUBLIC INTERFACE
#
#------------------------------------------------------------

#------------------------------------------------------------
# flatten [OBJECTREF]
#------------------------------------------------------------
# I<As instance method:> turn the "self" object into a scalar.
# I<As class method:> turn OBJECTREF argument into a scalar.

sub flatten {
    my $self = shift;

    # What should we flatten?
    my $fluffy = (ref($self) ? $self : shift); 
    my $flat = '';
    flatten_it($fluffy, 0, \$flat);
    $flat;
}

#------------------------------------------------------------
# inflate SCALARREF
#------------------------------------------------------------
# I<Class method:> turn scalar back into an object.

sub inflate {
    my $type = shift;
    my $flatref = shift;  
    ref($flatref)        or carp "please supply a SCALAREF as argument!";
    defined($$flatref)   or return undef;      # harmless kludge 
    inflate_it($flatref, 0);
}

#------------------------------------------------------------
1;

