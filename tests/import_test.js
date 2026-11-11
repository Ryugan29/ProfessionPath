// Tests de l'outil qui vérifie les partages des joueurs et les ajoute aux listes livrées
// (tools/import_shares.js). Lancés par tests/run.js. Renvoie le nombre d'échecs.
const assert = require("assert");
const { parseShare, mergeShare, renderNpcsLua, renderTrainerLevelsLua } = require("../tools/import_shares.js");

const KNOWN_RECIPES = new Set([9001, 9004]);
const SAMPLE = [
  "Voici mon partage :",
  "ProfessionPath-share 1;1.60.1.70862;frFR",
  "N;trainer;3355;Maitre Test;1453;0.5;0.6;Alliance;164;Forge;",
  "N;vendor;4444;Marchand Test;1453;0.52;0.61;Alliance;;;501,502",
  "R;164;9004;120;500",
  "N;vendor;5555;Sans objet;1453;0.1;0.1;Alliance;;;",
  "N;trainer;6666;Hors carte;1453;1.7;0.2;Alliance;164;Forge;",
  "R;164;123456;120;500",
  "R;164;9001;9999;",
  "merci !",
].join("\r\n");

let passed = 0;
let failed = 0;
function test(name, fn) {
  try {
    fn();
    passed += 1;
  } catch (error) {
    failed += 1;
    console.log(`ECHEC  ${name}\n       ${error.message}`);
  }
}

test("lit les lignes valides et ignore le texte autour", () => {
  const share = parseShare(SAMPLE, KNOWN_RECIPES);
  assert.strictEqual(share.build, "1.60.1.70862");
  assert.strictEqual(share.locale, "frFR");
  assert.deepStrictEqual(Object.keys(share.npcs).sort(), ["trainer:3355", "vendor:4444"]);
  assert.deepStrictEqual(share.npcs["trainer:3355"], {
    kind: "trainer", name: "Maitre Test", map: 1453, x: 0.5, y: 0.6, faction: "Alliance", professionID: 164, profession: "Forge",
  });
  assert.deepStrictEqual(share.npcs["vendor:4444"].items, [501, 502]);
  assert.deepStrictEqual(share.trainerLevels, { 9004: [120, 500] });
});

test("refuse les lignes douteuses en disant pourquoi", () => {
  const share = parseShare(SAMPLE, KNOWN_RECIPES);
  const reasons = share.rejected.map((r) => r.reason).join(" | ");
  assert.strictEqual(share.rejected.length, 4, reasons);
  assert.match(reasons, /aucun matériau/);
  assert.match(reasons, /position/);
  assert.match(reasons, /recette inconnue/);
  assert.match(reasons, /niveau/);
});

test("refuse un texte sans en-tête de partage", () => {
  assert.throws(() => parseShare("N;trainer;1;X;1;0.5;0.5;;164;Forge;", KNOWN_RECIPES), /en-tête/);
});

test("fusion : ajoute, confirme, et signale les contradictions sans rien écraser", () => {
  const store = { npcs: {}, trainerLevels: {} };
  const first = mergeShare(store, parseShare(SAMPLE, KNOWN_RECIPES));
  assert.strictEqual(first.added, 3);
  const again = mergeShare(store, parseShare(SAMPLE, KNOWN_RECIPES));
  assert.strictEqual(again.added, 0);
  assert.strictEqual(again.confirmed, 3);
  const moved = SAMPLE.replace("N;trainer;3355;Maitre Test;1453;0.5;0.6", "N;trainer;3355;Maitre Test;1453;0.9;0.9")
    .replace("R;164;9004;120;500", "R;164;9004;125;500");
  const conflict = mergeShare(store, parseShare(moved, KNOWN_RECIPES));
  assert.strictEqual(conflict.conflicts.length, 2);
  assert.strictEqual(store.npcs["trainer:3355"].x, 0.5, "la valeur existante doit être gardée");
  assert.deepStrictEqual(store.trainerLevels[9004], [120, 500]);
});

test("les fichiers Lua fabriqués contiennent les données, triées", () => {
  const store = { npcs: {}, trainerLevels: {} };
  mergeShare(store, parseShare(SAMPLE, KNOWN_RECIPES));
  const npcs = renderNpcsLua(store, "1.60.1.70862");
  assert.match(npcs, /ns\.NPCs = \{/);
  assert.match(npcs, /\["trainer:3355"\] = \{ kind = "trainer", name = "Maitre Test", map = 1453, x = 0\.5, y = 0\.6, faction = "Alliance", professionID = 164, profession = "Forge" \},/);
  assert.match(npcs, /items = \{ \[501\] = true, \[502\] = true \}/);
  assert.ok(npcs.indexOf("trainer:3355") < npcs.indexOf("vendor:4444"), "tri attendu");
  const levels = renderTrainerLevelsLua(store);
  assert.match(levels, /\[9004\] = \{ 120, 500 \},/);
});

console.log(`partages : ${passed} tests reussis, ${failed} en echec`);
module.exports = failed;
