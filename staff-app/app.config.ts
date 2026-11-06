import type {ExpoConfig} from 'expo/config';

// Vinha Equipe: one app, published once in the Vinha store accounts, used by every ministry's team.
const applicationId = process.env.STAFF_ANDROID_APPLICATION_ID;
const bundleIdentifier = process.env.STAFF_IOS_BUNDLE_IDENTIFIER;
if (process.env.EAS_BUILD_PROFILE === 'production' && process.env.EAS_BUILD_PLATFORM !== 'ios' && !applicationId)
  throw Error('Defina STAFF_ANDROID_APPLICATION_ID antes de gerar a versão de produção.');
if (process.env.EAS_BUILD_PROFILE === 'production' && process.env.EAS_BUILD_PLATFORM !== 'android' && !bundleIdentifier)
  throw Error('Defina STAFF_IOS_BUNDLE_IDENTIFIER antes de gerar a versão de produção.');

const config: ExpoConfig = {
  name: 'Vinha Equipe',
  slug: 'vinha-equipe',
  scheme: 'vinha-equipe',
  version: '0.1.0',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic',
  icon: './assets/icon.png',
  ios: {
    bundleIdentifier: bundleIdentifier || 'com.vinha.equipe.preview',
    supportsTablet: true,
    config: {usesNonExemptEncryption: false},
    infoPlist: {ITSAppUsesNonExemptEncryption: false},
  },
  android: {
    package: applicationId || 'com.vinha.equipe.preview',
    permissions: ['CAMERA'],
    allowBackup: false,
    adaptiveIcon: {
      foregroundImage: './assets/android-icon-foreground.png',
      backgroundImage: './assets/android-icon-background.png',
      monochromeImage: './assets/android-icon-monochrome.png',
    },
  },
  plugins: [
    'expo-secure-store',
    ['expo-camera', {cameraPermission: 'A câmera lê o QR Code dos ingressos e das retiradas na entrada do evento.', recordAudioAndroid: false}],
  ],
  runtimeVersion: {policy: 'appVersion'},
  ...(process.env.EXPO_PROJECT_ID ? {updates: {url: 'https://u.expo.dev/' + process.env.EXPO_PROJECT_ID, checkAutomatically: 'ON_LOAD', fallbackToCacheTimeout: 0}} : {}),
  extra: {...(process.env.EXPO_PROJECT_ID ? {eas: {projectId: process.env.EXPO_PROJECT_ID}} : {})},
};
export default config;
