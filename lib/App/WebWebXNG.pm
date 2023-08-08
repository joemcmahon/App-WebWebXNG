#ABSTRACT: A Perl wiki with some useful bells and whistles

use strict;
use warnings;

package App::WebWebXNG;

=head1 NAME

App::WebWebXNG - core module for WebWebXNG

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

# XXX: This is bulk-imported from the original WebWebX. It obviously
#      can't stay like this (most of this is going to move into objects
#      instantiated by this modules instance), but this gets us started
#      on building up the app from zero.
# ----------------------------------------------------------
# You shouldn't need to change anything in this file unless
# you're a developer.
# ----------------------------------------------------------

# Yes, this is a huge number of globals. Bear with me as I bring WebWebX into
# the Perl5 world... At this point it is -w and strict clean; I will be
# creating classes and objects to hide more of these details as I go along.

# These globals were originally created by the CGI script. We're
# termination adding them here to get this to build.
use vars qw(
  $IconUrl
  $Max
  $HelpUrl
  $HighlightColor
  $CgiUrl
  $MailProgram
  $DebugAdminValues
  $PasswordFile
  $DataDir
  $SecureUrl
  $DisplayComments
  $DisplayContentOnly
);

# These are very CGI specific and will probably be able to be deleted.
use vars qw(
  $SERVER
  $SCRIPT_ALIAS
  $SECURE_DIR
  $STATIC_PATH
);

# Old webwebx.pl globals.
use vars qw(
  $PageArchive
  $ScriptName
  $ScriptUrl
  $SigninUrl

  $UserAdmin

  $LinkWord
  $LinkPattern
  $TickedOrNot
  $SearchForm
  $ReferencePattern
  $ImagePattern
  $OtherSeparator
  $FieldSeparator
  $HighlightColour
  $DefaultPage
  $IconLinks
  $AdminEmail
  $MaxRecentChanges
  $SearchPage

  $CurrentHost
  $ReadAccess
  $EditAccess
  $ModifyAccess
  $AdminRec
  $AdminUser
  $MailPage
  $MailSensitivity
  $BlockAnonUsers
  $SystemTitle
  $BodyAttributes
  $MenuBackground
  $CuteIcons
  $AggressiveLocking
  $AnonAppendOnly
  $OnlyAdminCanUnlock

  $Today
  $dbIsLocked
  $LockDir
  $PrintedHtmlHeader
  $CurrentUser
  %Cgi
  @GlobalStatus
  @DebugMsgs
  @LiteralUrl
  @EndTags
  $Debug
  $DebugRawPage
  $DebugEnvVars
  $DebugCgiValues
  $title
  $RawInput
  %page
  %links
  $link
);

use vars qw( @AdminInfoFields );

@AdminInfoFields = qw(
  AdminEmail
  AdminUser
  AggressiveLocking
  AnonAppendOnly
  BlockAnonUsers
  BodyAttributes
  CuteIcons
  Debug
  DebugRawPage
  DebugEnvVars
  DebugCgiValues
  DefaultPage
  HighlightColour
  IconLinks
  MailSensitivity
  MaxRecentChanges
  MenuBackground
  OnlyAdminCanUnlock
  SearchPage
  SystemTitle
);

#------------------------------------------------------------------------------
# Support libraries
#------------------------------------------------------------------------------
use Carp;
use Storable;
use PageArchive::RCS;
use Sys::Hostname;
use App::WebWebXNG::AuthManager;

$SIG{TERM} = sub {
  FatalError("Premature termination, see error log");
};

sub _setup_kludge {

  # Change this to the nameof the server where you're running WebWebX.
  $SERVER = "prtims.stx.com";

  # Change this to the ScriptAlias you're using in your httpd.conf.
  $SCRIPT_ALIAS = "whiteboard";

  # Change this to the secure directory you'll be using (that's the one
  # where you put the .htaccess file).
  $SECURE_DIR = "private";

  # Change this to the directory that contains the icons and help files
  # (remember this has to be accessible to your httpd!).
  $STATIC_PATH = "~joe/webwebx";

  ### The directory which stores all of the databases.
  $DataDir = "/home/joe/whiteboard";

  ### The URL of the CGI *directory* in which this script is stored.
  ### This is NOT the full URL!
  $CgiUrl = "http://$SERVER/$SCRIPT_ALIAS";

  ### The URL of the secured CGI *directory* in which a link to this
  ### script is stored. This is NOT the full URL!
  $SecureUrl = "http://$SERVER/$SCRIPT_ALIAS/$SECURE_DIR";

  ### The URL of the icon directory.
  $IconUrl = "http://$SERVER/$STATIC_PATH/icons";

  ### The URL of the help directory.
  $HelpUrl = "http://$SERVER/$STATIC_PATH/help";

  ### The name of the password file to be used. The following
  ### must be true:
  ###   - the file must be readable and writable by the web server users or group.
  ###   - the directory containing the file must also be readable and writable
  ###     by the web server user or group.
  ###   - this must be file file that your .htaccess file references.
  ### Do NOT make this file 777!
# XXX: This is going to be replaced by a completely different password management scheme.
#      Mojolicious::Plugin:: Authentication should suffice and stays with our low-dependencies policy.
#      Leaving this for now until we start replacing the password management.
  $PasswordFile = "/home/joe/whiteboard/.htpasswd";

  ### Location of your system's "sendmail" program. If you do not have
  ### send mail or you want to stop all email notification, leave this
  ### variable blank.
# XXX: Mojolicious::Plugin::Mail can do this. We should consider whether to make this a
#      generalized notification interface and then let people plug in what they want.
  $MailProgram = "/usr/lib/sendmail";
}

=head1 DISPLAY

These methods provide basic dispatch and page formatting code. The dispatch code
will almost certainly have to be replaced when we move to Mojolicious.

=cut

# ----------------
# HTML Subroutines
# ----------------

=head2  ReDo ($moderef, $hashref, $msg, $msg ...)

Re-execute a mode. Sets Cgi hash to values specified, and sets
status message (if one is supplied). Used to redispatch a request.

=cut

sub ReDo {
  note("ReDoing");
  my $sub   = shift;
  my $reset = shift;
  ReleaseLock();
  push @GlobalStatus, @_;
  %Cgi = %$reset;
  $ENV{REQUEST_METHOD} = "GET";
  &$sub;
}

=head2 ReShow ($page, $message, $message, ...)

Show the same page again, adding any messages as appropriate.

=cut

sub ReShow {
  my ( $page, @messages ) = @_;
  push @GlobalStatus, @messages;
  $Cgi{ViewPage} = $page;
  HandleView();
}

=head2 PrintHtmlHeader (title)

Print the head of the HTML page the first time it is called. Subsequent
calls produce no output.

=over

=item title - The title to place in the header.

=back

=cut

sub PrintHtmlHeader {
  return if $PrintedHtmlHeader;

  my ($PageTitle) = shift;

  unless ($PrintedHtmlHeader) {
    print <<EOF;
Content-type: text/html; charset=ISO-8859-1
Pragma: no-cache

<html>
<head>
<meta http-equiv="Content_type" content="text/html; charset=ISO-8859-1">
<title>$SystemTitle: $PageTitle</title>
</head>

<body $BodyAttributes>
<table width=\"100\%\" border=0><tr valign=top>
<td bgcolor=\"$MenuBackground\">

EOF
    PrintIcons();

    print "</td><td width=\"90\%\">\n\n";

    if ($SystemTitle) {
      print "<center><h2><i>$SystemTitle</i></h2></center>";
    }

    if ( scalar @GlobalStatus ) {
      note("Messages found to print");
      print qq(<table border=0 width="50%"><tr>);
      if ($CuteIcons) {
        unless ($PrintedHtmlHeader) {
          note("Printing Spot");
          print qq(<td>);
          print qq(<img src="$IconUrl/spot.gif" align=center )
            . qq(alt="Spot">);
          print qq(</td>);
        }
      }
      print "<td><tt><i>";
      print join "<br>", @GlobalStatus;
      print "</i></tt></td></tr></table>";
    }
    print "<hr><p>\n\n" unless $PrintedHtmlHeader;
    $PrintedHtmlHeader++;
  }
}

=head2 PrintHtmlFooter ()

Prints the foot of the HTML page.

=cut

sub PrintHtmlFooter {
  print "\n";
  note("Done");
  if ( $AggressiveLocking and defined $PageArchive ) {
    my ( $unlocked, $locker ) = $PageArchive->is_unlocked($title);
    print "<p><hr><address>Being edited by $locker</address>"
      unless $unlocked;
  }
  if ($Debug) {
    print "<hr>Debug trace:<pre>";
    map { print } @DebugMsgs;
    print "</pre>";
  }
  print "</td>\n</tr></table>\n\n";
  print "</body>\n</html>\n";
}

=head2 PrintIcons

Prints whatever icons are appropriate for the current page.

=cut

sub PrintIcons {
  $title = "" unless defined $title;
  print "<center>\n\n&nbsp;<br>";
  if ( $CurrentUser ne "anonymous" ) {
    print "<i>Signed in as $CurrentUser</i><p>";
  } else {
    print "<i>Not signed in (anonymous)</i><p>";
  }
  IconLink( "$ScriptUrl", "spot.gif", "Server Home" );
  print "<hr>\n";

  # If we were viewing an editable page, go back there after signin.
  # Otherwise, reinvoke the requested function.
  my $what_to_do = (
    $title
    ? "ViewPage=$title"
    : $RawInput
  );

  IconLink( "$SigninUrl?$what_to_do", "signin.gif", "Sign In" )
    if $CurrentUser eq "anonymous";

  # note that after this, if the page doesn't exist $Cgi{max} will be undef.
  if ( defined $PageArchive ) {
    $Cgi{max} = $PageArchive->max_version($title) unless defined $Cgi{max};
  } else {
    $Cgi{max} = "";
  }
  my $Back = '';
  if ($title) {
    $Back = "&Back=$title";
    $Back .= ",$page{Revision}"
      if exists $page{Revision}
      && defined $Cgi{max}
      && $page{Revision} < $Cgi{max};
  }
  if ( $Cgi{Back} ) {
    my ( $p, $r ) = split( ',', $Cgi{Back} );
    $p .= "&ar=$r" if defined $r && $r < $Cgi{max};
    IconLink( "$ScriptUrl?ViewPage=$p$Back",
      "left.gif", "Back To Previous Page" );
    print "<hr>\n";
  }
  if ( $title && $title ne 'RecentChanges' && $title ne 'SearchForm' ) {

    # Check if we are currently browsing the archive.
    if ( $Cgi{ar} && $page{Archive} ) {
      my ( $prev, $next, $rev, $max );
      $rev = $Cgi{ar};
      $max = $Cgi{max};
      my $Max_str = $Cgi{max} ? "&max=$Cgi{max}" : "";
      $prev = $rev - 1;
      $next = $rev + 1;

      if ($ReadAccess) {
        IconLink( "$ScriptUrl?ViewPage=$title$Back",
          "viewtop.gif", "Most Recent" );
        if ( $prev > 0 ) {
          IconLink( "$ScriptUrl?ViewPage=$title&ar=$prev$Max$Back",
            "b_archive.gif", "Older" );
        }
        if ( $next < $max ) {
          IconLink( "$ScriptUrl?ViewPage=$title&ar=$next$Max$Back",
            "f_archive.gif", "Newer" );
        }
      }

      if ($EditAccess) {
        IconLink( "$ScriptUrl?RestorePage=$title&ar=$Cgi{ar}$Max$Back",
          "restore.gif", "Restore" );
      }

      if ($ModifyAccess) {
        IconLink( "$ScriptUrl?PurgePage=$title$Back", "purge.gif", "Purge" );
      }

      print "<hr>\n";

      print "<small>";
      print $Cgi{ar};
      print " of ";
      print $Cgi{max};
      print "</small>\n";

      print "<hr>\n";

    } else {
      my $max_v = "unknown";
      $max_v = $PageArchive->max_version($title)
        if defined $PageArchive;
      if ($ReadAccess) {
        IconLink( "$ScriptUrl?ViewPage=$title", "view.gif", "View" );
        IconLink( "$ScriptUrl?SearchRefs=$title&Back=$title$Back",
          "viewrefs.gif", "View Refs" );

        if ( $page{Archive} && $page{Revision} > 1 ) {
          my $max  = $page{Revision};
          my $prev = $max - 1;
          IconLink( "$ScriptUrl?ViewPage=$title&ar=$prev" . "&max=$max$Back",
            "archive.gif", "Archive ($max_v versions)" );
        }

        IconLink( "$ScriptUrl?PageInfo=$title&Back",
          "info.gif", "Information" );
        IconLink( "$ScriptUrl?MailNotify=$title&Back",
          "mail.gif", "Set Mail Notification" )
          unless $CurrentUser eq "anonymous";
        print "<hr>\n";
      }

      if ($EditAccess) {
        IconLink( "$ScriptUrl?EditPage=$title", "edit.gif", "Edit" );
        IconLink( "$ScriptUrl?EditLinks=$title$Back",
          "links.gif", "Edit Links" )
          unless ( $CurrentUser eq "anonymous" and $AnonAppendOnly );
        if ( defined $PageArchive ) {
          my ( $unlocked, $locker ) = $PageArchive->is_unlocked($title);
          IconLink( "$ScriptUrl?UnlockFile=true$Back&" . "unlock_target=$title",
            "unlock.gif", "Break Edit Lock" )
            if !$OnlyAdminCanUnlock && !$unlocked;
        }
        print "<hr>\n";
      }

      if ($ModifyAccess) {
        IconLink( "$ScriptUrl?PageProps=$title$Back",
          "props.gif", "Properties" );
        IconLink( "$ScriptUrl?RenamePage=$title$Back", "rename.gif", "Rename" );
        IconLink( "$ScriptUrl?DeletePage=$title$Back", "delete.gif", "Delete" );
        print "<hr>\n";
      }
    }
  }

  note("MaxRecentChanges is $MaxRecentChanges");
  note("ScriptUrl is $ScriptUrl");
  note("title is $title");
  if ( $MaxRecentChanges > 0 ) {
    IconLink( "$ScriptUrl?RecentChanges=true$Back",
      "changes.gif", "Recent Changes" );
  }

  if ($SearchPage) {
    IconLink( "$ScriptUrl?ViewPage=$SearchPage$Back",
      "search.gif", "Search All Pages" );
  }

  IconLink( "$ScriptUrl?EditMail=true$Back",
    "editmail.gif", "Set My Email Address" )
    unless $CurrentUser eq "anonymous";

  print "<hr>\n";
  IconLink( "$HelpUrl", "help.gif", "Help" );
  print "<hr>\n";

  my $is_admin = $AdminUser && ( $CurrentUser eq $AdminUser );
  note("AdminUser is $AdminUser");
  note("$CurrentUser is the admin") if $is_admin;
  my ( $can_manage, $can_user );
  if ( defined $UserAdmin ) {
    $can_manage = (
           $UserAdmin->has_attr( $CurrentUser, "siteadmin" )
        or $is_admin
    );
    note( "$CurrentUser can" . ( $can_manage ? "" : "not" ) . " manage site" );
    $can_user = (
           $UserAdmin->has_attr( $CurrentUser, "useradmin" )
        or $is_admin
    );
    note( "$CurrentUser can" . ( $can_user ? "" : "not" ) . " manage users" );
  }
  IconLink( "$ScriptUrl?SetAdminData=true$Back", "admin.gif", "Change Setup" )
    if $can_manage;
  IconLink( "$ScriptUrl?ManageUsers=true$Back", "admin.gif", "Manage Users" )
    if $can_user;
  IconLink( "$ScriptUrl?UserPWChange=true$Back",
    "admin.gif", "Change my password" )
    if !$can_user
    and ( $CurrentUser ne "anonymous" );
  IconLink( "$ScriptUrl?UnlockFile=true$Back",
    "unlock.gif", "Unlock Arbitrary Entry" )
    if $can_manage;
  IconLink( "$ScriptUrl?GlobalPurge=true$Back",
    "admin.gif", "Global Purge of Archives" )
    if $can_manage;

  if ( $Cgi{Back} ) {
    print "<hr>\n";
    IconLink( "$ScriptUrl?ViewPage=$Cgi{Back}",
      "left.gif", "Back To Previous Page" );
  }
  print "\n<center>\n";
}

