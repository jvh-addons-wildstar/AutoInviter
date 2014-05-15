require "Window"
 
local AutoInviter = {} 
 
function AutoInviter:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

	self.tItems = {} -- this keeps track of the list items
	self.tRules = {} -- rules are saved in a separate table and gets rebuilt onload, using window ID as key
	self.tActions = {} -- all available invite actions
	self.wndSelectedListItem = nil -- keep track of which list item is currently selected
    return o
end

function AutoInviter:Init()
    Apollo.RegisterAddon(self, true, "AutoInviter", {})
end
 
function AutoInviter:OnLoad()
    Apollo.RegisterSlashCommand("autoinviter", "OnConfigure", self)
    Apollo.RegisterEventHandler("ChatMessage", "OnChatMessage", self)
    
    self.wndMain = Apollo.LoadForm("AutoInviter.xml", "AutoInviterForm", nil, self)
	self.cboActions = self.wndMain:FindChild("cmbActions")
	self.chkCaseSensitive = self.wndMain:FindChild("chkCaseSensitive")
	self.txtTrigger = self.wndMain:FindChild("txtTrigger")
	self.txtWelcomeMessage= self.wndMain:FindChild("txtWelcomeMessage")
	self.btnUpdate = self.wndMain:FindChild("btnUpdate")
	
	self:ToggleControls(false) -- start with controls disabled until we select an item
    self.wndMain:Show(false)
    
	-- item list
	self.wndItemList = self.wndMain:FindChild("ItemList")	
end

function AutoInviter:OnConfigure()
	self.wndMain:Show(true) -- show the window
	self:PopulateActions()
	-- populate the item list
	self:PopulateItemList()
end

function AutoInviter:OnChatMessage(channelCurrent, tMessage)
	local eChannelType = channelCurrent:GetType()

	if eChannelType == ChatSystemLib.ChatChannel_Whisper or eChannelType == ChatSystemLib.ChatChannel_AccountWhisper then
		for idx, tSegment in ipairs( tMessage.arMessageSegments ) do
			keyword = tSegment.strText
		end

		for i, rule in pairs(self.tRules) do
			local strText = keyword
			if rule.enabled and rule.trigger ~= "" then
				ruletrigger = rule.trigger
				if rule.caseSensitive == false then
					ruletrigger = ruletrigger:lower()
					strText = strText:lower()
				end
				if ruletrigger == strText then
					local channelcommand = nil
					if rule.welcomeMessage ~= "" then
						ChatSystemLib.Command('/whisper ' .. tMessage.strSender .. ' ' .. rule.welcomeMessage)
					end
					if rule.action.circlename then
						-- circle id's seem to change randomly. Determine it at the time we receive a circle related message
						local guilds = GuildLib.GetGuilds()
						for i, guild in pairs(guilds) do
							local gtype = guild.GetType(guild)
							if gtype == GuildLib.GuildType_Circle and guild:GetName() == rule.action.circlename then
								channelcommand = guild:GetChannel():GetCommand() .. ' '
							end
						end
					end
					ChatSystemLib.Command(rule.action.command .. ' ' .. (channelcommand or "") .. tMessage.strSender)
				end
			end
		end
	end
end

-- when the Cancel button is clicked
function AutoInviter:OnCancel()
	self.wndMain:Show(false) -- hide the window
end

function AutoInviter:PopulateItemList()
	-- make sure the item list is empty to start with
	self:DestroyItemList()

	local duplicatedRules = self:CopyTable(self.tRules)
	self.tRules = {}
	for i, rule in pairs(duplicatedRules) do
		self:AddItem(rule, false)
	end
	-- now all the item are added, call ArrangeChildrenVert to list out the list items vertically
	self.wndItemList:ArrangeChildrenVert()
end

-- clear the item list
function AutoInviter:DestroyItemList()
	-- destroy all the wnd inside the list
	for idx,wnd in ipairs(self.tItems) do
		wnd:Destroy()
	end

	-- clear the list item array
	self.tItems = {}
end

function AutoInviter:AddItem(rule, bAddToRules)
	local wnd = Apollo.LoadForm("AutoInviter.xml", "ListItem", self.wndItemList, self)
	-- keep track of the window item created
	table.insert(self.tItems, wnd)
	self.tRules[wnd:GetId()] = rule
	-- give it a piece of data to refer to 
	self:FillListItem(wnd, rule)
	self:OnListItemSelected(wnd, wnd)
end

function AutoInviter:OnListItemSelected(wndHandler, wndControl)
    -- make sure the wndControl is valid
    if wndHandler ~= wndControl then
        return
    end

    -- change the old item's text color back to normal color
    for idx,wnd in ipairs(self.tItems) do
		wnd:FindChild("txtTrigger"):SetTextColor("white")
		wnd:FindChild("txtAction"):SetTextColor("white")
	end
    
	-- wndControl is the item selected - change its color to selected
	self.wndSelectedListItem = wndControl
	self.wndSelectedListItem:FindChild("txtTrigger"):SetTextColor("red")
	self.wndSelectedListItem:FindChild("txtAction"):SetTextColor("red")
    
    rule = self.tRules[wndControl:GetId()]
	self:ToggleControls(true)
	self.chkCaseSensitive:SetCheck(rule.caseSensitive)
	self.txtTrigger:SetText(rule.trigger)
	self.txtWelcomeMessage:SetText(rule.welcomeMessage)
	self.cboActions:SelectItemByText(rule.action.description)
