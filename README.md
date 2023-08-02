# WebWebXNG

WebWebXNG is a Perl wiki: a text-based Web collaboration server.
To make that clearer: it's a user-maintained "whiteboard" hosted on a website.
Users of the website can edit and create pages within it, linking both to
pages in the site and to any location elsewhere on the internet.

WebWebX is based on WikiWiki and WebWeb; it adds features designed
to make it easier to administer and easier to use, specifically:

 - Actual logins and access control. 
 - Access levels, maintained inside the wiki: administrator, users, and viewers.
Viewers have no account on the wiki; you can choose to have viewers not be
able to see anything, or to have read access to the pages. Users can view
and edit any page, but can't add or remove users. Administrators can add and
remove users, and alter global configuration.
 - Archiving. Previous versions of pages are saved in a source-code management
system, to allow a user to read and/or restore previous versions. Each save of
a page creates a new version. (The original SCM used was `rcs`; support for `rcs`
is still available, if you have an old WebWebX installation you want to port.)
 - Page locking and unlocking. To avoid editing races on pages, editing a page
locks it until it is resaved. Users and administrators can break an edit lock
if necessary.
 - Edit notifications. Users can choose to be notified (currently by mail, but
other options are currently being considered) if a page of interest is edited.
 - Extended citations
 - Access control lists, allowing users to dynamically control who has access
to their pages, with read (read only, no changes permitted), edit (read and edit content,
but no changes to permissions allowed), and modify, which allows users on the list
to modify page properties, and copy, rename, or delete the page. Access controls
can reference _access control pages_, which allow specific user lists to be centralized.
 - Self-administration for registering users, controllable by the admins.
 - Anonymous users do exist, and can be given privileges, if you are a free-speech fanatic
with plenty of time on your hands.

# Other improvements

The original WebWebX was a CGI program and had a _slew_ of dependencies on that.
The new WebWebX uses Mojolicious and has a native Perl web server which makes the
setup process approximately 1000% more sane.

# Installation

First, install `App::WebWebXNG` into your Perl:

    cpanm App::WebWebXNG

Next, set up the environment variables:

## SCM_TYPE

This is the source code management system you'll use to manage the page archive.
Currently, we support `RCS` for RCS, and `Git` for Git. (WebWebXNG will try to
dynamically load a `WebWebXNG::SCM::xxxx` module at startup, and will let you
know if the SCM you selected isn't available.)

# DBD_NAME

This is the `DBD` module to be loaded to access the user database. Any DBD driver
that can handle SELECT, INSERT, UPDATE, and DELETE should work. We have tested with
`DBD::Pg`, `DBD::mysql`, and `DBD::SQLite`. SQLite may suffice for testing, and even
production if you don't have a lot of users.

# CONNECT_STRING

This is the ifirst `DBI->connect` argument. Examples:
 - `"dbi:SQLite:dbname=$dbfile"`
 - `"dbi:Pg:dbname=$dbname"`

# DB_USER

This is the username for the database login. Is the null string if not set.

# DB_PASSWORD

This is the password for the database user. Is the null string if not set.


# TODOS
 - We really need to validate signups. Really.
 - We need password reset and account recovery.
 - Jump form.
 - Secrets management for the user database.