=head2 IconLink (link, icon, alt)

Prints an "icon" link, formatting appropriately for "icons on" or
"icons off".

=over

=item link - the CGI portion of the link

=item  icon - the icon to use

=item  alt  - the alt text to use

=back

=cut

sub IconLink {
  my ( $link, $icon, $alt ) = @_;
  print "<a href=\"$link\">";
  if ($IconLinks) {
    print "<img border=0 src=\"$IconUrl/$icon\" alt=\"$alt\">";
    print "</a><br>";
  } else {
    print "<font size=-1>" . $alt . "</font>";
    print "</a><p>";
  }
}

=head2 FatalError (message)

Prints an error message on the HTML page and exits the script.

=over

=item message - The message to display.

=back

=cut

sub FatalError {
  my ($message) = @_;

  PrintHtmlHeader("Error");

  $CuteIcons
    ? print "<img src=\"$IconUrl/oops.gif\" alt=\"Oops\"> <p>\n\n"
    : print "<h2>Error</h2>\n\n";

  print "$message. <p>\n\n";

  if ($AdminEmail) {
    print "If this error persists, please contact\n";
    print "<a href=\"mailto:$AdminEmail\">the administrator</a>\n";
    print "with details of the error. <p>\n";
  }

  PrintHtmlFooter;

  # Check if we have locked the database.
  if ( $ENV{REQUEST_METHOD} eq "POST" ) {
    ReleaseLock();
    note("Database unlocked");
  }
  croak($message);
}

=head2 ConvertAndPrintBody

Assumes that the HTML page has been retrieved from the database
into the hash "page". Converts the page body into sensible HTML
and print it out.

=cut

