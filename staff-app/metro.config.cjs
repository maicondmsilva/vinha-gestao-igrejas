const path = require('node:path');
const {getDefaultConfig} = require('expo/metro-config');

// Vinha Equipe reads the platform contract from ../shared (schemas, tokens, API shapes).
const config = getDefaultConfig(__dirname);
const shared = path.resolve(__dirname, '../shared');
config.watchFolders = [shared];
// Packages imported by shared files (react, zod) must come from this app's node_modules, so EAS builds
// (which install only this folder) and local builds resolve the same copy.
config.resolver.resolveRequest = (context, moduleName, platform) => {
  const bare = !moduleName.startsWith('.') && !path.isAbsolute(moduleName);
  const fromShared = context.originModulePath.startsWith(shared + path.sep);
  return context.resolveRequest(bare && fromShared ? {...context, originModulePath: path.join(__dirname, 'index.ts')} : context, moduleName, platform);
};
module.exports = config;
