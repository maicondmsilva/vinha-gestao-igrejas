import type {ExpoConfig} from 'expo/config';
import mpr from './brands/mpr.json';
const profiles:Record<string,typeof mpr>={mpr};
const profile=profiles[process.env.VINHA_APP_PROFILE||'mpr'];
if(!profile)throw Error('Perfil de ministério desconhecido.');
const applicationId=process.env.ANDROID_APPLICATION_ID;
if(process.env.EAS_BUILD_PROFILE==='production'&&!applicationId)throw Error('Defina ANDROID_APPLICATION_ID aprovado pelo titular antes de gerar a versão de produção.');
const config:ExpoConfig={name:profile.name,slug:profile.slug,version:'0.1.0',orientation:'portrait',userInterfaceStyle:'automatic',android:{package:applicationId||profile.previewApplicationId,permissions:[],allowBackup:false},plugins:['expo-secure-store'],extra:{ministrySlug:profile.ministrySlug,ministryId:profile.ministryId,appDisplayName:profile.name,releaseStatus:'development'}};
export default config;
