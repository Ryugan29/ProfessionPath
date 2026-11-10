-- Étoile sur les composants favoris, dans les sacs.
-- L'add-on ne fait qu'AFFICHER une petite image par-dessus la case : il ne déplace, n'utilise et
-- ne modifie aucun objet.
--
-- Chaque add-on de sacs dessine ses cases à sa façon : il faut donc un « branchement » par add-on.
-- Vérifié sur le code installé : Bagnon 12.1.8 (socle BagBrother). Les sacs du jeu et les autres add-ons sont branchés
-- d'après leur fonctionnement connu, sans avoir pu être essayés ici. Chaque branchement est
-- protégé : s'il ne correspond pas à la version installée, il est ignoré sans gêner le joueur,
-- et /mpp debug dit lesquels ont réussi.

local _, ns = ...

local Bags = {}
ns.Bags = Bags

local Favorites = ns.Favorites
local STAR_SIZE = 14
local RETRY_DELAY = 2 -- secondes : certains add-ons de sacs finissent de se préparer après la connexion

-- [case de sac] = { itemID = objet affiché, star = image de l'étoile (créée au premier besoin) }
-- Clés « faibles » : on ne retient jamais une case que son add-on aurait abandonnée.
local marks = setmetatable({}, { __mode = "k" })
local hooked, lastError = {}, nil
-- Fonctions déjà greffées, pour ne jamais greffer deux fois la même : { [propriétaire] = { [méthode] = true } }
local grafted = setmetatable({}, { __mode = "k" })

local function Guard(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    lastError = tostring(result)
    return nil
end

local function CreateStar(button)
    local star = button:CreateTexture(nil, "OVERLAY", nil, 7)
    star:SetTexture(Favorites.ICON)
    star:SetSize(STAR_SIZE, STAR_SIZE)
    star:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
    return star
end

local function Apply(button, mark)
    local favorite = Favorites.Is(mark.itemID)
    if favorite and not mark.star then mark.star = CreateStar(button) end
    if mark.star then mark.star:SetShown(favorite) end
end

-- Affiche ou cache l'étoile d'une case selon l'objet qu'elle contient (nil = case vide).
function Bags.Mark(button, itemID)
    if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then return end
    local mark = marks[button]
    if not mark then
        mark = {}
        marks[button] = mark
    end
    mark.itemID = itemID
    Guard(Apply, button, mark)
end

function Bags.IsStarred(button)
    local mark = marks[button]
    return mark ~= nil and mark.star ~= nil and mark.star:IsShown() == true
end

-- Noms des sacs branchés avec succès, pour /mpp debug.
function Bags.Hooked()
    local names = {}
    for name in pairs(hooked) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function Bags.LastError()
    return lastError
end

local function SlotItemID(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    if GetContainerItemID then return GetContainerItemID(bag, slot) end
    return nil
end

local function LinkItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Greffe « fn » après une fonction existante, sans la remplacer (hooksecurefunc est la méthode
-- prévue par le jeu). Les pannes de « fn » sont retenues au lieu de s'afficher chez le joueur.
local function HookAfter(owner, method, fn)
    if type(owner) ~= "table" or type(owner[method]) ~= "function" then return false end
    grafted[owner] = grafted[owner] or {}
    if not grafted[owner][method] then
        grafted[owner][method] = true
        hooksecurefunc(owner, method, function(...) Guard(fn, ...) end)
    end
    return true
end

local function AceAddon(name)
    if not LibStub then return nil end
    local ace = LibStub("AceAddon-3.0", true)
    return ace and ace:GetAddon(name, true) or nil
end

-- Branchements --------------------------------------------------------------------
-- Chacun renvoie deux réponses : « branché » (au moins une greffe posée) et « incomplet » (il
-- reste peut-être des fenêtres à brancher : on retentera, sans jamais greffer deux fois).

local integrations = {}

-- Sacs du jeu. Deux générations d'interface possibles selon le client : on prend celle qui existe.
integrations[#integrations + 1] = { name = "Blizzard", install = function()
    if type(ContainerFrame_Update) == "function" then
        hooksecurefunc("ContainerFrame_Update", function(container)
            Guard(function()
                local bag, name = container:GetID(), container:GetName()
                for index = 1, container.size or 0 do
                    local button = _G[name .. "Item" .. index]
                    if button then Bags.Mark(button, SlotItemID(bag, button:GetID())) end
                end
            end)
        end)
        return true
    end
    local function Update(frame)
        for _, button in frame:EnumerateValidItems() do
            Bags.Mark(button, SlotItemID(button:GetBagID(), button:GetID()))
        end
    end
    local found = HookAfter(ContainerFrameCombinedBags, "UpdateItems", Update)
    local container = ContainerFrameContainer or UIParent
    for _, frame in ipairs(container and container.ContainerFrames or {}) do
        found = HookAfter(frame, "UpdateItems", Update) or found
    end
    -- Le jeu peut créer des fenêtres de sac plus tard : on repasse à chaque nouvelle tentative.
    return found, true
end }

-- Bagnon et ses cousins : chaque case garde dans « info » la description de l'objet affiché.
-- Les versions récentes de Bagnon et Bagnonium se déclarent sous le nom de leur socle commun,
-- « BagBrother » (vérifié sur Bagnon 12.1.8) ; les anciennes sous leur propre nom.
for _, name in ipairs({ "BagBrother", "Bagnon", "Bagnonium", "Combuctor" }) do
    integrations[#integrations + 1] = { name = name, install = function()
        local addon = _G[name]
        return type(addon) == "table" and HookAfter(addon.Item, "Update", function(button)
            local info = button.info
            Bags.Mark(button, type(info) == "table" and (info.itemID or LinkItemID(info.hyperlink)) or nil)
        end)
    end }
end

-- AdiBags annonce chaque case qu'il redessine.
integrations[#integrations + 1] = { name = "AdiBags", install = function()
    local addon = AceAddon("AdiBags")
    if not (addon and type(addon.RegisterMessage) == "function") then return false end
    addon.RegisterMessage(Bags, "AdiBags_UpdateButton", function(_, button)
        Guard(function()
            Bags.Mark(button, button.itemId or SlotItemID(button.bag, button.slot))
        end)
    end)
    return true
end }

-- Baganator prévoit des « coins » que les autres add-ons peuvent remplir : il gère lui-même
-- l'emplacement de l'étoile, réglable dans ses options.
integrations[#integrations + 1] = { name = "Baganator", install = function()
    local api = type(Baganator) == "table" and Baganator.API
    if not (api and type(api.RegisterCornerWidget) == "function") then return false end
    api.RegisterCornerWidget(ns.L.FAV_WIDGET, "professionpath-favorite",
        function(_, details)
            if type(details) ~= "table" then return false end
            return Favorites.Is(details.itemID or LinkItemID(details.itemLink))
        end,
        function(itemButton)
            local star = itemButton:CreateTexture(nil, "OVERLAY")
            star:SetTexture(Favorites.ICON)
            star:SetSize(STAR_SIZE, STAR_SIZE)
            return star
        end,
        { default_position = "bottom_left", priority = 1 })
    return true
end }

integrations[#integrations + 1] = { name = "LiteBag", install = function()
    if type(LiteBag_RegisterHook) ~= "function" then return false end
    LiteBag_RegisterHook("LiteBagItemButton_Update", function(button)
        Guard(function() Bags.Mark(button, SlotItemID(button:GetParent():GetID(), button:GetID())) end)
    end)
    return true
end }

integrations[#integrations + 1] = { name = "Baggins", install = function()
    return type(Baggins) == "table" and HookAfter(Baggins, "UpdateItemButton", function(_, _, button, bag, slot)
        Bags.Mark(button, SlotItemID(bag, slot))
    end)
end }

integrations[#integrations + 1] = { name = "Inventorian", install = function()
    local addon = AceAddon("Inventorian")
    if not (addon and addon.bag and addon.bag.itemContainer) then return false end
    local function Update(container, bag, slot)
        local index = (bag < 0 and bag * 100 - slot) or (bag * 100 + slot)
        Bags.Mark(container.items and container.items[index], SlotItemID(bag, slot))
    end
    local found = HookAfter(addon.bag.itemContainer, "UpdateSlot", Update)
    local bankFound = addon.bank ~= nil and HookAfter(addon.bank.itemContainer, "UpdateSlot", Update)
    return found, not bankFound
end }

integrations[#integrations + 1] = { name = "ElvUI", install = function()
    if type(ElvUI) ~= "table" or type(ElvUI[1]) ~= "table" then return false end
    local module = ElvUI[1]:GetModule("Bags", true)
    return type(module) == "table" and HookAfter(module, "UpdateSlot", function(_, frame, bag, slot)
        local row = frame and frame.Bags and frame.Bags[bag]
        Bags.Mark(row and row[slot], SlotItemID(bag, slot))
    end)
end }

integrations[#integrations + 1] = { name = "ArkInventory", install = function()
    local api = type(ArkInventory) == "table" and ArkInventory.API
    if not (api and type(api.ItemFrameItemTableGet) == "function") then return false end
    return HookAfter(api, "ItemFrameUpdated", function(frame)
        local item = api.ItemFrameItemTableGet(frame)
        Bags.Mark(frame, type(item) == "table" and LinkItemID(item.h) or nil)
    end)
end }

-- Fenêtre du marchand (celle du jeu) : étoile sur les favoris qu'il vend. Même méthode que
-- l'add-on WhatsTraining, qui fonctionne sur ce client. L'onglet « Rachat » n'est pas marqué.
local DEFAULT_MERCHANT_SLOTS = 10

local function MarkMerchant(selling)
    local perPage = type(MERCHANT_ITEMS_PER_PAGE) == "number" and MERCHANT_ITEMS_PER_PAGE or DEFAULT_MERCHANT_SLOTS
    local page = type(MerchantFrame) == "table" and type(MerchantFrame.page) == "number" and MerchantFrame.page or 1
    for slot = 1, perPage do
        local button = _G["MerchantItem" .. slot .. "ItemButton"]
        if button then
            local itemID = selling and GetMerchantItemID and GetMerchantItemID((page - 1) * perPage + slot) or nil
            Bags.Mark(button, itemID)
        end
    end
end

integrations[#integrations + 1] = { name = "Marchand", install = function()
    local found = HookAfter(_G, "MerchantFrame_UpdateMerchantInfo", function() MarkMerchant(true) end)
    HookAfter(_G, "MerchantFrame_UpdateBuybackInfo", function() MarkMerchant(false) end)
    return found
end }

local complete = {}

-- Une tentative ratée est normale (add-on absent ou pas encore prêt) : ce n'est pas une panne à
-- signaler dans /mpp debug, d'où le pcall simple plutôt que Guard.
local function InstallAll()
    for _, integration in ipairs(integrations) do
        if not complete[integration.name] then
            local ok, found, incomplete = pcall(integration.install)
            if ok and found == true then
                hooked[integration.name] = true
                complete[integration.name] = not incomplete
            end
        end
    end
end

-- Un favori ajouté ou retiré : mettre à jour tout de suite les cases déjà affichées.
Favorites.OnChange(function()
    for button, mark in pairs(marks) do Guard(Apply, button, mark) end
    local api = type(Baganator) == "table" and Baganator.API
    if hooked.Baganator and api and type(api.RequestItemButtonsRefresh) == "function" then
        Guard(api.RequestItemButtonsRefresh)
    end
end)

-- Les add-ons de sacs peuvent se charger avant ou après celui-ci : on retente à chaque chargement.
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
    InstallAll()
    if event == "PLAYER_LOGIN" and C_Timer and C_Timer.After then C_Timer.After(RETRY_DELAY, InstallAll) end
end)
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_LOGIN")
pcall(eventFrame.RegisterEvent, eventFrame, "ADDON_LOADED")