sub ConvertAndPrintBody {
  my ($PageTitle) = shift;

  keys %page || FatalError("Page not found in database");

  my $locked = "";
  if ( $AggressiveLocking and defined $PageArchive ) {
    my ( $unlocked, $locker ) = $PageArchive->is_unlocked($title);
    $locked = " <i>(locked)</i>" unless $unlocked;
  }
  if ( $Cgi{EditLinks} ) {
    print "<h3>Edit links in <a href=\"$ScriptUrl?EditPage=$PageTitle\">";
    print "$PageTitle</a></h3>\n\n";
  } else {
    print "<h3>$PageTitle$locked</h3>\n\n";
  }
  %links = ();
  %links = split( $OtherSeparator, $page{Links} ) if $page{Links};

  $_ = $page{PageText};

  # Convert special characters into HTML entities.
  s/&/&amp;/g;
  s/</&lt;/g;
  s/>/&gt;/g;
  my $ToEncode =
      "[^\n!#$%'()*+,\-./0123456789:;=?"
    . "\@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\]^_`"
    . "abcdefghijklmnopqrstuvwxyz{|}~]";
  my %EncodedHTML = (
    '"' => '&quot;',
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
  );
  s/($ToEncode)/defined($EncodedHTML{$1}) ? $EncodedHTML{$1} : ' '/eg;

  # help prevent cross-site scripting attacks

  s/\\\n/ /g;

  # Highlight any diffs if neccessary.
  my $hc = $HighlightColor;
  if ( $Cgi{ShowDiffs} ) {
    s/${FieldSeparator}s${FieldSeparator}/<font color=\"$hc\">/g;
    s/${FieldSeparator}e${FieldSeparator}/<\/font>/g;
  }

  foreach ( split( /\n/, $_ ) ) {

    # Check if the line is blank.
    if (/^\s*$/) {

      # If so, finish off any lists and continue with the next line.
      EmitCode( "", 0 );
      print "<p>\n";
      next;
    }

    # Replace any literal URLs with an escape code.
    my $counter = 0;
    while (
s/\b((webweb)|(http)|(ftp)|(mailto)|(news)|(file)|(gopher)):[^\s\<\>\[\]"'\(\)]*[^\s\<\>\[\]"'\(\)\,\.\?]/$FieldSeparator$counter$FieldSeparator/
    ) {
      $LiteralUrl[ $counter++ ] = $&;
    }

    # Deal with any lists, ordered lists or descriptions.
    s/^(#+) (.+) - /<dt>$2<dd>/ && EmitCode( "dl", length $1 );
    s/^(#+) \*/<li>/            && EmitCode( "ul", length $1 );
    s/^(#+) \d+\.?/<li>/        && EmitCode( "ol", length $1 );

    s/^(\t+)(.+) - /<dt>$2<dd>/ && EmitCode( "dl", length $1 );
    s/^(\t+)\*/<li>/            && EmitCode( "ul", length $1 );
    s/^(\t+)\d+\.?/<li>/        && EmitCode( "ol", length $1 );

    s/^\s// && EmitCode( "pre", 1 );

    # Deal with any emphasized text or horizontal rules.

    s/'{3}(.*?)'{3}/<strong>$1<\/strong>/g;
    s/'{2}(.*?)'{2}/<em>$1<\/em>/g;
    s/^----*/<hr>/;

    # Link any internal references.

    pos = 0;
    my $lastpos = 0;
    my $out     = "";
    while ( my ( $start, $link ) = /\G(.*?)($TickedOrNot)/g ) {
      my $change = AsInternalLink($link);
      $out .= "$start$change";
      pos = $lastpos + length($link) + length($start);
      $lastpos = pos;
    }
    $_ = $out . substr( $_, $lastpos );

    # Link any external references.

    s/\[Search\]/$SearchForm/;    # Special case for search form.
    s/\[($ReferencePattern)\]/AsExternalLink($1)/geo;

    # Replace any placeholders for literal URLs.

    s/$FieldSeparator(\d+)$FieldSeparator/AsLiteralUrl($1)/geo;

    # Print the resulting HTML.

    print "$_\n";
  }

  # Make sure any lists are finished off.

  EmitCode( "", 0 );
}

=head2 AsInternalLink (title)

Creates an internal link to the page title given as an
argument. If the page does not exist a linked question
mark will be linked directly to the edit page.

=over

=item title - The title of the page to link to.

=back

=cut

sub AsInternalLink {
  my ($NewTitle) = @_;
  return $1 if ( $NewTitle =~ /`($LinkPattern)/ );

  if ( $Cgi{EditLinks} ) {
    "<a href=\"$ScriptUrl?EditPage=$NewTitle&Back=$title\">$NewTitle</a>";
  } else {
    $PageArchive->defined($NewTitle)
      ? "<a href=\"$ScriptUrl?ViewPage=$NewTitle&Back=$title\">"
      . "$NewTitle</a>"
      : "$NewTitle"
      . "<a href=\"$ScriptUrl?EditPage=$NewTitle&parent=$title\">?</a>";
  }
}

=head2 AsEditableLink (title)

Creates a straight link to an editable internal page.

=over

=item title - the title of the page to link to

=back

=cut

sub AsEditableLink {
  my ($EditTitle) = @_;
  "<a href=\"$ScriptUrl?EditPage=$EditTitle&Back=$Cgi{Back}\">$EditTitle</a>";
}

=head2 AsExternalLink (ref)

Creates an external link to the URL represented by the
given reference.

=over

=item reference - Used to look up the external URL.

=back

=cut

sub AsExternalLink {
  my ($ref) = @_;
  my ($url) = $links{"r$ref"};
  if ( $Cgi{EditLinks} ) {
    return
"<a href=\"$ScriptUrl?EditLink=$ref&page=$title\"><font color=\"$HighlightColour\">[$ref]</font></a>";
  } else {
    defined $url
      ? (
      $url =~ /$ImagePattern/i
      ? return "<img src=\"$url\" alt=\"$ref\">"
      : return "<a href=\"$url\">[$ref]</a>"
      )
      : return "[$ref<a href=\"$ScriptUrl?EditLink=$ref&page=$title\">?</a>]";
  }
}

=head2 AsLiteralUrl

Creates a link to a literal URL stored in an array
called "LiteralUrl".

=cut

sub AsLiteralUrl {
  my ($number) = @_;
  my ($url)    = $LiteralUrl[$number];
  if ( $url =~ /^webweb:(\w*):($LinkPattern)/ ) {
    return "<a href=\"$CgiUrl/$1?ViewPage=$2\">webweb:$1:$2</a>$'";
  }
  if ( $url =~ /^webweb:(\w*)/ ) {
    return "<a href=\"$CgiUrl/$1\">webweb:$1</a>$'";
  }
  $url =~ /$ImagePattern/i
    ? "<img src=\"$url\" alt=\"image\">"
    : "<a href=\"$url\">$url</a>";
}

=head2 EmitCode

Deals with matching up the beginning and end tags for the
various lists which appear.

=cut

sub EmitCode {
  my ( $code, $depth ) = @_;

  # Close all the lists that deeper than this one.
  while ( @EndTags > $depth ) {
    my ($EndTag) = pop(@EndTags);
    print "</$EndTag>\n";
  }

  # Add new begin tags until the current depth is correct.
  while ( @EndTags < $depth ) {
    push( @EndTags, ($code) );
    print "<$code>\n";
  }

  # Close the last tag and open a new one if it wasn't the right type.
  if ( @EndTags and $EndTags[$#EndTags] ne $code ) {
    print "</$EndTags[$#EndTags]><$code>\n";
    $EndTags[$#EndTags] = $code;
  }
}

=head2 PrintEditPage

Prints an HTML form in which the user can edit the current
page.

=cut

sub PrintEditPage {
  $_ = $page{PageText};

  # Convert special characters into HTML entities.
  s/&/&amp;/g;
  s/</&lt;/g;
  s/>/&gt;/g;
  my $ToEncode =
"[^\n!#$%'()*+,\-./0123456789:;=?\@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\]^_`abcdefghijklmnopqrstuvwxyz{|}~]";
  my %EncodedHTML = (
    '"' => '&quot;',
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
  );
  s/($ToEncode)/defined($EncodedHTML{$1}) ? $EncodedHTML{$1} : ' '/eg;

  # help prevent cross-site scripting attacks

  s/\r\n/\n/g;
  print <<EOF;
<h2>Edit $title</h2>

<form method=POST action="$ScriptUrl">
  <textarea rows=16 cols=60 wrap=virtual name="PageText">
  $_
  </textarea><br>
  <input type=submit value="Save">
  <input type=reset value="Reset"> <p>
  <input type=hidden name=EditPage value="$title">
  <input type=hidden name=parent value="$Cgi{parent}">
  </form>
EOF

}

=head2 PrintAppendPage

Prints an HTML form in which the user can edit text to be appended
to the current page.

=cut

sub PrintAppendPage {

  $_ = $page{PageText};

  # Convert special characters into HTML entities.

  s/&/&amp;/g;
  s/</&lt;/g;
  s/>/&gt;/g;
  s/\r\n/\n/g;

  print <<EOF;
<h2>Append to $title</h2>\n\n";
<form method=POST action=\"$ScriptUrl\">\n\n";
Here's the original page, for reference only.<br>
Editing in this area <b>will not change the page</b>.
<br>
<textarea rows=8 cols=60 wrap=virtual name="OldText">
$_
</textarea>
<p>
Anything you enter below will be <b>appended</b> to the original text
<br>
<textarea rows=12 cols=60 wrap=virtual name="NewText"></textarea> <br>
<input type=submit value="Save">
<input type=reset value="Reset"> <p>

<input type=hidden name=EditPage value="$title">
<input type=hidden name=parent value="$Cgi{parent}">
<>/form>
EOF
}

=head2 PrintEditLinkPage

Prints an HTML form in which the user can edit an external
link from the current page.

=cut

sub PrintEditLinkPage {

  my $value = $links{"r$link"};
  print <<EOF;
<h2>URL for [$link] in $title</h2>

<form method=POST action="$ScriptUrl">

<input size=40 name=ref value="$value">
<input type=submit value="Save">

<input type=hidden name=EditLink value="$link">
<input type=hidden name=page value="$title">
</form>
EOF
}

=head2 PrintPropertiesPage

Prints an HTML form in which the user can edit the properties of the
current page.

=cut

sub PrintPropertiesPage {
  print <<EOF;
<h2>Edit properties for $title</h2>

<h4>Access control</h4>

<form method=POST action="$ScriptUrl">
  <table border=0>
    <tr>
      <td align=right>
        Read:</td>
      <td>
        <input size=40 name=ReadACL value="$page{ReadACL}">
      </td>
    </tr>
    <tr>
      <td align=right>
        Edit:
      </td>
      <td>
        <input size=40 name=EditACL value="$page{EditACL}">
      </td>
    </tr>
    <tr>
      <td align=right>
        Modify:
      </td>
      <td>
        <input size=40 name=ModifyACL value="$page{ModifyACL}">
EOF

  if ( $CurrentUser eq $page{Owner} || $CurrentUser eq $AdminUser ) {
    my $locked = $page{Locked}       ? "checked" : "";
    my $sticky = $page{Sticky}       ? "checked" : "";
    my $arch   = $page{Archive}      ? "checked" : "";
    my $note   = $page{Notification} ? "checked" : "";
    print <<EOF;
	</td>
      </tr>
      <tr>
        <td align=right>
	  Owner:
	</td>
	<td>
          <input size=20 name=Owner value="$page{Owner}">
	</td>
      </tr>
      <tr>
        <td>
	</td>
	<td>
	  <input type=checkbox name=Locked $locked> Locked <br>
	  <input type=checkbox name=Sticky $sticky> Sticky <br>
	  <input type=checkbox name=Archive $arch> Archive <br>
	  <input type=checkbox name=Notification $note> E-mail notification
EOF
  }
  print <<EOF;
        </td>
      </tr>
      <tr>
        <td>
        </td>
        <td>
          <input type=submit value="Save">
          <input type=reset value="Reset">
        </td>
      </tr>
    </table>\n\n";
    <input type=hidden name=PageProps value="$title">
    <input type=hidden name=Back      value="$title">
  </form>
EOF
}

=head2 DetermineTitle ($title,\%page)

Determines properly-formatted title for the current page.

=cut

sub DetermineTitle {
  my ( $title, $pageref ) = @_;
  my $prettyTitle = $title;
  $prettyTitle .= " (revision $$pageref{Revision})"
    if $$pageref{Archive} && $$pageref{Revision} > 0;
  return $prettyTitle;
}

=head2 PrintRenamePage

Prints an HTML form in which the user can rename the current page.

=cut

sub PrintRenamePage {
  print <<EOF;
<h2>Rename $title?</h2>

<form method=POST action="$ScriptUrl">
Rename $title to
<input size=20 name="new"> <p>
<input type=checkbox name="replacerefs" checked>
Replace all references to the old page. (uncheck when copying page)<br>
<input type=checkbox name="copy">
Do not delete the old page. (check when copying page)<p>
<input type=submit value="Rename">
<input type=hidden name=RenamePage value="$title">
<input type=hidden name=Back value="$title">
</form>
EOF

}

=head1 INPUT METHODS

These methods handle the processing of the GET or POST data.

=head2 GetCgiInput

Fetches and decodes CGI information from the GET or POST method
and decodes it, storing the resulting name/value pairs in the
hash "Cgi".

=cut

sub GetCgiInput {

  # Get the input from one or other method.
  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    $RawInput = $ENV{QUERY_STRING} || "ViewPage=$DefaultPage";
  }
  if ( $ENV{REQUEST_METHOD} eq "POST" ) {
    read( STDIN, $RawInput, $ENV{CONTENT_LENGTH} );
  }

  # Process it.
  $RawInput =~ s/\0//g;    # Kill nulls
  foreach my $item ( split( /&/, $RawInput ) ) {
    $_ = $item;                         # For simpler match and cleanup
    s/\+/ /g;                           # Convert + signs to spaces.
    s/\%(..)/pack("C", hex($1))/geo;    # Decode hex encoded characters.
    s/$FieldSeparator//g;               # Remove any field separator characters.

    # Cut up the name/value pair and store it in the hash.
    my ( $name, $value ) = split( /=/, $_, 2 );
    $Cgi{$name} = $value;
  }

  # Initialize a few things so we don't need to worry about undefined
  # interpolated variables.
  $Cgi{parent} ||= "";

  if ($DebugCgiValues) {
    my @output = "Cgi values:";
    foreach my $key ( sort keys %Cgi ) {
      my $a = $Cgi{$key};
      $a =~ s/\n/\\n/g;
      push @output, $key . " = " . $a;
    }
    note(@output);
  }
}

=head1 DATABASE HANDLING METHODS

=head2 RequestLock

Creates a lock directory to indicate exclusive access to the whole database.
This is different from access to a specific item, controlled by PageArchive's
locking mechanism. It is designed to serialize access to the database for
operations that could end up in trouble if a race condition occurred.

Sleeps for up to 30 seconds if the lock exists, after which time it will
abort.

=cut

sub RequestLock {
  my ($count) = 0;
  note("Attempting to lock $LockDir");

  while ( mkdir( $LockDir, 0555 ) == 0 ) {

    # Check if the directory exists, or print an error message if the
    # directory could not be created for any other reason.
    $! == 17 || FatalError("Can't create lock $LockDir: $!");

    # Check that we haven't timed out.
    $count++ < 30 || FatalError("Timed out waiting for lock $LockDir");

    # Wait one second before trying again.
    sleep(1);
  }
  note("Locking succeeeded after $count tries");
}

=head2 ReleaseLock

Frees exclusive access to the database by removing the lock
directory.

=head2

sub ReleaseLock {
  rmdir($LockDir);
  note("Lock released");
}

=head2 DefaultPage( page )

Ensure that all page fields are set to the default value
if they aren't already set; this avoids undefined values

=cut

sub DefaultPage {
  my $page = shift;
  my $create;
  $create++ unless defined $page;

  $page = {} if $create;
  my %create = (
    Owner      => $CurrentUser,
    CreateUser => $CurrentUser,
    CreateDate => $Today,
    CreateHost => $ENV{REMOTE_HOST} || $ENV{REMOTE_ADDR},
    TimeStamp  => time,
  );

  my %default = (
    Owner        => '',
    CreateUser   => '',
    CreateDate   => '',
    CreateHost   => '',
    PageText     => '',
    Revision     => 0,
    Locked       => '',
    Sticky       => '',
    Archive      => 'on',
    MailNotify   => '',
    Notification => 'on',
    LastMailed   => 0,
    EditUser     => '',
    EditHost     => '',
    EditDate     => '',
    TimeStamp    => '',
    ReadACL      => '',
    EditACL      => '',
    ModifyACL    => '',
    Links        => undef,
  );

  while ( my ( $k, $v ) = each %default ) {
    $page->{$k} = $v unless defined $page->{$k};
  }

  # if creating, can be more specific about a few things
  if ($create) {
    my @fields = keys %create;
    @{$page}{@fields} = @create{@fields};
  }
  return wantarray ? %{$page} : $page;
}

=head2 RetrievePage( title, revision )

Wrapper around PageArchive::get to ensure that all of the
page fields are there.  Prevents undefined access later...

=cut

sub RetrievePage {
  my ( $title, $revision ) = @_;
  my %page = $PageArchive->get( $title, $revision );
  if ($DebugRawPage) {
    foreach my $z ( keys %page ) {
      note("$z: $page{$z}");
    }
  }
  %page = DefaultPage( \%page );
}

=head2 GetPage

Retrieves the page with the given title from the main database,
or from the page archive if a specific archive number is also
given.

=cut

sub GetPage {
  my ( $title, $revision ) = @_;
  my (%page);

  # Determine revision to fetch. If a specific revision is supplied,
  # use that. If not, check to see if the $Cgi{ar} field has a revision,
  # and use that if there is one. If not, assume we want the most recent
  # version.
  unless ($revision) {
    if ( $Cgi{ar} ) {
      $revision = $Cgi{ar};
    } else {
      $revision = $PageArchive->max_version($title);
    }
  }

  # if the page doesn't exist, $revision will be undef, which will
  # cause some bellyaching.
  $revision = "" unless defined $revision;
  note("Loading revision $revision of $title");

  # Check that the title is valid.
  $title =~ /^$LinkPattern$/ || FatalError("$title is an invalid name");

  # Return the page if it exists.
  %page = $PageArchive->get( $title, $revision );

  if (%page) {
    if ( $Cgi{ar} ) {
      $Cgi{ar} && AccessArchive();
    }
    return DefaultPage(%page);
  }

  # Otherwise build a new one.
  else {
    note("Page $title does not exist, creating object for it");
    DefaultPage();
  }
}

=head2 AccessArchive

Accesses the archived page whose name is passed as the argument.
Depends on the value of $Cgi{ar} to determine which version to fetch.

=cut

sub AccessArchive {
  my ( %archive, %arpage );

  %arpage         = RetrievePage( $title, $Cgi{ar} );
  $page{PageText} = $arpage{PageText};
  $page{Links}    = $arpage{Links};
}

=head2 ArchiveCurrentPage

Stores a copy of the current page in its archive file.

=cut

sub ArchiveCurrentPage {
  my ( $title, $pageref ) = @_;

  # Don't archive the page at all if archiving is switched off.
  # Otherwise, store the information in the archive.
  $PageArchive->put( $title, \%page, $page{Revision} );
  note("Requesting archival as $title,$page{Revision}");
}

=head2 SaveCurrentPage

Saves the local copy of the current page to the DBM
hash.

=cut

sub SaveCurrentPage {

  # Convert the page hash into one scalar value and store it in
  # the database.
  $PageArchive->put( $title, \%page, $page{Revision} );
  note("Saving page as $title,$page{Revision}");
  $PageArchive->getError()
    and FatalError("Could not put page: $PageArchive->getError()");
}

=head2 UpdateContents

 Uses information from the user to update the contents
 of the current page.

=cut

sub UpdateContents {

  # Update the page with the user's details.
  $page{EditUser}  = $CurrentUser;
  $page{EditHost}  = $ENV{REMOTE_HOST};
  $page{EditDate}  = $Today;
  $page{TimeStamp} = time();

  # Update contents in the local copy of the page.
  $page{PageText} = $Cgi{PageText};

  # Remove any stale external links.
  %links = ();
  %links = split( $OtherSeparator, $page{Links} ) if defined $page{Links};
  my %newlinks;
  foreach my $link ( keys(%links) ) {
    $link =~ /^r($ReferencePattern)/ || next;
    my $searchfor = $link;
    $searchfor =~ s/^r($ReferencePattern)/$1/;
    $page{PageText} =~ /\[$searchfor\]/
      && ( $newlinks{$link} = $links{$link} );
  }

  my @list = %newlinks;
  $page{Links} = join( $OtherSeparator, @list );

  # Save the local copy of the page.
  $page{Revision}++ if $page{Archive};
  note("Page updated with user input");
  &SaveCurrentPage;
}

=head2 UpdateLinks

Updates the local pages copy of the current external links
and saves the page.

=cut

sub UpdateLinks {
  my (@list);

  # Update the links hash with the new value.
  $links{"r$link"} = $Cgi{"ref"};

  # Convert the links hash into one scalar value and store it
  # in the page hash.
  @list = %links;
  $page{Links} = join( $OtherSeparator, @list );
  note("linkes updated");

  # Save the local copy of the page.
  SaveCurrentPage;
}

=head2 UpdateProperties

Updates the current page's properties and saves it to the
DBM file.

=cut

sub UpdateProperties {

  # Update the local copy of the current page.
  $page{ReadACL}   = $Cgi{ReadACL};
  $page{EditACL}   = $Cgi{EditACL};
  $page{ModifyACL} = $Cgi{ModifyACL};

  if ( $CurrentUser eq $page{Owner} || $CurrentUser eq $AdminUser ) {
    $Cgi{Owner} && ( $page{Owner} = $Cgi{Owner} );
    $page{Locked}       = $Cgi{Locked};
    $page{Sticky}       = $Cgi{Sticky};
    $page{Archive}      = $Cgi{Archive};
    $page{Notification} = $Cgi{Notification};
  }

  # Save the local copy of the page.
  note("Properties updated");
  &SaveCurrentPage;
}

=head1 MAIN HANDLING METHODS

These methods process the received input for each page type
and actually execute the requests.

=head2 HandleSearch

Shows results of a search.

=cut

sub HandleSearch {

  # Check if there is a specific page to jump back to.

  if ( $Cgi{Back} ) {
    $title = $Cgi{Back};
    %page  = RetrievePage($title);
    GetAccessVars();
  }

  # Get the pattern and escape any regexp characters.
  my $pattern = $Cgi{SearchRefs};
  $pattern =~ s/[+?.*[\]{}|\\]/\\$&/g;

  PrintHtmlHeader("Search Results");
  print "<h2>Search Results</h2>\n\n";

  my ( $total, $matched, %page );
  note("Building iterator");
  my @keys = $PageArchive->iterator();
  FatalError("Could not build iterator.") unless int @keys;

  note("Starting search");
  my $key;
  foreach my $key (@keys) {
    my ( $t, $v ) = split( /,/, $key );
    %page = RetrievePage( $t, $v );
    $t =~ /^$LinkPattern$/ || next;
    $total++;

    if ( $key =~ /\b\w*($pattern)\w*\b/i
      || $page{PageText} =~ /\b($pattern)\b/i ) {
      $matched++;
      print &AsInternalLink($t);
      print " . . . . . . ";
      print "$& <br>\n";
    }
  }
  note("Search completed");
  print "<p><hr>\n";
  print "<small>";
  $matched = $matched || "No";
  print $matched == 1 ? "1 page" : "$matched pages";
  print " found out of $total.</small>\n";

  PrintHtmlFooter;
}

=head2 HandleView

Display a page, if possible.

=cut

sub HandleView {

  # Get the title and fetch the page from the database.
  $title = $Cgi{ViewPage};

  # Handle the special-purpose pages.
  if ( ($title) eq "RecentChanges" ) {
    $Cgi{RecentChanges} = "true";
    HandleRecentChanges();
    return;
  }
  %page = RetrievePage($title);
  keys %page or FatalError("Page was not returned");

  # Check the user is allowed to access the page.
  GetAccessVars();
  $ReadAccess || FatalError("You do not have permission to view this page");

  # Print the page contents.

  my $prettyTitle = DetermineTitle( $title, \%page );
  PrintHtmlHeader($prettyTitle);
  ConvertAndPrintBody($prettyTitle);
  PrintHtmlFooter();
}

=head2 HandleDiffs

Show a "diffs" page between two versions of a page.

=cut

sub HandleDiffs {

  # Get the title and fetch the page from the database.
  $title = $Cgi{ShowDiffs};
  %page  = RetrievePage($title);

  # Check the user is allowed to access the page.
  GetAccessVars();
  $ReadAccess || FatalError("You do not have permission to view this page");

  # Print the page contents.

  my $prettyTitle = DetermineTitle( $title, \%page );
  PrintHtmlHeader($prettyTitle);

  HighlightDiffs();
  ConvertAndPrintBody($prettyTitle);

  # print "\n<p><hr>\n";
  # print "<small>Amendments have been highlighted.</small>\n";

  PrintHtmlFooter();
}

=head2 HighlightDiffs

Show the differences on a word-by-word basis between an old and new
copy of a page.

=cut

sub HighlightDiffs {

  # Get the first archived page.
  #$Cgi{ar} = $page{Revision} - 1;
  my %archive = RetrievePage( $title, $page{Revision} - 1 );

  #$PageArchive->delete($Cgi{ar});

  # Chop the contents into bits.
  my (@curr) = split( /\b/, $page{PageText} );
  my (@ar)   = split( /\b/, $archive{PageText} );
  my ( @new, @diff );
  my ($index) = 0;

  # Loop through the archive words.
  my $curr;
  foreach my $word (@ar) {
    $index > $#curr && last;
    $curr = $curr[ $index++ ];
    if ( $word =~ /\W+/ && $curr =~ /\W+/ ) {
      push( @new, $curr );
      next;
    }
    if ( $word eq $curr ) {
      push( @new, $curr );
      next;
    }
    while ( $word ne $curr ) {
      push( @diff, $curr );
      $index > $#curr && last;
      $curr = $curr[ $index++ ];
    }

    push( @new, "${FieldSeparator}s${FieldSeparator}" );
    push( @new, @diff );
    push( @new, "${FieldSeparator}e${FieldSeparator}" );
    push( @new, $curr );

    @diff = ();
  }

  if ( int @diff ) {
    push( @new, "${FieldSeparator}s${FieldSeparator}" );
    push( @new, @diff );
    push( @new, "${FieldSeparator}e${FieldSeparator}" );
  }

  if ( $index <= $#curr ) {
    push( @new, "${FieldSeparator}s${FieldSeparator}" );
    while ( $index <= $#curr ) {
      push( @new, $curr[ $index++ ] );
    }
    push( @new, "${FieldSeparator}e${FieldSeparator}" );
  }
  $page{PageText} = join( '', @new );
}

=head2 HandleLinks

Edit the reference links in a page.

=cut

sub HandleLinks {
  if ( ( $AnonAppendOnly or $BlockAnonUsers )
    and $CurrentUser eq "anonymous" ) {
    FatalError( "Edit links not permitted for anonymous users.<br>"
        . "Please sign in first." );
  }

  # Get the title and fetch the page from the database.
  $title = $Cgi{EditLinks};
  %page  = RetrievePage($title);

  # Check the user is allowed to access the page.
  GetAccessVars();
  $EditAccess
    || FatalError("You do not have permission to edit the links on this page");

  # Print the page contents (the links will be made editable automatically).
  my $prettyTitle = DetermineTitle( $title, \%page );
  PrintHtmlHeader("Edit links in $prettyTitle");
  ConvertAndPrintBody($prettyTitle);

  print "<p><hr>\n";
  print "<small>\n";
  print "Owned by $page{Owner}.\n";
  $page{EditDate}
    && $page{EditUser}
    && print "Last edited $page{EditDate} by $page{EditUser}.";
  print "</small>\n";
  PrintHtmlFooter();
}

=head2 HandleEditLink

Edit an individual external link.

=cut

sub HandleEditLink {

  # Get the title and the name of the link.
  $title = $Cgi{page};
  $link  = $Cgi{EditLink};

  # Check the user is allowed to access the page.
  GetAccessVars();
  $EditAccess || FatalError("You do not have permission to edit this page");

  # Get the page from the database, and restore the link hash.
  %page  = RetrievePage($title);
  %links = {} if $page{Links} eq "-";
  %links = split( $OtherSeparator, $page{Links} );

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Edit [$link] in $title");
    PrintEditLinkPage();
    PrintHtmlFooter();
  } else {
    UpdateLinks;
    ReShow( $title, "Successfully updated [$link]." );
  }
}

=head2 CuteThanks

Show "Spot", the WebWeb mascot, in the thank-you page.

=cut

sub CuteThanks {
  print "<img src=\"$IconUrl/thanks.gif\" alt=\"Thanks\"> <p>\n\n";
}

=head2 HandleEdit

Edit or append to a page.

=cut

sub HandleEdit {

  # Get the title and fetch the page from the database.
  $title = $Cgi{EditPage};
  note("Editing $title");
  %page = RetrievePage($title);

  # Check the user is allowed to access the page.
  GetAccessVars();
  $EditAccess || FatalError("You do not have permission to edit this page");
  note("access permitted");

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    my $optional;
    if ($AggressiveLocking) {
      note("checking locks");
      my ( $unlocked, $locker ) = $PageArchive->is_unlocked($title);
      $optional =
        $OnlyAdminCanUnlock
        ? ""
        : "<br>You can use the <b>Break Edit Lock</b> "
        . "command from the toolbar if it has been a "
        . "long time - an hour or more - since editing "
        . "started";
      if ($unlocked) {
        note("not locked, locking");
        my ( $available, $locked_by ) =
          $PageArchive->lock( $title, $CurrentUser, $CurrentHost );
        FatalError(
          "This page is now being edited.<p>" . "It is in use by $locked_by" )
          unless $available;
      } elsif ( $locker !~ /^$CurrentUser/ ) {
        FatalError( "This page is still being edited.<p>"
            . "It is in use by $locker$optional" );
      }

      # Allow the user to edit it if he is the locker.
    }
    PrintHtmlHeader("Edit $title");
    if ( $CurrentUser eq "anonymous" and $AnonAppendOnly ) {
      PrintAppendPage;
    } else {
      PrintEditPage();
    }
    PrintHtmlFooter();

  } else {

    # Possibly an append. Append the text if so.
    if ( $CurrentUser eq "anonymous" and !$BlockAnonUsers ) {
      if ($AnonAppendOnly) {
        $Cgi{PageText} .=
            $page{PageText}
          . "\n\n-----\nAnonymous append at "
          . scalar(localtime) . "\n\n"
          . $Cgi{NewText};
        note("Appending");
      }
    }

    # Check if we should send email notification.
    InheritProperties();
    ArchiveCurrentPage( $title, \%page );
    UpdateContents();
    $page{MailNotify} and SendNotification();
    if ($AggressiveLocking) {
      $PageArchive->unlock($title)
        or FatalError("Unable to release edit lock for $title");
    }
    ReleaseLock();
    note("Page $title now unlocked");
    ReShow( $title, "$title was updated successfully." );
  }
}

=head2 SendNotification

Send e-mail notifications to interested parties.

=cut

sub SendNotification {
  my (@mail) = split( $OtherSeparator, $page{MailNotify} );
  my ( $name, $address, @addresses, $recp, $bcc );

  # Check that enough time has elapsed since the last notification.
  note("Checking elapsed time");
  time - $page{LastMailed} < ( $MailSensitivity * 60 ) && return;

  # Update the internal timestamp (Note that since this subroutine
  # is only called after POST requests, the DBM file is automatically
  # locked so the save operation is safe).
  $page{LastMailed} = time;
  note("Saving new timestamp");
  SaveCurrentPage();

  # Make sure the mail program has been defined.
  $MailProgram || return;

  # Assemble the existing addresses into the list.
  note("Building list of users");

  my %emails = $PageArchive->get( $MailPage, 0 );

  foreach my $name (@mail) {
    ( $address = $emails{$name} ) || next;
    push( @addresses, $address );
  }

  # Use the first address as the recipient and put the others on
  # the Bcc list (blind carbon copy).
  $recp = pop(@addresses);
  $bcc  = join( ',', @addresses );

  $recp || return;

  open( my $mail, "|", "$MailProgram" );
  print $mail <<EOF;

To: $recp
From: WebWebX
EOF

  $bcc && print MAIL "Bcc: $bcc\n";

  print MAIL <<EOF;
Subject: $title has changed

EOF
  $SystemTitle
    && print MAIL "\"$SystemTitle\"\n\n";
  print MAIL <<EOF;
This is an automatic message sent by WebWebX.

Page: $title
Changed by: $CurrentUser
URL: $ScriptUrl?ViewPage=$title


yours,
WebWebX

EOF

  close(MAIL);
}

=head2 HandleRestore

Restore a page from the archives.

=cut

sub HandleRestore {

  # Get the page from the database so that we can check access.
  $title = $Cgi{RestorePage};
  %page  = RetrievePage($title);

  # Check the user is allowed to access the page.
  GetAccessVars();
  $EditAccess
    || FatalError("You do not have permission to restore this page");

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {

    PrintHtmlHeader("Restore $title?");
    print <<EOF;
<h2>Restore $title?</h2>

Are you sure you want to overwrite the contents of $title? <p>
<form method=POST action="$ScriptUrl">
<input type=hidden name=RestorePage value="$title">
<input type=hidden name="ar" value="$Cgi{ar}">
<input type=hidden name="max" value="$Cgi{max}">
<input type=submit value="Restore">
<input type=hidden name="Back" value="$title">
</form>
EOF
    PrintHtmlFooter();

  } else {

    # Archive the original copy of the page.
    {
      my (%Cgi)  = ();
      my (%page) = RetrievePage($title);
      ArchiveCurrentPage( $title, \%page );
    }

    # Save a copy of the page with the restored contents.
    # Note that we have to increment the page's revision manually
    # because ArchiveCurrentPage() normally does it.
    $page{Revision} = ++$Cgi{max};
    SaveCurrentPage();

    # Check if we should send email notification.
    $page{Notification} && SendNotification;

    ReleaseLock();

    $Cgi{ar} = "";
    ReShow(
      $title,
      "$title version $Cgi{ar} restored ",
      "as new version $Cgi{max}"
    );
  }
}

=head2 HandlePurge

Page processing for the "purge" form.

=cut

sub HandlePurge {

  # Get the title of the page and fetch from the database.
  $title = $Cgi{PurgePage};
  %page  = RetrievePage($title);

  # Check the user is allowed to access the page.
  GetAccessVars();
  $ModifyAccess
    || FatalError("You do not have permission to remove all former versions.");

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Remove all former versions of $title?");
    print <<EOF;
<h2>Remove all former versions of $title?</h2>

Are you sure you want to delete all previous versions of this page (the current version will not be altered)? <p>

<form method=POST action="$ScriptUrl">
<input type=hidden name=PurgePage value="$title">
<input type=submit value="Purge">
<input type=hidden name=Back value="$title">
</form>
EOF
    PrintHtmlFooter();

  } else {
    $PageArchive->purge($title);
    $page{Revision} = 1;
    SaveCurrentPage;
    ReleaseLock();
    ReShow( $title,
      "All versions previous to the current one have been removed." );
  }
}

