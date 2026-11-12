-- Profession Path — la fenêtre : métier, progression, prochaine recette, étapes, matériaux.
-- L'apparence (couleurs, boutons, animations) vient de Theme.lua ; ici on assemble et on remplit.

local _, ns = ...
local L, T = ns.L, ns.Theme
local C, S, D = T.colors, T.sizes, T.durations

local WIDTH, PAD = 460, 16
local INNER = WIDTH - 2 * PAD
local COLUMN_GAP = 24                              -- espace entre les deux colonnes du mode rectangle
local WIDE_WIDTH = 2 * PAD + 2 * INNER + COLUMN_GAP -- largeur du mode rectangle
local LIST_WIDTH = INNER - 8
local HEADER_HEIGHT = 38
local GAP = 14
local LABEL_HEIGHT = 20
local STEP_HEIGHT, MATERIAL_HEIGHT = 38, 26
local STAR_SIZE = 16
local MATERIAL_ICON_X = 20  -- l'icône du composant vient après l'étoile
local MATERIAL_TEXT_X = 44  -- le nom et la mini-barre viennent après l'icône
local STAR_OFF_ALPHA = 0.45 -- étoile éteinte : grise, mais assez visible pour donner envie de cliquer
local MATERIAL_COUNT_WIDTH = 150 -- place pour « 25 + 15 banque / 244 »
local MAX_VISIBLE_STEPS, MAX_VISIBLE_MATERIALS = 5, 7
local HERO_MATERIAL_HEIGHT = 22
local PREPARE_HEIGHT = 22        -- ligne de la section « À préparer toi-même »
local NPC_ROW_HEIGHT = 24        -- ligne de la section « PNJ du métier »
local NPC_BUTTON_WIDTH = 60
local HERO_MATERIALS_GAP = 10    -- espace entre l'explication et les matériaux de la carte
local HERO_INNER = INNER - 28    -- largeur utile de la carte « Prochaine recette »
local TAB_SIZE, TAB_GAP = 36, 4  -- onglets de métier, collés au bord droit de la fenêtre
local TAB_OFFSET = 2
local TAB_IDLE_ALPHA, TAB_UNREAD_ALPHA = 0.7, 0.4
local TOOLTIP_X = TAB_OFFSET + TAB_SIZE + 8 -- les infobulles du jeu s'ouvrent après les onglets
local WARNING_PAD = 10          -- marge haute et basse du bandeau « parcours provisoire »
local WARNING_TEXT_TOP = 28      -- le texte du bandeau commence sous son titre
local HERO_TEXT_TOP = 70
local SLIDE_DISTANCE = 10
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"

local root
local w = {}
local stepRows, materialRows, heroRows, prepareRows, npcRows, ticks = {}, {}, {}, {}, {}, {}
local tabButtons = {}
local justOpened = false
local closing = false
local lastSignature
local shownRatio = 0
local targetRatio

-- Réglages ---------------------------------------------------------------

