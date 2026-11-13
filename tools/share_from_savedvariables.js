// Fabrique le texte de partage (/ppath partager) directement depuis une sauvegarde de l'add-on,
// sans passer par le jeu : on charge la sauvegarde et Share.lua de l'add-on dans un interpréteur Lua.
// Le texte obtenu passe ensuite par la vérification habituelle :
//   node tools/share_from_savedvariables.js "<...>/WTF/Account/<compte>/SavedVariables/ProfessionPath.lua" <version.build> > partage.txt
//   node tools/import_shares.js partage.txt
// Comme en jeu, le texte ne contient ni nom de personnage ni royaume.

const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const SHARE_LUA = path.join(__dirname, "..", "ProfessionPath", "Share.lua");

function main() {
  const [savedFile, build] = process.argv.slice(2);
  if (!savedFile || !/^\d+\.\d+\.\d+\.\d+$/.test(build || "")) {
    console.error("Utilisation : node tools/share_from_savedvariables.js <ProfessionPath.lua> <version.build, ex. 1.60.1.70938>");
    process.exit(1);
  }
  const [version, buildNumber] = [build.split(".").slice(0, 3).join("."), build.split(".")[3]];
  const saved = fs.readFileSync(savedFile, "utf8");
  // Le minimum du jeu dont Share.lua a besoin pour fabriquer le texte (pas de fenêtre).
  const script = `
${saved}
local ns = { L = {}, Theme = { colors = {}, sizes = {} } }
ns.db = ProfessionPathDB
function ns.TrainerRecipes(prof) return ns.db.trainer and ns.db.trainer[prof.name] or {} end
function GetBuildInfo() return ${JSON.stringify(version)}, ${JSON.stringify(buildNumber)} end
function GetLocale() return "frFR" end
local share = assert((loadstring or load)(SHARE_SOURCE, "@Share.lua"))
share("ProfessionPath", ns)
return (ns.BuildShareText())
`;
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(SHARE_LUA, "utf8")));
  lua.lua_setglobal(L, to_luastring("SHARE_SOURCE"));
  if (lauxlib.luaL_loadstring(L, to_luastring(script)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    console.error(`Erreur : ${lua.lua_tojsstring(L, -1)}`);
    process.exit(1);
  }
  process.stdout.write(`${lua.lua_tojsstring(L, -1)}\n`);
}

main();
