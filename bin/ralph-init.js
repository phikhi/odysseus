#!/usr/bin/env node
// `npx ralph-pack` — the wizard, which is a shim and nothing else.
//
// Every decision, every question and every write lives in `init.sh`. This file
// exists because `npx` is how a developer expects to bootstrap a tool, and it is
// kept to an exec on purpose: the engine of this pack is bash, and a machine
// without node has to install exactly the same way (`bash init.sh --target .`).
// Logic here would be logic the bash fallback does not have, which is how a
// "pure bash with a node front door" becomes two installers that disagree.
//
// The suite runs with `node`, `npm` and `npx` shadowed by a hard failure, so
// nothing below is exercised there and nothing below may be needed: what the
// suite checks instead is that this file execs init.sh and carries no decisions.
"use strict";

const { spawnSync } = require("child_process");
const path = require("path");

const root = path.join(__dirname, "..");
const args = [
  path.join(root, "init.sh"),
  "--from",
  root,
  "--target",
  process.cwd(),
].concat(process.argv.slice(2));

const result = spawnSync("bash", args, { stdio: "inherit" });

if (result.error) {
  process.stderr.write(
    "ralph-pack: cannot run bash — this pack's engine is bash, and the node " +
      "wrapper only execs it: " + result.error.message + "\n"
  );
  process.exit(2);
}

process.exit(result.status === null ? 1 : result.status);
