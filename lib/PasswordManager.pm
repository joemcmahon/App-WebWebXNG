package PasswordManager;

use File::Copy;

=head1 NAME

PasswordManager - Add, update and delete user accounts.

=head1 DESCRIPTION

    $admin = new PasswordManager("/path/to/my/file");
    die "Can't use password file: $why"
        if $why = $admin->unusable();

    # See if user exists
    unless ($admin->exists("JoeBlow")) {
        my $why = $self->unusable;
        if ($why) {
            die "Error looking up JoeBlow: $why" if $why;
        }
        # actually-doesn't-exist code goes here
    }
    else {
        # actually-exists code goes here
    }

    # Add new user.
    $admin->add("JaneDoe",$password)
        or die "Couldn't add JaneDoe: " , $admin->unusable();

    # Change password.
    $admin->update("JoeBlow",$password)
        or die "Couldn't change JaneDoe: " , $admin->unusable();

    # Remove a user.
    $admin->delete($account_name)
        or die "Couldn't delete JaneDoe: " , $admin->unusable();

    # Various verifications.
    die "bad user name: $why" 
        if $why = verify_name($account_name);
    die "bad password: $why" 
        if $why = verify_pwd($account_name);

    # set/reset attributes
    $admin->attr_add("JaneDoe","manager");
    $admin->attr_del("JoeBlow","adduser");

=cut

#-------------------------------------------------------------------------
# new(FILE) - Construct new object using the supplied password file.
#-------------------------------------------------------------------------

sub new {

   my ($class,$file) = @_;
   my $self = {};
   bless $self, $class;

   $self->{File} = $file;

   # Note: not cross-platform for all platforms!
   ($self->{Dir}) = ($file =~ /(^.*\/)/);
   my $dir = $self->{Dir};

   my $exists   = -e $file;
   my $readable = -r $file;
   my $writable = -w $file;

   if (!$exists) {
       $self->unusable("$file does not exist");
   }
   elsif (!-r $file or !-w _) {
       $self->unusable("file $file is not both readable and writable");
   }
   elsif (!-r $dir or !-w _) { 
       $self->unusable("directory $dir is not both readable and writable");
   }
   else {  # usable.
       $self->unusable(0);
   }

   $self;
}

#-------------------------------------------------------------------------
# unusable() - set/get why the file is unusable (if it is)
#-------------------------------------------------------------------------

sub unusable {
    my ($self, $why) = @_;
    $self->{Failure} = $why if defined $why; 
    $self->{Failure};
}

#-------------------------------------------------------------------------
# add(NAME,PASSWD) - add a new password file entry 
#-------------------------------------------------------------------------

sub add {

   my ($self, $name, $passwd, @attrs) = @_;
   my $passwdfile = $self->{File};
   my $encrypted = $self->_encrypt($passwd);

   $self->unusable(0);

   return 0 unless($self->_lock);

   unless (open HTPASSWD, ">>$passwdfile") {
       $self->unusable("Password file $passwdfile could not be opened: $!");
       return 0;
   }
   my $attrs = join(",",@attrs);
   print HTPASSWD join(":",$name,$encrypted,$attrs),"\n";
   close HTPASSWD;
   
   $self->_unlock;

   return 1;
}

#-------------------------------------------------------------------------
# exists(NAME) - check if user exists already 
#-------------------------------------------------------------------------

sub exists {

   my ($self, $username) = @_;
   my $passwdfile = $self->{File};

   $self->unusable(0);

   unless (open HTPASSWD, "$passwdfile") {
       $self->unusable("Password file $passwdfile could not be opened: $!");
   }

   my $name;
   my $password;
   my $found = 0;
   while (<HTPASSWD>) {
       chomp;
       ($name,$password,$attrs) = split /:/, $_;
       if ($name eq $username) {
	   $found = 1;
	   last;
       }
   }
   close HTPASSWD;
   my @attrs = (defined $attrs ? split(/,/,$attrs) : ());
   return $found ? ($name,$password,@attrs) : ();
}

