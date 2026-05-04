export const slugFruits = [
  "apricot",
  "clementine",
  "dragonfruit",
  "fig",
  "kiwi",
  "kumquat",
  "lychee",
  "mango",
  "papaya",
  "peach",
  "persimmon",
  "plum",
  "rambutan",
  "starfruit",
  "yuzu"
];

export const slugCharacters = [
  "artist",
  "captain",
  "keeper",
  "pilot",
  "ranger",
  "scout",
  "scribe",
  "smith",
  "spark",
  "voyager"
];

export const slugPattern = /^[a-z][a-z0-9-]{0,47}$/;

export function parsePageMode(search) {
  const params = search instanceof URLSearchParams ? search : new URLSearchParams(search);
  const requestedFullMode = params.get("full") === "1";
  const requestedSession = params.get("session") || "";

  return {
    requestedFullMode,
    requestedSession,
    fullMode: requestedFullMode && requestedSession !== ""
  };
}

export function fullUrl(currentHref, slug) {
  const url = new URL(currentHref);
  url.searchParams.set("session", slug);
  url.searchParams.set("full", "1");
  return url.toString();
}

export function selectedCommand(presetValue) {
  return presetValue || "";
}

export function commandLabel(session) {
  if (!session) {
    return "-";
  }

  if (session.command === "") {
    return session.pane_command ? `tmux default (${session.pane_command})` : "tmux default";
  }

  return session.command || session.pane_command || "-";
}

export function suggestSlug(sessions, random = Math.random) {
  const taken = new Set((sessions || []).map((session) => session.slug));
  const maxAttempts = slugFruits.length * slugCharacters.length * 2;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const fruit = slugFruits[Math.floor(random() * slugFruits.length)];
    const character = slugCharacters[Math.floor(random() * slugCharacters.length)];
    const slug = `${fruit}-${character}`;

    if (!taken.has(slug) && slugPattern.test(slug)) {
      return slug;
    }
  }

  for (let index = 1; index < 1000; index += 1) {
    const slug = `mango-${index}`;

    if (!taken.has(slug)) {
      return slug;
    }
  }

  return "mango";
}

export function statusDotDescriptor(session) {
  const state = session?.alive ? "up" : "down";

  return {
    className: `status-dot ${state}`,
    title: state,
    ariaLabel: state
  };
}

export function nextActiveSession(sessions, active) {
  if (!active) {
    return null;
  }

  return (sessions || []).find((session) => session.slug === active.slug) || null;
}

export function fullModeMissingSessionMessage(slug) {
  return `Session not found: ${slug}`;
}

export function fullModeDeadSessionMessage(slug) {
  return `Session is not alive: ${slug}`;
}
