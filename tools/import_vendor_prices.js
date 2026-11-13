// Ajoute à Data/VendorPrices.lua les prix de marchand relevés dans une sauvegarde de l'add-on.
//
//   node tools/import_vendor_prices.js "<...>/SavedVariables/ProfessionPath.lua" <dossier des CSV> <version.build> <AAAA-MM-JJ>
//
// Le dossier des CSV contient ItemSparse.csv de wago.tools pour ce build (voir gen_thresholds.js).
// Règles :
//   - seuls les matériaux de recettes sont repris (liste des recettes : tests/data/bench.json) ;
//   - un prix lu en jeu peut contenir une remise de réputation (5 à 20 %) : on vérifie qu'il
//     correspond au prix des fichiers du jeu, remise comprise, et on livre le prix SANS remise ;
//   - un prix qui ne correspond pas est écarté et signalé ;
//   - les prix déjà livrés ne sont pas modifiés.

const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const ROOT = path.join(__dirname, "..");
const PRICES_LUA = path.join(ROOT, "ProfessionPath", "Data", "VendorPrices.lua");
const BENCH = path.join(ROOT, "tests", "data", "bench.json");
const MIN_RATIO = 0.8;   // remise de réputation la plus forte (Exalté : 20 %)
const MAX_RATIO = 1.001; // prix lu à peine au-dessus du prix officiel (arrondis du jeu)

function readSavedPrices(file) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const script = `${fs.readFileSync(file, "utf8")}
local out = {}
for id, price in pairs(ProfessionPathDB and ProfessionPathDB.vendor or {}) do
  if type(id) == "number" and type(price) == "number" then out[#out + 1] = id .. "=" .. price end
end
return table.concat(out, ";")`;
  if (lauxlib.luaL_loadstring(L, to_luastring(script)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
  const text = lua.lua_tojsstring(L, -1);
  return new Map(text ? text.split(";").map((pair) => pair.split("=").map(Number)) : []);
}

function parseCsv(text) {
  const rows = []; let row = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; } else if (c === '"') quoted = false; else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  const header = rows.shift();
  return rows.map((r) => Object.fromEntries(header.map((h, i) => [h, r[i]])));
}

function main() {
  const [savedFile, csvDir, build, date] = process.argv.slice(2);
  if (!savedFile || !csvDir || !/^\d+\.\d+\.\d+\.\d+$/.test(build || "") || !/^\d{4}-\d{2}-\d{2}$/.test(date || "")) {
    console.error("Utilisation : node tools/import_vendor_prices.js <ProfessionPath.lua> <dossier des CSV> <version.build> <AAAA-MM-JJ>");
    process.exit(1);
  }
  const reagents = new Set();
  for (const recipe of JSON.parse(fs.readFileSync(BENCH, "utf8")).recipes) {
    for (const [itemID] of recipe.reagents || []) reagents.add(itemID);
  }
  const items = new Map(parseCsv(fs.readFileSync(path.join(csvDir, "ItemSparse.csv"), "utf8")).map((r) => [Number(r.ID), r]));
  const current = fs.readFileSync(PRICES_LUA, "utf8");
  const shipped = new Set([...current.matchAll(/^ {4}\[(\d+)\] = /gm)].map((m) => Number(m[1])));

  const added = [];
  for (const [itemID, read] of [...readSavedPrices(savedFile)].sort((a, b) => a[0] - b[0])) {
    if (!reagents.has(itemID) || shipped.has(itemID)) continue;
    const item = items.get(itemID);
    const official = item ? Number(item.BuyPrice) / Math.max(1, Number(item.VendorStackCount) || 1) : NaN;
    const ratio = read / official;
    if (!(official > 0 && ratio >= MIN_RATIO && ratio <= MAX_RATIO)) {
      console.log(`écarté : ${itemID} (${item ? item.Display_lang : "?"}) lu ${read}, fichiers du jeu ${official}`);
      continue;
    }
    added.push(`    [${itemID}] = ${Number(official.toFixed(4))}, -- ${item.Display_lang}`);
  }
  if (added.length === 0) {
    console.log("Aucun nouveau prix.");
    return;
  }
  const section = [
    `    -- Ajoutés le ${date} (build ${build}) depuis une sauvegarde de l'add-on : marchands ouverts en jeu,`,
    "    -- livrés au prix des fichiers du jeu (sans remise de réputation).",
    ...added,
  ].join("\n");
  const closing = current.lastIndexOf("\n}");
  fs.writeFileSync(PRICES_LUA, `${current.slice(0, closing)}\n${section}${current.slice(closing)}`);
  console.log(`${added.length} prix ajoutés.`);
}

main();
