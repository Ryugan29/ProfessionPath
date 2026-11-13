-- Profession Path — maîtres de métier et marchands de fournitures, livrés avec l'add-on.
-- FICHIER FABRIQUÉ par tools/import_shares.js à partir des partages des joueurs (/ppath partager) :
-- ne pas le modifier à la main. Source : tools/community.json.
--
-- Les fichiers du jeu ne disent pas où se trouvent les PNJ. Chaque entrée vient d'un PNJ réellement
-- rencontré en jeu sur WoW Forever par un joueur, puis vérifiée. Rien n'est repris d'une autre
-- version du jeu ni d'un autre add-on. Un PNJ que le joueur a rencontré lui-même remplace celui-ci.
--
-- Forme : ["trainer:numéro"] ou ["vendor:numéro"] = { kind, name, map, x, y, faction,
--         professionID et profession (maître), items (marchand : matériaux de métier vendus) }

local _, ns = ...

ns.NPCsBuild = "1.60.1.70888" -- version du jeu des relevés

ns.NPCs = {
    ["trainer:1292"] = { kind = "trainer", name = "Maris Granger", map = 1453, x = 0.7202, y = 0.6233, faction = "Alliance", professionID = 393, profession = "Dépeçage" },
    ["trainer:251905"] = { kind = "trainer", name = "Zerril Douce-Brise", map = 2521, x = 0.438, y = 0.4391, professionID = 185, profession = "Cuisine" },
    ["trainer:251992"] = { kind = "trainer", name = "Fenn Beautemps", map = 2521, x = 0.4501, y = 0.4834, professionID = 356, profession = "Pêche" },
    ["trainer:257018"] = { kind = "trainer", name = "Naleeia Racommode", map = 2521, x = 0.4314, y = 0.4629, professionID = 129, profession = "Secourisme" },
    ["trainer:257019"] = { kind = "trainer", name = "Nyassa Prestepotion", map = 2521, x = 0.4372, y = 0.4347, profession = "Alchimie" },
    ["trainer:5482"] = { kind = "trainer", name = "Stephen Ryback", map = 1453, x = 0.7816, y = 0.5312, faction = "Alliance", professionID = 185, profession = "Cuisine" },
    ["trainer:5511"] = { kind = "trainer", name = "Therum Deepforge", map = 1453, x = 0.634, y = 0.3684, faction = "Alliance", professionID = 164, profession = "Forge" },
    ["trainer:5513"] = { kind = "trainer", name = "Gelman Stonehand", map = 1453, x = 0.5914, y = 0.3773, faction = "Alliance", professionID = 186, profession = "Minage" },
    ["trainer:5564"] = { kind = "trainer", name = "Simon Tanner", map = 1453, x = 0.718, y = 0.6291, faction = "Alliance", professionID = 165, profession = "Travail du cuir" },
    ["vendor:1448"] = { kind = "vendor", name = "Neal Allen", map = 1437, x = 0.1073, y = 0.5677, faction = "Alliance", items = { [159] = true, [1179] = true, [1205] = true, [2880] = true, [3030] = true, [3466] = true, [4399] = true, [4400] = true, [4470] = true, [11291] = true } },
    ["vendor:1453"] = { kind = "vendor", name = "Dewin Shimmerdawn", map = 1437, x = 0.0804, y = 0.5631, faction = "Alliance", items = { [3371] = true, [3372] = true, [8925] = true, [18256] = true } },
    ["vendor:1464"] = { kind = "vendor", name = "Helbrek l'aubergiste", map = 1437, x = 0.1067, y = 0.6084, faction = "Alliance", items = { [159] = true, [1179] = true, [1205] = true, [1645] = true, [1708] = true, [2594] = true, [8766] = true } },
    ["vendor:2481"] = { kind = "vendor", name = "Bliztik", map = 1431, x = 0.1802, y = 0.5452, items = { [3371] = true, [3372] = true, [8925] = true, [18256] = true } },
    ["vendor:251537"] = { kind = "vendor", name = "Uualia Solcrête", map = 2521, x = 0.4276, y = 0.2438, items = { [159] = true } },
    ["vendor:254358"] = { kind = "vendor", name = "Veena Vérinuage", map = 2521, x = 0.4476, y = 0.4546, items = { [159] = true, [1179] = true, [4470] = true } },
    ["vendor:254360"] = { kind = "vendor", name = "Belandiel Longvol", map = 2521, x = 0.448, y = 0.451, items = { [2320] = true, [2324] = true, [2604] = true, [2678] = true, [2880] = true, [3371] = true, [4289] = true, [4536] = true, [6217] = true, [6260] = true } },
    ["vendor:257019"] = { kind = "vendor", name = "Nyassa Prestepotion", map = 2521, x = 0.4372, y = 0.4347, items = { [3371] = true, [3372] = true, [8925] = true, [18256] = true } },
    ["vendor:3955"] = { kind = "vendor", name = "Shandrina", map = 1440, x = 0.4955, y = 0.6708, faction = "Alliance", items = { [2320] = true, [2321] = true, [2325] = true, [2604] = true, [2678] = true, [2692] = true, [2880] = true, [2928] = true, [3371] = true, [3372] = true, [3466] = true, [3713] = true, [3857] = true, [4289] = true, [4291] = true, [4340] = true, [4341] = true, [4342] = true, [4399] = true, [4400] = true, [6217] = true, [6530] = true, [8343] = true, [8925] = true } },
    ["vendor:5175"] = { kind = "vendor", name = "Gearcutter Cogspinner", map = 1455, x = 0.6805, y = 0.4323, faction = "Alliance", items = { [2880] = true, [3466] = true, [4399] = true, [4400] = true } },
    ["vendor:5512"] = { kind = "vendor", name = "Kaita Deepforge", map = 1453, x = 0.6331, y = 0.3744, faction = "Alliance", items = { [2880] = true, [3466] = true, [3857] = true, [18567] = true } },
    ["vendor:5519"] = { kind = "vendor", name = "Billibub Cogspinner", map = 1453, x = 0.6247, y = 0.3013, faction = "Alliance", items = { [2880] = true, [3466] = true, [4399] = true, [4400] = true } },
    ["vendor:6790"] = { kind = "vendor", name = "Trelayne l'aubergiste", map = 1431, x = 0.7384, y = 0.4427, faction = "Alliance", items = { [159] = true, [1179] = true, [1205] = true, [1645] = true, [1708] = true, [8766] = true } },
    ["vendor:8305"] = { kind = "vendor", name = "Kixxle", map = 1437, x = 0.502, y = 0.3785, items = { [3371] = true, [3372] = true, [8925] = true, [18256] = true } },
}
