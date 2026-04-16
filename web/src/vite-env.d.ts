/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_GA_MEASUREMENT_ID?: string;
  readonly VITE_APPSFLYER_ONELINK_TEMPLATE_URL?: string;
  readonly VITE_APPSFLYER_BANNER_WEB_KEY?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
