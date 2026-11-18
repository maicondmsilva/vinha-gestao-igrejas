import type {ExpoConfig} from 'expo/config';
// O arquivo roda no Node durante a geração do app (o projeto do app não carrega os tipos do Node).
declare const require: (id: string) => any;
declare const __dirname: string;
const {readdirSync, readFileSync} = require('node:fs') as {readdirSync: (p: string) => string[]; readFileSync: (p: string, e: string) => string};
const {join} = require('node:path') as {join: (...p: string[]) => string};
// Um código para todos os ministérios. Cada ministério é um arquivo brands/<perfil>.json, criado e atualizado
// pela Central da Vinha (node scripts/sync-ministry-apps.mjs). Não é preciso editar este arquivo para um novo ministério.

type Brand = {
  name: string;
  slug: string;
  ministryId: string;
  ministrySlug: string;
  previewApplicationId: string;
  previewBundleIdentifier?: string;
  /** Tema das barras do sistema; o conteúdo do app segue o tema escolhido na Central (vem da Vinha ao abrir). */
  theme?: 'light' | 'dark';
  /** Ícone do ministério enviado pela Vinha na Central (baixado pelo robô); sem ele, a arte base da Vinha. */
  icon?: string;
  iconBackground?: string;
};
const brandsDir = join(__dirname, 'brands');
const profiles: Record<string, Brand> = Object.fromEntries(
  readdirSync(brandsDir)
    .filter((f) => /^[a-z][a-z0-9]{1,23}\.json$/.test(f))
    .map((f) => [f.replace(/\.json$/, ''), JSON.parse(readFileSync(join(brandsDir, f), 'utf8')) as Brand]),
);
const profileKey = process.env.VINHA_APP_PROFILE || 'mpr';
const profile = profiles[profileKey];
if (!profile) throw Error('Perfil de ministério desconhecido.');

// Store identifiers belong to the ministry's own developer accounts and are never guessed.
const applicationId = process.env.ANDROID_APPLICATION_ID;
const bundleIdentifier = process.env.IOS_BUNDLE_IDENTIFIER;
if (process.env.EAS_BUILD_PROFILE === 'production' && process.env.EAS_BUILD_PLATFORM !== 'ios' && !applicationId)
  throw Error('Defina ANDROID_APPLICATION_ID aprovado pelo titular antes de gerar a versão de produção.');
if (process.env.EAS_BUILD_PROFILE === 'production' && process.env.EAS_BUILD_PLATFORM !== 'android' && !bundleIdentifier)
  throw Error('Defina IOS_BUNDLE_IDENTIFIER da conta Apple do ministério antes de gerar a versão de produção.');

const config: ExpoConfig = {
  name: profile.name,
  // Projeto único de atualizações para todos os ministérios ("vinha-app"); o que muda por ministério é nome,
  // ícone, identificadores de loja, link (scheme) e o canal de atualização.
  slug: 'vinha-app',
  scheme: profile.slug,
  version: '0.1.0',
  orientation: 'portrait',
  userInterfaceStyle: profile.theme || 'automatic', // tema escolhido na Central; o conteúdo do app também segue a Vinha
  icon: profile.icon || './assets/icon.png',
  ios: {
    bundleIdentifier: bundleIdentifier || profile.previewBundleIdentifier || profile.previewApplicationId,
    supportsTablet: true,
    config: {usesNonExemptEncryption: false},
    infoPlist: {ITSAppUsesNonExemptEncryption: false},
  },
  android: {
    package: applicationId || profile.previewApplicationId,
    permissions: ['POST_NOTIFICATIONS'],
    ...(process.env.GOOGLE_SERVICES_FILE ? {googleServicesFile: process.env.GOOGLE_SERVICES_FILE} : {}),
    allowBackup: false,
    // Ícone do ministério (enviado pela Vinha na Central) ou a arte base da Vinha.
    adaptiveIcon: profile.icon
      ? {foregroundImage: profile.icon, backgroundColor: profile.iconBackground || '#ffffff'}
      : {
          foregroundImage: './assets/android-icon-foreground.png',
          backgroundImage: './assets/android-icon-background.png',
          monochromeImage: './assets/android-icon-monochrome.png',
        },
  },
  plugins: [
    'expo-secure-store',
    'expo-notifications',
    'expo-video',
    [
      'expo-image-picker',
      {
        photosPermission: 'O app usa suas fotos para a foto de perfil e a foto das crianças no Kids.',
        cameraPermission: 'O app usa a câmera para tirar a foto de perfil e a foto das crianças no Kids.',
        microphonePermission: false,
      },
    ],
  ],
  // EAS Update: screen and text fixes reach every ministry app without a new store review.
  // Native changes bump runtimeVersion (appVersion policy) and require a new store build.
  runtimeVersion: {policy: 'appVersion'},
  // Cada ministério recebe as atualizações no seu próprio canal (production-<perfil>), com a sua personalização.
  ...(process.env.EXPO_PROJECT_ID
    ? {
        updates: {
          url: 'https://u.expo.dev/' + process.env.EXPO_PROJECT_ID,
          checkAutomatically: 'ON_LOAD',
          fallbackToCacheTimeout: 0,
          requestHeaders: {'expo-channel-name': (process.env.EAS_BUILD_PROFILE === 'production' ? 'production-' : 'preview-') + profileKey},
        },
      }
    : {}),
  extra: {
    ...(process.env.EXPO_PROJECT_ID ? {eas: {projectId: process.env.EXPO_PROJECT_ID}} : {}),
    ministrySlug: profile.ministrySlug,
    ministryId: profile.ministryId,
    profile: profileKey,
    appDisplayName: profile.name,
    releaseStatus: process.env.EAS_BUILD_PROFILE === 'production' ? 'production' : 'development',
  },
};
export default config;
