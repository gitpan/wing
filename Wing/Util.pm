#
# WING - Web-IMAP/NNTP Gateway
#
# Wing/Util.pm
#
# Author: Malcolm Beattie, mbeattie@sable.ox.ac.uk
#
# This program may be distributed under the GNU General Public License (GPL)
#
# 25 Aug 1998  Copied from development system to main cluster.
#
#
# Utility functions for Wing.pm
#
package Wing::Util;
use Apache::Constants qw(:common REDIRECT);
use Wing::Shared;
use strict;
use vars qw(@ISA @EXPORT);
@ISA = 'Exporter';
@EXPORT = qw(&dont_cache &redirect &wing_error &info_message_html);
#	     &address_search &address_update &address_delete);

#
# Prevent browser from caching: a simple $r->no_cache(1) is insufficient.
# If the second argument is specified, it's a MIME type which we send
# along with the send_http_header for convenience.
#
sub dont_cache ($;$) {
    my ($r, $type) = @_;
    $r->no_cache(1);
    $r->err_header_out(Pragma => "no-cache");
    $r->err_header_out("Cache-control" => "no-cache");
    if (defined($type)) {
	$r->content_type($type);
	$r->send_http_header;
    }
}

#
# Redirect browser to another URL
#
sub redirect ($$) {
    my ($r, $url) = @_;
    $r->header_out(Location => $url);
    $r->status(REDIRECT);
    $r->send_http_header;
    return OK;
}

#
# Generate a standard WING error message page. This is for errors
# that Should Not Happen (e.g. the user has been messing with
# explicit URLs or trying something naughty) so we don't care too
# much for user-friendliness.
#
sub wing_error ($$) {
    my ($r, $message) = @_;
    dont_cache($r, "text/html");
    $r->print(<<"EOT");
<html><head><title>WING Error</title></head>
<body><h1>WING Error</h1>
$message
</body></html>
EOT
    return OK;
}

sub info_message_html {
    my $s = shift;
    my $info = maild_get_and_reset($s, "message");
    if ($info) {
	$info = "<br><strong>$info</strong></br>\n";
    }
    return $info;
}

#
# Do an address search and return a list of matching entries, each
# [alias, comment, address, abook]. If there's no specific target
# to look for we return either a single "blank" entry which only
# contains the "place" passed or else the empty list if there isn't
# even a "place". If an explicit search fails then we return the
# single entry undef.
#
=for nothing

