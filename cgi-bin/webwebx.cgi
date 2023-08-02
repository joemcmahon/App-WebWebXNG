#!/usr/bin/perl -w
use strict;

#------------------------------------------------------------------------------
# Change the following library name to reflect where webwebx.pl, PageArchive.pm
# and Storable.pm have been installed. If you are planning on running multiple
# webwebs, you should install them in a globally-accessible library.
#------------------------------------------------------------------------------

BEGIN {
   unshift @INC,"/home/joe/public_html/webwebx/lib";
}
# --------------------------------------------------------------------------
# Change these variables to reflect your local setup.
# Anything else, like colors and various settings, are
# changeable via the admin page.
# --------------------------------------------------------------------------

use vars qw(
	    $DisplayComments
	    $DisplayContentOnly
	    $DataDir
	    $SecureUrl
	    $CgiUrl
	    $PasswordFile
	    $MailProgram
	    $HelpUrl
	    $MailProgram
	    $HelpUrl
	    $IconUrl
	    $SERVER
	    $SCRIPT_ALIAS
	    $SECURE_DIR
	    $STATIC_PATH
	   );

# Change this to the nameof the server where you're running WebWebX.
$SERVER       = "prtims.stx.com";

# Change this to the ScriptAlias you're using in your httpd.conf.
$SCRIPT_ALIAS = "whiteboard";

# Change this to the secure directory you'll be using (that's the one
# where you put the .htaccess file).
$SECURE_DIR   = "private";

# Change this to the directory that contains the icons and help files
# (remember this has to be accessible to your httpd!).
$STATIC_PATH  = "~joe/webwebx";

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
$PasswordFile = "/home/joe/whiteboard/.htpasswd";

### Location of your system's "sendmail" program. If you do not have
### send mail or you want to stop all email notification, leave this
### variable blank.
$MailProgram = "/usr/lib/sendmail";

eval {require "webwebx.pl"} or
  do {
      print "Content-type: text/html\n\r\n\r";
      print"<pre> $@</pre>\n";
  }
  