local function AvailableModes()
    local modes = {}
    for _, mode in ipairs(ns.Planner.MODES) do
        if mode ~= "cheap" or ns.HasPrices() then modes[#modes + 1] = mode end
    end
    return modes
end

local function CurrentMode()
    for _, mode in ipairs(AvailableModes()) do
        if mode == ns.db.mode then return mode end
    end
    return "simple"
end

local function SelectNextMode()
    local modes = AvailableModes()
    local current = CurrentMode()
    for index, mode in ipairs(modes) do
        if mode == current then
            ns.db.mode = modes[index % #modes + 1]
            return
        end
    end
end

local function ApplyTargetFromBox()
    local prof = ns.SelectedProfession()
    local value = tonumber(w.targetBox:GetText())
    if prof and value then
        ns.SetTarget(prof, math.max(prof.skill + 1, math.min(prof.max, math.floor(value))))
    end
    w.targetBox:ClearFocus()
    ns.RefreshUI()
end

local function CountSkipped(prof)
    local count = 0
    for _ in pairs(ns.SkippedFor(prof)) do count = count + 1 end
    return count
end

local function MarkDone(recipeID)
    local prof = ns.SelectedProfession()
    if not prof or not recipeID then return end
    ns.SkippedFor(prof)[recipeID] = true
    ns.RefreshUI()
end

local function ResetDone()
    local prof = ns.SelectedProfession()
    if not prof then return end
    ns.Character().skipped[prof.id] = {}
    ns.RefreshUI()
end

-- Textes du parcours ------------------------------------------------------

local function Percent(chance)
    return math.floor((chance or 0) * 100 + 0.5)
end

local function QuantityLabel(step)
    if not step.crafts then return "" end
    return (step.exact and L.STEP_QTY_EXACT or L.STEP_QTY_ESTIMATE):format(step.crafts)
end

-- Dit où et à quel niveau s'apprend une recette que le joueur ne connaît pas.
local function LearnText(recipe)
    if recipe.learnSource == "trainer" then
        local cost = recipe.learnCost and ns.MoneyText(recipe.learnCost)
        return L.LEARN_TRAINER:format(recipe.learnLevel) .. (cost and (" " .. L.LEARN_COST:format(cost)) or "")
    end
    if recipe.teachingItem then return L.LEARN_ITEM:format(ns.ItemName(recipe.teachingItem)) end
    return L.REASON_LEARN
end

-- Une ligne par visite au maître : « Maintenant : recette A, recette B ».
local function VisitsText(plan, prof)
    local lines = {}
    for _, visit in ipairs(plan.visits or {}) do
        local names = {}
        for _, recipe in ipairs(visit.recipes) do
            names[#names + 1] = recipe.name
        end
        local when = visit.level <= prof.skill and L.VISIT_NOW or L.VISIT_AT:format(visit.level)
        lines[#lines + 1] = L.VISIT_LINE:format(when, table.concat(names, ", "))
    end
    return table.concat(lines, "\n")
end

local function ReasonText(step, mode)
    local parts = {}
    if step.needsLearning then parts[#parts + 1] = LearnText(step.recipe) end
    if step.byColor then
        parts[#parts + 1] = L.REASON_COLOR:format(L["COLOR_" .. step.recipe.difficulty] or "?")
    elseif step.exact then
        parts[#parts + 1] = L.REASON_EXACT:format(step.from, step.to)
    else
        parts[#parts + 1] = L.REASON_CHANCE:format(Percent(step.chanceStart), Percent(step.chanceEnd))
    end
    if not step.needsLearning and not step.byColor then
        if mode == "fewmats" then parts[#parts + 1] = L.REASON_FEWMATS end
        if mode == "cheap" then parts[#parts + 1] = step.priced and L.REASON_CHEAP or L.REASON_NOPRICE end
    end
    return table.concat(parts, " ")
end

local function FooterText(plan, prof, mode)
    local notes = {}
    if plan.stopReason == "gap" then
        notes[#notes + 1] = L.STOP_GAP:format(plan.reached)
    elseif plan.stopReason == "nodata" then
        notes[#notes + 1] = L.STOP_NODATA
    elseif prof.skill >= ns.TargetFor(prof) then
        notes[#notes + 1] = L.STOP_DONE
    end
    if plan.stopReason == "trainer" then
        notes[#notes + 1] = L.STOP_TRAINER:format(plan.reached, plan.unlearnedHelpful or 0)
    elseif (plan.unlearnedHelpful or 0) > 0 then
        notes[#notes + 1] = L.NOTE_UNLEARNED:format(plan.unlearnedHelpful)
    end
    if plan.pricesMissing then notes[#notes + 1] = L.NOTE_PRICES end
    if ns.db.mode == "cheap" and mode ~= "cheap" then notes[#notes + 1] = L.MODE_CHEAP_UNAVAILABLE end
    if prof.scanSkill ~= prof.skill then notes[#notes + 1] = L.NOTE_STALE end
    return table.concat(notes, "\n")
end

-- Couleur d'une étape : corail = à apprendre, ambre = point garanti, jaune = estimation.
local function StepColor(step)
    if step.needsLearning then return C.alert end
    if step.byColor then return C[step.recipe.difficulty] or C.muted end
    return step.exact and C.accent or C.yellow
end

-- Infobulles ---------------------------------------------------------------

local function ShowTextTooltip(owner, title, body)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
    GameTooltip:Show()
end

-- Infobulle du jeu (objet, recette) : placée à droite de la fenêtre, pour ne pas la recouvrir.
local function ShowGameTooltip(owner, method, id)
    if not id or type(GameTooltip[method]) ~= "function" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", root, "TOPRIGHT", TOOLTIP_X, 0)
    -- Si le jeu refuse cet identifiant, on n'affiche simplement pas d'infobulle.
    if pcall(GameTooltip[method], GameTooltip, id) then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

-- Animations de la fenêtre --------------------------------------------------

-- Fait apparaître une ligne en fondu avec un léger glissement, décalé selon son rang.
local function Cascade(row, key, index)
    T.Tween(key, D.slide, function(progress)
        row:SetAlpha(progress)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", -SLIDE_DISTANCE * (1 - progress), row.offsetY)
    end, nil, index * D.stagger)
end

local function SetBar(ratio)
    -- Déjà en route vers cette valeur : on ne relance pas l'animation à chaque rafraîchissement.
    if ratio == targetRatio then return end
    targetRatio = ratio
    local from = shownRatio
    T.Tween("bar", D.fill, function(progress)
        shownRatio = from + (ratio - from) * progress
        w.barFill:SetWidth(math.max(1, INNER * shownRatio))
    end)
end

-- La carte apparaît en fondu, avec un bref éclat ambre. Deux animations séparées : l'éclat
-- se termine toujours, même si un clic sur « Terminé » remplace le fondu de la carte.
local function FlashHero()
    T.Tween("hero", D.slide, function(progress) w.hero:SetAlpha(progress) end)
    T.Tween("heroFlash", D.flash, function(progress) w.heroFlash:SetAlpha(0.22 * (1 - progress)) end)
end

-- Fait disparaître un élément, puis exécute l'action (utilisé pour « Terminé »).
local function FadeOutThen(frame, key, action)
    T.Tween(key, D.fade, function(progress)
        frame:SetAlpha(1 - progress)
    end, function()
        frame:SetAlpha(1)
        action()
    end)
end

-- Lignes des listes ---------------------------------------------------------

local function NewRow(parent, index, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LIST_WIDTH, height)
    row.offsetY = -(index - 1) * height
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, row.offsetY)
    row:EnableMouse(true)
    row.hover = T.Fill(row, "BACKGROUND", C.hover)
    row.hover:SetAllPoints(row)
    row.hover:SetAlpha(0)
    row:SetScript("OnLeave", function(self)
        T.HoverFade(self.hover, self.hover, 0)
        GameTooltip:Hide()
    end)
    -- Une ligne cachée pendant qu'on la survole ne doit pas rester allumée.
    row:SetScript("OnHide", function(self)
        T.Cancel(self.hover)
        self.hover:SetAlpha(0)
    end)
    return row
end

local ShowStepTooltip -- définie plus bas, une fois les libellés de quantité disponibles

local function StepRow(index)
    local row = stepRows[index]
    if row then return row end
    row = NewRow(w.stepsScroll.child, index, STEP_HEIGHT)

    -- Frise : un trait vertical et un point de couleur par étape.
    local line = T.Fill(row, "BORDER", C.border)
    line:SetWidth(1)
    line:SetPoint("TOP", row, "TOPLEFT", 7, 0)
    line:SetPoint("BOTTOM", row, "BOTTOMLEFT", 7, 0)
    row.dot = T.Fill(row, "ARTWORK", C.accent)
    row.dot:SetSize(7, 7)
    row.dot:SetPoint("CENTER", row, "LEFT", 7, 0)

    row.icon = T.Icon(row, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 22, 0)
    -- Deux lignes : le nom en entier, puis la plage de niveaux (et « à apprendre ») en petit.
    row.name = T.Text(row, S.body, C.text)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 50, -6)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -100, -6)
    row.range = T.Text(row, S.tiny, C.muted)
    row.range:SetPoint("TOPLEFT", row, "TOPLEFT", 50, -21)
    row.range:SetPoint("TOPRIGHT", row, "TOPRIGHT", -100, -21)
    row.quantity = T.Text(row, S.title, C.accent, "RIGHT")
    row.quantity:SetPoint("RIGHT", row, "RIGHT", -32, 0)
    row.quantity:SetWidth(64)

    row.check = CreateFrame("Button", nil, row)
    row.check:SetSize(16, 16)
    row.check:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    T.Border(row.check, C.faint)
    row.check.mark = row.check:CreateTexture(nil, "ARTWORK")
    row.check.mark:SetTexture(CHECK_TEXTURE)
    row.check.mark:SetAllPoints(row.check)
    row.check.mark:SetAlpha(0)
    row.check:SetScript("OnEnter", function(self)
        T.HoverFade(self.mark, self.mark, 1)
        ShowTextTooltip(self, L.DONE, L.DONE_TIP)
    end)
    row.check:SetScript("OnLeave", function(self)
        T.HoverFade(self.mark, self.mark, 0)
        GameTooltip:Hide()
    end)
    row.check:SetScript("OnClick", function()
        local recipeID = row.recipeID
        -- Clé d'animation propre au bouton : l'apparition en cascade de la ligne ne peut pas
        -- annuler ce clic.
        FadeOutThen(row, row.check, function() MarkDone(recipeID) end)
    end)

    row:SetScript("OnEnter", function(self)
        T.HoverFade(self.hover, self.hover, 1)
        if self.step then ShowStepTooltip(self, self.step) end
    end)
    stepRows[index] = row
    return row
end

-- Étoile « favori » : pleine et dorée si le composant est favori, grise et pâle sinon.
local function PaintStar(star)
    local favorite = ns.Favorites.Is(star.itemID)
    star.texture:SetDesaturated(not favorite)
    star.texture:SetAlpha(favorite and 1 or STAR_OFF_ALPHA)
end

local function ShowStarTooltip(star)
    local favorite = ns.Favorites.Is(star.itemID)
    -- Favori absent des sacs : on prévient, sinon l'absence d'étoile dans les sacs ressemble à une panne.
    local body = favorite and ns.BagCount(star.itemID) == 0 and L.FAV_NONE_IN_BAGS or L.FAV_TIP
    ShowTextTooltip(star, favorite and L.FAV_REMOVE or L.FAV_ADD, body)
end

-- « 25 / 244 », ou « 25 + 15 banque / 244 » quand une partie est restée en banque.
local function OwnedLabel(itemID, owned, needed)
    local banked = owned - math.min(owned, ns.BagCount(itemID))
    if banked > 0 then return L.OWNED_BANK:format(owned - banked, banked, needed) end
    return L.OWNED:format(owned, needed)
end

-- Quantité nécessaire pour une étape : « 14 », « ~14 » si le nombre de fabrications est une
-- moyenne, ou « x2 par fabrication » quand ce nombre est inconnu.
local function StepNeedLabel(step, material)
    if not material.total then return L.PER_CRAFT:format(material.perCraft) end
    return (step.exact and "" or "~") .. material.total
end

-- Infobulle d'une étape : celle de la recette, suivie de ses matériaux pour toute l'étape.
ShowStepTooltip = function(owner, step)
    ShowGameTooltip(owner, "SetSpellByID", step.recipe.id)
    local materials = ns.Planner.StepMaterials(step)
    if #materials == 0 then return end
    if not GameTooltip:IsShown() then
        GameTooltip:SetOwner(owner, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", root, "TOPRIGHT", TOOLTIP_X, 0)
        GameTooltip:SetText(step.recipe.name or "")
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.STEP_MATERIALS, C.accent[1], C.accent[2], C.accent[3])
    for _, material in ipairs(materials) do
        local owned = ns.OwnedCount(material.itemID)
        local color = material.total and owned >= material.total and C.success or C.text
        GameTooltip:AddDoubleLine(ns.ItemName(material.itemID),
            OwnedLabel(material.itemID, owned, StepNeedLabel(step, material)),
            1, 1, 1, color[1], color[2], color[3])
    end
    GameTooltip:Show()
end

local function MaterialStar(row)
    local star = CreateFrame("Button", nil, row)
    star.favoriteStar = true
    star:SetSize(STAR_SIZE, STAR_SIZE)
    star:SetPoint("LEFT", row, "LEFT", 0, 1)
    star.texture = star:CreateTexture(nil, "ARTWORK")
    star.texture:SetAllPoints(star)
    star.texture:SetTexture(ns.Favorites.ICON)
    star:SetScript("OnClick", function(self)
        ns.Favorites.Toggle(self.itemID)
        PaintStar(self)
        ShowStarTooltip(self)
    end)
    -- Passer sur l'étoile fait quitter la ligne aux yeux du jeu : on garde la ligne allumée.
    star:SetScript("OnEnter", function(self)
        T.HoverFade(row.hover, row.hover, 1)
        ShowStarTooltip(self)
    end)
    star:SetScript("OnLeave", function()
        T.HoverFade(row.hover, row.hover, 0)
        GameTooltip:Hide()
    end)
    return star
end

local function MaterialRow(index)
    local row = materialRows[index]
    if row then return row end
    row = NewRow(w.materialsScroll.child, index, MATERIAL_HEIGHT)

    row.star = MaterialStar(row)
    row.icon = T.Icon(row, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", MATERIAL_ICON_X, 1)
    row.name = T.Text(row, S.body, C.text)
    row.name:SetPoint("LEFT", row, "LEFT", MATERIAL_TEXT_X, 1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(MATERIAL_COUNT_WIDTH + 6), 1)
    row.count = T.Text(row, S.small, C.muted, "RIGHT")
    row.count:SetPoint("RIGHT", row, "RIGHT", 0, 1)
    row.count:SetWidth(MATERIAL_COUNT_WIDTH)

    -- Mini-barre « possédé / nécessaire » sous la ligne.
    local track = T.Fill(row, "BORDER", C.track)
    track:SetHeight(2)
    track:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", MATERIAL_TEXT_X, 2)
    track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
    row.fill = T.Fill(row, "ARTWORK", C.success)
    row.fill:SetHeight(2)
    row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", MATERIAL_TEXT_X, 2)

    row:SetScript("OnEnter", function(self)
        T.HoverFade(self.hover, self.hover, 1)
        ShowGameTooltip(self, "SetItemByID", self.itemID)
    end)
    materialRows[index] = row
    return row
end

-- Ligne de matériau dans la carte « Prochaine recette » : étoile, icône, nom, possédé / nécessaire.
local function HeroMaterialRow(index)
    local row = heroRows[index]
    if row then return row end
    row = NewRow(w.heroMaterials, index, HERO_MATERIAL_HEIGHT)
    row.heroMaterial = true
    row:SetWidth(HERO_INNER)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", w.heroMaterials, "TOPLEFT", 0, -LABEL_HEIGHT - (index - 1) * HERO_MATERIAL_HEIGHT)

    row.star = MaterialStar(row)
    row.icon = T.Icon(row, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", MATERIAL_ICON_X, 0)
    row.name = T.Text(row, S.small, C.text)
    row.name:SetPoint("LEFT", row, "LEFT", MATERIAL_TEXT_X, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(MATERIAL_COUNT_WIDTH + 6), 0)
    row.count = T.Text(row, S.small, C.muted, "RIGHT")
    row.count:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.count:SetWidth(MATERIAL_COUNT_WIDTH)

    row:SetScript("OnEnter", function(self)
        T.HoverFade(self.hover, self.hover, 1)
        ShowGameTooltip(self, "SetItemByID", self.itemID)
    end)
    heroRows[index] = row
    return row
end

-- Affichage ---------------------------------------------------------------

-- Matériaux de la prochaine recette, pour toute l'étape. Sans étape ou sans composants lus, la
-- zone est cachée.
local function RenderHeroMaterials(step)
    local materials = step and ns.Planner.StepMaterials(step) or {}
    for index, material in ipairs(materials) do
        local row = HeroMaterialRow(index)
        local owned = ns.OwnedCount(material.itemID)
        local enough = material.total ~= nil and owned >= material.total
        local color = enough and C.success or C.muted
        row.itemID = material.itemID
        row.star.itemID = material.itemID
        PaintStar(row.star)
        row.icon.texture:SetTexture(ns.ItemIcon(material.itemID) or UNKNOWN_ICON)
        row.name:SetText(ns.ItemName(material.itemID))
        row.count:SetText(OwnedLabel(material.itemID, owned, StepNeedLabel(step, material)))
        row.count:SetTextColor(color[1], color[2], color[3], 1)
        row:Show()
    end
    for index = #materials + 1, #heroRows do
        heroRows[index]:Hide()
    end
    w.heroMaterials:SetShown(#materials > 0)
    w.heroMaterials:SetHeight(LABEL_HEIGHT + #materials * HERO_MATERIAL_HEIGHT)
end

local function RenderSteps(plan, animate)
    local shown = 0
    for index = 2, #plan.steps do
        shown = shown + 1
        local step = plan.steps[index]
        local row = StepRow(shown)
        local color = StepColor(step)
        row.recipeID = step.recipe.id
        row.step = step
        row.dot:SetColorTexture(color[1], color[2], color[3], 1)
        row.icon.texture:SetTexture(step.recipe.icon or UNKNOWN_ICON)
        row.name:SetText(step.recipe.name)
        row.quantity:SetText(QuantityLabel(step))
        row.range:SetText(L.LEVEL_RANGE:format(step.from, step.to or step.from) .. (step.needsLearning and L.TAG_LEARN or ""))
        row:Show()
        if animate then Cascade(row, row, shown) end
    end
    for index = shown + 1, #stepRows do
        stepRows[index]:Hide()
    end
    w.steps:SetShown(shown > 0)
    w.stepsScroll:SetContent(math.min(shown, MAX_VISIBLE_STEPS) * STEP_HEIGHT, shown * STEP_HEIGHT)
    return shown
end

local function RenderMaterials(plan, animate, offset)
    local shown = 0
    for index, material in ipairs(plan.materials) do
        shown = index
        local row = MaterialRow(index)
        local owned = ns.OwnedCount(material.itemID)
        local enough = owned >= material.qty
        local color = enough and C.success or C.muted
        row.itemID = material.itemID
        row.star.itemID = material.itemID
        PaintStar(row.star)
        row.icon.texture:SetTexture(ns.ItemIcon(material.itemID) or UNKNOWN_ICON)
        row.name:SetText(ns.ItemName(material.itemID))
        row.count:SetText(OwnedLabel(material.itemID, owned, material.qty))
        row.count:SetTextColor(color[1], color[2], color[3], 1)
        local ratio = material.qty > 0 and math.min(1, owned / material.qty) or 1
        row.fill:SetShown(ratio > 0)
        row.fill:SetWidth(math.max(1, (LIST_WIDTH - MATERIAL_TEXT_X) * ratio))
        row:Show()
        if animate then Cascade(row, row, offset + index) end
    end
    for index = shown + 1, #materialRows do
        materialRows[index]:Hide()
    end
    w.materials:SetShown(shown > 0)
    w.materialsShown = shown -- Layout() en a besoin pour le mode rectangle
    w.materialsScroll:SetContent(math.min(shown, MAX_VISIBLE_MATERIALS) * MATERIAL_HEIGHT, shown * MATERIAL_HEIGHT)
end

-- Onglets de métier ---------------------------------------------------------

local function ShowTabTooltip(tab)
    local info = tab.info
    if not info then return end
    local body = L.TAB_UNREAD
    if info.read then
        local hasLevels = type(info.skill) == "number" and type(info.max) == "number"
        body = hasLevels and L.TAB_LEVEL:format(info.skill, info.max) or nil
    end
    ShowTextTooltip(tab, info.name or "?", body)
end

local function ProfessionTab(index)
    local tab = tabButtons[index]
    if tab then return tab end
    tab = CreateFrame("Button", nil, root)
    tab.professionTab = true
    tab:SetSize(TAB_SIZE, TAB_SIZE)
    tab:SetPoint("TOPLEFT", root, "TOPRIGHT", TAB_OFFSET, -(HEADER_HEIGHT + (index - 1) * (TAB_SIZE + TAB_GAP)))
    -- Même fond opaque que la fenêtre : l'onglet est posé sur le décor du jeu, pas sur la fenêtre.
    T.Fill(tab, "BACKGROUND", C.background):SetAllPoints(tab)
    T.Border(tab, C.border)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetPoint("TOPLEFT", tab, "TOPLEFT", 5, -4)
    tab.icon:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 4)
    tab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Liseré ambre : repère de l'onglet du métier affiché.
    tab.stripe = T.Fill(tab, "OVERLAY", C.accent)
    tab.stripe:SetWidth(3)
    tab.stripe:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
    tab.stripe:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)

    tab:SetScript("OnClick", function(self)
        -- Un métier jamais ouvert n'a pas de recettes à afficher : on rappelle quoi faire.
        if self.info and self.info.read and ns.SelectProfession(self.info.id) then
            ns.RefreshUI()
        end
        ShowTabTooltip(self)
    end)
    tab:SetScript("OnEnter", ShowTabTooltip)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tabButtons[index] = tab
    return tab
end

local function RenderTabs()
    local selected = ns.SelectedProfession()
    local list = ns.ProfessionTabs()
    for index, info in ipairs(list) do
        local tab = ProfessionTab(index)
        tab.info = info
        tab.active = info.read and selected ~= nil and info.id == selected.id
        tab.icon:SetTexture(info.icon or UNKNOWN_ICON)
        tab.icon:SetDesaturated(not info.read)
        tab.icon:SetAlpha(tab.active and 1 or (info.read and TAB_IDLE_ALPHA or TAB_UNREAD_ALPHA))
        tab.stripe:SetShown(tab.active)
        tab:Show()
    end
    for index = #list + 1, #tabButtons do
        tabButtons[index]:Hide()
    end
end

-- Bandeau « parcours provisoire » : affiché tant que le maître du métier n'a pas été lu, car le
-- parcours ignore alors les recettes qu'il enseigne.
local function RenderWarning(prof)
    local source = prof and ns.TrainerDataSource(prof)
    local show = prof ~= nil and source ~= "read"
    if show then
        -- Liste partagée par d'autres joueurs : utilisée, mais peut-être incomplète.
        local body = source == "shipped" and L.WARN_TRAINER_SHIPPED or L.WARN_TRAINER_BODY
        w.warning.body:SetText(body:format(prof.name or "?"))
    end
    w.warning:SetShown(show)
end

-- Coût estimé du parcours, à droite du titre des matériaux. Caché tant qu'aucun prix n'est connu.
local function RenderCost(cost)
    local money = cost and cost.total > 0 and ns.MoneyText(math.floor(cost.total + 0.5)) or nil
    local text = ""
    if money and cost.unpricedQty > 0 then
        text = L.COST_PARTIAL:format(money, cost.unpricedQty)
    elseif money then
        text = L.COST_TOTAL:format(money)
    end
    w.cost:SetText(text)
    w.costHover:SetShown(text ~= "")
end

-- Infobulle d'un objet à préparer : celle de l'objet, suivie de ce qu'il faut pour en fabriquer
-- la quantité demandée.
local function ShowPrepareTooltip(row)
    local entry = row.entry
    if not entry then return end
    ShowGameTooltip(row, "SetItemByID", entry.itemID)
    if not GameTooltip:IsShown() then
        GameTooltip:SetOwner(row, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", root, "TOPRIGHT", TOOLTIP_X, 0)
        GameTooltip:SetText(ns.ItemName(entry.itemID))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.PREPARE_MADE_WITH:format(entry.qty), C.accent[1], C.accent[2], C.accent[3])
    for _, reagent in ipairs(entry.reagents or {}) do
        local needed = reagent[2] * entry.crafts
        local owned = ns.OwnedCount(reagent[1])
        local color = owned >= needed and C.success or C.text
        GameTooltip:AddDoubleLine(ns.ItemName(reagent[1]), OwnedLabel(reagent[1], owned, needed),
            1, 1, 1, color[1], color[2], color[3])
    end
    if type(entry.yield) == "number" and entry.yield > 1 then
        GameTooltip:AddLine(L.PREPARE_YIELD:format(entry.yield), C.muted[1], C.muted[2], C.muted[3])
    end
    GameTooltip:Show()
end

local function PrepareRow(index)
    local row = prepareRows[index]
    if row then return row end
    row = NewRow(w.prepare, index, PREPARE_HEIGHT)
    row.prepareRow = true
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", w.prepare, "TOPLEFT", 0, -LABEL_HEIGHT - (index - 1) * PREPARE_HEIGHT)
    row.icon = T.Icon(row, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name = T.Text(row, S.body, C.text)
    row.name:SetPoint("LEFT", row, "LEFT", 24, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row:SetScript("OnEnter", function(self)
        T.HoverFade(self.hover, self.hover, 1)
        ShowPrepareTooltip(self)
    end)
    prepareRows[index] = row
    return row
end

-- Objets à fabriquer soi-même avant de s'en servir : leurs matériaux sont dans la liste du bas.
local function RenderPrepare(prepare)
    for index, entry in ipairs(prepare) do
        local row = PrepareRow(index)
        local name = ns.ItemName(entry.itemID)
        row.entry = entry
        row.itemID = entry.itemID
        row.icon.texture:SetTexture(ns.ItemIcon(entry.itemID) or UNKNOWN_ICON)
        row.name:SetText(entry.crafts ~= entry.qty and L.PREPARE_LINE_CRAFTS:format(entry.qty, name, entry.crafts)
            or L.PREPARE_LINE:format(entry.qty, name))
        row:Show()
    end
    for index = #prepare + 1, #prepareRows do
        prepareRows[index]:Hide()
    end
    w.prepare:SetShown(#prepare > 0)
    w.prepare:SetHeight(LABEL_HEIGHT + #prepare * PREPARE_HEIGHT)
end

local function RenderVisits(text)
    w.visitsText:SetText(text)
    w.visits:SetShown(text ~= "")
end

-- PNJ du métier ------------------------------------------------------------

local function NpcRow(index)
    local row = npcRows[index]
    if row then return row end
    row = NewRow(w.npcs, index, NPC_ROW_HEIGHT)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", w.npcs, "TOPLEFT", 0, -LABEL_HEIGHT - (index - 1) * NPC_ROW_HEIGHT)
    row.pin = T.Button(row, NPC_BUTTON_WIDTH, 20, function(self) ns.PinNpc(self.npc, self.zone) end)
    row.pin.npcPin = true
    row.pin:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.pin:SetLabel(L.NPC_MAP_BUTTON)
    row.pin.tooltip = function(self) ShowTextTooltip(self, L.NPC_MAP_BUTTON, L.NPC_MAP_TIP) end
    row.text = T.Text(row, S.body, C.text)
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.text:SetPoint("RIGHT", row.pin, "LEFT", -8, 0)
    row.text:SetWordWrap(false)
    npcRows[index] = row
    return row
end

-- Maîtres et marchands de fournitures du métier affiché, avec un bouton « Carte » chacun.
-- Le bouton « Mon maître sur la carte » de la section des visites vise le premier maître.
local function RenderNpcs(prof)
    local shown = prof and ns.NpcsToShow(prof) or {}
    local firstTrainer
    for index, entry in ipairs(shown) do
        local row = NpcRow(index)
        local format = entry.npc.kind == "trainer" and L.NPC_TRAINER or L.NPC_VENDOR
        row.text:SetText(format:format(entry.npc.name, entry.zone))
        row.pin.npc, row.pin.zone = entry.npc, entry.zone
        row:Show()
        if entry.npc.kind == "trainer" and not firstTrainer then firstTrainer = entry end
    end
    for index = #shown + 1, #npcRows do
        npcRows[index]:Hide()
    end
    w.npcsEmpty:SetShown(#shown == 0)
    local height = #shown > 0 and #shown * NPC_ROW_HEIGHT or (w.npcsEmpty:GetStringHeight() + 4)
    w.npcs:SetHeight(LABEL_HEIGHT + height)
    w.npcs:SetShown(prof ~= nil)
    w.visitPin.npc = firstTrainer and firstTrainer.npc or nil
    w.visitPin.zone = firstTrainer and firstTrainer.zone or nil
    w.visitPin:SetShown(firstTrainer ~= nil)
end

-- Petits repères sur la barre, aux niveaux où l'on change de recette.
local function RenderTicks(plan, target)
    local used = 0
    for _, step in ipairs(plan.steps) do
        if step.to and step.to < target then
            used = used + 1
            local tick = ticks[used]
            if not tick then
                tick = T.Fill(w.progress, "OVERLAY", C.background)
                tick:SetSize(2, 6)
                ticks[used] = tick
            end
            tick:ClearAllPoints()
            tick:SetPoint("LEFT", w.barTrack, "LEFT", INNER * step.to / target, 0)
            tick:Show()
        end
    end
    for index = used + 1, #ticks do
        ticks[index]:Hide()
    end
end

-- Remplit la carte « Prochaine recette ». message : texte seul quand il n'y a pas d'étape.
local function RenderHero(step, mode, message)
    local color = step and StepColor(step) or C.faint
    w.heroStripe:SetColorTexture(color[1], color[2], color[3], 1)
    w.heroIcon:SetShown(step ~= nil)
    w.doneButton:SetShown(step ~= nil)
    w.doneButton.recipeID = step and step.recipe.id or nil
    -- Sans recette, le message remonte à la place de l'icône au lieu de laisser un vide.
    w.heroTextTop = step and HERO_TEXT_TOP or 30
    w.heroReason:ClearAllPoints()
    w.heroReason:SetPoint("TOPLEFT", w.hero, "TOPLEFT", 14, -w.heroTextTop)
    RenderHeroMaterials(step)
    if not step then
        w.heroIcon.recipeID = nil
        w.heroName:SetText("")
        w.heroSub:SetText("")
        w.heroQuantity:SetText("")
        w.heroReason:SetText(message)
        return
    end
    w.heroIcon.recipeID = step.recipe.id
    w.heroIcon.texture:SetTexture(step.recipe.icon or UNKNOWN_ICON)
    w.heroName:SetText(step.recipe.name .. (step.needsLearning and L.TAG_LEARN or ""))
    w.heroSub:SetText(step.to and L.LEVEL_RANGE:format(step.from, step.to) or L.CRAFT_UNKNOWN)
    w.heroQuantity:SetText(QuantityLabel(step))
    w.heroReason:SetText(ReasonText(step, mode))
end

-- Empile les zones de haut en bas et ajuste la hauteur de la fenêtre à son contenu.
-- Deux affichages : « column » (une colonne, de haut en bas) et « wide » (un rectangle en deux
-- colonnes : à gauche ce qu'on fabrique, à droite ce qu'il faut pour le fabriquer).
-- Ce sont les mêmes blocs : seul leur placement change. Choix gardé dans ProfessionPathDB.layout.
local function IsWide()
    return ns.db.layout == "wide"
end

-- Mode rectangle : nombre de lignes de matériaux visibles sans faire défiler. La liste s'allonge
-- dans la place libre de la colonne de droite, sans la rendre plus haute que celle de gauche.
-- Jamais moins que le mode colonne, jamais plus que de matériaux.
function ns.WideMaterialRows(shown, leftHeight, rightHeight, footerHeight)
    local free = leftHeight - rightHeight - footerHeight - 2 * GAP
    local rows = math.floor((free - LABEL_HEIGHT) / MATERIAL_HEIGHT)
    return math.min(shown, math.max(MAX_VISIBLE_MATERIALS, rows))
end

local function Layout()
    local wide = IsWide()
    local top = HEADER_HEIGHT + GAP
    local heights = { left = top, right = top }
    -- column : colonne où va le bloc en mode rectangle ; en mode colonne, tout va à gauche.
    local function Place(frame, height, column)
        column = wide and column or "left"
        local x = column == "right" and (PAD + INNER + COLUMN_GAP) or PAD
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", root, "TOPLEFT", x, -heights[column])
        frame:SetHeight(height)
        heights[column] = heights[column] + height + GAP
    end

    Place(w.controls, 24)
    Place(w.progress, 46)
    if w.warning:IsShown() then
        Place(w.warning, WARNING_TEXT_TOP + w.warning.body:GetStringHeight() + WARNING_PAD)
    end

    local reasonHeight = (w.heroReason:GetText() or "") ~= "" and w.heroReason:GetStringHeight() or 0
    local heroContent = w.heroTextTop + reasonHeight
    if w.heroMaterials:IsShown() then
        w.heroMaterials:ClearAllPoints()
        w.heroMaterials:SetPoint("TOPLEFT", w.hero, "TOPLEFT", 14, -(heroContent + HERO_MATERIALS_GAP))
        heroContent = heroContent + HERO_MATERIALS_GAP + w.heroMaterials:GetHeight()
    end
    local heroHeight = heroContent + PAD
    if w.doneButton:IsShown() then
        w.doneButton:ClearAllPoints()
        w.doneButton:SetPoint("TOPRIGHT", w.hero, "TOPRIGHT", -14, -(heroContent + 10))
        heroHeight = heroHeight + 10 + 22
    end
    Place(w.hero, heroHeight)

    if w.visits:IsShown() then Place(w.visits, LABEL_HEIGHT + w.visitsText:GetStringHeight(), "left") end
    if w.npcs:IsShown() then Place(w.npcs, w.npcs:GetHeight(), "right") end
    if w.steps:IsShown() then Place(w.steps, LABEL_HEIGHT + w.stepsScroll:GetHeight(), "left") end
    if w.prepare:IsShown() then Place(w.prepare, w.prepare:GetHeight(), "right") end

    local notesHeight = (w.notes:GetText() or "") ~= "" and (w.notes:GetStringHeight() + 8) or 0
    if w.materials:IsShown() then
        -- Nombre de lignes visibles : fixe en colonne, selon la place libre en rectangle.
        local shown = w.materialsShown or 0
        local visible = math.min(shown, MAX_VISIBLE_MATERIALS)
        if wide then visible = ns.WideMaterialRows(shown, heights.left, heights.right, notesHeight + 22) end
        w.materialsScroll:SetContent(visible * MATERIAL_HEIGHT, shown * MATERIAL_HEIGHT)
        Place(w.materials, LABEL_HEIGHT + w.materialsScroll:GetHeight(), "right")
    end
    w.footerRow:ClearAllPoints()
    w.footerRow:SetPoint("TOPLEFT", w.footer, "TOPLEFT", 0, -notesHeight)
    Place(w.footer, notesHeight + 22, "right")

    root:SetWidth(wide and WIDE_WIDTH or WIDTH)
    root:SetHeight(math.max(heights.left, heights.right) - GAP + PAD)
    w.columnDivider:SetShown(wide)
end

-- Passe d'un affichage à l'autre (bouton du bas, ou /ppath affichage).
function ns.ToggleLayout()
    ns.db.layout = IsWide() and "column" or "wide"
    ns.RefreshUI()
end

local function RenderEmpty()
    w.profPill:SetLabel(L.PROFESSION_NONE)
    w.levelNumber:SetText("-")
    w.levelMax:SetText("")
    w.targetBox:SetText("")
    SetBar(0)
    RenderTicks({ steps = {} }, 1)
    RenderHero(nil, "simple", L.NO_PROFESSION)
    RenderWarning(nil)
    RenderVisits("")
    RenderNpcs(nil)
    RenderSteps({ steps = {} }, false)
    RenderPrepare({})
    RenderMaterials({ materials = {} }, false, 0)
    RenderCost(nil)
    w.notes:SetText("")
    w.resetButton:Hide()
end

function ns.RefreshUI()
    if not root or not root:IsShown() then return end
    local mode = CurrentMode()
    w.modePill:SetLabel(L.MODE:format(L["MODE_" .. mode]))
    w.animToggle:SetLabel(ns.db.reduceMotion and L.ANIM_OFF or L.ANIM_ON)
    w.layoutToggle:SetLabel(IsWide() and L.LAYOUT_WIDE or L.LAYOUT_COLUMN)
    RenderTabs()

    local prof = ns.SelectedProfession()
    if not prof then
        RenderEmpty()
        Layout()
        justOpened = false
        return
    end

    local target = ns.TargetFor(prof)
    local priceOf, sourceOf = ns.NewPricer()
    local plan = ns.Planner.Plan({
        skill = prof.skill,
        target = target,
        mode = mode,
        recipes = ns.RecipesForPlanner(prof),
        skipped = ns.SkippedFor(prof),
        priceOf = priceOf,
    })

    -- On ne rejoue les animations que si le parcours affiché a réellement changé.
    local first = plan.steps[1]
    local signature = table.concat({ tostring(prof.id), mode, target, first and first.recipe.id or 0, #plan.steps }, "|")
    local animate = justOpened or signature ~= lastSignature
    lastSignature = signature
    justOpened = false

    w.profPill:SetLabel(L.PROFESSION:format(prof.name or "?"))
    w.levelNumber:SetText(tostring(prof.skill))
    w.levelMax:SetText(L.LEVEL_MAX:format(prof.max))
    if not w.targetBox:HasFocus() then w.targetBox:SetText(tostring(target)) end
    SetBar(target > 0 and math.min(1, prof.skill / target) or 0)
    RenderTicks(plan, target)

    RenderHero(first, mode, L.NO_STEP)
    RenderWarning(prof)
    RenderVisits(VisitsText(plan, prof))
    RenderNpcs(prof)
    local stepCount = RenderSteps(plan, animate)
    -- Les objets que le joueur a intérêt à fabriquer lui-même sont remplacés par leurs matériaux.
    local detail = ns.Planner.ExpandMaterials(plan.materials, sourceOf)
    RenderPrepare(detail.prepare)
    RenderMaterials(detail, animate, stepCount)
    RenderCost(ns.Planner.PlanCost(detail.materials, priceOf))
    if animate then FlashHero() end

    w.notes:SetText(FooterText(plan, prof, mode))
    local skippedCount = CountSkipped(prof)
    w.resetButton:SetShown(skippedCount > 0)
    w.resetButton:SetLabel(L.RESET:format(skippedCount))
    Layout()
end

-- Ouverture et fermeture -----------------------------------------------------

-- Les fondus partent de l'opacité actuelle : rouvrir pendant une fermeture se fait sans à-coup.
local function Open()
    local from = root:IsShown() and root:GetAlpha() or 0
    closing = false
    root:SetAlpha(from)
    root:Show()
    T.Tween("root", D.fade, function(progress) root:SetAlpha(from + (1 - from) * progress) end)
end

local function Close()
    local from = root:GetAlpha()
    closing = true
    T.Tween("root", D.fade, function(progress)
        root:SetAlpha(from * (1 - progress))
    end, function()
        closing = false
        root:Hide()
        root:SetAlpha(1)
    end)
end

-- Construction de la fenêtre -----------------------------------------------

local function SectionLabel(parent, text)
    local label = T.Text(parent, S.small, C.muted)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    label:SetText(text)
    return label
end

local function NewSection()
    local section = CreateFrame("Frame", nil, root)
    section:SetWidth(INNER)
    return section
end

local function BuildHeader()
    local accentLine = T.Fill(root, "ARTWORK", C.accent)
    accentLine:SetHeight(2)
    accentLine:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    accentLine:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)

    local title = T.Text(root, S.title, C.accent)
    title:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -13)
    title:SetText(L.TITLE)

    local close = T.Button(root, 22, 22, Close)
    close:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8, -9)
    close:SetLabel("x")

    local separator = T.Fill(root, "ARTWORK", C.border)
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -HEADER_HEIGHT)
    separator:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -HEADER_HEIGHT)
end

local function BuildControls()
    w.controls = NewSection()
    w.profPill = T.Button(w.controls, 120, 24, function()
        ns.SelectNextProfession()
        ns.RefreshUI()
    end, { autoWidth = true })
    w.profPill:SetPoint("LEFT", w.controls, "LEFT", 0, 0)
    w.profPill.tooltip = function(self) ShowTextTooltip(self, L.TITLE, L.PROFESSION_TIP) end

    w.modePill = T.Button(w.controls, 160, 24, function()
        SelectNextMode()
        ns.RefreshUI()
    end, { autoWidth = true })
    w.modePill:SetPoint("LEFT", w.profPill, "RIGHT", 8, 0)
    w.modePill.tooltip = function(self)
        local mode = CurrentMode()
        local body = L["MODE_" .. mode .. "_DESC"] .. "\n\n" .. L.MODE_TIP
        if not ns.HasPrices() then body = body .. "\n\n" .. L.MODE_CHEAP_UNAVAILABLE end
        ShowTextTooltip(self, L["MODE_" .. mode], body)
    end
end

local function BuildProgress()
    w.progress = NewSection()
    w.levelNumber = T.Text(w.progress, S.number, C.text)
    w.levelNumber:SetPoint("TOPLEFT", w.progress, "TOPLEFT", 0, 0)
    w.levelMax = T.Text(w.progress, S.body, C.muted)
    w.levelMax:SetPoint("BOTTOMLEFT", w.levelNumber, "BOTTOMRIGHT", 5, 3)

    local box = CreateFrame("EditBox", nil, w.progress)
    box:SetSize(48, 22)
    box:SetPoint("TOPRIGHT", w.progress, "TOPRIGHT", 0, -3)
    box:SetFontObject(GameFontHighlight)
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(4)
    T.Fill(box, "BACKGROUND", C.card):SetAllPoints(box)
    T.Border(box, C.border)
    box:SetScript("OnEnterPressed", ApplyTargetFromBox)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ns.RefreshUI()
    end)
    w.targetBox = box
    local label = T.Text(w.progress, S.small, C.muted, "RIGHT")
    label:SetPoint("RIGHT", box, "LEFT", -8, 0)
    label:SetText(L.TARGET)

    w.barTrack = T.Fill(w.progress, "BACKGROUND", C.track)
    w.barTrack:SetHeight(6)
    w.barTrack:SetPoint("BOTTOMLEFT", w.progress, "BOTTOMLEFT", 0, 0)
    w.barTrack:SetPoint("BOTTOMRIGHT", w.progress, "BOTTOMRIGHT", 0, 0)
    w.barFill = T.Fill(w.progress, "ARTWORK", C.accent)
    w.barFill:SetHeight(6)
    w.barFill:SetPoint("BOTTOMLEFT", w.progress, "BOTTOMLEFT", 0, 0)
    w.barFill:SetWidth(1)
end

local function BuildWarning()
    w.warning = T.Card(root)
    w.warning.trainerWarning = true
    w.warning:SetWidth(INNER)
    w.warning:Hide()
    local stripe = T.Fill(w.warning, "ARTWORK", C.alert)
    stripe:SetWidth(3)
    stripe:SetPoint("TOPLEFT", w.warning, "TOPLEFT", 0, 0)
    stripe:SetPoint("BOTTOMLEFT", w.warning, "BOTTOMLEFT", 0, 0)
    local title = T.Text(w.warning, S.body, C.alert)
    title:SetPoint("TOPLEFT", w.warning, "TOPLEFT", 14, -WARNING_PAD)
    title:SetText(L.WARN_TRAINER_TITLE)
    w.warning.body = T.Text(w.warning, S.small, C.text)
    w.warning.body:SetPoint("TOPLEFT", w.warning, "TOPLEFT", 14, -WARNING_TEXT_TOP)
    w.warning.body:SetWidth(HERO_INNER)
    w.warning.body:SetWordWrap(true)
    w.warning.body:SetSpacing(2)
end

local function BuildHero()
    w.hero = T.Card(root)
    w.hero:SetWidth(INNER)
    w.heroStripe = T.Fill(w.hero, "ARTWORK", C.accent)
    w.heroStripe:SetWidth(3)
    w.heroStripe:SetPoint("TOPLEFT", w.hero, "TOPLEFT", 0, 0)
    w.heroStripe:SetPoint("BOTTOMLEFT", w.hero, "BOTTOMLEFT", 0, 0)
    w.heroFlash = T.Fill(w.hero, "BORDER", C.accent)
    w.heroFlash:SetAllPoints(w.hero)
    w.heroFlash:SetAlpha(0)

    local label = T.Text(w.hero, S.small, C.muted)
    label:SetPoint("TOPLEFT", w.hero, "TOPLEFT", 14, -10)
    label:SetText(L.NEXT_HEADER)

    w.heroIcon = T.Icon(w.hero, 36)
    w.heroIcon:SetPoint("TOPLEFT", w.hero, "TOPLEFT", 14, -28)
    w.heroIcon:EnableMouse(true)
    w.heroIcon:SetScript("OnEnter", function(self) ShowGameTooltip(self, "SetSpellByID", self.recipeID) end)
    w.heroIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    w.heroQuantity = T.Text(w.hero, S.number, C.accent, "RIGHT")
    w.heroQuantity:SetPoint("TOPRIGHT", w.hero, "TOPRIGHT", -14, -28)
    w.heroName = T.Text(w.hero, S.name, C.text)
    w.heroName:SetPoint("TOPLEFT", w.hero, "TOPLEFT", 60, -28)
    w.heroName:SetPoint("TOPRIGHT", w.hero, "TOPRIGHT", -110, -28)
    w.heroSub = T.Text(w.hero, S.small, C.muted)
    w.heroSub:SetPoint("TOPLEFT", w.hero, "TOPLEFT", 60, -48)

    w.heroReason = T.Text(w.hero, S.small, C.muted)
    w.heroReason:SetPoint("TOPLEFT", w.hero, "TOPLEFT", 14, -HERO_TEXT_TOP)
    w.heroReason:SetWidth(INNER - 28)
    w.heroReason:SetWordWrap(true)
    w.heroReason:SetSpacing(2)

    w.heroMaterials = CreateFrame("Frame", nil, w.hero)
    w.heroMaterials:SetSize(HERO_INNER, LABEL_HEIGHT)
    w.heroMaterials:Hide()
    local materialsLabel = T.Text(w.heroMaterials, S.small, C.muted)
    materialsLabel:SetPoint("TOPLEFT", w.heroMaterials, "TOPLEFT", 0, 0)
    materialsLabel:SetText(L.HERO_MATERIALS)

    w.doneButton = T.Button(w.hero, 96, 22, function(self)
        local recipeID = self.recipeID
        FadeOutThen(w.hero, "hero", function() MarkDone(recipeID) end)
    end, { accent = true })
    w.doneButton:SetLabel(L.DONE)
    w.doneButton.tooltip = function(self) ShowTextTooltip(self, L.DONE, L.DONE_TIP) end
end

local function BuildLists()
    w.visits = NewSection()
    SectionLabel(w.visits, L.VISITS_HEADER)
    w.visitsText = T.Text(w.visits, S.body, C.text)
    w.visitsText:SetPoint("TOPLEFT", w.visits, "TOPLEFT", 0, -LABEL_HEIGHT)
    w.visitsText:SetWidth(INNER)
    w.visitsText:SetWordWrap(true)
    w.visitsText:SetSpacing(3)
    w.visitPin = T.Button(w.visits, 150, 18, function(self) ns.PinNpc(self.npc, self.zone) end, { autoWidth = true })
    w.visitPin.npcPin = true
    w.visitPin:SetPoint("TOPRIGHT", w.visits, "TOPRIGHT", 0, 0)
    w.visitPin:SetLabel(L.VISIT_PIN)
    w.visitPin.tooltip = function(self) ShowTextTooltip(self, L.VISIT_PIN, L.NPC_MAP_TIP) end
    w.visitPin:Hide()

    w.npcs = NewSection()
    SectionLabel(w.npcs, L.NPC_HEADER)
    w.npcsEmpty = T.Text(w.npcs, S.small, C.muted)
    w.npcsEmpty:SetPoint("TOPLEFT", w.npcs, "TOPLEFT", 0, -LABEL_HEIGHT)
    w.npcsEmpty:SetWidth(INNER)
    w.npcsEmpty:SetWordWrap(true)
    w.npcsEmpty:SetText(L.NPC_NONE)
    w.npcs:Hide()

    w.steps = NewSection()
    SectionLabel(w.steps, L.STEPS_HEADER)
    w.stepsScroll = T.Scroll(w.steps, INNER)
    w.stepsScroll:SetPoint("TOPLEFT", w.steps, "TOPLEFT", 0, -LABEL_HEIGHT)

    w.prepare = NewSection()
    local prepareLabel = SectionLabel(w.prepare, L.PREPARE_HEADER)
    local prepareHover = CreateFrame("Frame", nil, w.prepare)
    prepareHover:SetAllPoints(prepareLabel)
    prepareHover:EnableMouse(true)
    prepareHover:SetScript("OnEnter", function(self) ShowTextTooltip(self, L.PREPARE_HEADER, L.PREPARE_TIP) end)
    prepareHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.prepare:Hide()

    w.materials = NewSection()
    local label = SectionLabel(w.materials, L.MATERIALS_HEADER)
    local hover = CreateFrame("Frame", nil, w.materials)
    hover:SetAllPoints(label)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(self) ShowTextTooltip(self, L.MATERIALS_HEADER, L.NOTE_SUBMATERIALS) end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.cost = T.Text(w.materials, S.small, C.muted, "RIGHT")
    w.cost:SetPoint("TOPRIGHT", w.materials, "TOPRIGHT", -8, 0)
    root.costLabel = w.cost
    w.costHover = CreateFrame("Frame", nil, w.materials)
    w.costHover:SetAllPoints(w.cost)
    w.costHover:EnableMouse(true)
    w.costHover:SetScript("OnEnter", function(self) ShowTextTooltip(self, L.COST_TOTAL:format(""), L.COST_TIP) end)
    w.costHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.costHover:Hide()
    w.materialsScroll = T.Scroll(w.materials, INNER)
    w.materialsScroll:SetPoint("TOPLEFT", w.materials, "TOPLEFT", 0, -LABEL_HEIGHT)
end

local function BuildFooter()
    w.footer = NewSection()
    w.notes = T.Text(w.footer, S.small, C.muted)
    w.notes:SetPoint("TOPLEFT", w.footer, "TOPLEFT", 0, 0)
    w.notes:SetWidth(INNER)
    w.notes:SetWordWrap(true)
    w.notes:SetSpacing(2)

    w.footerRow = CreateFrame("Frame", nil, w.footer)
    w.footerRow:SetSize(INNER, 22)
    w.animToggle = T.Button(w.footerRow, 120, 22, function()
        ns.db.reduceMotion = not ns.db.reduceMotion
        ns.RefreshUI()
    end, { autoWidth = true })
    w.animToggle:SetPoint("LEFT", w.footerRow, "LEFT", 0, 0)
    w.animToggle.tooltip = function(self) ShowTextTooltip(self, L.ANIM_ON, L.ANIM_TIP) end

    w.layoutToggle = T.Button(w.footerRow, 140, 22, function() ns.ToggleLayout() end, { autoWidth = true })
    w.layoutToggle.layoutToggle = true
    w.layoutToggle:SetPoint("LEFT", w.animToggle, "RIGHT", 8, 0)
    w.layoutToggle.tooltip = function(self)
        ShowTextTooltip(self, IsWide() and L.LAYOUT_WIDE or L.LAYOUT_COLUMN, L.LAYOUT_TIP)
    end

    w.resetButton = T.Button(w.footerRow, 150, 22, ResetDone, { autoWidth = true })
    w.resetButton:SetPoint("RIGHT", w.footerRow, "RIGHT", 0, 0)
    w.resetButton.tooltip = function(self) ShowTextTooltip(self, L.DONE, L.RESET_TIP) end
end

-- Taille de la fenêtre --------------------------------------------------------
-- La poignée du coin bas droit agrandit ou réduit toute la fenêtre d'un bloc (zoom), en gardant
-- son coin haut gauche à la même place. La taille est mémorisée : ProfessionPathDB.scale.

local MIN_SCALE, MAX_SCALE = 0.6, 1.3
local OPEN_OFFSET_Y = 300 -- à l'ouverture, le haut de la fenêtre est 300 pixels au-dessus du centre
local GRIP_SIZE = 14

local function ClampScale(scale)
    if type(scale) ~= "number" then return 1 end
    return math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
end

local function ApplyScale(scale)
    scale = ClampScale(scale)
    local old = root:GetScale() or 1
    local left, top = root:GetLeft(), root:GetTop()
    root:SetScale(scale)
    -- Les positions s'expriment à l'échelle de la fenêtre : on les convertit pour que le coin
    -- haut gauche ne bouge pas à l'écran.
    if left and top then
        root:ClearAllPoints()
        root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
    end
    ns.db.scale = scale
end

-- Position du curseur, dans les mêmes unités que la taille de la fenêtre à l'écran.
local function CursorPosition()
    local x, y = GetCursorPosition()
    local unit = UIParent:GetEffectiveScale() or 1
    return x / unit, y / unit
end

local function BuildResizeGrip()
    local grip = CreateFrame("Button", nil, root)
    grip.resizeGrip = true
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel((root:GetFrameLevel() or 1) + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("LeftButtonUp")

    -- Pendant le glisser : la nouvelle taille suit l'écart entre la souris et son point de départ,
    -- en moyenne sur la largeur et la hauteur (tirer vers le bas à droite agrandit).
    local function Follow(self)
        local x, y = CursorPosition()
        local start = self.start
        local widthRatio = (start.width + (x - start.x)) / start.width
        local heightRatio = (start.height + (start.y - y)) / start.height
        ApplyScale(start.scale * (widthRatio + heightRatio) / 2)
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local scale = root:GetScale() or 1
        local x, y = CursorPosition()
        local width, height = (root:GetWidth() or 0) * scale, (root:GetHeight() or 0) * scale
        if width <= 0 or height <= 0 then return end
        GameTooltip:Hide()
        self.start = { x = x, y = y, scale = scale, width = width, height = height }
        self:SetScript("OnUpdate", Follow)
    end)
    local function Stop(self)
        self:SetScript("OnUpdate", nil)
        self.start = nil
    end
    grip:SetScript("OnMouseUp", Stop)
    -- Fenêtre fermée (Échap) pendant un glisser : le bouton relâché ne serait jamais vu.
    grip:SetScript("OnHide", Stop)
    grip:SetScript("OnDoubleClick", function(self)
        -- Le second appui a relancé un glisser : on l'arrête, sinon il annulerait la remise à zéro.
        Stop(self)
        ApplyScale(1)
    end)
    grip:SetScript("OnEnter", function(self) ShowTextTooltip(self, L.RESIZE_TITLE, L.RESIZE_TIP) end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Build()
    root = CreateFrame("Frame", "ProfessionPathFrame", UIParent)
    root:SetSize(WIDTH, 400)
    -- Accrochée par le haut : quand la hauteur change, le haut de la fenêtre ne bouge pas.
    root:SetPoint("TOP", UIParent, "CENTER", 0, OPEN_OFFSET_Y)
    root:SetFrameStrata("MEDIUM")
    root:SetToplevel(true)
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    -- Les onglets dépassent à droite : ils doivent rester à l'écran avec la fenêtre. Une valeur
    -- positive à droite agrandit la zone gardée à l'écran (même convention que la bibliothèque
    -- de Details).
    root:SetClampRectInsets(0, TAB_OFFSET + TAB_SIZE, 0, 0)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", root.StartMoving)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Après un déplacement, on la raccroche par son coin haut gauche, pour la même raison.
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    root:Hide()
    -- Permet de fermer la fenêtre avec la touche Échap.
    tinsert(UISpecialFrames, "ProfessionPathFrame")

    T.Fill(root, "BACKGROUND", C.background):SetAllPoints(root)
    T.Border(root, C.border)

    BuildHeader()
    BuildControls()
    BuildProgress()
    BuildWarning()
    BuildHero()
    BuildLists()
    BuildFooter()
    BuildResizeGrip()
    -- Trait vertical entre les deux colonnes du mode rectangle.
    w.columnDivider = T.Fill(root, "BORDER", C.border)
    w.columnDivider:SetWidth(1)
    w.columnDivider:SetPoint("TOPLEFT", root, "TOPLEFT", PAD + INNER + COLUMN_GAP / 2, -(HEADER_HEIGHT + GAP))
    w.columnDivider:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", PAD + INNER + COLUMN_GAP / 2, PAD)
    w.columnDivider:Hide()
    root.sections = w -- pour les tests hors du jeu : vérifier où chaque bloc est placé
    -- La taille choisie la dernière fois. Le décalage de départ s'exprime à l'échelle de la fenêtre :
    -- on le convertit pour qu'elle s'ouvre au même endroit quelle que soit sa taille.
    local scale = ClampScale(ns.db.scale)
    root:SetScale(scale)
    root:ClearAllPoints()
    root:SetPoint("TOP", UIParent, "CENTER", 0, OPEN_OFFSET_Y / scale)

    root:SetScript("OnShow", function()
        justOpened = true
        T.Cancel("bar")
        targetRatio = nil
        shownRatio = 0
        w.barFill:SetWidth(1)
        ns.RefreshUI()
    end)
    root:SetScript("OnHide", function()
        closing = false
        GameTooltip:Hide()
    end)
end

function ns.ToggleUI()
    if not ns.db then return end
    if not root then Build() end
    if root:IsShown() and not closing then
        Close()
        return
    end
    -- Aucun métier lu : on tente une lecture, au cas où la fenêtre de métier serait déjà ouverte.
    if not ns.SelectedProfession() then ns.TryScan() end
    Open()
end
