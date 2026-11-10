-- Profession Path — design system « Forge moderne ».
-- Tout ce qui définit l'apparence est ici : couleurs, tailles de texte, composants de base
-- (cadre, bouton, zone défilante) et moteur d'animation. UI.lua ne fait qu'assembler.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- Couleurs { rouge, vert, bleu, opacité } ----------------------------------

Theme.colors = {
    background = { 0.055, 0.060, 0.075, 0.97 },
    card = { 1, 1, 1, 0.045 },
    hover = { 1, 1, 1, 0.08 },
    border = { 1, 1, 1, 0.09 },
    track = { 1, 1, 1, 0.08 },
    accent = { 0.96, 0.68, 0.22, 1 },
    text = { 0.92, 0.91, 0.88, 1 },
    muted = { 0.62, 0.64, 0.68, 1 },
    faint = { 0.40, 0.42, 0.46, 1 },
    success = { 0.37, 0.83, 0.55, 1 },
    alert = { 1.00, 0.42, 0.37, 1 },
    -- Couleurs de difficulté, proches de celles du jeu pour qu'on les reconnaisse.
    orange = { 1.00, 0.50, 0.25, 1 },
    yellow = { 1.00, 0.86, 0.25, 1 },
    green = { 0.25, 0.75, 0.25, 1 },
}

Theme.sizes = { tiny = 10, small = 11, body = 12, title = 14, name = 16, number = 26 }

-- Durées des animations, en secondes : courtes pour rester agréables à la centième ouverture.
Theme.durations = { hover = 0.12, fade = 0.18, slide = 0.24, fill = 0.45, flash = 0.5, stagger = 0.03 }

local FONT_PATH = GameFontNormal:GetFont()

-- Briques de base ----------------------------------------------------------

