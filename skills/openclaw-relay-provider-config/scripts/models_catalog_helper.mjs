#!/usr/bin/env node

import process from "node:process";

function usage() {
  console.error(`Usage:
  node scripts/models_catalog_helper.mjs upsert --model-ref REF --alias NAME
  node scripts/models_catalog_helper.mjs remove-provider --provider-id ID

Read current agents.defaults.models JSON from stdin.
Empty stdin is treated as {}.
Write updated JSON to stdout.`);
}

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (!command) {
    usage();
    process.exit(1);
  }

  const options = {};
  for (let i = 0; i < rest.length; i += 1) {
    const arg = rest[i];
    if (!arg.startsWith("--")) {
      console.error(`Unknown argument: ${arg}`);
      usage();
      process.exit(1);
    }
    const key = arg.slice(2);
    const value = rest[i + 1];
    if (value == null || value.startsWith("--")) {
      console.error(`Missing value for --${key}`);
      usage();
      process.exit(1);
    }
    options[key] = value;
    i += 1;
  }

  return { command, options };
}

function parseCatalog(raw) {
  const trimmed = raw.trim();
  if (!trimmed) {
    return {};
  }

  let parsed;
  try {
    parsed = JSON.parse(trimmed);
  } catch (error) {
    console.error(`Failed to parse stdin JSON: ${error.message}`);
    process.exit(1);
  }

  if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object") {
    console.error("agents.defaults.models must be a JSON object");
    process.exit(1);
  }

  return parsed;
}

function upsertModel(catalog, modelRef, alias) {
  if (!modelRef) {
    console.error("Missing required argument: --model-ref");
    process.exit(1);
  }
  if (!alias) {
    console.error("Missing required argument: --alias");
    process.exit(1);
  }

  const existingEntry = catalog[modelRef];
  if (
    existingEntry !== undefined &&
    (existingEntry === null || Array.isArray(existingEntry) || typeof existingEntry !== "object")
  ) {
    console.error(`agents.defaults.models["${modelRef}"] must be a JSON object when present`);
    process.exit(1);
  }

  return {
    ...catalog,
    [modelRef]: {
      ...(existingEntry ?? {}),
      alias,
    },
  };
}

function removeProvider(catalog, providerId) {
  if (!providerId) {
    console.error("Missing required argument: --provider-id");
    process.exit(1);
  }

  return Object.fromEntries(
    Object.entries(catalog).filter(([key]) => key !== providerId && !key.startsWith(`${providerId}/`)),
  );
}

const { command, options } = parseArgs(process.argv.slice(2));
const input = await readStdin();
const catalog = parseCatalog(input);

let updated;
if (command === "upsert") {
  updated = upsertModel(catalog, options["model-ref"], options.alias);
} else if (command === "remove-provider") {
  updated = removeProvider(catalog, options["provider-id"]);
} else {
  console.error(`Unsupported command: ${command}`);
  usage();
  process.exit(1);
}

process.stdout.write(`${JSON.stringify(updated)}\n`);
