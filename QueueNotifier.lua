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

local icon = LibStub("LibDBIcon-1.0")

function QueueNotifier:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("QueueNotifierDB", {
		profile = {
			screenshotEnabled = false,
			broadcastEnabled = true,
			chatPrintEnabled = true,
			minimap = {
				hide = false,
			},
		},
	})
	self:SetupOptions()
	self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "OnEvent")
	self:RegisterComm(addonName)
	self:PrintStartupMessage()
	icon:Register(addonName, LDB, self.db.profile.minimap)
	self.guildQueueTable = {} -- Initialize the table to track queue statuses
end

function QueueNotifier:PrintStartupMessage()
	if self.db.profile.screenshotEnabled then
		self:Print("TGA screenshots are enabled.")
	else
		self:Print("TGA screenshots are disabled.")
	end
	if self.db.profile.broadcastEnabled then
		self:Print("Queue Data Sharing is enabled.")
	else
		self:Print("Queue Data Sharing is disabled.")
	end
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
					logo = {
						name = "",
						type = "description",
						image = "Interface\\AddOns\\QueueNotifier\\logo.png",
						imageWidth = 64,
						imageHeight = 64,
						width = "full",
						order = 2,
					},
					description = {
						type = "description",
						name = "QueueNotifier is a World of Warcraft addon designed to enhance your PvP experience by providing detailed information about your and your guild members' battleground queue statuses.\n\nFeatures:\n- Screenshots on Queue pop: Automatically take TGA screenshots when the battlefield is ready to be entered.\n- Guild Queue Data Sharing: Share and view your guild members' PvP queue statuses.\n- Queue Status Display: Display queue statuses in a tooltip when hovering over the minimap icon.\n- Chat Notifications: Receive chat notifications about your queue statuses.",
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
						order = 1,
					},
					description = {
						type = "description",
						name = "When enabled, this feature saves a TGA screenshot when you are prompted to join. Screenshots are saved in the Screenshots folder of your WoW directory. Third-party applications can use these files to trigger notifications on various devices. Manage your screenshots regularly to avoid excessive disk usage.",
						order = 2,
					},
					broadcastEnabled = {
						type = "toggle",
						name = "Send and Receive Guild Queue Data",
						desc = "Enable or disable sharing and viewing guild members queue statuses. You need to be in guild for this functionality to work.",
						get = function(info)
							return self.db.profile.broadcastEnabled
						end,
						set = function(info, value)
							self.db.profile.broadcastEnabled = value
						end,
						order = 3,
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
						order = 4,
					},
				},
			},
		},
	}

	LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, options, { "/qn" })
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName)
end

function QueueNotifier:OnEvent(event, ...)
	if event == "UPDATE_BATTLEFIELD_STATUS" then
		self:HandleBattlefieldEventWithIndex(...)
	end
end

--- Handle the battlefield event
--- @param battlefieldIndex number The index of the battlefield
function QueueNotifier:HandleBattlefieldEventWithIndex(battlefieldIndex)
	local status, _, _, _, _, queueType, _, _, _, _, _ = GetBattlefieldStatus(battlefieldIndex)

	local playerGUID = UnitGUID("player")
	local playerName = UnitName("player")
	local playerClass, _ = UnitClassBase("player")
	local key = playerGUID .. "-" .. tostring(battlefieldIndex)

	-- self:Print(key)
	-- queued - Waiting for a battlefield to become ready, you're in the queue
	-- confirm - Ready to join a battlefield
	-- active - Inside an active battlefield
	-- none - Not queued for anything in this index
	-- error - This should never happen
	-- self:Print("status: " .. tostring(status)) -- none, queued, confirm, active
	-- self:Print("queueType: " .. tostring(queueType)) -- BRAWLSOLORBG. BATTLEGROUND

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
		self:Print(
			string.format(
				"%s%s%s %s%s%s (%s / %s %s%s%s)%s",
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
				self.COLOR.RESET
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
		-- if self:UpgradeAvailable(self.ADDON_VERSION, payload.addonVersion) then
		-- 	self:Print(string.format("A new version (%s) is available. Please update!", payload.addonVersion))
		-- end
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

		-- If classColor is nil, use a default gray color
		if not classColor then
			classColor = { colorStr = "FF808080" } -- Just the hex code, no |c
		end

		local line = string.format(
			"|c%s%s|r: %s%s|r (%s) - %s / %s",
			classColor.colorStr,
			data.player,
			self.STATUS_COLOR[data.status],
			data.status,
			data.queueType,
			data.timeWaited,
			data.estimatedWaitTime
		)
		tooltip:AddLine(line)
	end
	tooltip:Show()
end

function QueueNotifier:ShowOptions()
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
end