=head2 HandleGlobalPurge

Page processing for the "global purge" form.

=cut

sub HandleGlobalPurge {

  # User must be the administrator.
  FatalError("You are not the administrator")
    unless ( ( $AdminUser && ( $CurrentUser eq $AdminUser ) )
    or $UserAdmin->has_attr( $CurrentUser, "siteadmin" ) );

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Purge all archives for $SystemTitle?");
    print <<EOF;
<h2>Purge all archives for $SystemTitle?</h2>

Are you sure you want to purge <i>all</i> of the archives for <i>every</i> page? <p>
<form method=POST action="$ScriptUrl">
<input type=hidden name=GlobalPurge value="1">
<input type=submit value="Purge everything">
<input type=hidden name=Back value="$Cgi{Back}">
</form>
EOF

    PrintHtmlFooter();
  } else {
    my $here  = $title;
    my @names = $PageArchive->iterator();
    my $name;
    foreach my $name (@names) {
      my ( $t, $v ) = split( /,/, $name );
      next unless $t;
      %page = RetrievePage( $t, $v );
      note("$t had $v versions");
      $PageArchive->purge($t);
      $page{Revision} = 1;
      $title = $t;
      SaveCurrentPage();
    }
    ReleaseLock();
    ReDo(
      \&HandleGlobalPurge,
      { GlobalPurge => 1, Back => $Cgi{Back} },
      "All archives purged successfully."
    );
  }
}

