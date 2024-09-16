local addonName, ns = ...

---@class QueueNotifier : AceAddon-3.0, AceConsole-3.0, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0
local QueueNotifier = LibStub("AceAddon-3.0"):NewAddon(
	"QueueNotifier",
	"AceConsole-3.0",
	"AceEvent-3.0",
	"AceComm-3.0",
	"AceSerializer-3.0"
)

-- Define the addon version
QueueNotifier.ADDON_VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version")

QueueNotifier.COLOR = {
	RED = "|cFFFF0000",
	GREEN = "|cFF00FF00",
	BLUE = "|cFF6699FF",
	GRAY = "|cFF808080",
	GOLD = "|cFFFFD700",
	RESET = "|r",
}

QueueNotifier.STATUS_COLOR = {
	active = QueueNotifier.COLOR.GREEN,
	queued = QueueNotifier.COLOR.GOLD,
	confirm = QueueNotifier.COLOR.RED,
	none = QueueNotifier.COLOR.GRAY,
}

local LDB = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
	type = "data source",
	text = addonName,
	icon = "Interface\\AddOns\\QueueNotifier\\Icons\\QueueNotifierIcon.png",
	OnTooltipShow = function(tooltip)
		QueueNotifier:UpdateTooltip(tooltip)
	end,
	OnClick = function(self, button)
		if button == "RightButton" then
			QueueNotifier:ShowOptions()
		end
	end,
})

function QueueNotifier:OnInitialize()
	-- Initialize database
	self.db = LibStub("AceDB-3.0"):New("QueueNotifierDB", {
		profile = {
			screenshotEnabled = false,
			broadcastEnabled = true,
			chatPrintEnabled = true,
			autoDisableChatEnabled = false,
			minimap = {
				hide = false,
			},
		},
	})

	-- Set up options using AceConfig
	self:SetupOptions()

	-- Apply the AutoPushSpellToActionBar setting during initialization based on the current CVar value
	self:ApplyAutoPushSpellSetting()

	-- Register events
	self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "OnEvent")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
	self:RegisterEvent("PLAYER_LOGOUT", "OnPlayerLogout")

	-- Register communication channels
	self:RegisterComm(addonName)

	-- Register minimap icon with LibDBIcon
	local icon = LibStub("LibDBIcon-1.0")
	icon:Register(addonName, LDB, self.db.profile.minimap)

	-- Initialize additional properties
	self.guildQueueTable = {}
	self.chatDisabledForSoloShuffle = false
end

function QueueNotifier:UpgradeAvailable(newVersion)
	local function parseVersion(v)
		return { v:match("(%d+)%.(%d+)%.(%d+)") }
	end

	local currentVersion = parseVersion(self.ADDON_VERSION)
	local newVersionParsed = parseVersion(newVersion)

	for i = 1, 3 do
		if newVersionParsed[i] > currentVersion[i] then
			return true
		elseif newVersionParsed[i] < currentVersion[i] then
			return false
		end
	end

	return false -- Versions are equal
end