#-------------------------------------------------------------------------
# update(USER,PASSWORD,ATTRS) - change password and/or attributes
#-------------------------------------------------------------------------

sub update {
   my $self = shift;
   my ($username, $newpasswd, @newattrs) = @_;
   
   my $encrypted = $self->_encrypt($newpasswd) if $newpasswd;
   my $passwdfile = $self->{File};
   my $newattrs = join(",",@newattrs);
   $newattrs = "" unless defined $newattrs;

   $self->unusable(0);

   return 0 unless $self->_lock;

   my $tmp = $self->{Dir}.".htpasswdtmp";
   unless(open TMP, ">".$tmp) {
      $self->unusable("couldn't open $tmp: $!");
      return 0;
   }

   unless(open HTPASSWD, "$passwdfile") {
      $self->unusable("couldn't open $passwdfile: $!");
      return 0;
   }

   my ($name, $passwd, $attrs);

   while (<HTPASSWD>) {
      chomp;
      ($name,$passwd,$attrs) = split /:/;
      $attrs ||= "";
      ($name ne $username) ? print TMP
                           : print TMP join(":",$username,
                                               ($encrypted 
                                                  ?  $encrypted : $passwd),
                                                (defined $newattrs
                                                  ? $newattrs : $attrs)
                                           );
       print TMP "\n";
   }
   close HTPASSWD;
   close TMP;

   move($tmp, $passwdfile);
   $self->_unlock;
   1;
}

#-------------------------------------------------------------------------
# delete(USER) - delete a user 
#-------------------------------------------------------------------------

sub delete {

   my ($self, $username) = @_;
   my $passwdfile = $self->{File};

   $self->unusable(0);

   $self->_lock;

   my $tmp = $self->{Dir}.".htpasswdtmp";
   unless(open TMP, ">".$tmp) {
      $self->unusable("couldn't open $tmp: $!");
      return 0;
   }

   unless(open HTPASSWD, "$passwdfile") {
      $self->unusable("couldn't open $passwdfile: $!");
      return 0;
   }

   while (<HTPASSWD>) {
      print TMP unless /^$username:/;
   }
   close HTPASSWD;
   close TMP;

   # Finished updating TMP file, now rename tmp to .htpasswd.
   move($tmp,$passwdfile);

   $self->_unlock;
   1;
}

#-------------------------------------------------------------------------
# verify(USER,PASSWORD) - verify a user is a valid one
#   returns: 1 - OK
#            0 - not OK
#        undef - couldn't check
#-------------------------------------------------------------------------

sub verify {
    my ($self, $user, $pw) = @_;
    my $passwdfile         = $self->{File};
    my ($lookup,$opw)      = $self->exists($user);

    return undef if $self->unusable();
    
    unless (defined $opw) {
        $self->unusable("User $user not found");
        return 0;
    }
    elsif ($opw eq $self->_encrypt($pw,substr($opw,0,2))) {
        $self->unusable(0);
        return 1;
    }
    else {
        $self->unusable("User $user password does not match");
        return 0;
    }
}
   
#-------------------------------------------------------------------------
# users() - return all current users
#-------------------------------------------------------------------------

sub users {
   my ($self) = @_;
   my $passwdfile = $self->{File};

   $self->unusable(0);

   unless (open HTPASSWD, "$passwdfile") {
       $self->unusable("Password file $passwdfile could not be opened: $!");
   }

   my $name;
   my $password;
   my @users = ();
   while (<HTPASSWD>) {
      ($name,$password) = split /:/, $_;
      push @users,$name;
   }
   close HTPASSWD;
   @users;
}

#-------------------------------------------------------------------------
# verify_name(NAME)
#-------------------------------------------------------------------------

sub verify_name {

   my ($self, $account) = @_;

   # Make sure we only have .htpasswd safe characters.
   (length($account) < 15) or 
      return "must be 14 or fewer characters.";
   ($account =~ /^[a-z0-9-_]+$/i )  or 
      return "may contain only alphabetics, numerics, and underscores.";
   0;

}

