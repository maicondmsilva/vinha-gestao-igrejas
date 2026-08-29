import { index, integer, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

export const churches = sqliteTable('churches', {
  id: text('id').primaryKey(), name: text('name').notNull(), appName: text('app_name').notNull(),
  slug: text('slug').notNull(), primaryColor: text('primary_color').notNull().default('#285c45'),
  accentColor: text('accent_color').notNull().default('#d8b769'), logoKey: text('logo_key'),
  openingVideoKey: text('opening_video_key'), seniorPastorName: text('senior_pastor_name').notNull().default('Pastor titular'),
  seniorPastorCpf: text('senior_pastor_cpf'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_churches_slug').on(table.slug)]);

export const churchUsers = sqliteTable('church_users', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  personId: text('person_id'),
  externalUserId: text('external_user_id').notNull(), email: text('email').notNull(), name: text('name').notNull(),
  role: text('role').notNull().default('member'), status: text('status').notNull().default('active'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_church_users_tenant_external').on(table.churchId, table.externalUserId)]);

export const auditLogs = sqliteTable('audit_logs', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  actorUserId: text('actor_user_id').notNull(), action: text('action').notNull(), entityType: text('entity_type').notNull(),
  entityId: text('entity_id'), metadata: text('metadata', { mode: 'json' }).$type<Record<string, unknown>>(),
  ipAddress: text('ip_address'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const families = sqliteTable('families', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  name: text('name').notNull(), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const familyMembers = sqliteTable('family_members', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  familyId: text('family_id').notNull().references(() => families.id), personId: text('person_id').notNull(),
  relationship: text('relationship').notNull(), isGuardian: integer('is_guardian', { mode: 'boolean' }).notNull().default(false),
  canPickupMinor: integer('can_pickup_minor', { mode: 'boolean' }).notNull().default(false),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_family_member_unique').on(table.churchId, table.familyId, table.personId)]);

export const people = sqliteTable('people', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  familyId: text('family_id').references(() => families.id), fullName: text('full_name').notNull(),
  photoKey: text('photo_key'), birthDate: text('birth_date'), gender: text('gender'),
  maritalStatus: text('marital_status'), cpf: text('cpf'), email: text('email'), phone: text('phone'),
  familyRelationship: text('family_relationship'), journeyStatus: text('journey_status').notNull().default('visitor'),
  campus: text('campus'), groupName: text('group_name'), firstVisitAt: integer('first_visit_at', { mode: 'timestamp' }),
  joinedAt: integer('joined_at', { mode: 'timestamp' }), baptized: integer('baptized', { mode: 'boolean' }).notNull().default(false),
  baptismDate: text('baptism_date'), tags: text('tags', { mode: 'json' }).$type<string[]>().notNull().default([]),
  appRole: text('app_role').notNull().default('member'), status: text('status').notNull().default('active'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_people_tenant_email').on(table.churchId, table.email)]);

export const personAddresses = sqliteTable('person_addresses', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  personId: text('person_id').notNull().references(() => people.id), postalCode: text('postal_code'),
  street: text('street'), number: text('number'), complement: text('complement'), district: text('district'),
  city: text('city'), state: text('state'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_person_addresses_person').on(table.churchId, table.personId)]);

export const emergencyContacts = sqliteTable('emergency_contacts', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  personId: text('person_id').notNull().references(() => people.id), name: text('name').notNull(),
  relationship: text('relationship'), phone: text('phone').notNull(), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const personMinistries = sqliteTable('person_ministries', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  personId: text('person_id').notNull().references(() => people.id), ministryName: text('ministry_name').notNull(),
  functionName: text('function_name'), status: text('status').notNull().default('active'),
  startedAt: integer('started_at', { mode: 'timestamp' }), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_person_ministry_unique').on(table.churchId, table.personId, table.ministryName)]);

export const personConsents = sqliteTable('person_consents', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  personId: text('person_id').notNull().references(() => people.id), consentType: text('consent_type').notNull(),
  granted: integer('granted', { mode: 'boolean' }).notNull(), source: text('source').notNull().default('admin'),
  termId: text('term_id'), acceptedByPersonId: text('accepted_by_person_id'), subjectPersonId: text('subject_person_id'),
  acceptanceSnapshot: text('acceptance_snapshot', { mode: 'json' }).$type<Record<string, unknown>>(),
  ipAddress: text('ip_address'), userAgent: text('user_agent'),
  grantedAt: integer('granted_at', { mode: 'timestamp' }), revokedAt: integer('revoked_at', { mode: 'timestamp' }),
}, table => [index('idx_person_consent_type').on(table.churchId, table.personId, table.consentType)]);

export const consentTerms = sqliteTable('consent_terms', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  consentType: text('consent_type').notNull(), title: text('title').notNull(), version: text('version').notNull(),
  content: text('content').notNull(), effectiveAt: integer('effective_at', { mode: 'timestamp' }).notNull(),
  active: integer('active', { mode: 'boolean' }).notNull().default(true), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_consent_term_version').on(table.churchId, table.consentType, table.version)]);

export const children = sqliteTable('children', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  personId: text('person_id').references(() => people.id), fullName: text('full_name').notNull(), birthDate: text('birth_date').notNull(),
  gender: text('gender'), photoKey: text('photo_key'), allergies: text('allergies'), medicalNotes: text('medical_notes'),
  specialNeeds: text('special_needs'), createdByPersonId: text('created_by_person_id'),
  createdVia: text('created_via').notNull().default('admin'), status: text('status').notNull().default('active'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const childGuardians = sqliteTable('child_guardians', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  childId: text('child_id').notNull().references(() => children.id), guardianPersonId: text('guardian_person_id').notNull().references(() => people.id),
  relationship: text('relationship').notNull(), isPrimary: integer('is_primary', { mode: 'boolean' }).notNull().default(false),
  canManage: integer('can_manage', { mode: 'boolean' }).notNull().default(true), canPickup: integer('can_pickup', { mode: 'boolean' }).notNull().default(true),
  linkedByPersonId: text('linked_by_person_id'), verifiedAt: integer('verified_at', { mode: 'timestamp' }),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_child_guardian_unique').on(table.churchId, table.childId, table.guardianPersonId)]);

export const kidsRooms = sqliteTable('kids_rooms', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  name: text('name').notNull(), minAgeMonths: integer('min_age_months').notNull().default(0),
  maxAgeMonths: integer('max_age_months').notNull().default(144), capacity: integer('capacity').notNull().default(20),
  location: text('location'), color: text('color').notNull().default('#4d8066'), status: text('status').notNull().default('active'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const kidsSessions = sqliteTable('kids_sessions', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  roomId: text('room_id').notNull().references(() => kidsRooms.id), eventName: text('event_name').notNull(),
  startsAt: integer('starts_at', { mode: 'timestamp' }).notNull(), endsAt: integer('ends_at', { mode: 'timestamp' }),
  status: text('status').notNull().default('open'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const kidsCheckins = sqliteTable('kids_checkins', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  sessionId: text('session_id').notNull().references(() => kidsSessions.id), childId: text('child_id').notNull().references(() => children.id),
  checkinGuardianId: text('checkin_guardian_id').notNull().references(() => people.id), checkoutGuardianId: text('checkout_guardian_id').references(() => people.id),
  checkinByUserId: text('checkin_by_user_id').notNull(), checkoutByUserId: text('checkout_by_user_id'),
  securityCode: text('security_code').notNull(), labelToken: text('label_token').notNull().default(''), checkedInAt: integer('checked_in_at', { mode: 'timestamp' }).notNull(),
  checkedOutAt: integer('checked_out_at', { mode: 'timestamp' }), status: text('status').notNull().default('checked_in'),
  notes: text('notes'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_kids_checkin_session_child').on(table.churchId, table.sessionId, table.childId)]);

export const kidsRoomVolunteers = sqliteTable('kids_room_volunteers', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  sessionId: text('session_id').notNull().references(() => kidsSessions.id), personId: text('person_id').notNull().references(() => people.id),
  role: text('role').notNull().default('Voluntário'), checkedInAt: integer('checked_in_at', { mode: 'timestamp' }),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_kids_volunteer_session').on(table.churchId, table.sessionId, table.personId)]);

export const kidsIncidents = sqliteTable('kids_incidents', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  sessionId: text('session_id').notNull().references(() => kidsSessions.id), childId: text('child_id').notNull().references(() => children.id),
  category: text('category').notNull(), description: text('description').notNull(), severity: text('severity').notNull().default('low'),
  guardianNotified: integer('guardian_notified', { mode: 'boolean' }).notNull().default(false),
  recordedByUserId: text('recorded_by_user_id').notNull(), occurredAt: integer('occurred_at', { mode: 'timestamp' }).notNull(),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const guardianCalls = sqliteTable('guardian_calls', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  checkinId: text('checkin_id').notNull().references(() => kidsCheckins.id), guardianPersonId: text('guardian_person_id').notNull().references(() => people.id),
  reason: text('reason').notNull(), status: text('status').notNull().default('sent'), channel: text('channel').notNull().default('app'),
  sentAt: integer('sent_at', { mode: 'timestamp' }).notNull(), acknowledgedAt: integer('acknowledged_at', { mode: 'timestamp' }),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const pastoralNotes = sqliteTable('pastoral_notes', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  personId: text('person_id').notNull().references(() => people.id), authorUserId: text('author_user_id').notNull(),
  content: text('content').notNull(), visibility: text('visibility').notNull().default('pastoral'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(), updatedAt: integer('updated_at', { mode: 'timestamp' }),
});

export const customFieldDefinitions = sqliteTable('custom_field_definitions', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  label: text('label').notNull(), fieldType: text('field_type').notNull().default('text'),
  required: integer('required', { mode: 'boolean' }).notNull().default(false), options: text('options', { mode: 'json' }).$type<string[]>(),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
});

export const personCustomFieldValues = sqliteTable('person_custom_field_values', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  personId: text('person_id').notNull().references(() => people.id),
  fieldId: text('field_id').notNull().references(() => customFieldDefinitions.id), value: text('value'),
  updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_person_custom_field').on(table.churchId, table.personId, table.fieldId)]);