function QueueNotifier:SetupOptions()
	local options = {
		name = addonName,
		handler = QueueNotifier,
		type = "group",
		args = {
			Information = {
				name = "Addon Information",
				type = "group",
				order = 1,
				args = {
					version = {
						name = "Version: " .. QueueNotifier.ADDON_VERSION,
						type = "description",
						width = "full",
						fontSize = "medium",
						order = 1,
					},
					description = {
						type = "description",
						name = [[QueueNotifier is designed to enhance your PvP experience.

Features:
- Screenshots on Queue Pop: Automatically take TGA screenshots when the battlefield is ready to be entered.
- Guild Queue Data Sharing: Share and view your guild members' PvP queue statuses.
- Queue Status Display: Display queue statuses in a tooltip when hovering over the minimap icon.
- Chat Notifications: Receive chat notifications about your queue statuses.
- Auto Disable Chat During Solo Shuffle: Automatically disable chat during solo shuffle matches and re-enable it afterwards.
- Disable Auto Push Spell to Action Bar: Prevent newly learned spells from automatically being added to your action bar.]],
						width = "full",
						fontSize = "medium",
						order = 3,
					},
				},
			},
			Settings = {
				name = "Settings",
				type = "group",
				order = 2,
				args = {
					screenshotEnabled = {
						type = "toggle",
						name = "Enable TGA Screenshots",
						desc = "Enable or disable taking TGA screenshots when the battlefield queue status is 'confirm'.",
						get = function(info)
							return self.db.profile.screenshotEnabled
						end,
						set = function(info, value)
							self.db.profile.screenshotEnabled = value
						end,
						width = "full",
						order = 1,
					},
					screenshotDescription = {
						type = "description",
						name = "When enabled, this feature saves a TGA screenshot when you are prompted to join. Screenshots are saved in the Screenshots folder of your WoW directory. Third-party applications can use these files to trigger notifications on various devices. Manage your screenshots regularly to avoid excessive disk usage.",
						width = "full",
						order = 2,
					},
					broadcastEnabled = {
						type = "toggle",
						name = "Send and Receive Guild Queue Data",
						desc = "Enable or disable sharing and viewing guild members queue statuses. You need to be in a guild for this functionality to work.",
						get = function(info)
							return self.db.profile.broadcastEnabled
						end,
						set = function(info, value)
							self.db.profile.broadcastEnabled = value
						end,
						width = "full",
						order = 3,
					},
					broadcastDescription = {
						type = "description",
						name = "When enabled, you can share and view your guild members' PvP queue statuses.",
						width = "full",
						order = 4,
					},
					chatPrintEnabled = {
						type = "toggle",
						name = "Enable Queue Chat Messages",
						desc = "Enable or disable queue statuses in the chat.",
						get = function(info)
							return self.db.profile.chatPrintEnabled
						end,
						set = function(info, value)
							self.db.profile.chatPrintEnabled = value
						end,
						width = "full",
						order = 5,
					},
					chatPrintDescription = {
						type = "description",
						name = "When enabled, this feature will print queue statuses in your chat window.",
						width = "full",
						order = 6,
					},
					autoDisableChatEnabled = {
						type = "toggle",
						name = "Auto Disable Chat During Solo Shuffle",
						desc = "Enable or disable automatic chat disabling during solo shuffle matches.",
						get = function(info)
							return self.db.profile.autoDisableChatEnabled
						end,
						set = function(info, value)
							self.db.profile.autoDisableChatEnabled = value
						end,
						width = "full",
						order = 7,
					},
					autoDisableChatDescription = {
						type = "description",
						name = "When enabled, chat will be automatically disabled during solo shuffle matches and re-enabled afterwards.",
						width = "full",
						order = 8,
					},
					autoPushSpellToActionBarDisabled = {
						type = "toggle",
						name = "Disable Auto Push Spell To Action Bar",
						desc = "Prevents newly learned spells from being automatically added to your action bar.",
						get = function(info)
							-- Read the value directly from the CVar
							return GetCVar("AutoPushSpellToActionBar") == "0"
						end,
						set = function(info, value)
							-- Set the CVar based on the toggle state
							SetCVar("AutoPushSpellToActionBar", value and "0" or "1")
						end,
						width = "full",
						order = 9,
					},
					autoPushSpellToActionBarDisabledDescription = {
						type = "description",
						name = "When enabled, this feature will prevent newly learned spells from being automatically pushed to your action bar, giving you full control over which spells you add and where.",
						width = "full",
						order = 10,
					},
				},
			},
		},
	}

	-- Register options with AceConfig
	LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, options)

	-- Register options in the Blizzard Interface Options panel and store the reference
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName)

	-- Register slash command to open options
	LibStub("AceConsole-3.0"):RegisterChatCommand("qn", function()
		QueueNotifier:ShowOptions()
	end)
end

function QueueNotifier:ApplyAutoPushSpellSetting()
	-- Apply the current value of the CVar directly
	local autoPushDisabled = GetCVar("AutoPushSpellToActionBar") == "0"
	if autoPushDisabled then
		SetCVar("AutoPushSpellToActionBar", 0)
	else
		SetCVar("AutoPushSpellToActionBar", 1)
	end
end

