// Banc d'essai hors jeu : fait tourner le calcul du parcours sur les vraies recettes de chaque
// métier (tests/data/bench.json, fabriqué par tools/gen_thresholds.js) et affiche un tableau,
// pour repérer les quantités absurdes et les trous sans attendre de tomber dessus en jeu.
//
// Utilisation : node tools/bench.js [niveau de départ] [niveau visé]     (par défaut 1 et 300)
//
// LIMITE IMPORTANTE : le niveau d'apprentissage des recettes de maître n'est pas dans les
// fichiers du jeu. Le banc n'utilise donc que les recettes dont ce niveau est connu (celles
// apprises par un objet), en supposant que le joueur les apprend dès qu'il en a le niveau.
// Les trous qu'il affiche correspondent en général à des recettes de maître manquantes : ils
// montrent où la lecture des maîtres en jeu est indispensable, pas un défaut du calcul.

const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const ROOT = path.join(__dirname, "..");
const data = JSON.parse(fs.readFileSync(path.join(ROOT, "tests", "data", "bench.json"), "utf8"));
const from = Number(process.argv[2] || 1);
const target = Number(process.argv[3] || 300);
const MIN_RECIPES = 20;
const MODES = ["simple", "fewmats"];

function luaRecipe(recipe) {
  const reagents = recipe.reagents.map(([item, count]) => `{${item},${count}}`).join(",");
  return (
    `{id=${recipe.id},name=${JSON.stringify(recipe.name)},learned=false,learnSource="trainer",` +
    `learnLevel=${recipe.thresholds[0]},skillUps=${recipe.skillUps},` +
    `thresholds={${recipe.thresholds.join(",")}},reagents={${reagents}}}`
  );
}

function runPlan(recipes, mode) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const plannerPath = path.join(ROOT, "ProfessionPath", "Planner.lua").replace(/\\/g, "/");
  const source = `
    local ns = {}
    assert(loadfile(${JSON.stringify(plannerPath)}))("bench", ns)
    local plan = ns.Planner.Plan({ skill = ${from}, target = ${target}, mode = "${mode}", recipes = { ${recipes.map(luaRecipe).join(",")} } })
    local crafts, biggest, biggestName = 0, 0, ""
    for _, step in ipairs(plan.steps) do
      crafts = crafts + (step.crafts or 0)
      if (step.crafts or 0) > biggest then biggest, biggestName = step.crafts, step.recipe.name end
    end
    return string.format("%d|%d|%d|%d|%d|%d|%s", plan.reached, #plan.steps, crafts, #plan.visits, #plan.materials, biggest, biggestName)
  `;
  if (lauxlib.luaL_loadstring(L, to_luastring(source)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
  const [reached, steps, crafts, visits, materials, biggest, biggestName] = lua.lua_tojsstring(L, -1).split("|");
  return { reached: Number(reached), steps: Number(steps), crafts: Number(crafts), visits: Number(visits), materials: Number(materials), biggest: Number(biggest), biggestName };
}

const bySkillLine = new Map();
for (const recipe of data.recipes) {
  if (recipe.thresholds[0] > 0) {
    const list = bySkillLine.get(recipe.skillLine) || [];
    bySkillLine.set(recipe.skillLine, [...list, recipe]);
  }
}

const rows = [];
for (const [skillLine, recipes] of bySkillLine) {
  if (recipes.length >= MIN_RECIPES) {
    for (const mode of MODES) {
      const result = runPlan(recipes, mode);
      rows.push({
        "métier": data.skillLines[skillLine],
        "priorité": mode,
        "recettes": recipes.length,
        "atteint": result.reached,
        "étapes": result.steps,
        "fabrications": result.crafts,
        "par point": result.reached > from ? (result.crafts / (result.reached - from)).toFixed(2) : "-",
        "visites": result.visits,
        "matériaux": result.materials,
        "plus grosse étape": `${result.biggest} x ${result.biggestName}`,
      });
    }
  }
}

process.stdout.write(`Tables du jeu ${data.build} — parcours de ${from} à ${target}, recettes au niveau d'apprentissage connu.\n`);
console.table(rows);