=head2 HandleInfo

Display page ownership/control/update info.

=cut

sub HandleInfo {
  $title = $Cgi{PageInfo};
  %page  = RetrievePage($title);

  GetAccessVars();
  $ReadAccess
    || FatalError("You do not have permission to see this page's information");

  PrintHtmlHeader("Information about $title");
  print <<EOF;
<h2>Information about $title</h2>\n\n";
<h4>General Information</h4>\n\n";
<ul>\n";
  <li>Owned by $page{Owner}
  <li>Created $page{CreateDate} by $page{CreateUser} from $page{CreateHost}
  <li>Last edited $page{EditDate} by $page{EditUser} from $page{EditHost}
  <li>Revision $page{Revision}
</ul> <p>
EOF

  my ( $ra, $ma, $ea );

  if ( $page{ReadACL} || $page{EditACL} || $page{ModifyACL} ) {
    print "<h4>Access Control</h4>\n\n";
    print "<dl>\n";
    if ( $page{ReadACL} ) {
      $ra = $page{ReadACL};
      if ( $ra =~ /^\s*-\s*$/ ) {
        print "<dt><em>No read access</em>\n";
      } else {
        $ra =~ s/\+($LinkPattern)/AsInternalLink($1)/ge;
        print "<dt><em>Read access</em>\n";
        print "<dd>$ra\n";
      }
    }

    if ( $page{EditACL} ) {
      $ea = $page{EditACL};
      if ( $ea =~ /^\s*-\s*$/ ) {
        print "<dt><em>No edit access</em>\n";
      } else {
        $ea =~ s/\+($LinkPattern)/AsInternalLink($1)/ge;
        print "<dt><em>Edit access</em>\n";
        print "<dd>$ea\n";
      }
    }

    if ( $page{ModifyACL} ) {
      $ma = $page{ModifyACL};
      if ( $ma =~ /^\s*-\s*$/ ) {
        print "<dt><em>No modify access</em>\n";
      } else {
        $ma =~ s/\+($LinkPattern)/AsInternalLink($1)/ge;
        print "<dt><em>Modify access</em>\n";
        print "<dd>$ma\n";
      }
    }
    print "</dl> <p>\n";
  }

  my %emails = $PageArchive->get( $MailPage, 0 );
  my @mail   = split( $OtherSeparator, $page{MailNotify} );
  if (@mail) {
    print "Users to be notified:<ul>\n";
    foreach my $user (@mail) {
      print "<li>$user ($emails{$_})\n";
    }
    print "</ul><p>\n";
    print "Last notification was on ", scalar( localtime( $page{LastMailed} ) );
    print "<p>\n";
  } else {
    print "No users have requested notification.<p>\n";
  }

  if ( $emails{ $page{Owner} } || $AdminEmail ) {
    print "<h4>Send email to...</h4>\n\n";
    print "<ul>\n\n";

    if ( $emails{ $page{Owner} } ) {
      print "<li><a href=\"mailto:$emails{$page{Owner}}\">The owner</a>\n";
    }

    if ($AdminEmail) {
      print "<li><a href=\"mailto:$AdminEmail\">The administrator</a>\n";
    }

    print "\n</ul> <p>\n\n";
  }

  PrintHtmlFooter();
}

=head2 HandleProperties

Process control for the properties update form.

=cut

sub HandleProperties {
  $title = $Cgi{PageProps};
  %page  = RetrievePage($title);

  # Check the user is allowed to access the page.
  GetAccessVars();
  $ModifyAccess
    || FatalError("You do not have permission to edit this page's properties");

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Edit $title");
    PrintPropertiesPage();
    PrintHtmlFooter();
  } else {
    UpdateProperties();
    ReleaseLock();
    ReShow( $title, "Properties updated for this page." );
  }
}

=head2 HandleRename

Process control for the "rename" form.

=cut

sub HandleRename {
  $title = $Cgi{RenamePage};

  # Check that the page exists.
  $PageArchive->defined($title)
    || FatalError("$title hasn't been created yet");

  # Check the user is allowed to access the page.
  %page = RetrievePage($title);
  GetAccessVars();
  $ModifyAccess
    || FatalError("You do not have permission to rename this page");

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Rename $title");
    PrintRenamePage();
    PrintHtmlFooter();

  } else {
    $Cgi{new} =~ /^$LinkPattern$/ || FatalError("Invalid name given");

    $PageArchive->defined( $Cgi{new} )
      && FatalError("$Cgi{new} already exists");
    $PageArchive->put( $Cgi{new}, \%page, 1 );

    unless ( $Cgi{copy} ) {
      DeletePage();
    }

    my $refcount;
    if ( $Cgi{replacerefs} ) {
      $refcount = ReplaceReferences();
    }

    my $action = $Cgi{copy} ? "copied" : "renamed";

    # Change title temporarily so that icons point to the right page.
    {
      my ($old)   = $title;
      my ($title) = $Cgi{new};
    }

    ReleaseLock();
    ReShow(
      $Cgi{new},
      "$title was $action.",
      (
        $Cgi{replacerefs}
        ? "Global references were changed " . "($refcount updated)."
        : ""
      )
    );
  }
}

=head2 ReplaceReferences

Scan through the whole archive and replace all references to a page.

=cut

sub ReplaceReferences {
  my ($new) = $Cgi{new};
  my ($old) = $title;
  my ( $t, $n, $m, %page );

  my @titles = $PageArchive->iterator();
  foreach my $raw (@titles) {
    my ( $title, $v ) = split( /,/, $raw );
    $title =~ /^$LinkPattern$/ or next;
    $n++;

    %page = RetrievePage( $title, $v );
    if ( $page{PageText} =~ s/\b$old\b/$new/geo ) {
      $m++;
      SaveCurrentPage();
    }
  }

  $m = $m || "No";
  return ( $m == 1 ? "1 page" : "$m pages" ) . " out of $n";
}

=head2 DeletePage

Delete a single page from the archive.

=cut

sub DeletePage {
  $PageArchive->delete($title);
}

=head2 HandleDelete

Process control for the "delete" form.

=cut

sub HandleDelete {

  # Get the title of the page and fetch from the database.
  $title = $Cgi{"DeletePage"};
  %page  = RetrievePage($title);

  # Check the user is allowed to access the page.
  GetAccessVars();
  $ModifyAccess
    || FatalError("You do not have permission to delete this page");

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Delete $title?");

    print <<EOF;
<h2>Delete $title?</h2>

Are you sure you want to delete $title? <p>
<form method=POST action="$ScriptUrl">
<input type=hidden name=DeletePage value="$title">
<input type=submit value="Delete">
<input type=hidden name=Back value="$title">
</form>
EOF

    PrintHtmlFooter();

  } else {
    $page{Revision} = 0;
    $PageArchive->purge($title);
    DeletePage();
    ReleaseLock();

    PrintHtmlHeader("Deleted $title");

    print "<h2>Deleted $title</h2>\n\n";
    print "$title was deleted successfully. <p>\n";

    $CuteIcons && CuteThanks();
    PrintHtmlFooter();
  }
}

=head2 HandleMail

Process control for the form that adds/removes a user from the notification
list.

=cut

