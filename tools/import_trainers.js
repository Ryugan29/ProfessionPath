// Fabrique Data/Trainers.lua : l'annuaire des maîtres de métier de WoW Forever.
//
// Source : les pages « Trainers » de wow-professions.com/forever (une par métier), écrites pour
// Forever. Chaque maître y est donné avec sa faction, son rang, sa carte (numéro uiMapID du jeu)
// et ses coordonnées. On ne reprend que ces faits, pas les textes du site.
//
// Utilisation (depuis le dossier du projet) :
//   1. télécharger https://www.wow-professions.com/forever/<métier>-trainers dans un dossier,
//      sous le nom <métier>.html (alchemy, blacksmithing, cooking, enchanting, engineering,
//      first-aid, fishing, herbalism, leatherworking, mining, skinning, tailoring) ;
//   2. node tools/import_trainers.js <dossier> <date du relevé, ex. 2026-11-13>

const fs = require("fs");
const path = require("path");

// Page du site -> numéro du métier dans le jeu (skillLine).
const PROFESSIONS = {
  alchemy: 171, blacksmithing: 164, cooking: 185, enchanting: 333, engineering: 202, "first-aid": 129,
  fishing: 356, herbalism: 182, leatherworking: 165, mining: 186, skinning: 393, tailoring: 197,
};

// Section de la page -> maximums de métier que le PNJ permet d'atteindre.
// « trainers » couvre 1-150 (Cuisine, Secourisme, Pêche) ou 1-300 (métiers de récolte) selon son titre.
const SECTION_UNLOCKS = {
  junior: [75], apprentice: [75], journeyman: [150], expert: [225], artisan: [300],
};

const OUTPUT = path.join(__dirname, "..", "ProfessionPath", "Data", "Trainers.lua");
const MAX_SKILL = 300;

function decode(text) {
  return text.replace(/&#39;|&#x27;|&rsquo;/g, "'").replace(/&amp;/g, "&").replace(/<[^>]+>/g, "").trim();
}

// Tableau « Ranks » : { [maximum du rang] = { skill = métier requis, level = niveau requis } }.
function parseRanks(html) {
  const rules = {};
  const start = html.indexOf('id="ranks"');
  if (start < 0) return rules;
  const table = html.slice(start, html.indexOf("</table>", start));
  for (const row of table.matchAll(/<tr><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td>/g)) {
    const max = Number(decode(row[4]));
    if (!Number.isInteger(max) || max <= 0 || max > MAX_SKILL) continue;
    // Case vide ou « - » : aucune condition (Number("") vaudrait 0, d'où la vérification).
    const cell = (text) => (/^\d+$/.test(decode(text)) ? Number(decode(text)) : null);
    rules[max] = { skill: cell(row[2]), level: cell(row[3]) };
  }
  return rules;
}

function sectionUnlocks(id, title) {
  if (SECTION_UNLOCKS[id]) return SECTION_UNLOCKS[id];
  if (id !== "trainers") return null; // spécialisations, etc. : pas un rang de métier
  const range = title.match(/\((\d+)-(\d+)\)/);
  const top = range ? Number(range[2]) : 0;
  return [75, 150, 225, 300].filter((max) => max <= top);
}

// Un bloc « vendor » : nom, carte et coordonnées.
function parseBlock(block) {
  const embed = block.match(/data-zone="(\d+)" data-coords="([\d.]+), ([\d.]+)" data-title="([^"]*)"/);
  if (!embed) return null;
  const link = block.match(/<a href="\/forever\/npc\/[^"]*">([^<]+)<\/a>/);
  const name = decode(link ? link[1] : embed[4]);
  const x = Number(embed[2]) / 100;
  const y = Number(embed[3]) / 100;
  if (!name || !(x > 0 && x <= 1 && y > 0 && y <= 1)) return null;
  return { name, map: Number(embed[1]), x: Number(x.toFixed(4)), y: Number(y.toFixed(4)) };
}

