#
# WING - Web-IMAP/NNTP Gateway
#
# Wing/Login.pm
#
# Author: Malcolm Beattie, mbeattie@sable.ox.ac.uk
#
# This program may be distributed under the GNU General Public License (GPL)
#
# 25 Aug 1998  Copied from development system to main cluster.
# 15 Sep 1998  Changes for Herald.
# 23 Feb 1999  Release version 0.5
# 18 Mar 1999  Fold in generic initial_mailbox($username) for finding
#              user's IMAP server.
# 10 Jul 2000  Add extra sanity check to ensure username is not all digits
#  6 Jul 2001  RM - Added support for per-port security options
#
package Wing::Login;
use Apache::Constants qw(:common REDIRECT);
use DBI;
use SQL;
use Socket;
use IO::Socket;

use Wing::Shared;
use Wing::Util;
use strict;

use vars qw(@session_chars $id $start $username $host $server $pid);
@session_chars = ('A' .. 'Z', 'a' .. 'z', 0 .. 9, '.', '-');


#
# Generate a cryptographically strongly random 120-bit session id
# returned as 24 characters from the 64-character set [A-Za-z0-9.-].
# Platforms without /dev/urandom will have to rewrite this.
#
sub make_session_id {
    if (!defined(fileno(RANDOM))) {
	open(RANDOM, "/dev/urandom") or return undef;
    }
    my $rawid;
    if (read(RANDOM, $rawid, 24) != 24) {
	return undef;
    }
    $rawid =~ s/(.)/$session_chars[ord($1) & 63]/esg;
    return $rawid;
}

sub contact_maild {
    my $r = shift;
    my $s = IO::Socket->new(Domain => AF_UNIX,
			    Type => SOCK_STREAM,
			    Peer => $MAILD_SOCKET_PATH);
    if (!defined($s)) {
	$r->warn("failed to contact maild server socket: $!");
    }
    return $s;
}
    
sub create_session ($$$$) {
    my ($r, $password, $folder, $port) = @_;
    my $session = make_session_id();
    if (!defined($session)) {
	$r->warn("make_session_id failed, errno indicates: $!");
	return undef;
    }
    # There's an argument that we ought to loop around and check the
    # session ID we've just created isn't already in use. However,
    # since it's a crypto-random 120-bit quantity, we don't bother.
    my $s = contact_maild($r) or return undef;
    print $s join("\n", $MAILD_PROTOCOL_VERSION,
		  $session, $username, $password, $host, $folder,
		  port_requires_ip_check($port)), "\n";
    chomp($pid = <$s>);
    close($s);
    if ($pid eq "NO") {
	return undef; # authentication failed
    }
    if ($pid eq "") {
	# maild exited without writing a PID down the connection
	return "*busy";
    }
    if ($pid + 0 ne $pid) {
	# weird error: the pid isn't an ordinary number
	return "*badpid";
    }
    $id = $session;
    $start = 'now';
    $server = $r->server->server_hostname;
    eval { sql_insert(*id, *start, *username, *host, *server, *pid) };
    if ($@) {
	$r->warn("create_session: $@");
	return "*badinsert";
    }
    return $session;
}

#
# Just authenticate a user via a Mail::Cclient connection to c-client
# spec {$host}INBOX (i.e. it should be a POP or IMAP spec).
# Returns true if the user authenticates successfully, false otherwise.
#
sub authenticate_only ($$$$) {
    my ($r, $password, $mailbox, $port) = @_;
    my $s = contact_maild($r) or return undef;
    print $s join("\n", $MAILD_PROTOCOL_VERSION,
		  "*authonly", $username, $password, $host, $mailbox,
		  port_requires_ip_check($port)), "\n";
    chomp($pid = <$s>);
    $r->warn("authonly login for $username for $mailbox returned $pid\n"); #debug
    close($s);
    return $pid ne "NO";
}

sub login_incorrect ($) {
    my ($r) = @_;
    my ($host, $path_info) = login_url($username);
    my $login_url = server_url($r, $host) . $path_info;
    $r->content_type("text/html");
    $r->send_http_header;
    $r->print(<<"EOT");
<html><head><title>Login incorrect</title></head>
<body><h1>Login incorrect</h1>
Please <a href="$login_url">try again</a>.
</body></html>
EOT
    return OK;
}

sub server_busy ($) {
    my ($r) = @_;
    my ($host, $path_info) = login_url($username);
    my $login_url = server_url($r, $host) . $path_info;
    $r->content_type("text/html");
    $r->send_http_header;
    $r->print(<<"EOT");
<html><head><title>Server busy</title></head>
<body><h1>Server busy</h1>
Please <a href="$login_url">try again</a>.
</body></html>
EOT
    return OK;
}

