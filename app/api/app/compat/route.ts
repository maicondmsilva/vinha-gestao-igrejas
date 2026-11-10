import {compatFor, versionValid, vinhaApps, type VinhaApp} from '../../../../shared/contract/apps.ts';

// Public and cacheable: tells a native build whether it can keep talking to this platform.
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams,
    app = q.get('app') || '',
    version = q.get('version') || '';
  if (!(app in vinhaApps) || !versionValid(version))
    return Response.json({error: 'Informe o aplicativo e a versão.', code: 'validation'}, {status: 400, headers: {'Cache-Control': 'no-store'}});
  return Response.json(compatFor(app as VinhaApp, version), {headers: {'Cache-Control': 'public, max-age=300'}});
}