end

function AutoInviter:FillListItem(wnd, rule)
	local trigger = wnd:FindChild("txtTrigger")
	local enabled = wnd:FindChild("chkEnable")
	local txtAction = wnd:FindChild("txtAction")
	self.tRules[wnd:GetId()] = rule
	if trigger then -- make sure the text wnd exist
		trigger:SetText(rule.trigger)
		enabled:SetCheck(rule.enabled)
		txtAction:SetText(rule.action.description)
	end
end

function AutoInviter:PopulateActions()
	self.tActions = {}
	self:AddAction("Invite to party/raid", "/invite")
	local guilds = GuildLib.GetGuilds()
	for i, guild in pairs(guilds) do
		local type = guild.GetType(guild)
		if type == GuildLib.GuildType_Guild then
			self:AddAction("Invite to Guild", "/ginvite")
		elseif type == GuildLib.GuildType_Circle then
			self:AddAction("Invite to '" .. guild:GetName() .."' circle", "/cinvite", guild:GetName())
		end
	end
	
	for i, action in pairs(self.tActions) do
		self.cboActions:AddItem(action.description, "", action)
	end
end

function AutoInviter:AddAction(description, command, circlename)
	local action = {}
	action.description = description
	action.command = command
	action.circlename = circlename

	table.insert(self.tActions, action)
end

function AutoInviter:ToggleControls(enabled)
	self.cboActions:Enable(enabled)
	self.chkCaseSensitive:Enable(enabled)
	self.txtTrigger:Enable(enabled)
	self.txtWelcomeMessage:Enable(enabled)
	self.btnUpdate:SetOpacity(1)


	if enabled == false then
		self.chkCaseSensitive:SetCheck(false)
		self.txtTrigger:SetText("")
		self.txtWelcomeMessage:SetText("")
		self.btnUpdate:SetOpacity(0)
	end
end

function AutoInviter:GetDisplayedRule()
	rule = {}
	rule.enabled = self.wndSelectedListItem:FindChild("chkEnable"):IsChecked()
	rule.caseSensitive = self.chkCaseSensitive:IsChecked()
	rule.trigger = self.txtTrigger:GetText()
	rule.welcomeMessage = self.txtWelcomeMessage:GetText()
	rule.action = self.cboActions:GetSelectedData()

	return rule
end

function AutoInviter:AddNewRule()
	rule = {}
	rule.enabled = true
	rule.caseSensitive = false
	rule.trigger = ""
	rule.welcomeMessage = ""
	rule.action = self.tActions[1]

	self:AddItem(rule)
	self.wndItemList:ArrangeChildrenVert()
end

function AutoInviter:DeleteSelectedRule()
	for i, window in pairs(self.tItems) do
		wndId = window:GetId()
		if wndId == self.wndSelectedListItem:GetId() then
			self.tRules[wndId] = nil
			table.remove(self.tItems, i)
			window:Destroy()
		end
	end
	self.wndItemList:ArrangeChildrenVert()
	self:ToggleControls(false)
end

function AutoInviter:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
        return nil
    end	
	
	local save = {}
	save.tRules = self.tRules
	save.saved = true
	return save
end

function AutoInviter:OnRestore(eLevel, tData)
	if tData.saved ~= nil then
		self.tRules = tData.tRules
	end
end

function AutoInviter:CopyTable(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[self:CopyTable(orig_key)] = self:CopyTable(orig_value)
        end
        setmetatable(copy, self:CopyTable(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


---------------------------------------------------------------------------------------------------
-- AutoInviterForm Functions
---------------------------------------------------------------------------------------------------

function AutoInviter:OnAddRule( wndHandler, wndControl, eMouseButton )
	self:AddNewRule()
end

function AutoInviter:OnDeleteRule( wndHandler, wndControl, eMouseButton )
	self:DeleteSelectedRule()
end

function AutoInviter:OnSaveRule( wndHandler, wndControl, eMouseButton )
	if self.wndSelectedListItem ~= nil then
		self:FillListItem(self.wndSelectedListItem, self:GetDisplayedRule())
		self.btnUpdate:SetOpacity(0) -- fade out the save button as feedback
	end
end

function AutoInviter:OnDataDirty( wndHandler, wndControl, eMouseButton )
	self.btnUpdate:SetOpacity(1) -- data changed, fade in the save button
end

---------------------------------------------------------------------------------------------------
-- ListItem Functions
---------------------------------------------------------------------------------------------------

function AutoInviter:OnTriggerEnableChange( wndHandler, wndControl, eMouseButton )
	local enabled = wndControl:IsChecked()
	local wndId = wndControl:GetParent():GetId()

	self.tRules[wndId].enabled = enabled
end

-----------------------------------------------------------------------------------------------
-- AutoInviter Instance
-----------------------------------------------------------------------------------------------
local AutoInviterInst = AutoInviter:new()
AutoInviterInst:Init()