#
# WING - Web-IMAP/NNTP Gateway
#
# Wing/Shared.pm
#
# Author: Malcolm Beattie, mbeattie@sable.ox.ac.uk
#
# This program may be distributed under the GNU General Public License (GPL)
#
# 25 Aug 1998  Copied from development system to main cluster.
# 15 Sep 1998  Changes for Herald.
#  5 Feb 1999  Anonymised configuration for public release of 0.6
#
#
# Data shared between Wing.pm and maild (and some assorted constants
# of configuration options used by only one but which are convenient
# to keep centralised here).
#
package Wing::Shared;
use Exporter;
no strict;
@ISA = qw(Exporter);
@EXPORT = qw($MAILD_PROTOCOL_VERSION $MAILD_SOCKET_DIR
	     $MAILD_SOCKET_PATH &make_session_socket $MAILD_TMPDIR
	     $DEFAULT_LINES_PER_PAGE $DEFAULT_CWD @DEFAULT_DISPLAY_HEADERS
	     $DEFAULT_COMPOSE_HEADERS $MANDATORY_COMPOSE_HEADERS
	     &escape_html &url_encode &url_decode &maild_encode &maild_decode
	     &maild_get &maild_set &maild_get_and_reset &maild_reset
	     &canon_encode &canon_decode %header_is_address
	     $WING_DOMAIN $IMAPDU_COMMAND
	     $SENDMAIL_COMMAND $SENDMAIL_FROM_HOSTNAME $LDAP_ROOT
	     @WING_DBI_CONNECT_ARGS &make_wing_cookie &login_url
	     $MOTD_PATH &wing_directory $FORWARD_FILE
	     $VACATION_MESSAGE_FILE $VACATION_ACTIVE_FILE @VACATION_DB_FILES
	     &ABOOK_ACTIVE &ABOOK_OWNED $DEFAULT_ABOOK &is_legal_alias
	     $SENT_MAIL_MAILBOX $DISK_QUOTA &initial_mailbox $LOGIN_TITLE);

$MAILD_PROTOCOL_VERSION = "1.0";

#
# Functions to encode/decode data between Wing.pm and maild.
# Currently this involves escaping whitespace characters and %.
#
sub maild_encode {
    my @args = @_;
    foreach (@args) {
	s/([%\s])/sprintf("%%%02x",ord($1))/eg;
    }
    return wantarray ? @args : $args[0];
}

sub maild_decode {
    my @args = @_;
    foreach (@args) {
	s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    }
    return wantarray ? @args : $args[0];
}

sub maild_get {
    my ($s, $attr) = @_;
    print $s "get $attr\n";
    chomp(my $result = <$s>);
    return maild_decode($result);
}

sub maild_set {
    my ($s, $attr, $value) = @_;
    printf $s "set %s %s\n", $attr, maild_encode($value);
}

sub maild_reset {
    my ($s, $attr) = @_;
    print $s "set $attr\n";
}

sub maild_get_and_reset {
    my ($s, $attr) = @_;
    my $result = maild_get($s, $attr);
    maild_set($s, $attr, "");
    return $result;
}

#
# Escape HTML metacharacters
#
sub escape_html {
    my $str = shift;
    $str =~ s/&/&amp;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/</&lt;/g;
    return $str;
}

#
# Standard functions to encode/decode URL information
#
sub url_encode {
    my @args = @_;
    foreach (@args) {
	s/(\W)/sprintf("%%%02x",ord($1))/eg;
    }
    return wantarray ? @args : $args[0];
}

sub url_decode {
    my @args = @_;
    foreach (@args) {
	s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    }
    return wantarray ? @args : $args[0];
}
#
# Functions to encode/decode information into URLs (note that standard
# url_{en,de}code escapes such as %2f are no good because they are
# handled implictly by browsers and the web daemon.
#
sub canon_encode {
    my @args = @_;
    foreach (@args) {
	s/(\W)/sprintf('@%02x',ord($1))/eg;
    }
    return wantarray ? @args : $args[0];
}

