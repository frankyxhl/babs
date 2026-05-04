import { execFileSync } from "node:child_process";

export const prefix = process.env.HARDLINE_E2E_PREFIX;

export function uniqueSlug(label) {
  const suffix = `${Date.now()}-${Math.floor(Math.random() * 10000)}`;
  return `${label}-${suffix}`.toLowerCase().replace(/[^a-z0-9-]/g, "-").slice(0, 48);
}

export async function createSession(request, slug, command = "") {
  const response = await request.post("/api/sessions", {
    data: { slug, command }
  });

  if (!response.ok()) {
    throw new Error(`create ${slug} failed: ${response.status()} ${await response.text()}`);
  }

  return response.json();
}

export async function deleteSession(request, slug) {
  const response = await request.delete(`/api/sessions/${encodeURIComponent(slug)}`);

  if (!response.ok() && response.status() !== 404) {
    throw new Error(`delete ${slug} failed: ${response.status()} ${await response.text()}`);
  }
}

export async function listSessions(request) {
  const response = await request.get("/api/sessions");

  if (!response.ok()) {
    throw new Error(`list sessions failed: ${response.status()} ${await response.text()}`);
  }

  return (await response.json()).sessions || [];
}

export async function captureScreen(request, slug) {
  const response = await request.get(`/api/sessions/${encodeURIComponent(slug)}/screen`);

  if (!response.ok()) {
    throw new Error(`capture ${slug} failed: ${response.status()} ${await response.text()}`);
  }

  return (await response.json()).screen || "";
}

export async function cleanupSessions(request, slugs) {
  for (const slug of slugs) {
    await deleteSession(request, slug).catch(() => {});
  }
}

export function cleanupTmuxPrefix() {
  if (!prefix) {
    return;
  }

  let output = "";

  try {
    output = execFileSync("tmux", ["list-sessions", "-F", "#{session_name}"], {
      encoding: "utf8"
    });
  } catch (_error) {
    return;
  }

  for (const session of output.split("\n").filter(Boolean)) {
    if (session.startsWith(`${prefix}-`)) {
      try {
        execFileSync("tmux", ["kill-session", "-t", session]);
      } catch (_error) {
        // Best-effort cleanup. Individual tests assert the manager-visible state.
      }
    }
  }
}