sub already_logged_in ($$$$) {
    #
    # Handle a user who is already logged in with another session.
    # Authenticate them and then tell them about it.
    #
    my ($r, $password, $mailbox, $port) = @_;
    authenticate_only($r, $password, $mailbox, $port) 
	or return login_incorrect($r);
    #
    # Convert the dotted quad IP address of the client (as held by
    # the sessions database) and convert it into a FQDN (if possible).
    #
    my $client = inet_aton($host);
    $client = gethostbyaddr($client, AF_INET) if $client;
    $client ||= $host; # fall back to dotted quad

    my $kill_url = server_url($r, $server) . "/wing/kill/$username/$id";
    dont_cache($r, "text/html");
    $r->print(<<"EOT");
<html><head><title>Already logged in</title></head>
<body><h1>Already logged in</h1>
You already have a WING session open from $client, logged in at
$start. If you wish to forcibly log out that session (losing any
draft message and attachments entered) then please click
<a href="$kill_url">here</a>.
</body></html>
EOT
    return OK;
}

sub handler {
    my $r = shift;
    my ($port) = sockaddr_in($r->connection->local_addr);
    my %in = $r->content; # note that we only accept POSTed data
    $username = $in{username};
    my $password = $in{password};
    #
    # Default username (and later maybe other defaults) come from path_info
    #
    my ($junk, $handler, $default_username, @other_stuff) =
	split(m(/), $r->path_info);
    $username ||= $default_username;

    if (!exists($in{login})) {
	#
	# Generate the login screen
	#
	my $login_url = server_url($r, $WING_DOMAIN) . "/";
	dont_cache($r, "text/html");
	$r->print(<<"EOT");
<html><head><title>Login access bypassed frontend</title>
<body><h1 align="center">Login access bypassed frontend</h1>
Please use the official URL
<a href="$login_url"><tt>$login_url</tt></a>
to login.
</body></html>
EOT
	return OK;
    }
    #
    # Sanity-check username
    #
    if ($username eq "" || length($username) > 8
	|| $username =~ /\W/ || $username !~ /\D/ || $username ne lc($username))
    {
	my ($host, $path_info) = login_url();
	my $login_url = server_url($r, $host) . $path_info;
	$r->content_type("text/html");
	$r->send_http_header;
	$r->print(<<"EOT");
<html><head><title>Login failed</title></head>
<body><h1>Login failed</h1>
An illegal username was entered: please correct and
<a href="$login_url">retry login</a>.
<p>
Remember that usernames and passwords are case sensitive.
</body></html>
EOT
	return OK;
    }

    #
    # Find session type. For now we support two types of session:
    # portal and normal.
    #
    my $sess_type = $in{sess_type};
    if ($sess_type ne "portal") {
	$sess_type = "";
    }

    my $full_spec = initial_mailbox($username);

    #
    # Connect to the database
    #
    #$r->warn("PID $$ connecting to database for $username"); # debug
    sql_connect(@WING_DBI_CONNECT_ARGS);
    sql_table("sessions");
    #
    # First look for a current session. Do it in a database
    # transaction so that we don't commit until either (a) the find
    # succeeds (bad: it means the user is already logged in) or (b)
    # the find fails and the subsequent session creation is done.
    #
#XXX#    sql_begin;
#XXX#    sql_do("lock table sessions");
    sql_select(*id, *start, *host, *server, *pid, username => $username);
    if (sql_fetch) {
#XXX#	sql_commit;
	sql_sth->finish;
	sql_disconnect;
	#$r->warn("PID $$ disconnected from database: $username already logged in"); # debug
	return already_logged_in($r, $password, $full_spec, $port);
    }

    #
    # At this point, we know the user isn't logged in anywhere (and
    # we're in the middle of a db transaction so nobody else can get in)
    # so we try to create a session.
    #
    $host = $r->connection->remote_ip;
    my $session = create_session($r, $password, $full_spec, $port);
#XXX#    sql_commit;
    sql_disconnect;
    #$r->warn("PID $$ disconnected from database: successful login"); # debug
    if (!defined($session)) {
	return login_incorrect($r);
    }
    if ($session eq "*busy") {
	return server_busy($r);
    }
    if (substr($session, 0, 1) eq "*") {
	# some other error
	$r->warn("create_session failed and returned: $session");
	return login_incorrect($r);
    }
    my $server_url = server_url($r);
    $r->header_out("Set-Cookie" => 
		   make_wing_cookie($username, $session,
				    port_sets_secure_cookie($port)));
    $session = "x" if port_requires_cookies($port);
    return redirect($r,
	"$server_url/wing/cmd/$username/$session/check-cookie/$sess_type");
}

1;
