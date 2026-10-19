import { sites } from '@openai/sites-vite-plugin';
import tailwindcss from '@tailwindcss/vite';
import vinext from 'vinext';
import { defineConfig } from 'vite';
import hostingConfig from './.openai/hosting.json';
import { nitro } from 'nitro/vite';
import { fileURLToPath } from 'node:url';
import {assertDeploymentIsolation} from './app/lib/deployment-safety';

const SITE_CREATOR_PLACEHOLDER_DATABASE_ID =
  '00000000-0000-4000-8000-000000000000';

const { d1, r2 } = hostingConfig;

// macOS Seatbelt blocks FSEvents, so Codex previews need polling for HMR.
const isCodexSeatbeltSandbox = process.env.CODEX_SANDBOX === 'seatbelt';

const localBindingConfig = {
  main: './worker.ts',
  triggers: { crons: ['*/5 * * * *'] },
  compatibility_flags: ['nodejs_compat'],
  d1_databases: d1
    ? [
        {
          binding: d1,
          database_name: 'site-creator-d1',
          database_id: SITE_CREATOR_PLACEHOLDER_DATABASE_ID,
        },
      ]
    : [],
  r2_buckets: r2
    ? [
        {
          binding: r2,
          bucket_name: 'site-creator-r2',
        },
      ]
    : [],
};

export default defineConfig(async ({command}) => {
  assertDeploymentIsolation(process.env);
  // Keep Wrangler and Miniflare state project-local. These are non-secret tool
  // settings; application environment belongs in ignored `.env*` files.
  process.env.WRANGLER_WRITE_LOGS ??= 'false';
  process.env.WRANGLER_LOG_PATH ??= '.wrangler/logs';
  process.env.MINIFLARE_REGISTRY_PATH ??= '.wrangler/registry';

  // Wrangler snapshots its log path while the Cloudflare plugin is imported.
  const isVercelBuild = Boolean(process.env.VERCEL || process.env.NITRO_PRESET === 'vercel');
  // Nitro's fetchable dev environment has no RSC `runner`. Use Vinext's native
  // runner only for the Docker-local preview; deployment builds retain Nitro.
  const localPreview = command === 'serve' && process.env.NEXT_PUBLIC_VINHA_ENV === 'local';
  const { cloudflare } = isVercelBuild ? { cloudflare: null } : await import('@cloudflare/vite-plugin');

  return {
    server: isCodexSeatbeltSandbox
      ? { watch: { useFsEvents: false, usePolling: true } }
      : undefined,
    resolve: isVercelBuild ? {
      alias: {
        'cloudflare:workers': fileURLToPath(new URL('./app/lib/cloudflare-env-stub.ts', import.meta.url)),
      },
    } : undefined,
    plugins: isVercelBuild
      ? [vinext(), tailwindcss(), ...(localPreview ? [] : [nitro()])]
      : [
          vinext(),
          tailwindcss(),
          sites(),
          cloudflare!({
            viteEnvironment: { name: 'rsc', childEnvironments: ['ssr'] },
            config: localBindingConfig,
          }),
        ],
  };
});
