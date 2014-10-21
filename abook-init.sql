--
-- Initialise WING address book tables.
-- Must be run as the httpd user.
--

create sequence abook_ids_seq;

drop table abook_ids;
create table abook_ids (
	id		int	default nextval('abook_ids_seq') not null,
	username	char8	not null,
	tag		text	not null
);

drop index abook_ids_idx;
create unique index abook_ids_idx on abook_ids (username, tag);

drop table abook_perms;
create table abook_perms (
	id		int	not null,	-- Address book id
	type		char	not null,	-- (u)ser, (g)roup, (o)ther
	name		char8	not null	-- username or groupname
);

drop table abook_aliases;
create table abook_aliases (
	id		int	not null,	-- Address book id
	alias		text	not null,
	first_name	text	not null,
	last_name	text	not null,
	comment		text	not null,
	email		text	not null
);