sub address_search {
    my ($conn, $target, $searchin) = @_;
    my $r = $conn->{request};
    my $s = $conn->{maild};
    #
    # search for $target in $searchin (default/own/main/LDAP root dn/abookname)
    $r->warn("address_search for $target in $searchin");#debug

    if ($searchin =~ /=/) {
	#
	# Anything with an = is taken to be an LDAP root dn
	#

	# XXX do an LDAP search
	return ["", "", "", ""];
    }
    my $dbh = DBI->connect(@WING_DBI_CONNECT_ARGS);
    my $error = Wing::Abook->init($dbh);
    if ($error) {
	$r->warn("Wing::Abook::init failed: $error");
	return ["", "", "", ""]; # XXX should notify user nicely
    }
    my @abooks;
    my @matches;
    print $s "username\n";
    chomp(my $username = <$s>);
    if ($searchin eq "own") {
	@abooks = Wing::Abook->list($username);
    } elsif ($searchin eq "main") {
	my $mainabook = Wing::Abook->new($username);
	@abooks = $mainabook if defined $mainabook;
	$r->warn("main abook for $username has id ", $mainabook ? $mainabook->id : "<undef>");#debug
    } elsif ($searchin eq "default") {
	print $s "get abook_list\n";
	chomp(my $result = <$s>);
	# split "fred:bill.public:o=Foo, c=xy:george.shared"
	@abooks = split(/:/, $result);
	# turn them into Wing::Abook objects
	@abooks = map { Wing::Abook->new($_) } @abooks;
	# throw out any that don't exist
	@abooks = grep { defined } @abooks;
    } else {
	my $abook = Wing::Abook->new($searchin);
	@abooks = $abook if defined $abook;
    }
    #
    # Strip out abooks for which permissions are not suitable
    #
#    $r->warn("before perms: abooks=", join(", ",map {$_->name} @abooks));#debug
    #
    # XXX Need to look up group and tell maild on login so we can ask it now.
    #
    @abooks = grep { $_->check_perm("XXX", $username) } @abooks;
#    $r->warn("after perms: abooks=", join(", ", map {$_->name} @abooks));#debug

    #
    # Go through each object in @abooks and hunt for $target.
    # We first make a note of whether it's a straight key lookup
    # for an alias or a trawl through looking for addresses.
    #
    my $alias_lookup = $target !~ /[@ *]/;
    foreach my $ab (@abooks) {
#	$r->warn("searching in abook id ", $ab->id);#debug
	if ($alias_lookup) {
	    my ($comment, $address) = $ab->get_entry($target);
	    if (defined($comment)) {
		push(@matches, [$target, $comment, $address, $ab->name]);
	    }
	} else {
	    # XXX address searches not yet implemented
	}
    }
    if (!@matches && $target =~ /^[a-z]{1,8}$/) {
	#
	# Fall back to looking sane usernames up in users table
	#
	my $address = "";
	my $sth = $dbh->prepare(
	    "select sender from users where username = '$target'"
	);
	if ($sth) {
	    if ($sth->execute) {
		$address = $sth->fetchrow_arrayref->[0];
	    }
	    $sth->finish;
	}
	return [$target, "", $address, ""];
    }
    return @matches ? @matches : [$target, "", "", ""];
}

sub address_update {
    my ($conn, $alias, $comment, $address, $abook) = @_;
    my $r = $conn->{request};
    my $s = $conn->{maild};
    print $s "username\n";
    chomp(my $username = <$s>);
    my $dbh = DBI->connect(@WING_DBI_CONNECT_ARGS);
    my $error = Wing::Abook->init($dbh);
    if ($error) {
	$r->warn("Wing::Abook::init failed: $error");
	return "failed to initialise address book database";
    }
    my $ab = Wing::Abook->new($abook);
    if (!$ab) {
	#
	# It doesn't exist but we will implicitly create it provided
	# it's an address book owned by this username.
	# XXX We parse $abook ourselves (user or user.tag) whereas we
	# maybe should export such a function from Wing::Abook in case
	# we ever want to change how address books are named.
	#
	my $req_owner = $abook;
	$req_owner =~ s/\.(.*)//;
	if ($req_owner eq $username) {
	    Wing::Abook->create($abook)
		or return "Cannot create new address book $abook";
	}
	$ab = Wing::Abook->new($abook)
	    or return "Cannot re-open newly created address book $abook";
    }
    return "You do not have permission to update address book $abook"
	unless $ab->owner eq $username;
    #
    # Rather than check for existence and then choose between insert
    # and store we just do a straight delete (ignoring errors) then add.
    #
    $ab->delete_entry($alias);
    $ab->add_entry($alias, $comment, $address)
	or return "Failed to update or add entry $alias to address book $abook";
    return 0;
}

sub address_delete {
    my ($conn, $alias, $abook) = @_;
    my $r = $conn->{request};
    my $s = $conn->{maild};
    print $s "username\n";
    chomp(my $username = <$s>);
    my $dbh = DBI->connect(@WING_DBI_CONNECT_ARGS);
    my $error = Wing::Abook->init($dbh);
    if ($error) {
	$r->warn("Wing::Abook::init failed: $error");
	return "failed to initialise address book database";
    }
    my $ab = Wing::Abook->new($abook) or return "No such address book: $abook";
    return "You do not have permission to update address book $abook"
	unless $ab->owner eq $username;
    $ab->delete_entry($alias)
	or return "Failed to delete entry $alias from address book $abook";
    return 0;
}

=cut

1;

