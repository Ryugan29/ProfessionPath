// Ajoute aux listes livrées avec l'add-on ce que les joueurs ont partagé avec /ppath partager.
//
// Utilisation (depuis la racine du projet) :
//   node tools/import_shares.js partage1.txt [partage2.txt ...]
// Chaque fichier contient le texte collé par un joueur dans une issue GitHub (le texte autour
// est ignoré). Chaque ligne est vérifiée ; une ligne douteuse est refusée et la raison affichée.
// Une donnée qui contredit une donnée déjà connue n'écrase jamais l'ancienne : elle est signalée.
//
// Données conservées : tools/community.json (source de vérité, versionnée).
// Fichiers fabriqués : ProfessionPath/Data/NPCs.lua et ProfessionPath/Data/TrainerLevels.lua.

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const STORE = path.join(__dirname, "community.json");
const NPCS_LUA = path.join(ROOT, "ProfessionPath", "Data", "NPCs.lua");
const LEVELS_LUA = path.join(ROOT, "ProfessionPath", "Data", "TrainerLevels.lua");
const THRESHOLDS_LUA = path.join(ROOT, "ProfessionPath", "Data", "Thresholds.lua");

const HEADER = /^ProfessionPath-share 1;([^;]*);([^;]*)$/;
const FACTIONS = new Set(["", "Alliance", "Horde", "Neutral"]);
const MAX_ID = 10000000;
const MAX_MAP = 100000;
const MAX_LEVEL = 450;
const MAX_NAME = 64;
const POSITION_TOLERANCE = 0.02; // un PNJ revu à deux pas de sa place n'est pas une contradiction

function intOrNull(text, min, max) {
  if (!/^\d+$/.test(text)) return null;
  const value = Number(text);
  return value >= min && value <= max ? value : null;
}

// Un nom lisible : ni vide, ni trop long, ni caractère de contrôle, ni code de mise en forme
// du jeu (« | » : couleurs |c, images |T...), qui s'afficherait chez tous les joueurs.
function validText(text) {
  return Boolean(text) && text.length <= MAX_NAME && !/[\u0000-\u001f|]/.test(text);
}

function parseNpc(fields) {
  const [, kind, idText, name, mapText, xText, yText, faction, profIDText, profession, itemsText] = fields;
  if (fields.length !== 11) return { reason: "nombre de champs inattendu" };
  if (kind !== "trainer" && kind !== "vendor") return { reason: "genre de PNJ inconnu" };
  const id = intOrNull(idText, 1, MAX_ID);
  if (id === null) return { reason: "numéro de PNJ invalide" };
  if (!validText(name)) return { reason: "nom de PNJ invalide" };
  if (profession && !validText(profession)) return { reason: "nom de métier invalide" };
  const map = intOrNull(mapText, 1, MAX_MAP);
  if (map === null) return { reason: "numéro de carte invalide" };
  const x = Number(xText);
  const y = Number(yText);
  if (!(x > 0 && x <= 1 && y > 0 && y <= 1)) return { reason: "position hors de la carte" };
  if (!FACTIONS.has(faction)) return { reason: "faction inconnue" };
  const npc = { kind, name, map, x, y };
  if (faction) npc.faction = faction;
  if (kind === "trainer") {
    const professionID = profIDText === "" ? null : intOrNull(profIDText, 1, MAX_ID);
    if (profIDText !== "" && professionID === null) return { reason: "numéro de métier invalide" };
    if (professionID === null && !profession) return { reason: "maître sans métier" };
    if (professionID !== null) npc.professionID = professionID;
    if (profession) npc.profession = profession;
  } else {
    const items = itemsText === "" ? [] : itemsText.split(",").map((t) => intOrNull(t, 1, MAX_ID));
    if (items.length === 0 || items.includes(null)) return { reason: "marchand sans aucun matériau de métier valide" };
    npc.items = [...new Set(items)].sort((a, b) => a - b);
  }
  return { key: `${kind}:${id}`, npc };
}

