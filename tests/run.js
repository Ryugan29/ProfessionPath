// Lance les tests Lua de l'add-on en dehors du jeu.
// Utilise « fengari », un interpréteur Lua écrit en JavaScript (installé par : npm install).
//   - planner_test.lua : vérifie le calcul du parcours.
//   - smoke_test.lua   : charge l'add-on entier dans un faux jeu et manipule la fenêtre.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const root = path.join(__dirname, "..").replace(/\\/g, "/");

// Chaque test tourne dans un interpréteur neuf, pour ne pas influencer le suivant.
function runLua(source, label) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const failed =
    lauxlib.luaL_loadbuffer(L, to_luastring(source), null, to_luastring("@" + label)) !== lua.LUA_OK ||
    lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK;
  if (failed) {
    console.log(`ERREUR dans ${label} : ${lua.lua_tojsstring(L, -1)}`);
    return 1;
  }
  return lua.lua_tointeger(L, -1);
}

// Charge un fichier de l'add-on comme le fait le jeu : il reçoit (nom de l'add-on, table partagée).
const loader = `
local ROOT = ${JSON.stringify(root)}
local function loadAddonFile(file, addonName, ns)
  local chunk = assert(loadfile(ROOT .. "/ProfessionPath/" .. file))
  chunk(addonName, ns)
end
`;

const plannerTest = `${loader}
local ns = {}
loadAddonFile("Planner.lua", "ProfessionPath", ns)
return assert(loadfile(ROOT .. "/tests/planner_test.lua"))(ns)
`;

const favoritesTest = `${loader}
local ns = {}
loadAddonFile("Favorites.lua", "ProfessionPath", ns)
return assert(loadfile(ROOT .. "/tests/favorites_test.lua"))(ns)
`;

// L'essai à blanc charge les fichiers dans l'ordre exact du .toc : un fichier oublié dans le .toc
// ferait échouer les tests ici, au lieu de casser l'add-on en jeu.
const tocFiles = fs
  .readFileSync(path.join(__dirname, "..", "ProfessionPath", "ProfessionPath.toc"), "utf8")
  .split(String.fromCharCode(10))
  .map((line) => line.trim())
  .filter((line) => line.endsWith(".lua") && !line.startsWith("#"))
  .map((line) => line.split(String.fromCharCode(92)).join("/"));

const smokeTest = `${loader}
return assert(loadfile(ROOT .. "/tests/smoke_test.lua"))(loadAddonFile, { ${tocFiles.map((f) => JSON.stringify(f)).join(", ")} })
`;

const failures =
  runLua(plannerTest, "planner_test") + runLua(favoritesTest, "favorites_test") + runLua(smokeTest, "smoke_test") +
  require("./import_test.js") + require("./trainers_test.js");
process.exit(failures === 0 ? 0 : 1);
