-- No access expansion: internal writes still require the validated owner RPC.
set local lock_timeout='3s';
set local statement_timeout='30s';
create index finance_entries_unit_fk on private.finance_entries(unit_id,organization_id);
create policy finance_catalog_deny_direct on private.finance_catalog as restrictive for all to public using(false) with check(false);
create policy finance_links_deny_direct on private.finance_account_links as restrictive for all to public using(false) with check(false);
create policy finance_entries_deny_direct on private.finance_entries as restrictive for all to public using(false) with check(false);