function parsePage(html) {
  const trainers = new Map(); // clé : nom + carte
  const sections = html.split(/<h2 class="gtitle" id="/).slice(1);
  for (const section of sections) {
    const id = section.slice(0, section.indexOf('"'));
    const title = decode(section.slice(section.indexOf(">") + 1, section.indexOf("</h2>")));
    const unlocks = sectionUnlocks(id, title);
    if (!unlocks) continue;
    // Onglets de faction ; une section sans onglet vaut pour les deux.
    const tabs = section.split(/<div class="tab-content is-(horde|alliance)[^"]*"/);
    const parts = tabs.length > 1 ? [] : [[null, section]];
    for (let i = 1; i < tabs.length; i += 2) parts.push([tabs[i] === "horde" ? "Horde" : "Alliance", tabs[i + 1]]);
    for (const [faction, content] of parts) {
      for (const block of content.split('<div class="vendor">').slice(1)) {
        const npc = parseBlock(block);
        if (!npc) continue;
        const key = `${npc.name}|${npc.map}`;
        const entry = trainers.get(key) || { ...npc, factions: new Set(), unlocks: new Set() };
        if (faction) entry.factions.add(faction); else { entry.factions.add("Horde"); entry.factions.add("Alliance"); }
        unlocks.forEach((max) => entry.unlocks.add(max));
        trainers.set(key, entry);
      }
    }
  }
  return [...trainers.values()];
}

// Chaîne Lua : un nom avec un caractère de contrôle serait mal écrit (\u n'existe pas en Lua 5.1).
function luaString(text) {
  if (/[\u0000-\u001f]/.test(text)) throw new Error(`caractère de contrôle dans « ${text} »`);
  return JSON.stringify(text);
}

function render(all, date) {
  const lines = [
    "-- Généré par tools/import_trainers.js : ne pas modifier à la main.",
    `-- Maîtres de métier de WoW Forever, d'après wow-professions.com/forever (relevé du ${date}).`,
    "-- ns.RankRules[métier][maximum du rang] = { skill = métier requis, level = niveau requis (nil si aucun) }",
    "-- ns.Trainers[métier] = { { name, map, x, y, faction (nil = les deux), unlocks = { [maximum] = true } } }",
    "",
    "local _, ns = ...",
    "",
    `ns.TrainersDate = ${luaString(date)}`,
    "ns.RankRules = {",
  ];
  for (const [skillLine, page] of all) {
    const ranks = Object.entries(page.rules).sort((a, b) => a[0] - b[0])
      .map(([max, r]) => `[${max}] = { skill = ${r.skill ?? "nil"}, level = ${r.level ?? "nil"} }`);
    lines.push(`    [${skillLine}] = { ${ranks.join(", ")} },`);
  }
  lines.push("}", "", "ns.Trainers = {");
  for (const [skillLine, page] of all) {
    lines.push(`    [${skillLine}] = {`);
    const sorted = [...page.trainers].sort((a, b) => a.name.localeCompare(b.name) || a.map - b.map);
    for (const t of sorted) {
      const faction = t.factions.size === 1 ? luaString([...t.factions][0]) : "nil";
      const unlocks = [...t.unlocks].sort((a, b) => a - b).map((max) => `[${max}] = true`).join(", ");
      lines.push(`        { name = ${luaString(t.name)}, map = ${t.map}, x = ${t.x}, y = ${t.y}, faction = ${faction}, unlocks = { ${unlocks} } },`);
    }
    lines.push("    },");
  }
  lines.push("}", "");
  return lines.join("\n");
}

function main() {
  const [dir, date] = process.argv.slice(2);
  if (!dir || !/^\d{4}-\d{2}-\d{2}$/.test(date || "")) {
    console.error("Utilisation : node tools/import_trainers.js <dossier des pages> <AAAA-MM-JJ>");
    process.exit(1);
  }
  const all = [];
  for (const [page, skillLine] of Object.entries(PROFESSIONS)) {
    const file = path.join(dir, `${page}.html`);
    if (!fs.existsSync(file)) throw new Error(`page manquante : ${file}`);
    const html = fs.readFileSync(file, "utf8");
    const result = { rules: parseRanks(html), trainers: parsePage(html) };
    if (result.trainers.length === 0) throw new Error(`aucun maître lu dans ${page}.html`);
    console.log(`${page} : ${result.trainers.length} PNJ, rangs ${Object.keys(result.rules).join("/")}`);
    all.push([skillLine, result]);
  }
  all.sort((a, b) => a[0] - b[0]);
  fs.writeFileSync(OUTPUT, render(all, date));
  console.log(`écrit : ${OUTPUT}`);
}

if (require.main === module) main();
module.exports = { parsePage, parseRanks };
