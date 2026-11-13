import type {ExpoConfig} from 'expo/config';
// One code base, one store listing per ministry. `node scripts/new-ministry-app.mjs` adds lines between the markers.
// <ministry-imports>
import mpr from './brands/mpr.json';
// </ministry-imports>

type Brand = {
  name: string;
  slug: string;
  ministryId: string;
  ministrySlug: string;
  previewApplicationId: string;
  previewBundleIdentifier?: string;
  /** Optional per-ministry art; defaults to the Vinha base assets. */
  icon?: string;
};
const profiles: Record<string, Brand> = {
  // <ministry-profiles>
  mpr,
  // </ministry-profiles>
};
const profile = profiles[process.env.VINHA_APP_PROFILE||'mpr'];
if (!profile) throw Error('Perfil de ministério desconhecido.');

// Store identifiers belong to the ministry's own developer accounts and are never guessed.
const applicationId = process.env.ANDROID_APPLICATION_ID;
const bundleIdentifier = process.env.IOS_BUNDLE_IDENTIFIER;
if (process.env.EAS_BUILD_PROFILE==='production' && process.env.EAS_BUILD_PLATFORM !== 'ios' && !applicationId)
  throw Error('Defina ANDROID_APPLICATION_ID aprovado pelo titular antes de gerar a versão de produção.');
if (process.env.EAS_BUILD_PROFILE==='production' && process.env.EAS_BUILD_PLATFORM !== 'android' && !bundleIdentifier)
  throw Error('Defina IOS_BUNDLE_IDENTIFIER da conta Apple do ministério antes de gerar a versão de produção.');

const config: ExpoConfig = {
  name: profile.name,
  slug: profile.slug,
  scheme: profile.slug,
  version: '0.1.0',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic', // o tema do conteúdo vem do painel; aqui só barras do sistema
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
    adaptiveIcon: {
      foregroundImage: './assets/android-icon-foreground.png',
      backgroundImage: './assets/android-icon-background.png',
      monochromeImage: './assets/android-icon-monochrome.png',
    },
  },
  plugins: ['expo-secure-store', 'expo-notifications', 'expo-video'],
  // EAS Update: screen and text fixes reach every ministry app without a new store review.
  // Native changes bump runtimeVersion (appVersion policy) and require a new store build.
  runtimeVersion: {policy: 'appVersion'},
  ...(process.env.EXPO_PROJECT_ID ? {updates: {url: 'https://u.expo.dev/' + process.env.EXPO_PROJECT_ID, checkAutomatically: 'ON_LOAD', fallbackToCacheTimeout: 0}} : {}),
  extra: {
    ...(process.env.EXPO_PROJECT_ID ? {eas: {projectId: process.env.EXPO_PROJECT_ID}} : {}),
    ministrySlug: profile.ministrySlug,
    ministryId: profile.ministryId,
    appDisplayName: profile.name,
    releaseStatus: process.env.EAS_BUILD_PROFILE === 'production' ? 'production' : 'development',
  },
};
export default config;
