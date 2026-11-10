// Fabrique les données de recettes de l'add-on à partir des tables du jeu.
//
// Utilisation (depuis le dossier du projet) :
//   node tools/gen_thresholds.js <dossier des CSV> <version du jeu>
//   ex. node tools/gen_thresholds.js C:/tables 1.60.1.70862
//
// Le dossier doit contenir ces fichiers, téléchargés sur
//   https://wago.tools/db2/<Table>/csv?build=<version du jeu>
// (wago.tools publie les tables de données extraites du client du jeu) :
//   SkillLineAbility, ItemEffect, ItemXItemEffect, ItemSparse, SpellReagents, SpellName, SkillLine
//
// Ce qu'on en tire, par recette :
//   jaune, gris   : SkillLineAbility (TrivialSkillLineRankLow / High). Vert = milieu des deux.
//   apprentissage : niveau de métier requis pour apprendre la recette.
//       - SkillLineAbility.MinSkillLineRank quand il est crédible (le jeu laisse presque
//         toujours 1, une valeur de remplissage) ;
//       - sinon le niveau requis par l'objet qui apprend la recette (plan, patron, formule) :
//         ItemEffect (type « apprend un sort ») -> ItemXItemEffect -> ItemSparse.RequiredSkillRank ;
//       - sinon 0 = inconnu. C'est le cas des recettes apprises chez un maître : ce niveau
//         n'est pas dans les fichiers du jeu, l'add-on le lit en jeu dans la fenêtre du maître.
//
// Sorties :
//   ProfessionPath/Data/Thresholds.lua : livré avec l'add-on.
//   ProfessionPath/Data/Crafts.lua     : livré avec l'add-on (objet fabriqué par chaque recette, table SpellEffect).
//   tests/data/bench.json              : recettes complètes, pour le banc d'essai hors jeu.

const fs = require("fs");
const path = require("path");

const [csvDir, build] = process.argv.slice(2);
if (!csvDir || !build) {
  console.error("Utilisation : node tools/gen_thresholds.js <dossier des CSV> <version du jeu>");
  process.exit(1);
}

const ROOT = path.join(__dirname, "..");
const LUA_OUTPUT = path.join(ROOT, "ProfessionPath", "Data", "Thresholds.lua");
const BENCH_OUTPUT = path.join(ROOT, "tests", "data", "bench.json");
const CRAFTS_OUTPUT = path.join(ROOT, "ProfessionPath", "Data", "Crafts.lua");
const CREATE_ITEM_EFFECT = 24; // effet « fabrique un objet » d'un sort de recette
const LEARN_SPELL_TRIGGER = "6";
const MAX_REAGENTS = 8;

/** Lit un CSV (champs entre guillemets gérés) et renvoie une liste d'objets { colonne: valeur }. */
function readTable(name, requiredColumns) {
  const text = fs.readFileSync(path.join(csvDir, `${name}.csv`), "utf8");
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (quoted) {
      if (char === '"' && text[i + 1] === '"') {
        cell += '"';
        i += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        cell += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(cell);
      cell = "";
    } else if (char === "\n") {
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
    } else if (char !== "\r") {
      cell += char;
    }
  }
  if (cell !== "" || row.length > 0) rows.push([...row, cell]);

  const header = rows[0];
  for (const column of requiredColumns) {
    if (!header.includes(column)) throw new Error(`Colonne absente de ${name}.csv : ${column}`);
  }
  return rows
    .slice(1)
    .filter((cells) => cells.length === header.length)
    .map((cells) => Object.fromEntries(header.map((column, index) => [column, cells[index]])));
}

function toInt(value, label) {
  const number = Number(value);
  if (!Number.isInteger(number)) throw new Error(`Valeur non entière (${label}) : ${value}`);
  return number;
}

/** Pour chaque recette : l'objet qui l'apprend et le niveau de métier qu'il demande. */
function buildTeachingItems() {
  const itemsByEffect = new Map();
  for (const link of readTable("ItemXItemEffect", ["ItemEffectID", "ItemID"])) {
    const list = itemsByEffect.get(link.ItemEffectID) || [];
    itemsByEffect.set(link.ItemEffectID, [...list, link.ItemID]);
  }
  const itemInfo = new Map();
  for (const item of readTable("ItemSparse", ["ID", "RequiredSkill", "RequiredSkillRank"])) {
    itemInfo.set(item.ID, {
      skillLine: toInt(item.RequiredSkill, "RequiredSkill"),
      rank: toInt(item.RequiredSkillRank, "RequiredSkillRank"),
    });
  }
  const teaching = new Map();
  for (const effect of readTable("ItemEffect", ["ID", "TriggerType", "SpellID"])) {
    if (effect.TriggerType === LEARN_SPELL_TRIGGER) {
      for (const itemID of itemsByEffect.get(effect.ID) || []) {
        const info = itemInfo.get(itemID);
        if (info && info.rank > 0) {
          const list = teaching.get(effect.SpellID) || [];
          teaching.set(effect.SpellID, [...list, { itemID: toInt(itemID, "ItemID"), ...info }]);
        }
      }
    }
  }
  return teaching;
}

