-- Profession Path — niveau et prix des recettes enseignées par les maîtres, livrés avec l'add-on.
-- FICHIER FABRIQUÉ par tools/import_shares.js à partir des partages des joueurs (/ppath partager) :
-- ne pas le modifier à la main. Source : tools/community.json.
--
-- Les fichiers du jeu ne disent pas à quel niveau un maître enseigne une recette. Chaque ligne vient
-- d'un maître réellement lu en jeu sur WoW Forever par un joueur, puis vérifiée.
-- Forme : [numéro de la recette] = { niveau de métier requis, prix en cuivre (ou nil) }
-- Rangé par numéro : la liste sert dans toutes les langues du jeu. Un maître lu par le joueur la remplace.

local _, ns = ...

ns.TrainerLevels = {
    [2153] = { 15, 50 },
    [2159] = { 50, 250 },
    [2160] = { 35, 100 },
    [2161] = { 50, 100 },
    [2162] = { 40, 100 },
    [2165] = { 75, 250 },
    [2166] = { 95, 450 },
    [2167] = { 75, 350 },
    [2168] = { 85, 350 },
    [3278] = { 115, 1000 },
    [3753] = { 25, 75 },
    [3756] = { 40, 150 },
    [3759] = { 50, 200 },
    [3760] = { 125, 600 },
    [3761] = { 60, 350 },
    [3763] = { 55, 300 },
    [3764] = { 120, 500 },
    [3766] = { 100, 400 },
    [3768] = { 105, 500 },
    [3770] = { 110, 500 },
    [3780] = { 125, 750 },
    [3816] = { 30, 50 },
    [3817] = { 75, 200 },
    [3818] = { 125, 500 },
    [6500] = { 125, 300 },
    [7135] = { 90, 400 },
    [7928] = { 150, 5000 },
    [9060] = { 25, 100 },
    [9062] = { 25, 100 },
    [9065] = { 45, 150 },
    [9068] = { 70, 400 },
    [9074] = { 95, 500 },
    [9145] = { 100, 500 },
    [9193] = { 125, 500 },
    [9194] = { 125, 500 },
    [20648] = { 75, 500 },
    [20649] = { 125, 1000 },
    [21175] = { 200, 4000 },
    [1229432] = { 20, 100 },
    [1244433] = { 110, 800 },
    [1259342] = { 90, 250 },
    [1259347] = { 120, 1200 },
}
