const path=require('node:path');
const {getDefaultConfig}=require('expo/metro-config');
const config=getDefaultConfig(__dirname);
const shared=path.resolve(__dirname,'../shared');
config.watchFolders=[shared];
// Shared code must use this app's packages (React renderer, zod), not the web application's copies:
// EAS installs only this folder, so every bare import from ../shared resolves from here.
config.resolver.resolveRequest=(context,moduleName,platform)=>{
 const bare=!moduleName.startsWith('.')&&!path.isAbsolute(moduleName);
 const redirect=moduleName==='react'||moduleName.startsWith('react/')||(bare&&context.originModulePath.startsWith(shared+path.sep));
 return context.resolveRequest(redirect?{...context,originModulePath:path.join(__dirname,'index.ts')}:context,moduleName,platform);
};
module.exports=config;