function Theme.Fill(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return texture
end

--- Trait fin d'un pixel tout autour d'un cadre.
function Theme.Border(frame, color)
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = Theme.Fill(frame, "BORDER", color)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
            edge:SetWidth(1)
        end
        edges[#edges + 1] = edge
    end
    return edges
end

function Theme.Text(parent, size, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT_PATH, size, "")
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetJustifyH(justify or "LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(false)
    return text
end

--- Carte : zone légèrement plus claire que le fond, avec un trait fin.
function Theme.Card(parent)
    local card = CreateFrame("Frame", nil, parent)
    Theme.Fill(card, "BACKGROUND", Theme.colors.card):SetAllPoints(card)
    Theme.Border(card, Theme.colors.border)
    return card
end

--- Icône du jeu recadrée (sans son bord d'origine) avec un trait fin autour.
function Theme.Icon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.texture = holder:CreateTexture(nil, "ARTWORK")
    holder.texture:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
    holder.texture:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
    holder.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Theme.Border(holder, Theme.colors.border)
    return holder
end

-- Animations ---------------------------------------------------------------

local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()

local function EaseOut(progress)
    local rest = 1 - progress
    return 1 - rest * rest * rest
end

local function ReduceMotion()
    return ns.db ~= nil and ns.db.reduceMotion == true
end

driver:SetScript("OnUpdate", function(self, elapsed)
    local finished = {}
    for key, tween in pairs(tweens) do
        tween.elapsed = tween.elapsed + elapsed
        if tween.elapsed >= tween.duration then
            finished[#finished + 1] = { key = key, tween = tween }
        elseif tween.elapsed > 0 then
            tween.apply(EaseOut(tween.elapsed / tween.duration))
        end
    end
    -- Les fins sont traitées après la boucle : une fin peut lancer une nouvelle animation.
    -- On ne termine une animation que si elle n'a pas été remplacée entre-temps par une autre.
    for _, entry in ipairs(finished) do
        local tween = entry.tween
        if tweens[entry.key] == tween then
            tweens[entry.key] = nil
            tween.apply(1)
            if tween.onDone then tween.onDone() end
        end
    end
    if next(tweens) == nil then self:Hide() end
end)

--- Anime une valeur de 0 à 1. « key » identifie l'animation : en relancer une avec la même
-- clé remplace la précédente. apply(progression) dessine l'état ; onDone est appelé à la fin.
function Theme.Tween(key, duration, apply, onDone, delay)
    if ReduceMotion() or duration <= 0 then
        tweens[key] = nil
        apply(1)
        if onDone then onDone() end
        return
    end
    apply(0)
    tweens[key] = { elapsed = -(delay or 0), duration = duration, apply = apply, onDone = onDone }
    driver:Show()
end

--- Arrête une animation en cours sans la terminer.
function Theme.Cancel(key)
    tweens[key] = nil
end

--- Fait varier l'opacité d'un élément au survol.
function Theme.HoverFade(key, texture, target)
    local start = texture:GetAlpha()
    Theme.Tween(key, Theme.durations.hover, function(progress)
        texture:SetAlpha(start + (target - start) * progress)
    end)
end

-- Composants ---------------------------------------------------------------

--- Bouton plat. options : { accent = true } pour l'action principale, { autoWidth = true }
-- pour une « pastille » qui s'adapte à son texte.
function Theme.Button(parent, width, height, onClick, options)
    options = options or {}
    local colors = Theme.colors
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    Theme.Fill(button, "BACKGROUND", colors.card):SetAllPoints(button)
    button.glow = Theme.Fill(button, "BORDER", options.accent and colors.accent or colors.hover)
    button.glow:SetAllPoints(button)
    button.glow:SetAlpha(0)
    Theme.Border(button, options.accent and colors.accent or colors.border)

    button.label = Theme.Text(button, Theme.sizes.body, options.accent and colors.accent or colors.text, "CENTER")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)

    function button:SetLabel(text)
        self.label:SetText(text)
        if options.autoWidth then self:SetWidth(self.label:GetStringWidth() + 22) end
    end

    button:SetScript("OnEnter", function(self)
        Theme.HoverFade(self, self.glow, options.accent and 0.22 or 1)
        if self.tooltip then self.tooltip(self) end
    end)
    button:SetScript("OnLeave", function(self)
        Theme.HoverFade(self, self.glow, 0)
        GameTooltip:Hide()
    end)
    -- Un bouton caché pendant qu'on le survole ne doit pas rester allumé.
    button:SetScript("OnHide", function(self) self.glow:SetAlpha(0) end)
    button:SetScript("OnClick", onClick)
    return button
end

--- Zone défilante à la molette, avec un fin repère de position à droite.
function Theme.Scroll(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetWidth(width)
    scroll.child = CreateFrame("Frame", nil, scroll)
    scroll.child:SetSize(width, 1)
    scroll:SetScrollChild(scroll.child)

    scroll.thumb = Theme.Fill(scroll, "OVERLAY", Theme.colors.faint)
    scroll.thumb:SetWidth(2)
    scroll.thumb:Hide()

    local function UpdateThumb(self)
        local visible, content = self:GetHeight(), self.contentHeight or 0
        local range = content - visible
        if range <= 1 then
            self.thumb:Hide()
            return
        end
        local thumbHeight = math.max(14, visible * visible / content)
        local offset = (self:GetVerticalScroll() / range) * (visible - thumbHeight)
        self.thumb:SetHeight(thumbHeight)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -offset)
        self.thumb:Show()
    end

    --- À appeler quand le contenu change : hauteur visible et hauteur totale du contenu.
    function scroll:SetContent(visibleHeight, contentHeight)
        self:SetHeight(math.max(1, visibleHeight))
        self.contentHeight = contentHeight
        self.child:SetHeight(math.max(1, contentHeight))
        local range = math.max(0, contentHeight - visibleHeight)
        self:SetVerticalScroll(math.min(self:GetVerticalScroll(), range))
        UpdateThumb(self)
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, direction)
        local range = math.max(0, (self.contentHeight or 0) - self:GetHeight())
        local target = self:GetVerticalScroll() - direction * 30
        self:SetVerticalScroll(math.max(0, math.min(range, target)))
        UpdateThumb(self)
    end)
    return scroll
end