function parseRecipe(fields, knownRecipes) {
  const [, , recipeText, levelText, costText] = fields;
  if (fields.length !== 5) return { reason: "nombre de champs inattendu" };
  const recipeID = intOrNull(recipeText, 1, MAX_ID);
  // Absente des seuils : recette inconnue, ou sans plage de progression (jaune = gris dans le jeu),
  // que l'add-on ne sait de toute façon pas utiliser.
  if (recipeID === null || !knownRecipes.has(recipeID)) {
    return { reason: "recette absente des données de l'add-on (inconnue ou sans plage de progression)" };
  }
  // Le jeu répond 0 pour « aucun niveau requis » : c'est le niveau 1.
  const rawLevel = intOrNull(levelText, 0, MAX_LEVEL);
  if (rawLevel === null) return { reason: "niveau de métier invalide" };
  const level = Math.max(1, rawLevel);
  const cost = costText === "" ? null : intOrNull(costText, 0, MAX_ID * 100);
  if (costText !== "" && cost === null) return { reason: "prix invalide" };
  return { recipeID, value: [level, cost] };
}

/** Lit un partage. Renvoie { build, locale, npcs, trainerLevels, rejected }. */
function parseShare(text, knownRecipes) {
  const lines = String(text).split(/\r?\n/).map((line) => line.trim());
  const headerIndex = lines.findIndex((line) => HEADER.test(line));
  if (headerIndex < 0) throw new Error("en-tête « ProfessionPath-share 1 » introuvable");
  const [, build, locale] = lines[headerIndex].match(HEADER);
  const result = { build, locale, npcs: {}, trainerLevels: {}, rejected: [] };
  for (const line of lines.slice(headerIndex + 1)) {
    const fields = line.split(";");
    if (fields[0] === "N") {
      const parsed = parseNpc(fields);
      if (parsed.reason) result.rejected.push({ line, reason: parsed.reason });
      else result.npcs[parsed.key] = parsed.npc;
    } else if (fields[0] === "R") {
      const parsed = parseRecipe(fields, knownRecipes);
      if (parsed.reason) result.rejected.push({ line, reason: parsed.reason });
      else result.trainerLevels[parsed.recipeID] = parsed.value;
    }
  }
  return result;
}

function sameNpc(a, b) {
  return a.map === b.map && Math.abs(a.x - b.x) <= POSITION_TOLERANCE && Math.abs(a.y - b.y) <= POSITION_TOLERANCE;
}

/** Ajoute un partage aux données connues, sans jamais écraser une donnée différente. */
function mergeShare(store, share) {
  const report = { added: 0, confirmed: 0, conflicts: [] };
  for (const [key, npc] of Object.entries(share.npcs)) {
    const known = store.npcs[key];
    if (!known) {
      store.npcs[key] = npc;
      report.added += 1;
    } else if (sameNpc(known, npc)) {
      report.confirmed += 1;
    } else {
      report.conflicts.push(`${key} (${npc.name}) : ${npc.map} ${npc.x},${npc.y} au lieu de ${known.map} ${known.x},${known.y}`);
    }
  }
  for (const [recipeID, value] of Object.entries(share.trainerLevels)) {
    const known = store.trainerLevels[recipeID];
    if (!known) {
      store.trainerLevels[recipeID] = value;
      report.added += 1;
    } else if (known[0] === value[0] && known[1] === value[1]) {
      report.confirmed += 1;
    } else {
      report.conflicts.push(`recette ${recipeID} : ${value.join("/")} au lieu de ${known.join("/")}`);
    }
  }
  return report;
}

function luaString(text) {
  return JSON.stringify(text);
}

function npcLua(key, npc) {
  const parts = [`kind = ${luaString(npc.kind)}`, `name = ${luaString(npc.name)}`, `map = ${npc.map}`, `x = ${npc.x}`, `y = ${npc.y}`];
  if (npc.faction) parts.push(`faction = ${luaString(npc.faction)}`);
  if (npc.professionID) parts.push(`professionID = ${npc.professionID}`);
  if (npc.profession) parts.push(`profession = ${luaString(npc.profession)}`);
  if (npc.items) parts.push(`items = { ${npc.items.map((id) => `[${id}] = true`).join(", ")} }`);
  return `    [${luaString(key)}] = { ${parts.join(", ")} },`;
}

