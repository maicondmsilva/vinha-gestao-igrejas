// Platform ↔ app handshake. Every native request says who it is (`x-vinha-client`), and the apps ask
// `/api/app/compat` at start so the platform can ask for an update before an old build talks to a changed API.

/** Bumped when an API used by the apps changes in a way an old build cannot handle. */
export const contractVersion = 1;
export const clientHeader = 'x-vinha-client';

export const vinhaApps = {
  staff: {name: 'Vinha Equipe', minimum: '0.1.0', latest: '0.1.0'},
  member: {name: 'Aplicativo do ministério', minimum: '0.1.0', latest: '0.1.0'},
} as const;
export type VinhaApp = keyof typeof vinhaApps;
export type ClientInfo = {app: VinhaApp; version: string; platform: 'android' | 'ios' | 'web' | 'other'};
export type CompatStatus = 'ok' | 'update_available' | 'update_required';
export type CompatResponse = {app: VinhaApp; version: string; status: CompatStatus; minimum: string; latest: string; contract: number; message: string};

const semver = /^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$/;
export const versionValid = (v: string) => semver.test(v);

/** -1, 0 or 1, comparing numeric x.y.z versions. */
export function compareVersions(a: string, b: string) {
  const pa = a.split('.').map(Number),
    pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) < (pb[i] || 0) ? -1 : 1;
  return 0;
}

/** Header value the apps send: `staff/0.1.0 (android)`. */
export const clientHeaderValue = (c: ClientInfo) => `${c.app}/${c.version} (${c.platform})`;

export function parseClient(value: string | null | undefined): ClientInfo | null {
  const m = /^(staff|member)\/(\d{1,4}\.\d{1,4}\.\d{1,4}) \((android|ios|web|other)\)$/.exec(value || '');
  return m ? {app: m[1] as VinhaApp, version: m[2], platform: m[3] as ClientInfo['platform']} : null;
}

export function compatFor(app: VinhaApp, version: string): CompatResponse {
  const a = vinhaApps[app];
  const status: CompatStatus = compareVersions(version, a.minimum) < 0 ? 'update_required' : compareVersions(version, a.latest) < 0 ? 'update_available' : 'ok';
  const message =
    status === 'update_required'
      ? `Esta versão do ${a.name} não é mais compatível. Atualize pela loja de aplicativos para continuar.`
      : status === 'update_available'
        ? `Há uma versão nova do ${a.name} na loja.`
        : '';
  return {app, version, status, minimum: a.minimum, latest: a.latest, contract: contractVersion, message};
}
