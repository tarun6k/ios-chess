import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.adaptivechess.app',
  appName: 'Chess',
  webDir: 'dist',
  android: {
    allowMixedContent: false,
  },
  ios: {
    // Match --color-bg so the webview never flashes white behind the app.
    backgroundColor: '#f3f2f2',
    contentInset: 'never',
  },
};

export default config;