#-------------------------------------------------------------------------
# verify_password(PASSWORD)
#-------------------------------------------------------------------------

sub verify_password {

   # No restrictions on password
   0;

}

#-------------------------------------------------------------------------
# _encrypt(PASSWORD,[SALT])
#-------------------------------------------------------------------------
# encrypt a password

sub _encrypt {

   my ($self,$password,$salt) = @_;
   
   # if salt wasn't supplied then generate it.
   # 62 is the size of the array ('0'..'9','a'..'z','A'..'Z'), so
   # [int(62 * rand)] randomly picks one element from the array.
   srand(time);
   $salt = shift || (('0'..'9','a'..'z','A'..'Z')[int(62 * rand)] .
                     ('0'..'9','a'..'z','A'..'Z')[int(62 * rand)])
      unless $salt;

   crypt($password,$salt);
	
}

#-------------------------------------------------------------------------
#  attr_add
#-------------------------------------------------------------------------
# add one or more attributes to a user's entry.
sub attr_add {
   my ($self, $name, @attrs) = @_;

   $self->unusable(0);

   my ($oname, $passwd, @oldattrs) = $self->exists($name);

   if ($oname) {
       my %attrs;
       foreach my $attr (@oldattrs,@attrs) { 
          next unless defined $attr;
          $attrs{$attr}++;
       }
       @oldattrs = keys %attrs;
       $self->update($name,"",@oldattrs);
   }
   else {
       $self->unusable("$name is not a defined user");
       return 0;
   }

}

#-------------------------------------------------------------------------
#  attr_del
#-------------------------------------------------------------------------
# add one or more attributes to a user's entry.
sub attr_del {
   my ($self, $name, @attrs) = @_;

   $self->unusable(0);

   my ($oname, $passwd, @oldattrs) = $self->exists($name);
  
   if ($oname) { 
       my %attrs;
       my $attr;
       foreach $attr (@oldattrs) { $attrs{$attr}++ }
       foreach $attr (@attrs)    { delete $attrs{$attr}}
       @oldattrs = keys %attrs;
       return 1 if $self->update($name,"",@oldattrs);
       $self->unusable("Could not delete attributes for $name: " 
                       . $self->unusable());
       return 0;
   }
   else {
       $self->unusable("$name is not a defined user");
       return 0;
   }
}

#-------------------------------------------------------------------------
#  has_attr
#-------------------------------------------------------------------------
#  return true or false, depending on whether a user has the specified
#  attribute(s).
sub has_attr {
   my ($self,$name,@attrs) = @_;
   my (%attrs,@not_found);

   $self->unusable(0);

   my ($oname, $passwd, @oattrs) = $self->exists($name);
   if ($oname) {
       foreach my $check (@attrs) {
           push @not_found, $check unless grep /^$check$/,@oattrs;
       }
       $self->unusable("$name does not have: ",join(",",@not_found)) 
           if int(@not_found);
       return ! int(@not_found);
   }
   else {
       $self->unusable("$name is not a defined user");
       return 0;
   }
}

#-------------------------------------------------------------------------
#  _lock 
#-------------------------------------------------------------------------
# Loosely based on example from the Perl Cookbook.
# Use directory as a lock to avoid a race condition for the lock.

sub _lock {

   my $self = shift;
   my $passwdfile = $self->{File};
   my $lockfile = $passwdfile."_lock";
   my $timer = 10;

   $self->unusable(0);

   # Try creating lock directory, if successful then we got a lock,
   # otherwise try again after waiting 1 second - given up after 10 seconds.
   $self->unusable(0);
   while (1) {
      last if mkdir($lockfile, 0777);
      $self->unusable("Can't get lock on $lockfile: $!") if (--$timer < 1) ;
      sleep 1;
   }
   return (!$self->unusable());

}

#-------------------------------------------------------------------------
# _unlock
#-------------------------------------------------------------------------

sub _unlock {

   my $self = shift;
   rmdir($self->{File}."_lock");

}

#-------------------------------------------------------------------------

1;
