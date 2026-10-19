-- Cover complete foreign-key scopes, including archived records.
create index cell_categories_unit_fk_idx on public.church_cell_categories(unit_id,organization_id);
create index cell_category_links_cell_fk_idx on public.church_cell_category_links(cell_id,organization_id,unit_id);
create index cell_participants_cell_fk_idx on public.church_cell_participants(cell_id,organization_id,unit_id);
create index cell_meetings_cell_fk_idx on public.church_cell_meetings(cell_id,organization_id,unit_id);
create index cell_attendance_meeting_fk_idx on public.church_cell_attendance(meeting_id,cell_id,organization_id,unit_id);