sub HandleMail {
  if ( $CurrentUser eq "anonymous" ) {
    FatalError( "Anonymous users are not allowed to set mail "
        . "notification.<br>Please log in first." );
  }

  # Get the title of the page and fetch from the database.
  $title = $Cgi{MailNotify};
  %page  = RetrievePage($title);

  GetAccessVars();

  # Get the mail list from the page and the user's address.
  my @mail   = split( $OtherSeparator, $page{MailNotify} );
  my @exists = grep /^$CurrentUser$/, @mail;

  # Make sure the user has added his mail address to the system.
  my %emails  = $PageArchive->get( $MailPage, 0 );
  my $address = $emails{$CurrentUser};
  if ( !$address ) {
    HandleEditMail();
    return;
  }

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Email notification for $title");
    if ( @exists > 0 ) {
      print <<EOF;
<h2>Remove your email address?</h2>
<form method=POST action=\"$ScriptUrl\">\n\n";

Remove your email address ($address) from this page? <p>
<input type=hidden name=MailNotify value="$title">;
<input type=hidden name=Back       value="$title">
<input type=submit value="Remove">
</form>
EOF
    } else {
      print <<EOF;
<h2>Add your email address</h2>
<form method=POST action="$ScriptUrl">
Add your email address ($address) to this page? <p>
<input type=hidden name=MailNotify value="$title">
<input type=hidden name=Back       value="$title">
<input type=submit value="Add">
</form>
EOF
    }
    PrintHtmlFooter();

  } else {
    my $which;
    if ( @exists > 0 ) {
      @mail  = grep !/^$CurrentUser$/, @mail;
      $which = "Removed";
    } else {
      push( @mail, $CurrentUser );
      $which = "Added";
    }

    $page{MailNotify} = join( $OtherSeparator, @mail );
    SaveCurrentPage();
    ReleaseLock();
    ReShow( $title, "$which your email address." );
  }
}

=head2 HandleEditMail

Handles the form that accepts and saves a user's email address.

=cut

sub HandleEditMail {
  FatalError( "Anonymous users may not specify a mail address.<br>"
      . "Please log in first." )
    if $CurrentUser eq "anonymous";

  my %addresses = $PageArchive->get( $MailPage, 0 );
  my $address   = $addresses{$CurrentUser} || '';

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Edit email address for $CurrentUser");
    print <<EOF;
<h2>Edit email address for $CurrentUser</h2>

Edit your email address below and click on "Save". <p>

<form method="POST" action="$ScriptUrl">
<input size=40 name="address" value="$address">
<input type="submit" value=\"Save\">
<input type="hidden" name="Back"     value="$Cgi{Back}">
<input type="hidden" name="EditMail" value="true">
</form>
EOF
    PrintHtmlFooter();
  } else {
    my $msg;
    if ( $Cgi{address} ) {
      my $fixed = ( $addresses{$CurrentUser} ? "updated" : "added" );
      $addresses{$CurrentUser} = $Cgi{address};
      $PageArchive->put( $MailPage, \%addresses, 0 );
      $msg = "Your email address has been $fixed successfully.";
    } else {
      delete( $addresses{$CurrentUser} );
      $PageArchive->put( $MailPage, \%addresses, 0 );
      $msg = "Your email address has been removed successfully.";
    }
    ReleaseLock();
    ReShow( $Cgi{Back}, $msg );
  }
}

=head2 HandleRecentChanges

Scans the archive and displays a page showing the most recently-updated
pages (up to the limit set by the administrator).

=cut

sub HandleRecentChanges {
  my ( $count, %times );

  # we want to be able to go back to here...
  $title = "RecentChanges";
  PrintHtmlHeader("Recent Changes");
  print "<h2>Recent Changes</h2>\n\n";

  my @titles       = $PageArchive->iterator();
  my %locked_pages = ();

  foreach my $title (@titles) {
    my ( $t, $v ) = split( /,/, $title );
    %page = RetrievePage( $t, $v );
    $t =~ /^$LinkPattern$/ or next;
    $times{ $page{TimeStamp} } = $title;

    my ( $unlocked, $locker ) = $PageArchive->is_unlocked($t);
    $locked_pages{$t} = $locker unless $unlocked;
  }

  my $lastday  = 32;
  my $lastmon  = 13;
  my $lastyear = 100;

  my $time;
  foreach my $time ( reverse sort ( keys(%times) ) ) {
    ++$count > $MaxRecentChanges && last;

    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime($time);
    my ( $t, $v ) = split( /,/, $times{$time} );
    %page = GetPage( $t, $v );

    if ( $mday < $lastday || $mon < $lastmon || $year < $lastyear ) {
      my $month = (
        qw(January February March April May June July
          August September October November December)
      )[$mon];
      print "<h4>$month $mday</h4>\n\n";

      $lastyear = $year;
      $lastmon  = $mon;
      $lastday  = $mday;
    }

    $hour < 10 && ( $hour = "0$hour" );
    $min < 10  && ( $min  = "0$min" );

    print "<strong>${hour}:${min}</strong> ";
    ( $t, $v ) = split( /,/, $times{$time} );
    print AsInternalLink($t);
    print " . . . . . ";
    print "by $page{EditUser} from $page{EditHost}. <br>\n";
  }

  if ( scalar keys %locked_pages ) {
    print "<hr><h3>The following pages are currently "
      . "being edited:</h3><p>";

    foreach my $page ( sort keys %locked_pages ) {
      print AsInternalLink($page);
      print " . . . . . ";
      print "by $locked_pages{$page}";
      print "<br>";
    }
  }
  PrintHtmlFooter();
}

=head1 ADMINISTRATION METHODS

These methods handle all of the administrator commands.

=cut

=head2 GetAdminInfo

Load the admin info. Force it to be created if there is none.

=cut

sub GetAdminInfo {

  # Check that the admin record can never be accessed indirectly.
  $AdminRec =~ /$LinkPattern/
    && FatalError("Admin record could be accessed as a page");

  # Get the record and grab the system properties from it.
  my %rec = $PageArchive->get( $AdminRec, 0 );
  if (%rec) {

    # load up global variables
    load_global( 1, \%rec, \@AdminInfoFields );
    if ($DebugAdminValues) {
      my @notes = "Admin settings:";
      foreach my $key ( sort keys %rec ) {
        push @notes, $key . " = " . (exists $rec{$key} and defined $rec{$key} ? $rec{$key} : "undef");
      }
      note(@notes);
    }
    if ($DebugEnvVars) {
      my @notes = "Environment:";
      foreach my $key ( sort keys %ENV ) {
        push @notes, $key . " = " . (exists $ENV{$key} and defined $ENV{$key} ? $ENV{$key} : "undef");
      }
      note(@notes);
    }
  } else {
    GetCgiInput();
    EditAdminRecord();
    Cleanup();
    exit;
  }
}

=head2 UserPWChange

Allow users to change their passwords.

=cut

sub UserPWChange {
  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    PrintHtmlHeader("Change password");
    print <<EOF;
<h2>Change Password</h2>

<form method=POST action=\"$ScriptUrl\">
<table border=0>\n";
  <tr>
    <td>
      <table border=0>
        <tr>
          <td align=right>You are:</td>
          <td><b>$CurrentUser</b></td>
        </tr>

        <tr>
          <td align=right>Old password:</td>
          <td><input type=password size=20 name="OldPass"</td>
	</tr>

        <tr>
          <td align=right>New password:</td>
          <td><input type=password size=20 name="NewPass"></td>
	</tr>

        <tr>
          <td align=right>New password again:<br>(for verification)</td>
          <td><input type=password size=20 name="NewPass2"></td>
	</tr>

        <tr>
          <td></td>
          <td>
	    <input type=submit value="Do it">
	    <input type=reset value="Reset">
	  </td>
        </tr>

      </table>

;
    </td>
  </tr>
</table>

<input type=hidden name=UserPWChange value="true">
EOF

    if ( $Cgi{Back} ) {
      print "<input type=hidden name=Back value=\"$Cgi{Back}\">\n\n";
    }
    print "</form>\n";

    PrintHtmlFooter();

  } else {
    my $redo_hash = {
      OldPass      => $Cgi{OldPass},
      NewPass      => $Cgi{NewPass},
      NewPass2     => $Cgi{NewPass2},
      Back         => $Cgi{Back},
      UserPWChange => "true",
    };

    my $opassword = $Cgi{OldPass};
    unless ($opassword) {
      ReDo( \&UserPWChange, $redo_hash, "No old password supplied" );
      return;
    }
    my $npassword = $Cgi{NewPass};
    unless ($npassword) {
      ReDo( \&UserPWChange, $redo_hash, "No new password supplied" );
      return;
    }
    my $vpassword = $Cgi{NewPass2};
    unless ($vpassword) {
      ReDo( \&UserPWChange, $redo_hash,
        "No duplicate new password (for verification) supplied" );
      return;
    }

    # Passwords gotta match.
    unless ( $npassword eq $vpassword ) {
      ReDo(
        \&UserPWChange, $redo_hash,
        "New password and verification password do not match. ",
        "Please try again."
      );
      return;
    }

    # Old password has to be right.
    my ($good_user) = $UserAdmin->verify( $CurrentUser, $opassword );
    unless ( defined $good_user ) {
      FatalError( "Could not access password file: " . $UserAdmin->unusable() );
    } elsif ( !$good_user ) {
      ReDo( \&UserPWChange, $redo_hash,
        "User ID/password combination invalid: " . $UserAdmin->unusable() );
      return;
    } else {

      # Do it.
      my $why;
      $UserAdmin->update( $good_user, $npassword );
      $why = $UserAdmin->unusable();
      FatalError("Couldn't update $good_user: $why") if $why;
    }

    # Report success.
    ReDo(
      \&UserPWChange,
      $redo_hash,
      "Your password has been updated successfully. ",
      "You must quit this browser session for your new password ",
      "to take effect."
    );
    return;
  }

}

=head2 ManageUsers

Add or remove users, reset passwords.

=cut

