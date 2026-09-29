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

export const churchUnits = sqliteTable('church_units', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  parentUnitId: text('parent_unit_id'), name: text('name').notNull(), type: text('type').notNull().default('campus'),
  slug: text('slug').notNull(), legalName: text('legal_name'), taxId: text('tax_id'), pastorName: text('pastor_name'),
  email: text('email'), phone: text('phone'), postalCode: text('postal_code'), street: text('street'), number: text('number'),
  complement: text('complement'), district: text('district'), city: text('city'), state: text('state'),
  financialAutonomy: integer('financial_autonomy', { mode: 'boolean' }).notNull().default(false),
  communicationAutonomy: integer('communication_autonomy', { mode: 'boolean' }).notNull().default(true),
  brandingAutonomy: integer('branding_autonomy', { mode: 'boolean' }).notNull().default(false),
  status: text('status').notNull().default('active'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_church_units_slug').on(table.churchId, table.slug), index('idx_church_units_parent').on(table.churchId, table.parentUnitId)]);

export const userUnitAccess = sqliteTable('user_unit_access', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  userId: text('user_id').notNull().references(() => churchUsers.id), unitId: text('unit_id').notNull().references(() => churchUnits.id),
  role: text('role').notNull().default('viewer'), includeChildren: integer('include_children', { mode: 'boolean' }).notNull().default(false),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_user_unit_access_unique').on(table.churchId, table.userId, table.unitId), index('idx_user_unit_access_user').on(table.churchId, table.userId)]);

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

export const events = sqliteTable('events', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  unitId: text('unit_id').references(() => churchUnits.id), createdByUserId: text('created_by_user_id').notNull().references(() => churchUsers.id),
  title: text('title').notNull(), publicSlug: text('public_slug').notNull(), description: text('description').notNull(), category: text('category').notNull().default('Geral'),
  format: text('format').notNull().default('presential'), locationName: text('location_name'), address: text('address'), onlineUrl: text('online_url'),
  startsAt: integer('starts_at', { mode: 'timestamp' }).notNull(), endsAt: integer('ends_at', { mode: 'timestamp' }).notNull(),
  scope: text('scope').notNull().default('unit'), registrationMode: text('registration_mode').notNull().default('public'),
  capacity: integer('capacity'), status: text('status').notNull().default('draft'), publishedAt: integer('published_at', { mode: 'timestamp' }),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(), updatedAt: integer('updated_at', { mode: 'timestamp' }),
}, table => [uniqueIndex('idx_events_public_slug').on(table.publicSlug), index('idx_events_church_unit_start').on(table.churchId, table.unitId, table.startsAt)]);

export const eventTickets = sqliteTable('event_tickets', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id), eventId: text('event_id').notNull().references(() => events.id),
  name: text('name').notNull(), priceCents: integer('price_cents').notNull().default(0), quantity: integer('quantity'),
  salesStartAt: integer('sales_start_at', { mode: 'timestamp' }), salesEndAt: integer('sales_end_at', { mode: 'timestamp' }),
  status: text('status').notNull().default('active'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [index('idx_event_tickets_event').on(table.churchId, table.eventId)]);

export const eventMedia = sqliteTable('event_media', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  eventId: text('event_id').notNull().references(() => events.id), objectKey: text('object_key').notNull(),
  mediaType: text('media_type').notNull().default('gallery'), altText: text('alt_text'), sortOrder: integer('sort_order').notNull().default(0),
  contentType: text('content_type').notNull(), sizeBytes: integer('size_bytes').notNull(), createdByUserId: text('created_by_user_id').notNull(),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_event_media_object_key').on(table.objectKey), index('idx_event_media_event').on(table.churchId, table.eventId, table.mediaType, table.sortOrder)]);

export const eventScheduleItems = sqliteTable('event_schedule_items', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id), eventId: text('event_id').notNull().references(() => events.id),
  title: text('title').notNull(), description: text('description'), location: text('location'), startsAt: integer('starts_at', { mode: 'timestamp' }).notNull(), endsAt: integer('ends_at', { mode: 'timestamp' }),
  sortOrder: integer('sort_order').notNull().default(0), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [index('idx_event_schedule_event').on(table.churchId, table.eventId, table.startsAt)]);

export const eventGuests = sqliteTable('event_guests', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id), eventId: text('event_id').notNull().references(() => events.id),
  name: text('name').notNull(), role: text('role'), biography: text('biography'), profileUrl: text('profile_url'), sortOrder: integer('sort_order').notNull().default(0),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [index('idx_event_guests_event').on(table.churchId, table.eventId, table.sortOrder)]);

export const eventOrganizers = sqliteTable('event_organizers', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id), eventId: text('event_id').notNull().references(() => events.id),
  name: text('name').notNull(), role: text('role'), email: text('email'), phone: text('phone'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [index('idx_event_organizers_event').on(table.churchId, table.eventId)]);

export const eventRegistrations = sqliteTable('event_registrations', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id), eventId: text('event_id').notNull().references(() => events.id),
  ticketId: text('ticket_id').notNull().references(() => eventTickets.id), personId: text('person_id').references(() => people.id),
  fullName: text('full_name').notNull(), email: text('email').notNull(), phone: text('phone'), document: text('document'),
  quantity: integer('quantity').notNull().default(1), amountCents: integer('amount_cents').notNull().default(0),
  paymentStatus: text('payment_status').notNull().default('not_required'), registrationStatus: text('registration_status').notNull().default('confirmed'),
  checkinToken: text('checkin_token').notNull(), checkedInAt: integer('checked_in_at', { mode: 'timestamp' }),
  consentSnapshot: text('consent_snapshot', { mode: 'json' }).$type<Record<string,unknown>>(), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_event_registration_token').on(table.checkinToken), index('idx_event_registration_event').on(table.churchId, table.eventId)]);

export const eventCoupons = sqliteTable('event_coupons', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id), eventId: text('event_id').notNull().references(() => events.id),
  code: text('code').notNull(), discountType: text('discount_type').notNull().default('percent'), discountValue: integer('discount_value').notNull(),
  maxUses: integer('max_uses'), usedCount: integer('used_count').notNull().default(0), startsAt: integer('starts_at', { mode: 'timestamp' }),
  endsAt: integer('ends_at', { mode: 'timestamp' }), status: text('status').notNull().default('active'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_event_coupon_code').on(table.churchId, table.eventId, table.code), index('idx_event_coupons_event').on(table.churchId, table.eventId)]);

export const paymentProviderSettings = sqliteTable('payment_provider_settings', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id), provider: text('provider').notNull(),
  displayName: text('display_name').notNull(), accountReference: text('account_reference'), environment: text('environment').notNull().default('sandbox'),
  methods: text('methods', { mode: 'json' }).$type<string[]>().notNull().default([]), status: text('status').notNull().default('not_configured'),
  credentialCiphertext: text('credential_ciphertext'), credentialIv: text('credential_iv'), credentialHint: text('credential_hint'),
  webhookTokenCiphertext: text('webhook_token_ciphertext'), webhookTokenIv: text('webhook_token_iv'),
  lastTestedAt: integer('last_tested_at', { mode: 'timestamp' }), lastTestStatus: text('last_test_status'),
  isPrimary: integer('is_primary', { mode: 'boolean' }).notNull().default(false), updatedByUserId: text('updated_by_user_id').notNull(),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(), updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_payment_provider_church').on(table.churchId, table.provider), index('idx_payment_provider_primary').on(table.churchId, table.isPrimary)]);

export const eventPaymentOrders = sqliteTable('event_payment_orders', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  eventId: text('event_id').notNull().references(() => events.id), registrationId: text('registration_id').notNull().references(() => eventRegistrations.id),
  provider: text('provider').notNull(), paymentMethod: text('payment_method').notNull().default('all'), amountCents: integer('amount_cents').notNull(),
  currency: text('currency').notNull().default('BRL'), providerPaymentId: text('provider_payment_id'), checkoutUrl: text('checkout_url'),
  status: text('status').notNull().default('created'), expiresAt: integer('expires_at', { mode: 'timestamp' }),
  feeCents: integer('fee_cents').notNull().default(0), netAmountCents: integer('net_amount_cents'),
  settledAt: integer('settled_at', { mode: 'timestamp' }), reconciliationStatus: text('reconciliation_status').notNull().default('pending'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(), updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_event_payment_registration').on(table.registrationId), uniqueIndex('idx_event_payment_provider_id').on(table.provider, table.providerPaymentId), index('idx_event_payment_church_status').on(table.churchId, table.status)]);

export const paymentWebhookEvents = sqliteTable('payment_webhook_events', {
  id: text('id').primaryKey(), provider: text('provider').notNull(), externalEventId: text('external_event_id').notNull(),
  eventType: text('event_type'), status: text('status').notNull().default('received'), payload: text('payload', { mode: 'json' }).$type<Record<string,unknown>>(),
  receivedAt: integer('received_at', { mode: 'timestamp' }).notNull(), processedAt: integer('processed_at', { mode: 'timestamp' }),
}, table => [uniqueIndex('idx_payment_webhook_provider_event').on(table.provider, table.externalEventId)]);

export const appRegistrationRequests = sqliteTable('app_registration_requests', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id),
  unitId: text('unit_id').notNull().references(() => churchUnits.id), externalUserId: text('external_user_id').notNull(),
  matchedPersonId: text('matched_person_id').references(() => people.id), fullName: text('full_name').notNull(),
  cpf: text('cpf'), email: text('email').notNull(), phone: text('phone').notNull(), birthDate: text('birth_date'),
  themePreference: text('theme_preference').notNull().default('system'), status: text('status').notNull().default('new_pending'),
  matchScore: integer('match_score').notNull().default(0), matchReason: text('match_reason'), requestedAt: integer('requested_at', { mode: 'timestamp' }).notNull(),
  reviewedByUserId: text('reviewed_by_user_id'), reviewedAt: integer('reviewed_at', { mode: 'timestamp' }), decisionNote: text('decision_note'),
}, table => [uniqueIndex('idx_app_registration_external').on(table.churchId, table.externalUserId), index('idx_app_registration_queue').on(table.churchId, table.unitId, table.status, table.requestedAt)]);

export const saasPlans = sqliteTable('saas_plans', {
  id: text('id').primaryKey(), code: text('code').notNull(), name: text('name').notNull(), description: text('description'),
  basePriceCents: integer('base_price_cents').notNull().default(0), billingCycle: text('billing_cycle').notNull().default('monthly'),
  active: integer('active', { mode: 'boolean' }).notNull().default(true), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_saas_plans_code').on(table.code)]);

export const saasSubscriptions = sqliteTable('saas_subscriptions', {
  id: text('id').primaryKey(), churchId: text('church_id').notNull().references(() => churches.id), planId: text('plan_id').notNull().references(() => saasPlans.id),
  status: text('status').notNull().default('trialing'), appAddon: integer('app_addon', { mode: 'boolean' }).notNull().default(false),
  trialEndsAt: integer('trial_ends_at', { mode: 'timestamp' }), currentPeriodEnd: integer('current_period_end', { mode: 'timestamp' }),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull(), updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_saas_subscription_church').on(table.churchId)]);

export const saasSubscriptionModules = sqliteTable('saas_subscription_modules', {
  id: text('id').primaryKey(), subscriptionId: text('subscription_id').notNull().references(() => saasSubscriptions.id), moduleCode: text('module_code').notNull(),
  enabled: integer('enabled', { mode: 'boolean' }).notNull().default(true), limitValue: integer('limit_value'), createdAt: integer('created_at', { mode: 'timestamp' }).notNull(),
}, table => [uniqueIndex('idx_saas_subscription_module').on(table.subscriptionId, table.moduleCode)]);

export const saasOnboardingProgress = sqliteTable('saas_onboarding_progress', {
  churchId: text('church_id').primaryKey().references(() => churches.id),
  status: text('status').notNull().default('in_progress'), currentStep: text('current_step').notNull().default('identity'),
  completedSteps: text('completed_steps', { mode: 'json' }).$type<string[]>().notNull().default([]),
  startedAt: integer('started_at', { mode: 'timestamp' }).notNull(), updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull(),
  completedAt: integer('completed_at', { mode: 'timestamp' }), updatedByUserId: text('updated_by_user_id').references(() => churchUsers.id),
}, table => [index('idx_saas_onboarding_status').on(table.status, table.updatedAt)]);