sub canon_decode {
    my @args = @_;
    foreach (@args) {
	s/\@([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    }
    return wantarray ? @args : $args[0];
}

#
# Directory which contains the main maild socket and a subdirectory
# "sessions" containing a socket named after each current session.
# Must be owned/readable/writable by the web server daemon user and
# inaccessible (i.e. not even readonly) to all other users.
#
$MAILD_SOCKET_DIR = "/var/lib/maild";
$MAILD_SOCKET_PATH = "$MAILD_SOCKET_DIR/maild";

#
# Turns a username and session into a socket path
#
sub make_session_socket {
    my ($username, $session) = @_;
    return "$MAILD_SOCKET_DIR/sessions/$username:$session";
}

#
# Directory to hold the per-user temporary directories. Each per-user
# temporary directory is created at the started of a session and
# checked for security so MAILD_TMPDIR can be an ordinary mode 01777
# temporary directory such as /tmp or /var/tmp.
#
$MAILD_TMPDIR = $ENV{TMPDIR} || "/tmp";

#
# Default number of lines for each "page" listing folder messages
#
$DEFAULT_LINES_PER_PAGE = 20;

#
# Default headers included in the display of a message
#
@DEFAULT_DISPLAY_HEADERS = qw(From Subject To Date Message-Id);

#
# Default header fields included in the composition of a message.
# Note that this is a space-separated string and not a real
# list like @DEFAULT_DISPLAY_HEADERS).
#
$DEFAULT_COMPOSE_HEADERS = "To Cc Subject";

#
# Mandatory header fields included in the composition of a message.
# Note that this is a space-separated string and not a real
# list like @DEFAULT_DISPLAY_HEADERS).
#
$MANDATORY_COMPOSE_HEADERS = "To Subject";

#
# Default initial "current working directory" relative to
# the default directory where the IMAP server starts each connection.
#
$DEFAULT_CWD = "";

#
# Headers which are addresses. These headers have associated "Lookup"
# buttons in the composition window so that the user can look up
# addresses for that header in their address book.
#
%header_is_address = map { $_ => 1 } (qw(To Cc Bcc Reply-To));

#
# This is the "cluster" domain name which WING is running in. It
# expects DNS entries username.$WING_DOMAIN and http://$WING_DOMAIN
# as the primary WING access URL.
#
$WING_DOMAIN = "edit-wing-domain.example.org";

#
#
# This is the command and arguments used to fire up sendmail
# in order to send a message. The option "-f username@hostname"
# is appended.
#
$SENDMAIL_COMMAND = "/usr/sbin/sendmail -t -oi -oee";

#
# This command us called as follows:
#     imapdu group gid username uid
# and should produce a "du -x -S ..." listing of mail folder usage.
#
$IMAPDU_COMMAND = "/usr/local/bin/imapdu";

#
# This is the hostname from which the "-f username@hostname" option
# mentioned above is constructed.
#
$SENDMAIL_FROM_HOSTNAME = $WING_DOMAIN;

#
# This is the root dn for a local LDAP search
#
$LDAP_ROOT = "o=Some Organisation, c=ZZ";

#
# This is the DBI database spec name, username and password field
# of the WING database which holds session and address book information.
#
@WING_DBI_CONNECT_ARGS =
    ("dbi:Pg:dbname=your_wing_db;host=your_frontend_host.$WING_DOMAIN", "", "");

#
# This generates the Set-Cookie content for a WING cookie
#
sub make_wing_cookie {
    my ($username, $session, $expires) = @_;
    my $cookie =
	"$username=$session; path=/wing/cmd/$username; domain=$WING_DOMAIN";
    if (defined($expires)) {
	$cookie .= "; expires=$expires";
    }
    return $cookie;
}

#
# Forms a login URL
#
sub login_url {
    my $username = shift;
    my $url = "http://$WING_DOMAIN";
    $url .= "/login/$username" if $username;
    return $url;
}

#
# Given a connection to maild, returns the directory (may be across NFS)
# within which the user's wing-specific files are held.
#
sub wing_directory {
    my $s = shift;
    my $group = maild_get($s, "group");
    print $s "username\n";
    chomp(my $username = <$s>);
    return "/imap/$group/$username/wing";
}

$FORWARD_FILE = "forward";
$VACATION_MESSAGE_FILE = "vacation.message";
$VACATION_ACTIVE_FILE = "vacation.active";
@VACATION_DB_FILES = qw(vacationdb.dir vacationdb.pag);

#
# The path to the motd which is included in the login screen
#
$MOTD_PATH = "/etc/motd.wing";

#
# Constants for address book info flags
#
sub ABOOK_ACTIVE () { 0x1 }
sub ABOOK_OWNED () { 0x2 }

#
# Name of the default address book which everyone should have
#
$DEFAULT_ABOOK = "personal";

#
# This function determines whether a string is syntactically a legal
# alias (i.e. it can be held in an address book, used in SQL without
# quoting and doesn't have an @). For safety, we restrict it even
# further.
#
sub is_legal_alias {
    my $alias = shift;
    if (length($alias) > 0 && length($alias) < 64 && $alias !~ /[^\w.-]/) {
	return 1;
    }
    return 0;
}

#
# Mailbox to which outgoing message are copied if the user has
# turned on the copy-outgoing option.
#
$SENT_MAIL_MAILBOX = "sent-mail";

#
# Disk quota for each user (in KB). For the moment, I assume a fixed quota
# which is the same for every user and it would be nice for it to
# stay that way. If really necessary, the user database can have a quota
# field (or we can pick up the user's quota via RPC) but that gets
# a bit messy.
#
$DISK_QUOTA = 20 * 1024; # 20 MB

#
# Initial mailbox for a given username. With a single IMAP server,
# just return "{your-imap-server-name.example.org/imap}INBOX". With a
# cluster where a named maps username.your-cluster.example.org to the
# relevant IMAP server, return "{$_[0].your-cluster.example.org/imap}INBOX"
#
sub initial_mailbox {
    my $username = shift;
    return "{edit-initial-mailbox.example.org/imap}INBOX";
}

#
# HTML title and heading used for initial login screen
#
$LOGIN_TITLE = "WING Mail Service Login";

1;