sub ManageUsers {

  # Check that the user is allowed to edit the password file.
  unless ( $AdminUser && ( $CurrentUser eq $AdminUser ) ) {
    note("Checking for useradmin flag");
    my $is_admin = $UserAdmin->has_attr( $CurrentUser, "useradmin" );
    unless ($is_admin) {
      my $why = $UserAdmin->unusable();
      unless ( $why =~ /does not have/ ) {
        FatalError(
          "Cannot check useradmin authority for " . "$CurrentUser: $why" );
      } else {
        FatalError("You do not have 'useradmin' authority.");
      }
    }
  }

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    note("ManageUsers entered with GET - UserName: $Cgi{UserName}");

    my $can_user =
      $UserAdmin->has_attr( $Cgi{UserName}, "useradmin" ) ? "checked" : "";
    note( "$Cgi{UserName} can" . ( $can_user ? "" : "not" ) . " useradmin" );
    my $can_site =
      $UserAdmin->has_attr( $Cgi{UserName}, "siteadmin" ) ? "checked" : "";
    note( "$Cgi{UserName} can" . ( $can_site ? "" : "not" ) . " siteadmin" );

    my @users = map { "<OPTION value=\"$_\">$_\n" }
      sort $UserAdmin->users();

    PrintHtmlHeader("Manage users");

    print <<EOF;
<h2>Manage Users</h2>

<form method=POST action="$ScriptUrl">

<table border=0>
  <tr>
    <td>
      <table border=0>
        <tr>
          <td align=right>User:</td>
EOF
    print qq(<td><input size=20 name="UserName" );
    print qq(value="$Cgi{UserName}") if defined $Cgi{UserName};
    print <<EOF;
          </td>
        </tr>

        <tr>
          <td align=right>Password:</td>
          <td><input type=password size=20 name="PassWord"></td>
	</tr>

        <tr>
          <td align=right>Options:</td>
	  <td><input type=radio name="UserAction" value="add">
              Add this user.</td>\n";
	</tr>

        <tr>
          <td></td>
          <td><input type=radio name="UserAction" value="del">
	       Delete this user.</td>
        </tr>

        <tr>
          <td></td>
          <td><input type=radio name="UserAction" value="show" checked>
	      Show current privileges for this user.</td>
        </tr>

        <tr>
            <td></td>
            <td>
	    <input type=radio name="UserAction" value="change">
	           Change this user's privileges and/or password.</td>
        </tr>
      </table>

    </td>
    <td valign=top>
      <table border=0>
        <tr>
          <td align=right valign=top>Or select from<br>current users:</td>
          <td>&nbsp;</td>
          <td valign=top>
            <select multiple name=\"UserName\" size=10>
            @users
            </SELECT>";
          </td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td valign=top>
      <h3>User privileges:</h3>
      <input type=checkbox name="UserManagerFlag" $can_user>Can manage users
      <br>
      <input type=checkbox name="SiteManagerFlag" $can_site>Can manage site
    </td>
  </tr>

  <tr>
    <td></td>
    <td>
      <input type=submit value="Do it">
      <input type=reset value="Reset">
    </td>
  </tr>
</table>
<input type=hidden name=ManageUsers value=\"true\">
EOF

    if ( $Cgi{Back} ) {
      print "<input type=hidden name=Back value=\"$Cgi{Back}\">\n\n";
    }
    print "</form>\n";

    PrintHtmlFooter();

  } else {
    note("ManageUsers entered with POST");
    note("Cgi{UserAction} is '$Cgi{UserAction}'");
    my $remanage_msg = undef;

    # Must have user name at minimum.
    my $name = $Cgi{UserName}
      or $remanage_msg = "You must supply a user name.";

    # If this is a "change" or "add" we need a password too.
    my $password = $Cgi{PassWord};
    if ( $Cgi{UserAction} eq "add" ) {
      $remanage_msg = "No password supplied for 'add'."
        unless $password;
    }

    # Do it.
    my $why;
    if ( $Cgi{UserAction} eq "show" ) {
      my ( $u, $p, @attrs ) = $UserAdmin->exists($name);
      $why = $UserAdmin->unusable();
      if ($why) {
        $remanage_msg = "Can't show $name: $why.";
      } elsif ( !defined $u ) {
        $remanage_msg = "$name is not in the password file.";
      } else {
        note("Showing $name");
        $remanage_msg = "Current privileges shown below.";
      }
    } elsif ( $Cgi{UserAction} eq "add" ) {
      note("Looking for $name");
      if ( $UserAdmin->exists($name) ) {
        $remanage_msg = ("$name already exists in the password file.");
      }
      unless ( $why = $UserAdmin->unusable() ) {
        note("Adding $name");
        $UserAdmin->add( $name, $password );
        $why = $UserAdmin->unusable();
        note("add failed: $why")                      if $why;
        $remanage_msg = ("Couldn't add $name: $why.") if $why;
      } else {
        $remanage_msg = ("Lookup of $name failed: $why.");
      }
    } elsif ( $Cgi{UserAction} eq "del" ) {
      note("Checking for $name");
      my ( $u, $p, @attr ) = $UserAdmin->exists($name);
      unless ( defined $u ) {
        if ( $why = $UserAdmin->unusable() ) {
          $remanage_msg = ("Error finding $name: $why");
        } else {
          $remanage_msg = ("$name does not exist in the password file");
        }
      } else {
        note("removing $name");
        $UserAdmin->delete($name);
        $why          = $UserAdmin->unusable();
        $remanage_msg = ("Couldn't delete $name: $why") if $why;
      }
    } elsif ( $Cgi{UserAction} eq "change" ) {
      note("looking for $name");
      my ( $u, $p, @attrs ) = $UserAdmin->exists($name);
      $why = $UserAdmin->unusable();
      if ($why) {
        $remanage_msg = "Can't change $name: $why";
      } elsif ( !defined $u ) {
        $remanage_msg = "$name not in the password file.";
      } else {
        note("changing $name");
        $UserAdmin->update( $name, $password ) if $password;
        $why          = $UserAdmin->unusable();
        $remanage_msg = ("Couldn't update $name: $why") if $why;

        # may need to update flags as well.
        my $add = [];
        my $del = [];
        push @{ $Cgi{UserManagerFlag} ? $add : $del }, "useradmin";
        push @{ $Cgi{SiteManagerFlag} ? $add : $del }, "siteadmin";
        note( "adding: " . join( " ", @$add ) );
        $UserAdmin->attr_add( $name, @$add );
        $why          = $UserAdmin->unusable();
        $remanage_msg = ("Couldn't add to $name: $why") if $why;

        unless ($why) {
          note( "deleting: " . join( " ", @$del ) );
          $UserAdmin->attr_del( $name, @$del );
          $why          = $UserAdmin->unusable();
          $remanage_msg = ("Couldn't delete from $name: $why")
            if $why;
        }
        $Cgi{UserAction} = "show";    # force reshow
        $remanage_msg    = "Privileges/password updated for $name.";
      }
    }

    note("remanage_msg is '$remanage_msg'");

    # Report success.
    my %which = ( 'add', "Added", 'del', "Deleted", 'change', "Changed", );

    $remanage_msg = "$which{$Cgi{UserAction}} user $name for $SystemTitle"
      unless defined $remanage_msg;
    my $hold = $Cgi{Back};
    ReDo(
      \&ManageUsers,
      {
        Back        => $hold,
        ManageUsers => 1,
        UserName    => $name,
        UserAction  => $Cgi{UserAction}
      },
      $remanage_msg
    );
  }

}

=head2 EditAdminRecord

Create or update the admin data.

=cut

