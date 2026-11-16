// Stub of the plugin's app-server module. codex-client.mjs never imports it,
// but scripts/codex-plugin checks that this file exists before calling a root
// usable, so the fixture must carry it.
export const BROKER_ENDPOINT_ENV = "CODEX_COMPANION_APP_SERVER_ENDPOINT";
export const BROKER_BUSY_RPC_CODE = -32001;

export class CodexAppServerClient {
  static async connect() {
    throw new Error("stub: the app-server client is not used by codex-client.mjs");
  }
}