/** Niveau d'apprentissage d'une recette et sa provenance, ou 0 s'il est inconnu. */
function learnLevel(row, teachingItems, stats) {
  if (row.min > 1 && row.min <= row.yellow) {
    stats.learnFromTable += 1;
    return { level: row.min, itemID: 0 };
  }
  const items = (teachingItems || []).filter((item) => item.skillLine === row.skillLine && item.rank <= row.yellow);
  if (items.length === 0) return { level: 0, itemID: 0 };
  // Plusieurs objets peuvent apprendre la même recette : on retient le moins exigeant.
  const easiest = items.reduce((best, item) => (item.rank < best.rank ? item : best));
  if (items.some((item) => item.rank !== easiest.rank)) stats.learnConflicts += 1;
  stats.learnFromItem += 1;
  return { level: easiest.rank, itemID: easiest.itemID };
}

function buildRecipes() {
  const stats = { kept: 0, skippedNoRange: 0, conflicts: 0, learnFromTable: 0, learnFromItem: 0, learnConflicts: 0, crafts: 0, craftsSkipped: 0 };
  const teaching = buildTeachingItems();
  const bySpell = new Map();
  const columns = ["Spell", "SkillLine", "MinSkillLineRank", "TrivialSkillLineRankLow", "TrivialSkillLineRankHigh", "NumSkillUps"];
  for (const raw of readTable("SkillLineAbility", columns)) {
    const row = {
      spell: toInt(raw.Spell, "Spell"),
      skillLine: toInt(raw.SkillLine, "SkillLine"),
      min: toInt(raw.MinSkillLineRank, "MinSkillLineRank"),
      yellow: toInt(raw.TrivialSkillLineRankLow, "TrivialSkillLineRankLow"),
      grey: toInt(raw.TrivialSkillLineRankHigh, "TrivialSkillLineRankHigh"),
      skillUps: toInt(raw.NumSkillUps, "NumSkillUps"),
    };
    if (row.grey > 0 && row.yellow >= row.grey) {
      // Jaune >= gris : le jeu ne décrit pas de vraie plage de progression, on n'invente rien.
      stats.skippedNoRange += 1;
    } else if (row.grey > 0) {
      const learn = learnLevel(row, teaching.get(raw.Spell), stats);
      const entry = {
        id: row.spell,
        skillLine: row.skillLine,
        skillUps: Math.max(1, row.skillUps),
        thresholds: [learn.level, row.yellow, Math.floor((row.yellow + row.grey) / 2), row.grey],
        teachingItem: learn.itemID,
      };
      const previous = bySpell.get(row.spell);
      if (previous && previous.thresholds.join() !== entry.thresholds.join()) {
        // Deux lignes contradictoires pour la même recette : on l'écarte plutôt que de choisir.
        stats.conflicts += 1;
        bySpell.set(row.spell, null);
      } else if (previous === undefined) {
        bySpell.set(row.spell, entry);
      }
    }
  }
  const recipes = [...bySpell.values()].filter((entry) => entry !== null).sort((a, b) => a.id - b.id);
  stats.kept = recipes.length;
  return { recipes, stats };
}

/**
 * Ce que chaque recette fabrique : Map(numéro de recette -> { itemID, qty }).
 * Une recette est écartée si la table lui donne plusieurs objets fabriqués, ou une quantité qui
 * n'est pas un entier d'au moins 1 : dans le doute, on ne livre rien plutôt qu'une supposition.
 */
function buildCrafts(recipes, stats) {
  const wanted = new Set(recipes.map((recipe) => recipe.id));
  const found = new Map();
  for (const row of readTable("SpellEffect", ["SpellID", "Effect", "EffectItemType", "EffectBasePointsF", "DifficultyID"])) {
    const spell = toInt(row.SpellID, "SpellID");
    const itemID = toInt(row.EffectItemType, "EffectItemType");
    if (wanted.has(spell) && toInt(row.Effect, "Effect") === CREATE_ITEM_EFFECT && row.DifficultyID === "0" && itemID > 0) {
      const qty = Number(row.EffectBasePointsF);
      const valid = Number.isInteger(qty) && qty >= 1;
      // Une ligne répétée à l'identique ne rend pas la recette ambiguë ; une ligne différente, si.
      const previous = found.get(spell);
      const same = previous && previous.itemID === itemID && previous.qty === qty;
      if (!valid || (found.has(spell) && !same)) found.set(spell, null);
      else if (!found.has(spell)) found.set(spell, { itemID, qty });
    }
  }
  const crafts = new Map();
  for (const [spell, craft] of found) {
    if (craft) crafts.set(spell, craft);
    else stats.craftsSkipped += 1;
  }
  stats.crafts = crafts.size;
  return crafts;
}

