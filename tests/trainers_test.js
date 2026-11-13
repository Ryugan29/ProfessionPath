// Tests de l'outil qui fabrique l'annuaire des maîtres (tools/import_trainers.js), sur une page
// fictive au format de wow-professions.com. Lancés par tests/run.js. Renvoie le nombre d'échecs.
const assert = require("assert");
const { parsePage, parseRanks } = require("../tools/import_trainers.js");

function block(name, zone, coords) {
  return `<div class="vendor"><p><a href="/forever/npc/x">${name}</a> is here.</p>
<div class="map-embed" data-zone="${zone}" data-coords="${coords}" data-title="${name}"></div></div>`;
}

const PAGE = `
<h2 class="gtitle" id="ranks">Test Ranks</h2>
<table><tbody>
<tr><td><b>Apprentice Test</b></td><td>-</td><td>-</td><td>75</td><td>10</td></tr>
<tr><td><b>Journeyman Test</b></td><td>50</td><td>10</td><td>150</td><td>5</td></tr>
</tbody></table>
<h2 class="gtitle" id="apprentice">Apprentice Test Trainers (1-75)</h2>
<div class="tab-content is-horde active" id="horde-tab">${block("Ug&#39;thok", 1454, "80.7, 23.6")}</div>
<div class="tab-content is-alliance" id="alliance-tab">${block("Smith Argus", 1429, "41.7, 65.5")}${block("Shared Trainer", 2000, "10, 20")}</div>
<div class="tab-content is-horde" id="horde-tab">${block("Shared Trainer", 2000, "10, 20")}</div>
<h2 class="gtitle" id="journeyman">Journeyman Test Trainers (75-150)</h2>
<div class="tab-content is-alliance" id="alliance-tab">${block("Smith Argus", 1429, "41.7, 65.5")}${block("Bad Spot", 1429, "140, 20")}</div>
<h2 class="gtitle" id="specializations">Specialization Trainers</h2>
<div class="tab-content is-alliance" id="alliance-tab">${block("Special Guy", 1455, "50, 50")}</div>
`;

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

const byName = Object.fromEntries(parsePage(PAGE).map((t) => [t.name, t]));

test("lit le nom, la carte, les coordonnées (0 à 1) et la faction", () => {
  const ug = byName["Ug'thok"];
  assert.deepStrictEqual([ug.map, ug.x, ug.y, [...ug.factions]], [1454, 0.807, 0.236, ["Horde"]]);
});

test("un maître présent dans plusieurs rangs les cumule", () => {
  assert.deepStrictEqual([...byName["Smith Argus"].unlocks].sort(), [150, 75]);
});

test("un maître des deux factions est noté pour les deux", () => {
  assert.deepStrictEqual([...byName["Shared Trainer"].factions].sort(), ["Alliance", "Horde"]);
});

test("ignore les positions hors carte et les spécialisations", () => {
  assert.strictEqual(byName["Bad Spot"], undefined);
  assert.strictEqual(byName["Special Guy"], undefined);
});

test("lit le tableau des rangs (métier et niveau requis)", () => {
  assert.deepStrictEqual(parseRanks(PAGE), { 75: { skill: null, level: null }, 150: { skill: 50, level: 10 } });
});

console.log(`annuaire des maitres : ${passed} tests reussis, ${failed} en echec`);
module.exports = failed;