-- Function to disable chat
function QueueNotifier:DisableChat()
	if not C_SocialRestrictions.IsChatDisabled() then
		C_SocialRestrictions.SetChatDisabled(true)
		self:Print("Chat disabled for solo shuffle match.")
		self.chatDisabledForSoloShuffle = true
	end
end

-- Function to enable chat
function QueueNotifier:EnableChat()
	if self.chatDisabledForSoloShuffle then
		C_SocialRestrictions.SetChatDisabled(false)
		self:Print("Chat enabled after solo shuffle match.")
		self.chatDisabledForSoloShuffle = false
	end
end

-- Event handler for entering the world
function QueueNotifier:OnPlayerEnteringWorld()
	self:AdjustChatForSoloShuffle()
end

function QueueNotifier:OnZoneChanged()
	self:AdjustChatForSoloShuffle()
end

function QueueNotifier:OnPlayerLogout()
	if self.chatDisabledForSoloShuffle then
		self:EnableChat() -- Ensure chat is enabled on logout
	end
end

function QueueNotifier:OnEvent(event, ...)
	if event == "UPDATE_BATTLEFIELD_STATUS" then
		self:HandleBattlefieldEventWithIndex(...)
	end
end

function QueueNotifier:AdjustChatForSoloShuffle()
	local _, instanceType = IsInInstance()
	if instanceType == "pvp" or instanceType == "arena" then
		if C_PvP.IsRatedSoloShuffle() and self.db.profile.autoDisableChatEnabled then
			self:DisableChat()
		else
			self:EnableChat()
		end
	else
		self:EnableChat()
	end
end

--- Handle the battlefield event
--- @param battlefieldIndex number The index of the battlefield
function QueueNotifier:HandleBattlefieldEventWithIndex(battlefieldIndex)
	local status, _, _, _, _, queueType = GetBattlefieldStatus(battlefieldIndex)

	if C_PvP.IsRatedSoloShuffle() then
		if status == "active" and self.db.profile.autoDisableChatEnabled then
			self:DisableChat()
		elseif status == "none" then
			self:EnableChat()
		end
	end

	-- Retrieve the roles selected for PvP queues
	local tankRole, healerRole, dpsRole = GetPVPRoles()
	local roleList = {}

	if tankRole then
		table.insert(roleList, "TANK")
	end
	if healerRole then
		table.insert(roleList, "HEALER")
	end
	if dpsRole then
		table.insert(roleList, "DAMAGER")
	end

	local rolesString = table.concat(roleList, ", ")

	-- If the player has selected the TANK role, display a red warning message
	if tankRole and status == "queued" then
		self:Print(self.COLOR.RED .. "Warning: You are queueing as a TANK role!" .. self.COLOR.RESET)
	end

	local playerGUID = UnitGUID("player")
	local playerName = UnitName("player")
	local _, playerClass = UnitClass("player")
	local key = playerGUID .. "-" .. tostring(battlefieldIndex)

	if status == "confirm" and self.db.profile.screenshotEnabled then
		self:TakeEnhancedScreenshot()
	end

	local timeWaited = (GetBattlefieldTimeWaited(battlefieldIndex) or 0) / 1000
	local estimatedWaitTime = (GetBattlefieldEstimatedWaitTime(battlefieldIndex) or 0) / 1000
	local formattedTimeWaited = self:FormatTime(timeWaited)
	local formattedEstimatedWaitTime = estimatedWaitTime > 0 and self:FormatTime(estimatedWaitTime) or "N/A"
	local timeDifference = timeWaited - estimatedWaitTime
	local formattedTimeDifference, timePassedColor = self:GetTimeDifference(timeDifference, estimatedWaitTime)

	if self.db.profile.chatPrintEnabled and (status == "queued" or status == "confirm") then
		local rolesSuffix = ""
		if rolesString ~= "" then
			rolesSuffix = " as " .. rolesString
		end

		self:Print(
			string.format(
				"%s%s%s %s%s%s (%s / %s %s%s%s)%s%s",
				self.COLOR.GOLD,
				self.STATUS_COLOR[status or "none"] or self.COLOR.GRAY,
				status or "none",
				self.COLOR.GREEN,
				queueType,
				self.COLOR.RESET,
				formattedTimeWaited,
				formattedEstimatedWaitTime,
				timePassedColor or "",
				formattedTimeDifference or "",
				self.COLOR.RESET,
				self.COLOR.RESET,
				rolesSuffix
			)
		)
	end

	local playerPayload = {
		key = key,
		player = playerName,
		status = status,
		queueType = queueType,
		class = playerClass,
		timeWaited = formattedTimeWaited,
		estimatedWaitTime = formattedEstimatedWaitTime,
		timeDifference = formattedTimeDifference,
		roles = rolesString,
		addonVersion = self.ADDON_VERSION,
	}

	self:UpdateGuildQueueTable(playerPayload)
	self:BroadcastQueueStatus(playerPayload)