sub EditAdminRecord {
  my %rec = $PageArchive->get( $AdminRec, 0 );

  # Check that the user is allowed to edit the admin record.
  ( ( $CurrentUser ne $AdminUser ) )
    and !$UserAdmin->has_attr( $CurrentUser, "siteadmin" )
    and ( int %rec )
    and FatalError("You are not the administrator");

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {
    note("Presenting page");
    PrintHtmlHeader("Customize $ScriptName");
    print <<EOF;
<h2>Customize $ScriptName</h2>

<form method=POST action="$ScriptUrl">
<table border=0>
EOF

    my $title     =~ ( $SystemTitle    =~ s/"/&quot;/g );
    my $body_attr =~ ( $BodyAttributes =~ s/"/&quot;/g );

    my $cute       = $CuteIcons          ? "checked" : "";
    my $icon       = $IconLinks          ? "checked" : "";
    my $anon       = $AnonAppendOnly     ? "checked" : "";
    my $block      = $BlockAnonUsers     ? "checked" : "";
    my $aggressive = $AggressiveLocking  ? "checked" : "";
    my $only       = $OnlyAdminCanUnlock ? "checked" : "";
    my $debug      = $Debug              ? "checked" : "";
    my $admin_vals = $DebugAdminValues   ? "checked" : "";
    my $cgi_vals   = $DebugCgiValues     ? "checked" : "";
    my $raw_page   = $DebugRawPage       ? "checked" : "";
    my $env_vars   = $DebugEnvVars       ? "checked" : "";

    $AdminUser || ( $AdminUser = $CurrentUser );

    print <<EOF;
  <tr><td align=right>Admin User:</td>
      <td><input size=20 name="AdminUser" value="$AdminUser"></td></tr>
  <tr><td align=right>Admin Email:</td>
      <td><input size=40 name="AdminEmail" value="$AdminEmail"</td></tr>
  <tr><td align=right>Default Page:</td>
      <td><input size=20 name="DefaultPage" value="$DefaultPage"></td></tr>
  <tr><td align=right>Search Page:</td>
      <td><input size=20 name="SearchPage" value="$SearchPage"></td></tr>
  <tr><td align=right>System Title:</td>
      <td><input size=40 name="SystemTitle" value="$title"></td></tr>
  <tr><td align=right>Mail Sensitivity:</td>
      <td><input size=5 name="MailSensitivity" value="$MailSensitivity">
          minutes.</td></tr>
  <tr><td align=right>Recent Changes:</td>
      <td><input size=5 name="MaxRecentChanges" value="$MaxRecentChanges">
          pages maximum</td></tr>
  <tr><td align=right>Body Attributes:</td>
      <td><input size=40 name="BodyAttributes" value="$BodyAttributes"></td></tr>
  <tr><td align=right>Menu Background:</td>
      <td><input size=10 name="MenuBackground" value="$MenuBackground"></td></tr>
  <tr><td align=right>Highlight Colour:</td>
      <td><input size=10 name="HighlightColour" value="$HighlightColour"></td></tr>
  <tr><td align=right>Options:</td>
      <td><input type=checkbox name="CuteIcons" $cute>
           Show cute icons.</td></tr>
  <tr><td></td>
      <td><input type=checkbox name="IconLinks" $icon>
           Show toolbar as icons.</td></tr>
  <tr><td></td>
      <td><input type=checkbox name="AnonAppendOnly" $anon>
          "Anonymous" users append-only.</td></tr>
  <tr><td></td>
      <td><input type=checkbox name="BlockAnonUsers" $block>
           No editing by \"anonymous\" users</td></tr>
  <tr><td></td>
      <td><input type=checkbox name="AggressiveLocking" $aggressive>
	   Lock pages on edit.</td></tr>
  <tr><td></td>
      <td><input type=checkbox name="OnlyAdminCanUnlock" $only>
	   Only admin may break edit locks.</td></tr>
  <tr><td></td>
      <td><input type=checkbox name="Debug" $debug>
	   Show debug trace info
           <blockquote>
	     <input type=checkbox name="DebugRawPage" $raw_page>
	       Dump raw pages<br>
	     <input type=checkbox name="DebugEnvVars" $env_vars>
	       Dump environment variables<br>
	     <input type=checkbox name="DebugCgiValues" $cgi_vals>
               Dump CGI values<br>
             <input type=checkbox name="DebugAdminValues" $admin_vals>
	       Dump admin values
           </blockquote>
      </td></tr><tr>
      <td></td><td>
        <input type=submit value="Save">
	<input type=reset value="Reset">
      </td>
  </tr>
</table>
<input type=hidden name="SetAdminData" value="true">
EOF

    if ( $Cgi{Back} ) {
      print "<input type=hidden name=Back value=\"$Cgi{Back}\">\n\n";
    }
    print "</form>\n";

    PrintHtmlFooter();

  } else {
    note("Updating");

    # Update our local copies of the information.
    load_global( 1, \%Cgi, \@AdminInfoFields );

    # Store them in the database.
    my (%rec);
    store_global( \%rec, @AdminInfoFields );

    $rec{CuteIcons}          = ( $CuteIcons          ? 1 : 0 );
    $rec{IconLinks}          = ( $IconLinks          ? 1 : 0 );
    $rec{AggressiveLocking}  = ( $AggressiveLocking  ? 1 : 0 );
    $rec{BlockAnonUsers}     = ( $BlockAnonUsers     ? 1 : 0 );
    $rec{AnonAppendOnly}     = ( $AnonAppendOnly     ? 1 : 0 );
    $rec{OnlyAdminCanUnlock} = ( $OnlyAdminCanUnlock ? 1 : 0 );
    $rec{Debug}              = ( $Debug              ? 1 : 0 );
    $rec{DebugRawPage}       = ( $DebugRawPage       ? 1 : 0 );
    $rec{DebugEnvVars}       = ( $DebugEnvVars       ? 1 : 0 );
    $rec{DebugCgiValues}     = ( $DebugCgiValues     ? 1 : 0 );
    $rec{DebugAdminValues}   = ( $DebugAdminValues   ? 1 : 0 );

    $PageArchive->put( $AdminRec, \%rec, 0 );
    note("Stored admin info");
    my $errstate = $PageArchive->getError();
    FatalError($errstate) if $errstate;

    my $back = $Cgi{Back};
    ReDo(
      \&EditAdminRecord,
      { SetAdminData => 1, Back => $back },
      "Customizations saved succesfully."
    );
  }
}

=head2 UnlockFile

Allows a user to break the lock on a file that was being edited.

=cut

sub UnlockFile {

  # Two possible GET modes:
  #  1. breaking a lock on the edit page
  #  2. an arbitrary unlock
  # One POST mode:
  #  1. an arbitrary unlock

  if ( $ENV{REQUEST_METHOD} eq "GET" ) {

    # GET, mode 1: break a lock on the edit page
    if ( defined $Cgi{unlock_target} ) {
      $title = $Cgi{unlock_target};

      # Now fall out into the unlock code.
    }

    # GET, mode 2: get page name to unlock
    else {
      # create and send the form
      PrintHtmlHeader("Unlock a Page");
      print <<EOF;
<h2>Unlock a page</h2>

<form method="POST" action="$ScriptUrl">
Enter the name of the page to be unlocked:
<input size=20 name="unlock_target"> <p>
<input type=hidden name=UnlockFile value="true">
<input type=hidden name=Back       value="$title">
<input type=submit value="Unlock">
</form>
EOF
      PrintHtmlFooter();
      return;
    }
  }

  # GET mode 1 and POST: break arbitrary lock (actually do it)
  # Make sure page is still there!
  my $revision = $PageArchive->max_version($title);
  FatalError("Page $title no longer exists, so it can't be unlocked.")
    unless defined $revision;

  # grab page so can get at ACL
  %page = RetrievePage( $title, $revision );

  note("Unlocking $title");
  unless ($OnlyAdminCanUnlock) {

    # Check the user is allowed to access the page.
    GetAccessVars();
    $EditAccess
      || FatalError("You do not have permission to unlock this page");
  } else {

    # Check that the user is the administrator.
    ( $CurrentUser ne $AdminUser )
      and !$UserAdmin->has_attr( $CurrentUser, "siteadmin" )
      and FatalError("You are not the administrator");
  }

  # If AggressiveLocking is off, force an error.
  FatalError("You can't unlock files if aggressive locking is off.")
    unless $AggressiveLocking;

  note("unlocking permitted");
  note("Checking '$title' for validity");
  $title =~ /$LinkPattern/
    or FatalError("$title is an invalid page name");
  $PageArchive->defined($title)
    or FatalError("$title doesn't exist.");
  do_unlock($title);
  note("unlock complete");
}

=head2 do_unlock (page)

 Unlocks the page if possible.

=cut

sub do_unlock {
  my $discard_this;
  my ($target) = shift;

  # See if the page is locked.
  my ( $unlocked, $locker ) = $PageArchive->is_unlocked($target);
  FatalError("$target is not locked") if $unlocked;

  # Try to unlock it.
  $PageArchive->unlock($target)
    or FatalError("Unable to release edit lock.");
  ( $unlocked, $discard_this ) = $PageArchive->is_unlocked($target);
  FatalError( "Internal error: unlock of $target failed. "
      . "Check the HTTP error log for information." )
    unless $unlocked;

  # Unlocked, print the page.
  PrintHtmlHeader("Unlock of $target successful");
  print "The lock by $locker has been broken successfully. <p>";

  ReShow( $target, "$target was updated successfully." );
}

=head1 ACCESS METHODS

Process the access control stuff.

=head2 CheckAccess (acl)

Determine if the current ACL allows a user to access a page.

=cut

sub CheckAccess {
  my ($acl) = @_;
  my ( $users, $pages, @pages );

  # Grant access if the user owns the page or is the administrator.
  $CurrentUser eq $page{Owner} && return "true";
  return 1
    if ( $CurrentUser eq $AdminUser )
    or $UserAdmin->has_attr( $CurrentUser, "siteadmin" );

  # Deny access if the page is locked by the owner.
  $page{Locked} && return;

  # Grant access if the ACL is blank.
  $page{$acl} || return "true";
  $page{$acl} =~ /^\s*$/ && return "true";

  # Deny access if the ACL is a minus sign.
  $page{$acl} =~ /^\s*-\s*$/ && return;

  # Split the ACL into a list of users and a list of ACL pages.
  $users = $page{$acl};
  $pages = $users;
  $users =~ s/\+$LinkPattern//g;
  $pages =~ s/.*?\+($LinkPattern)\b[^\+]*/push(@pages, $1)/ge;

  # Check the separated list of users first.
  $users =~ /\b$CurrentUser\b/ && return "true";

  # Check each of the ACL pages.
  foreach my $bit (@pages) {
    my %page = RetrievePage($bit);
    $page{PageText} =~ /^\+.*\b$CurrentUser\b/m && return "true";
  }
}

=head2 GetAccessVars

Set the global access levels for further checking.

=cut

sub GetAccessVars {

  # Determine if this is an anonymous user and should be blocked.
  my $block_me = $BlockAnonUsers && ( $CurrentUser eq "anonymous" );

  # Get each individual permission for this user.
  # Anonymous users *never* have modify access.
  $ReadAccess   = CheckAccess("ReadACL");
  $EditAccess   = ( $block_me ? 0 : CheckAccess("EditACL") );
  $ModifyAccess = (
    $CurrentUser eq "anonymous"
    ? 0
    : CheckAccess("ModifyACL")
  );

  # Cascade the permissions.
  $EditAccess = "true" if $ModifyAccess;
  $ReadAccess = "true" if $EditAccess;
}

=head2 InheritProperties

Handle the process of getting the parent page's properties and giving them
to the current (new) page.

=cut

sub InheritProperties {

  # Get the parent page.
  $Cgi{parent} || return;
  my %parent = RetrievePage( $Cgi{parent} );

  # Inherit the ACL lists automatically.
  $page{ReadACL}   = $parent{ReadACL};
  $page{EditACL}   = $parent{EditACL};
  $page{ModifyACL} = $parent{ModifyACL};

  # Check if the parent page is sticky.
  if ( $parent{Sticky} ) {

    # If so, inherit the sticky bit, owner and lock status.
    $page{Sticky}       = $parent{Sticky};
    $page{Locked}       = $parent{Locked};
    $page{Owner}        = $parent{Owner};
    $page{Archive}      = $parent{Archive};
    $page{MailNotify}   = $parent{MailNotify};
    $page{Notification} = $parent{Notification};
  }
}

=head1 INTERNAL UTILITY ROUTINES

=head2 note

Add a message to the debug log.

=cut

sub note {
  my $now   = scalar localtime(time);
  my $space = " " x ( 1 + length($now) );
  local $_;
  push @DebugMsgs, "$now: " . shift(@_) . "\n";
  foreach my $part (@_) { push @DebugMsgs, "$space $part\n"; }
}

# XXX: These two functions need to be handled in a better way.
#      Leaving them here for the moment, but they should be replaced soon.

=head2 load_global( mode, hash_ref, array_ref )

Assign values to global variables with values from hash,
keyed off of global variable names.  uses array of variable
names for precise control.  if mode is 0, non-existant hash
entries will not affect the global variables.  if mode is 1
the corresponding entries will be set to undef.

=cut

sub load_global {
  my ( $mode, $h, $k ) = @_;
  my @c;
  foreach my $key (@$k) {
    if ($mode) {    # Always set the variable
      push @c, "\$$key = \$h->{$key}";
    } else {        # Set only if in the record
      push @c, "\$$key = \$h->{$key}" if exists $h->{$key};
    }
  }
  eval join( ';', @c ); ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
}

=head2 store_global( hash_ref, array_ref )

Store values of global variables in hash,
keyed off of global variable names. Uses array of variable
names for precise control.

=cut

sub store_global {
  my ( $h, @k ) = @_;
  my @c;
  foreach my $key (@k) {
    push @c, "\$h->{$key} = \$$key";
  }
  eval join( ';', @c ); ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
}

=head2 Cleanup

Force cleanup of PageArchive object.

=cut

sub Cleanup {

  # implicitly call PageArchive->DESTROY, closing archive handle.
  $PageArchive = undef;
}

=head2 main

Actually runs the whole show.

=cut

sub main {
  _setup_kludge();

  #----------------------
  # Initialization.
  #----------------------
  # Blow up if password file is unusable
  if ($PasswordFile) {
    $UserAdmin = App::WebWebXNG::AuthManager->new($PasswordFile);
    my $why = $UserAdmin->unusable;
    FatalError($why) if $why;
  }

  # Empty debug array,
  @DebugMsgs = ();

  # ---------------------
  # Internals Configuration Section
  #
  #    If you are altering this script, be very careful with the variables
  #    below. The system is sensitive to changes in these variables and they
  #    are not very well documented.
  # ---------------------

  # Defaults for use when the system is being configured for the
  # first time.

  # First page to be shown when the script is accessed.
  $DefaultPage || ( $DefaultPage = "FrontPage" );

  # Name of the search page linked to the "search" item in the command bar.
  $SearchPage || ( $SearchPage = "SearchForm" );

  # Default number of minutes that must pass before sending out another
  # mail notification.
  $MailSensitivity || ( $MailSensitivity = 5 );

  # Maximum number of entries on the "recent changes" page.
  $MaxRecentChanges || ( $MaxRecentChanges = 30 );

  # Body white, text black.
  $BodyAttributes
    || ( $BodyAttributes = "text=\"#000000\" bgcolor=\"#ffffff\"" );

  # Menu light yellow.
  $MenuBackground || ( $MenuBackground = "#ffffdd" );

  # Highlight color is bright red.
  $HighlightColour || ( $HighlightColour = "#ff0000" );

  # Show the cute spider icon.
  $CuteIcons || ( $CuteIcons = "true" );

  # Lock pages when they are being edited.
  $AggressiveLocking || ( $AggressiveLocking = 1 );

  # Don't permit users without IDs to edit pages.
  $BlockAnonUsers || ( $BlockAnonUsers = 1 );

  # Anonymous users are only allowed to append.
  $AnonAppendOnly || ( $AnonAppendOnly = 1 );

  # Allow anybody who can edit the page to unlock it.
  $OnlyAdminCanUnlock || ( $OnlyAdminCanUnlock = 0 );

  # Turn debugging off by default.
  $Debug || ( $Debug = 1 );

  # Get the name of this script (since it may be a symbolic link).
  my @path = split( '/', "$ENV{SCRIPT_NAME}" );
  $ScriptName = pop(@path) || 'WebWebX';

  # Get the name of the current user.
  $CurrentUser = $ENV{REMOTE_USER} || "anonymous";

  # Get the name of the remote host.
  my $hostname = hostname();
  $CurrentHost = $ENV{REMOTE_HOST} || $hostname || "localhost";

  # Get today's date.
  my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime($^T);

  $Today = (
    qw(January February March April May June July
      August September October November December)
  )[$mon]
    . " "
    . $mday . ", "
    . ( $year + 1900 );

  # Work out all of the other directory names.
  $LockDir = "$DataDir/$ScriptName" . ".lck";

  # Work out the URL for this script.
  $ScriptUrl = "$CgiUrl/$ScriptName";
  $SigninUrl = "$SecureUrl/$ScriptName";
  $ScriptUrl = $SigninUrl if $CurrentUser ne "anonymous";

  # Internal field separator characters.
  $FieldSeparator = "\263";
  $OtherSeparator = "\264";

  # LinkPattern is the regular expression which matches page titles.
  $LinkWord    = "[A-Z][a-z]+";
  $LinkPattern = "($LinkWord){2,}";
  $TickedOrNot = "``$LinkPattern|$LinkPattern";

  # ReferencePattern is a regular expression which matches external references.
  $ReferencePattern = "[A-Z,a-z,0-9]+";

  # ImagePattern is a regexp which matched all image URLs (the search is
  # case insensitive).
  $ImagePattern = q(\.gif$|\.jpg$|\.jpeg$);

  # Name of the admin record.
  $AdminRec = "admin000";

  # Name of the mail directory page.
  $MailPage = "MAIL000";

  # The search form.
  $SearchForm =
      "<form>\n"
    . "<input size=40 name=SearchRefs value=\"\">\n"
    . "<input type=hidden name=Back value=\"$SearchPage\">\n"
    . "</form>\n";

  # -----------------
  # Main Program Body
  # -----------------

  $| = 1;

  #print "Content-type: text/plain\n\r\n\r";

  $PageArchive = PageArchive::RCS->new(
    $DataDir,
    Logger => \&main::note,
    Fatal  => \&main::FatalError
  );

  my $errstate = $PageArchive->getError();
  FatalError($errstate) if $errstate;

  @GlobalStatus      = ();
  @LiteralUrl        = ();
  @EndTags           = ();
  %page              = ();
  %links             = ();
  $PrintedHtmlHeader = 0;
  $RawInput          = '';
  %Cgi               = ();

  $Cgi{UserName} = $CurrentUser;

  GetAdminInfo();
  GetCgiInput();
  note($AdminUser);
  if ( $ENV{REQUEST_METHOD} eq "POST" ) {
    RequestLock();
    $dbIsLocked = 1;
  } else {
    $dbIsLocked = 0;
  }

  my %jump_table = (
    SearchRefs    => \&HandleSearch,
    ViewPage      => \&HandleView,
    ShowDiffs     => \&HandleDiffs,
    EditLinks     => \&HandleLinks,
    EditLink      => \&HandleEditLink,
    EditPage      => \&HandleEdit,
    RestorePage   => \&HandleRestore,
    PurgePage     => \&HandlePurge,
    PageProps     => \&HandleProperties,
    PageInfo      => \&HandleInfo,
    RenamePage    => \&HandleRename,
    DeletePage    => \&HandleDelete,
    MailNotify    => \&HandleMail,
    EditMail      => \&HandleEditMail,
    RecentChanges => \&HandleRecentChanges,
    SetAdminData  => \&EditAdminRecord,
    UnlockFile    => \&UnlockFile,
    ManageUsers   => \&ManageUsers,
    UserPWChange  => \&UserPWChange,
    GlobalPurge   => \&HandleGlobalPurge,
  );
  my $to_do = undef;
  foreach my $key ( keys %Cgi ) {
    if ( defined( $to_do = $jump_table{$key} ) ) {
      note("Executing $_");
      &$to_do;
      last;
    }
  }

  # Handle the "page name alone" case.
  unless ( defined $to_do ) {
    ($title) = split( /&/, $ENV{QUERY_STRING} );
    $Cgi{ViewPage} = $title;
    note("defaulting to ViewPage on $to_do");
    HandleView();
  }

  if ( $ENV{REQUEST_METHOD} eq "POST" ) {
    ReleaseLock();
  }
  Cleanup();

}

main() if not caller();

"The information superhighway? Aren't highways long, gray things
where thousands of people die every year?";