function renderCraftsLua(recipes, crafts, stats) {
  const today = new Date().toISOString().slice(0, 10);
  return [
    "-- Profession Path — ce que chaque recette fabrique.",
    "-- FICHIER FABRIQUÉ AUTOMATIQUEMENT par tools/gen_thresholds.js : ne pas le modifier à la main.",
    "--",
    `-- Source : table du jeu SpellEffect (effet « fabrique un objet »), version ${build}, via wago.tools, le ${today}.`,
    "-- Sert à donner un prix aux objets que le joueur sait fabriquer lui-même (coût de leurs matériaux).",
    "-- Format : [numéro de la recette] = { numéro de l'objet fabriqué, quantité obtenue par fabrication }",
    `-- ${stats.crafts} recettes. Écartées : ${stats.craftsSkipped} (plusieurs objets fabriqués, ou quantité non entière).`,
    "",
    "local _, ns = ...",
    "",
    `ns.CraftsBuild = "${build}"`,
    "",
    "ns.Crafts = {",
    ...recipes.filter((recipe) => crafts.has(recipe.id)).map((recipe) => {
      const craft = crafts.get(recipe.id);
      return `    [${recipe.id}] = { ${craft.itemID}, ${craft.qty} },`;
    }),
    "}",
    "",
  ].join(String.fromCharCode(10));
}

/** Ajoute nom et matériaux, pour le banc d'essai uniquement (non livré avec l'add-on). */
function withDetails(recipes) {
  const names = new Map(readTable("SpellName", ["ID", "Name_lang"]).map((row) => [row.ID, row.Name_lang]));
  const reagents = new Map();
  for (const row of readTable("SpellReagents", ["SpellID", "Reagent_0", "ReagentCount_0"])) {
    const list = [];
    for (let slot = 0; slot < MAX_REAGENTS; slot += 1) {
      const itemID = toInt(row[`Reagent_${slot}`], "Reagent");
      const count = toInt(row[`ReagentCount_${slot}`], "ReagentCount");
      if (itemID > 0 && count > 0) list.push([itemID, count]);
    }
    reagents.set(row.SpellID, list);
  }
  return recipes.map((recipe) => ({
    ...recipe,
    name: names.get(String(recipe.id)) || `#${recipe.id}`,
    reagents: reagents.get(String(recipe.id)) || [],
  }));
}

function skillLineNames() {
  const rows = readTable("SkillLine", ["ID", "DisplayName_lang"]);
  return Object.fromEntries(rows.map((row) => [row.ID, row.DisplayName_lang]));
}

function renderLua(recipes, stats) {
  const today = new Date().toISOString().slice(0, 10);
  const known = recipes.filter((recipe) => recipe.thresholds[0] > 0).length;
  const teachingItems = recipes.filter((recipe) => recipe.teachingItem > 0);
  return [
    "-- Profession Path — seuils de couleur des recettes.",
    "-- FICHIER FABRIQUÉ AUTOMATIQUEMENT par tools/gen_thresholds.js : ne pas le modifier à la main.",
    "-- Pour corriger ou ajouter une recette, utiliser Data/Corrections.lua.",
    "--",
    `-- Source : tables du jeu (SkillLineAbility, ItemEffect, ItemXItemEffect, ItemSparse),`,
    `-- version ${build}, via wago.tools, le ${today}.`,
    "-- Format : [numéro de la recette] = { apprentissage, jaune, vert, gris }",
    "--   jaune et gris viennent de la table ; vert = milieu entre les deux.",
    "--   apprentissage = niveau de métier requis pour apprendre la recette, ou 0 quand les",
    "--   fichiers du jeu ne le donnent pas (recettes apprises chez un maître : lues en jeu).",
    `-- ${stats.kept} recettes, dont ${known} avec un niveau d'apprentissage connu`,
    `--   (${stats.learnFromTable} donnés par la table, ${stats.learnFromItem} par l'objet qui apprend la recette).`,
    `-- Écartées : ${stats.skippedNoRange} sans plage de progression, ${stats.conflicts} contradictoires.`,
    "",
    "local _, ns = ...",
    "",
    `ns.ThresholdsBuild = "${build}"`,
    "",
    "ns.Thresholds = {",
    ...recipes.map((recipe) => `    [${recipe.id}] = { ${recipe.thresholds.join(", ")} },`),
    "}",
    "",
    "-- [numéro de la recette] = numéro de l'objet (plan, patron, formule) qui l'apprend.",
    "ns.TeachingItems = {",
    ...teachingItems.map((recipe) => `    [${recipe.id}] = ${recipe.teachingItem},`),
    "}",
    "",
  ].join("\n");
}

const { recipes, stats } = buildRecipes();
fs.writeFileSync(LUA_OUTPUT, renderLua(recipes, stats), "utf8");
const crafts = buildCrafts(recipes, stats);
fs.writeFileSync(CRAFTS_OUTPUT, renderCraftsLua(recipes, crafts, stats), "utf8");
fs.mkdirSync(path.dirname(BENCH_OUTPUT), { recursive: true });
fs.writeFileSync(BENCH_OUTPUT, JSON.stringify({ build, skillLines: skillLineNames(), recipes: withDetails(recipes).map((recipe) => ({ ...recipe, creates: crafts.get(recipe.id) || null })) }), "utf8");
process.stdout.write(`${stats.kept} recettes écrites.\n${JSON.stringify(stats)}\n`);
