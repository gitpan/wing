--
-- Initialise user tables.
-- Must be run as root (not the PostgreSQL superuser).
--

drop index users_uid_ix;
drop table users;

create table users (
	username	char(8)		not null primary key,
	uid		integer		not null,
	gid		integer		not null,
	sender		text,		-- canonical sender email address
	quota		integer
);
create unique index users_uid_ix on users (uid);

--
-- Once we do a grant, PostgreSQL removes the implicit right that
-- the table creator has on the table. Blech. We have to explicitly
-- grant ourselves access rights.
--
grant all on users to root;
grant select on users to public;

drop index groups_gid_ix;
drop table groups;

create table groups (
	name		char(8)		not null primary key,
	gid		integer		not null
);
create unique index groups_gid_ix on groups (gid);

grant all on groups to root;
grant select on groups to public;
