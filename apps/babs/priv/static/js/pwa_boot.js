export async function registerBabsServiceWorker({
  navigator: navigatorRef = globalThis.navigator,
  window: windowRef = globalThis.window,
  scriptUrl = "/sw.js"
} = {}) {
  if (!windowRef?.isSecureContext) {
    return { status: "skipped", reason: "insecure-context" };
  }

  if (!navigatorRef?.serviceWorker?.register) {
    return { status: "skipped", reason: "unsupported" };
  }

  try {
    await navigatorRef.serviceWorker.register(scriptUrl);
    return { status: "registered" };
  } catch (error) {
    return { status: "failed", reason: error instanceof Error ? error.message : String(error) };
  }
}
