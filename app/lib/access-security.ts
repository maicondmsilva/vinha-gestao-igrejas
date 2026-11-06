// Only verified server identities and database memberships may reach these policies.
export function selectActiveMembership<T extends { organization_id: string; organization_slug: string; status: string }>(
 memberships: T[], hint: string, preferred?: string | null,
): T | null {
 const active = memberships.filter(item => item.status === 'active');
 if (hint) return active.find(item => item.organization_id === hint || item.organization_slug === hint) || null;
 if (preferred) return active.find(item => item.organization_id === preferred) || null;
 return active.length === 1 ? active[0] : null;
}

export function trustedSessionRequest(request: Request): boolean {
 if (['GET', 'HEAD', 'OPTIONS'].includes(request.method)) return true;
 // A bearer token is never attached by the browser on its own, so it carries no CSRF risk. It is only
 // honoured without cookies (createSupabaseRequestClient), so a cookie session still needs the origin check.
 if (!request.headers.get('cookie') && /^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(request.headers.get('authorization') || '')) return true;
 if (request.headers.get('sec-fetch-site') === 'cross-site') return false;
 // Browser session writes require an exact origin; no forwarded/host-header trust.
 return request.headers.get('origin') === new URL(request.url).origin;
}

type Operator = { full_name: string; role: string };
type VerifiedClient = {
 auth: {
  getUser: () => Promise<{ data: { user: { id: string; email?: string } | null }; error: unknown }>;
  mfa: { getAuthenticatorAssuranceLevel: () => Promise<{ data: { currentLevel: string | null } | null; error: unknown }> };
 };
 rpc: (name: 'platform_operator_context') => PromiseLike<{ data: Operator[] | null; error: unknown }>;
};
export async function verifiedPlatformIdentity(client: VerifiedClient, method: string) {
 try {
  const identity = await client.auth.getUser();
  if (identity.error || !identity.data.user) return null;
  const [operators, assurance] = await Promise.all([
   client.rpc('platform_operator_context'), client.auth.mfa.getAuthenticatorAssuranceLevel(),
  ]);
  if (operators.error || assurance.error || assurance.data?.currentLevel !== 'aal2') return null;
  // Ambiguous or malformed operator context must not grant access.
  if (!Array.isArray(operators.data) || operators.data.length !== 1) return null;
  const operator = operators.data[0];
  if (!['owner', 'admin', 'support', 'read_only'].includes(operator.role)) return null;
  if (!['GET', 'HEAD', 'OPTIONS'].includes(method) && !['owner', 'admin'].includes(operator.role)) return null;
  return { user: identity.data.user, operator };
 } catch { return null; }
}