end

function QueueNotifier:FormatTime(totalSeconds)
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("%02d:%02d", minutes, seconds)
end

function QueueNotifier:GetTimeDifference(timeDifference, estimatedWaitTime)
	if estimatedWaitTime > 0 then
		if timeDifference > 0 then
			return string.format("+%s", self:FormatTime(timeDifference)), self.COLOR.RED
		else
			return string.format("-%s", self:FormatTime(math.abs(timeDifference))), self.COLOR.GREEN
		end
	else
		return "N/A", self.COLOR.RESET
	end
end

function QueueNotifier:TakeEnhancedScreenshot()
	local originalFormat = GetCVar("screenshotFormat")
	local isFormatChanged = false

	if originalFormat ~= "tga" then
		isFormatChanged = self:SetScreenshotFormat("tga")
	end

	Screenshot()

	if isFormatChanged then
		self:SetScreenshotFormat(originalFormat)
	end
end

function QueueNotifier:SetScreenshotFormat(format)
	if format ~= "tga" and format ~= "jpeg" then
		self:Print("Invalid screenshot format specified.")
		return false
	end
	SetCVar("screenshotFormat", format)
	return true
end

function QueueNotifier:BroadcastQueueStatus(payload)
	if IsInGuild() and self.db.profile.broadcastEnabled then
		local message = self:Serialize(payload)
		self:SendCommMessage(addonName, message, "GUILD")
	end
end

function QueueNotifier:OnCommReceived(prefix, message, distribution, sender)
	if sender == UnitName("player") then
		return
	end
	local success, payload = self:Deserialize(message)
	if success then
		self:UpdateGuildQueueTable(payload)
	end
end

function QueueNotifier:UpdateGuildQueueTable(payload)
	if payload.status ~= "queued" then
		self:RemoveQueueEntry(payload.key)
	else
		self.guildQueueTable[payload.key] = payload
	end
end

function QueueNotifier:RemoveQueueEntry(key)
	self.guildQueueTable[key] = nil
end

--- @param tooltip GameTooltip the actual tooltip
function QueueNotifier:UpdateTooltip(tooltip)
	tooltip:ClearLines()
	tooltip:AddLine("PvP Queues:")

	if not next(self.guildQueueTable) then
		tooltip:AddLine("No active queues.")
		return
	end

	for key, data in pairs(self.guildQueueTable) do
		local classColor = RAID_CLASS_COLORS[data.class]

		if not classColor then
			classColor = { colorStr = "FF808080" }
		end

		local rolesSuffix = ""
		if data.roles and data.roles ~= "" then
			rolesSuffix = " as " .. data.roles
		end

		local line = string.format(
			"|c%s%s|r: %s%s|r (%s) - %s / %s%s",
			classColor.colorStr,
			data.player,
			self.STATUS_COLOR[data.status],
			data.status,
			data.queueType,
			data.timeWaited,
			data.estimatedWaitTime,
			rolesSuffix
		)
		tooltip:AddLine(line)
	end
	tooltip:Show()
end

function QueueNotifier:ShowOptions()
	if Settings and Settings.OpenToCategory then
		-- Use the new Settings API if available
		Settings.OpenToCategory(self.optionsFrame.name)
	else
		-- Fallback for older WoW versions using InterfaceOptionsFrame_OpenToCategory
		InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
		InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) -- Double call to ensure proper display
	end
end