function renderNpcsLua(store, build) {
  const keys = Object.keys(store.npcs).sort();
  return [
    "-- Profession Path — maîtres de métier et marchands de fournitures, livrés avec l'add-on.",
    "-- FICHIER FABRIQUÉ par tools/import_shares.js à partir des partages des joueurs (/ppath partager) :",
    "-- ne pas le modifier à la main. Source : tools/community.json.",
    "--",
    "-- Les fichiers du jeu ne disent pas où se trouvent les PNJ. Chaque entrée vient d'un PNJ réellement",
    "-- rencontré en jeu sur WoW Forever par un joueur, puis vérifiée. Rien n'est repris d'une autre",
    "-- version du jeu ni d'un autre add-on. Un PNJ que le joueur a rencontré lui-même remplace celui-ci.",
    "--",
    "-- Forme : [\"trainer:numéro\"] ou [\"vendor:numéro\"] = { kind, name, map, x, y, faction,",
    "--         professionID et profession (maître), items (marchand : matériaux de métier vendus) }",
    "",
    "local _, ns = ...",
    "",
    `ns.NPCsBuild = ${build ? luaString(build) : "nil"} -- version du jeu des relevés`,
    "",
    "ns.NPCs = {",
    ...keys.map((key) => npcLua(key, store.npcs[key])),
    "}",
    "",
  ].join("\n");
}

function renderTrainerLevelsLua(store) {
  const ids = Object.keys(store.trainerLevels).map(Number).sort((a, b) => a - b);
  return [
    "-- Profession Path — niveau et prix des recettes enseignées par les maîtres, livrés avec l'add-on.",
    "-- FICHIER FABRIQUÉ par tools/import_shares.js à partir des partages des joueurs (/ppath partager) :",
    "-- ne pas le modifier à la main. Source : tools/community.json.",
    "--",
    "-- Les fichiers du jeu ne disent pas à quel niveau un maître enseigne une recette. Chaque ligne vient",
    "-- d'un maître réellement lu en jeu sur WoW Forever par un joueur, puis vérifiée.",
    "-- Forme : [numéro de la recette] = { niveau de métier requis, prix en cuivre (ou nil) }",
    "-- Rangé par numéro : la liste sert dans toutes les langues du jeu. Un maître lu par le joueur la remplace.",
    "",
    "local _, ns = ...",
    "",
    "ns.TrainerLevels = {",
    ...ids.map((id) => {
      const [level, cost] = store.trainerLevels[id];
      return `    [${id}] = { ${level}, ${cost === null ? "nil" : cost} },`;
    }),
    "}",
    "",
  ].join("\n");
}

function knownRecipeIDs() {
  const text = fs.readFileSync(THRESHOLDS_LUA, "utf8");
  return new Set([...text.matchAll(/^ {4}\[(\d+)\] = \{/gm)].map((m) => Number(m[1])));
}

function main(files) {
  if (files.length === 0) {
    console.error("Utilisation : node tools/import_shares.js partage1.txt [partage2.txt ...]");
    process.exit(1);
  }
  const store = fs.existsSync(STORE) ? JSON.parse(fs.readFileSync(STORE, "utf8")) : { build: null, npcs: {}, trainerLevels: {} };
  const recipes = knownRecipeIDs();
  for (const file of files) {
    const share = parseShare(fs.readFileSync(file, "utf8"), recipes);
    const report = mergeShare(store, share);
    store.build = store.build || share.build;
    console.log(`${file} (${share.locale}, ${share.build}) : ${report.added} ajouts, ${report.confirmed} confirmations, ` +
      `${report.conflicts.length} contradictions, ${share.rejected.length} lignes refusées`);
    for (const conflict of report.conflicts) console.log(`  contradiction : ${conflict}`);
    for (const rejected of share.rejected) console.log(`  refusée (${rejected.reason}) : ${rejected.line}`);
  }
  fs.writeFileSync(STORE, `${JSON.stringify(store, null, 2)}\n`, "utf8");
  fs.writeFileSync(NPCS_LUA, renderNpcsLua(store, store.build), "utf8");
  fs.writeFileSync(LEVELS_LUA, renderTrainerLevelsLua(store), "utf8");
  console.log(`Total : ${Object.keys(store.npcs).length} PNJ, ${Object.keys(store.trainerLevels).length} recettes de maître.`);
}

module.exports = { parseShare, mergeShare, renderNpcsLua, renderTrainerLevelsLua };
if (require.main === module) main(process.argv.slice(2));
