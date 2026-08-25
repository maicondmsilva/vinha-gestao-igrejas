import { integer, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

export const churches = sqliteTable('churches', {
  id: text('id').primaryKey(), name: text('name').notNull(), appName: text('app_name').notNull(),
  slug: text('slug').notNull(), primaryColor: text('primary_color').notNull().default('#285c45'),
  accentColor: text('accent_color').notNull().default('#d8b769'), logoKey: text('logo_key'),
  openingVideoKey: text('opening_video_key'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_churches_slug').on(table.slug)]);

export const churchUsers = sqliteTable('church_users', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  externalUserId: text('external_user_id').notNull(), email: text('email').notNull(), name: text('name').notNull(),
  role: text('role').notNull().default('member'), status: text('status').notNull().default('active'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_church_users_tenant_external').on(table.churchId, table.externalUserId)]);

export const families = sqliteTable('families', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  name: text('name').notNull(), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const people = sqliteTable('people', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  familyId: text('family_id').references(() => families.id), fullName: text('full_name').notNull(),
  email: text('email'), phone: text('phone'), journeyStatus: text('journey_status').notNull().default('visitor'),
  groupName: text('group_name'), joinedAt: integer('joined_at', { mode: 'timestamp' }),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_people_tenant_email').on(table.churchId, table.email)]);
