#
# WING - Web-IMAP/NNTP Gateway
#
# Wing/Balance.pm
#
# Author: Malcolm Beattie, mbeattie@sable.ox.ac.uk
#
# This program may be distributed under the GNU General Public License (GPL)
#
# 17 Sep 1998  Initial version.
# 07 Oct 1998  Does login screen itself instead of redirecting to wing servers.
#              This avoids people bookmarking wing server URLs.
# 23 Feb 1999  Release version 0.5
# 18 Mar 1999  Separate out login banner for non-Oxford release
#
#
# Redirect queries to a live WING server. Reads list of live servers
# from /etc/wing.live at startup and redirects successive queries
# to a choice of WING server based on (time + $$ + $i++) % @live_list.
# This is intended to be a handler for / (so that users need only type
# the main host name) and for /login/username so we decline any other
# request and pass it on to other Apache handlers.
#
# /etc/wing.live should contain FQDNs of the currently live WING
# servers, one per line. "#" can be used to introduced comments which,
# along with blank lines, are ignored.
#
# In future we should do proper load-balancing and automatic detection
# of any down WING servers but this will do for now.
#
package Wing::Balance;
use Apache::Constants qw(:common REDIRECT);
use Wing::Util;
use Wing::Shared;
use strict;

my $LIVE_LIST_PATH = "/etc/wing.live";
my $MOTD_PATH = "/etc/motd.wing";

my @live_list;
my $live_list_mtime = 0;
my $i = 0;

sub get_live_list {
    my @list;
    local(*LIVE);
    if (open(LIVE, $LIVE_LIST_PATH)) {
	while (<LIVE>) {
	    chomp;
	    s/^\s*//;
	    s/\s*#.*$//;
	    next if /^$/;
	    push(@list, $_);
	}
	close(LIVE);
    } else {
	warn "$LIVE_LIST_PATH: $!\n";
    }
    if (!@list) {
	warn "Wing::Balance: no live WING servers found in $LIVE_LIST_PATH\n";
    }
    return @list;
}

sub get_live_list_mtime {
    my $mtime = (stat($LIVE_LIST_PATH))[9];
    return $mtime;
}

#
# This is the query handler
#
sub handler {
    my $r = shift;
    my $uri = $r->uri;
    my $username = "";

    my $new_mtime = get_live_list_mtime();
    if ($new_mtime > $live_list_mtime) {
	@live_list = get_live_list();
	$live_list_mtime = $new_mtime;
    }

    if (@live_list == 0) {
	return DECLINED;
    }

    if ($uri =~ m{^/login/([a-zA-Z0-9]+)/?$}) {
	$username = $1;
    }
    elsif ($uri ne "/index.html") {
	# Note that "GET /" turns into /index.html by the time it reaches us
	return DECLINED;
    }
    my $j = (time + $$ + $i++) % @live_list;
    $i = 0 if $i > $#live_list;		# simply not to worry about wrapping
    my $server_url = server_url($r, $live_list[$j]);
    my $action = "$server_url/wing/login";
    $action .= "/$username" if $username;

    #
    # Read /etc/motd.wing or equivalent
    #
    my $motd;
    {
	local($/) = undef; # slurp
	local(*MOTD);
	open(MOTD, $MOTD_PATH);
	$motd = <MOTD>;
	close(MOTD);
    }

    # Tab order - username is first if not filled in, last otherwise
    my $user_tab = $username ? 5 : 1;

    #
    # Generate the login screen
    #
    dont_cache($r, "text/html");
    $r->print(<<"EOT");
<html><head><title>$LOGIN_TITLE</title>
<body><h1 align="center">$LOGIN_TITLE</h1>
<form action="$action" method="POST">
<table cellpadding=5>
<tr>
  <td rowspan=4>
    $LOGIN_LOGO
  </td>
  <td>Username</td>
  <td><input name="username" value="$username" size=8 maxlength=8 tabindex=$user_tab></td>
</tr>
<tr>
  <td>Password</td>
  <td><input type="password" name="password" size=16 tabindex=2></td>
</tr>
<tr>
  <td>Session type</td>
  <td>
    <select name="sess_type" size=1 tabindex=3>
      <option value="" selected>Normal</option>
      <option value="portal">Portal (requires frames)</option>
    </select>
  </td>
</tr>
<tr>
  <td>
    <input type="submit" name="login" value="Login" tabindex=4>
  </td>
</tr>
</table>
</form>
$motd
</body></html>
EOT
    return OK;
}

1;

