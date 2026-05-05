import { copyFileSync, mkdirSync } from "node:fs";

const files = [
  ["node_modules/@xterm/xterm/lib/xterm.js", "apps/babs/priv/static/js/xterm.js"],
  ["node_modules/@xterm/xterm/css/xterm.css", "apps/babs/priv/static/css/xterm.css"],
  [
    "node_modules/@xterm/addon-fit/lib/addon-fit.js",
    "apps/babs/priv/static/js/xterm-addon-fit.js"
  ],
  ["deps/phoenix/priv/static/phoenix.mjs", "apps/babs/priv/static/js/phoenix.mjs"]
];

mkdirSync("apps/babs/priv/static/js", { recursive: true });
mkdirSync("apps/babs/priv/static/css", { recursive: true });

for (const [source, target] of files) {
  copyFileSync(source, target);
}
