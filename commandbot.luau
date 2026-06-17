
local _start = DateTime.now().UnixTimestampMillis;

local _metadata = {
	['_VERSION'] = {1, 13, 1};
}

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService");
local HTTPService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer;

--//preallocate or sum shit wtv u call it for the stuff so you can call it globally while having optimizations
local runner;
local tokenizer;
local permissions;

-- local configs = readfile ('/') or {
-- 	["default"] = {

-- 	}
-- }

--// object
local signal = {} do
	local subscription = {};

	function subscription.new(t, callback)
		local self = setmetatable({}, {__index = subscription});
		self.callback = callback;
		self.t = t;

		table.insert(t, callback);
		return self;
	end;

	function subscription:Disconnect()
		table.remove(self.t, table.find(self.t, self.callback))
	end;

	function signal.new()
		local self = setmetatable({}, {__index = signal});
		self._subscriptions = {};
		return self;
	end;

	@[deprecated]
	function signal:Fire(...)
		return self:Emit(...);
	end;

	function signal:Emit(...)
		for i, v in self._subscriptions do
			task.spawn(v, ...);
		end;
	end;

	function signal:Connect(callback)
		return subscription.new(self._subscriptions, callback)
	end;

	function signal:Once(callback)
		local connection;
		connection = self:Connect(function()
			callback();
			connection:Disconnect();
		end);
		return connection;
	end;

	function signal:Wait()
		local fired = false;
		local con = self:Once(function() fired = true; end)
		repeat task.wait() until fired;
	end;
end;

--// object --------- on execution passes: self:command, source:player, ...:any (the args)
local command = {} do
	function command.new(commandInfo)
		local self = setmetatable({}, {__index = command});
		self.name = commandInfo.name;
		self.callback = commandInfo.callback;
		self.cleanup = commandInfo.cleanup;
		self.clientLocked = commandInfo.clientLocked;

		self._alive = false;
		self._activeThreads = {};

		self.onExecuted = signal.new();

		return self;
	end;

	--//

	function command:executeFromTokenized(tokenizedCommand)

	end;

	function command:execute(modifiers: {string}, source: Player, args: {[number]: any})
		self.onExecuted:Emit(modifiers, source, args);
		return pcall(function(...)
			self:closeActiveThread();
			self._alive = true;
			local perms = permissions.getPlayerPermissions(source);
			if not perms then runner.sendChatMessage("invalid permissions"); return; end;
			if self.clientLocked and not perms.clientCommandAccess then runner.sendChatMessage("you cant access this command via client access"); return; end;
			local thread = task.spawn(
				function()
					self.callback(self, source, table.unpack(args));
					
                end
			)

			table.insert(self._activeThreads, thread)
		end)
	end;

    function command:cleanThreads()
        for i, v in self._activeThreads do
            if coroutine.status(v) == "dead" then
                table.remove(self._activeThreads, i);
                break;
            end;
            if coroutine.status(v) == "suspended" then
                table.remove(self._activeThreads, i);
                break;
            end;
        end;    
    end;

	function command:closeActiveThread(source)
		if not self._activeThreads then return; end;
		if self.cleanup then self.cleanup(self, source) end;
		self._alive = false;

        for i, v in self._activeThreads do
            coroutine.close(v);
        end;
        table.clear(self._activeThreads);
	end;
end

--// object
local permission = {} do
	function permission.new(name: string, clientCommandAccess: boolean?)
		local self = setmetatable({}, {__index = permission})
		self.playerName = name;
		self.clientCommandAccess = clientCommandAccess or false;
		self.blacklistedCommands = {};
		return self;
	end;
end

--// object(s)
permissions = setmetatable({
	-- permission.new(game:GetService("Players").LocalPlayer.Name, true); -- [let the client to use commands]
	permission.new("vvhereelse", true); -- the controller
}, {
	__index = {
		getPlayerPermissions = function(player: Player)
			for i, v in permissions do
				if v.playerName == player.Name then
					return v;
				end;
			end;
			return nil;
		end;
	};
})

local commands;

commands = setmetatable({
	--//list commands
	command.new {
		name = "commands/help/cmd/cmds";
		callback = function()
			local allCommandsList = {};
			for i, v in commands do
				table.insert(allCommandsList, v.name);
			end;

			local stringPages = {};

			local pageId = 1;
			local pageCharSize = 0;
			for i, v in allCommandsList do
				pageCharSize += v:len();
				if pageCharSize > 100 then
					pageId += 1;
					pageCharSize = 0;
				end;
				if not stringPages[pageId] then
					stringPages[pageId] = "";
				end;
				stringPages[pageId] ..= `{v}, `;
			end;

			for i, v in stringPages do
				runner.sendChatMessage(v);
				task.wait(2);
			end;
		end;
	};
	--// say the selectors
	command.new {
		name = "selectors/types";
		callback = function()
			local toSay = ""
			for i, v in tokenizer.typeConverters do
				toSay ..= ", ".. i
			end;
			runner.sendChatMessage(toSay);
		end;
	};

	--run lua code
	command.new {
		name = "lua/code/script";
		callback = function(self, source, code: string)
			local fn = loadstring(code);
			setfenv(fn, {
				['print'] = function(...)
					runner.sendChatMessage("[print] " .. table.concat(table.pack(...), " "));
				end;
				['warn'] = function(...)
					runner.sendChatMessage("[warning] " .. table.concat(table.pack(...), " "));
				end;
				['game'] = game;
				['workspace'] = workspace;
				['task'] = task;
			})
			local success, er = pcall(fn);

			if not success then
				runner.sendChatMessage("error: " .. er);
			end;
		end;
	};
    --//modify
    command.new {
		name = "modify";
		callback = function(self, source: Player, type: "property" | "method", instance: Instance, p: string, ...)
			local member = instance[p];
			if member == nil then runner.sendChatMessage(`{p} isnt a valid member of {instance.Name}`); return; end;
            if type == "property" then
				instance[p] = table.pack(...)[1]
			elseif type == "method" then
				member(instance, ...)
			else
				runner.sendChatMessage(`unknown method type "{type}" use property or method`)
			end;
		end;
	};

    --//global
    command.new {
		name = "global";
		callback = function(self, source: Player, name: string, toSet: any)
            _G[name] = toSet;
            runner.sendChatMessage(`saved {name} as {toSet}`);
		end;
	};

    --//gamble command (does a random command)
	command.new {
		name = "random";
		callback = function(self, source)
			local toRun = commands[math.random(1, #commands)];
			toRun:execute({}, source, {});

			runner.sendChatMessage(`executed "{toRun.name:split("/")[1]}"`)
		end;
	};

	--//permission add,remove & list
	command.new {
		name = "perms/permission/permissions";
		callback = function(self, source: Player, type: string, player: Player)
			local name = player.Name or player;
			if type=="add" then
				local perms = permission.new(name, false);
				table.insert(permissions, perms);

				runner.sendChatMessage(`{name} now has command permissions`);
				return;
			elseif type == "remove" then
				for i, v in permissions do
					if v.playerName == name then
						runner.sendChatMessage(`{name} no longer command permissions`);
						table.remove(permissions, i);
						break;
					end;
				end;
			elseif type == "list" then
				local allPermittedUsers = {} :: {string}
				for i, v in permissions do
					table.insert(
						allPermittedUsers, v.playerName
					);
				end;
				runner.sendChatMessage(table.concat(allPermittedUsers, ", "));
			end;

		end;
		clientLocked = true;
	};

	--//print
	command.new {
		name = "print";
		callback = function(self, source, ...)
			print(...);
		end;
	};

	--//humanoid
	command.new {
		name = "hum/humanoid/char/character";
		callback = function(self, source, property: string, value: any)
			LocalPlayer.Character.Humanoid[property] = value;
		end;
	};
	--//humanoid methods
	command.new {
		name = "humanoidmethod";
		callback = function(self, source, property: string, ...)
			local humanoid = LocalPlayer.Character.Humanoid; 
			humanoid[property](humanoid, ...);
		end;
	};

	--//takedamage
	command.new {
		name = "damage/takedamage";
		callback = function(self, source, damage: number)
			LocalPlayer.Character.Humanoid:TakeDamage(damage); 
		end;
	};

	--//tp/goto
	command.new {
		name = "goto/teleport";
		callback = function(self, source, target: Player, offset: Vector3?)
			local targetChar = target.Character;
			LocalPlayer.Character:PivotTo(targetChar:GetPivot() * CFrame.new(offset or Vector3.zero));
		end;
	};

	--//skid fling
	command.new {
		name = "fl/kill/fling/sfling/skidfling";
		callback = function(self, source, TargetPlayer: Player)
			local Character = LocalPlayer.Character
			local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
			local RootPart = Humanoid and Humanoid.RootPart

			local TCharacter = TargetPlayer.Character
			local THumanoid
			local TRootPart
			local THead
			local Accessory
			local Handle

			if TCharacter:FindFirstChildOfClass("Humanoid") then
				THumanoid = TCharacter:FindFirstChildOfClass("Humanoid")
			end
			if THumanoid and THumanoid.RootPart then
				TRootPart = THumanoid.RootPart
			end
			if TCharacter:FindFirstChild("Head") then
				THead = TCharacter.Head
			end
			if TCharacter:FindFirstChildOfClass("Accessory") then
				Accessory = TCharacter:FindFirstChildOfClass("Accessory")
			end
			if Accessoy and Accessory:FindFirstChild("Handle") then
				Handle = Accessory.Handle
			end

			if Character and Humanoid and RootPart then
				if RootPart.AssemblyLinearVelocity.Magnitude < 50 then
					getgenv().OldPos = RootPart.CFrame
				end
				if THumanoid and THumanoid.Sit and not AllBool then
					return
				end
				if THead then
					workspace.CurrentCamera.CameraSubject = THead
				elseif not THead and Handle then
					workspace.CurrentCamera.CameraSubject = Handle
				elseif THumanoid and TRootPart then
					workspace.CurrentCamera.CameraSubject = THumanoid
				end
				if not TCharacter:FindFirstChildWhichIsA("BasePart") then
					return
				end

				local FPos = function(BasePart, Pos, Ang)
					RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
					Character:PivotTo(CFrame.new(BasePart.Position) * Pos * Ang)
					RootPart.AssemblyLinearVelocity = Vector3.new(9e7, 9e7 * 10, 9e7)
					RootPart.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
				end

				local SFBasePart = function(BasePart)
					local TimeToWait = 2
					local Time = tick()
					local Angle = 0

					repeat
						if RootPart and THumanoid then
							if BasePart.Velocity.Magnitude < 50 then
								Angle = Angle + 100

								FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle),0 ,0))
								task.wait()

								FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(2.25, 1.5, -2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(-2.25, -1.5, 2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection,CFrame.Angles(math.rad(Angle), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection,CFrame.Angles(math.rad(Angle), 0, 0))
								task.wait()
							else
								FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, -1.5, -THumanoid.WalkSpeed), CFrame.Angles(0, 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, 1.5, TRootPart.Velocity.Magnitude / 1.25), CFrame.Angles(math.rad(90), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, -1.5, -TRootPart.Velocity.Magnitude / 1.25), CFrame.Angles(0, 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, 1.5, TRootPart.Velocity.Magnitude / 1.25), CFrame.Angles(math.rad(90), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, -1.5 ,0), CFrame.Angles(math.rad(-90), 0, 0))
								task.wait()

								FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
								task.wait()
							end
						else
							break
						end
					until BasePart.Velocity.Magnitude > 500 or BasePart.Parent ~= TargetPlayer.Character or TargetPlayer.Parent ~= Players or TargetPlayer.Character ~= TCharacter or THumanoid.Sit or Humanoid.Health <= 0 or tick() > Time + TimeToWait
				end

				workspace.FallenPartsDestroyHeight = 0/0

				Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

				if TRootPart and THead then
					if (TRootPart.CFrame.p - THead.CFrame.p).Magnitude > 5 then
						SFBasePart(THead)
					else
						SFBasePart(TRootPart)
					end
				elseif TRootPart and not THead then
					SFBasePart(TRootPart)
				elseif not TRootPart and THead then
					SFBasePart(THead)
				elseif not TRootPart and not THead and Accessory and Handle then
					SFBasePart(Handle)
				end

				Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
				workspace.CurrentCamera.CameraSubject = Humanoid

				repeat
					RootPart.CFrame = getgenv().OldPos * CFrame.new(0, .5, 0)
					Character:PivotTo(getgenv().OldPos * CFrame.new(0, .5, 0))
					Humanoid:ChangeState("GettingUp")

					for i, x in Character:GetChildren() do
						if x:IsA("BasePart") then
							x.AssemblyLinearVelocity, x.AssemblyAngularVelocity = Vector3.new(), Vector3.new()
						end
					end
					task.wait()
				until (RootPart.Position - getgenv().OldPos.p).Magnitude < 25
				workspace.FallenPartsDestroyHeight = getgenv().FPDH
			end
		end;
	};

	--//chat/say
	command.new {
		name = "say/chat";
		callback = function(self, source, ...)
			local t = table.pack(...);
			for i, v in t do
				if typeof(v) == "Instance" then
					if v:IsA("Player") then
						t[i] = v.Name;
					else
						t[i] = (`instance({v.Name})`);
					end;
				elseif typeof(v) == "Vector3" then
					t[i] = `vector3({v.X}, {v.Y}, {v.Z})`;
				end;
			end;
			TextChatService.TextChannels.RBXGeneral:SendAsync(
				table.concat(t, " ")
			);
		end;
	};

	--//GLOBAL chat/say [[not working rn lmao idk what to do for ts]]
	command.new {
		name = "globalsay/globalchat/gsay/gchat";
		callback = function(self, source, ...)
			local t = table.pack(...);
			for i, v in t do
				if typeof(v) == "Instance" then
					if v:IsA("Player") then
						t[i] = v.Name;
					else
						t[i] = (`instance({v.Name})`);
					end;
				elseif typeof(v) == "Vector3" then
					t[i] = `vector3({v.X}, {v.Y}, {v.Z})`;
				else
					warn("Couldnt say type " .. typeof(v));
				end;
			end;
			-- TextChatService.TextChannels.RBXGeneral:SendAsync(
			-- 	table.concat(t, " ")
			-- );
		end;
	};

	--//mock
	command.new {
		name = "mock/copy";
		callback = function(self, source, toCopy: Player)
			self.con = TextChatService.MessageReceived:Connect(function(tcm: TextChatMessage)
				if tcm.Status ~= Enum.TextChatMessageStatus.Success then return; end;
				if not tcm.TextSource then return; end;
				if tcm.TextSource.UserId ~= toCopy.UserId then return; end;

				runner.sendChatMessage(tcm.Text);
			end)
		end;
		cleanup = function(self, source)
			if self.con then self.con:Disconnect(); end;
		end;
	};

	--//follow/chase
	command.new {
		name = "follow/chase";
		callback = function(self, source, targetPlayer: Player, offset: Vector3?)
			while task.wait(0.1) do
				local localCharacter = LocalPlayer.Character;
				local targetCharacter = targetPlayer.Character;

				if not (localCharacter and targetCharacter) then continue; end;
				if not (localCharacter.HumanoidRootPart and targetCharacter.HumanoidRootPart) then continue; end;

				local curPv = localCharacter.HumanoidRootPart.CFrame;
				local targetPv = targetCharacter.HumanoidRootPart.CFrame;

				local MoveToCf = (targetPv * CFrame.new(offset or Vector3.zero));

				local distance = (curPv.Position - MoveToCf.Position).Magnitude;

				if (distance > 30) or (distance < 1.5) then
					localCharacter.HumanoidRootPart.CFrame = MoveToCf;
					continue;
				end;

				if (curPv.Y+4 < targetPv.Y) and (distance > 5) then
					localCharacter.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping);
				end;

				local MoveTo = MoveToCf.Position
				localCharacter.Humanoid:MoveTo(
					MoveTo
				);
			end;
		end;
	};

	--//freeze
	command.new {
		name = "freeze/anchor";
		callback = function(self, source, targetPlayer: Player)
			local localCharacter = LocalPlayer.Character;
			for i, v in localCharacter:QueryDescendants("BasePart") do
				v.Anchored = true;
			end;
		end;
	};

	--//unfreeze
	command.new {
		name = "unfreeze/thaw/unanchor";
		callback = function(self, source, targetPlayer: Player)
			local localCharacter = LocalPlayer.Character;
			for i, v in localCharacter:QueryDescendants("BasePart") do
				v.Anchored = false;
			end;
		end;
	};

    --//carpet
	command.new {
		name = "platform/float/carpet";
		callback = function(self, source, targetPlayer: Player)
			while task.wait() do
				local localChar = LocalPlayer.Character;
				local targetChar = targetPlayer.Character;

				if not localChar or not targetChar then continue end;

				localChar:PivotTo(targetChar:GetPivot() * CFrame.new(0, -2, 0) * CFrame.fromOrientation(math.rad(90), 0, 0))
			end;
		end;
	};

	--//prefix
	command.new {
		name = "prefix/setprefix";
		callback = function(self, source, newPrefix: string)
			if #newPrefix > 1 then runner.sendChatMessage("prefix is more than 1 char"); return; end;
			tokenizer.commandPrefix = newPrefix;
			runner.sendChatMessage(`set prefix to {newPrefix}`);
		end;
	};

	--//output
	command.new {
		name = "output";
		args = "bool";
		callback = function(self, source, enabling)
			_G.doOutput = (enabling == true);
		end;
	};

	--//config [unfinished]
	command.new {
		name = "config";
		args = "";
		callback = function(self, source, type: "save" | "load" , configName: string)
			if not configName then configName = "default"; end;

		end;
	};
}, {
	__index = {
		findFromName = function(name)
			name = name:lower();

			for i, v in commands do
				local commandName = v.name;
				if name == commandName:lower() then return v; end;

				for _, subName in commandName:split("/") do
					if subName:lower() == name then return v; end;
				end;
			end;
			return nil;
		end;
	};
});

local retardedPhrases = {
	["autobots roll out"] = "beep boop bip bop bip boop";
	["kitten"] = "yes dada";
}

--// for glb:directory, its like a global for code
local nameInstanceMap = {
	["game"] = game;
	["workspace"] = workspace;
};

tokenizer = {
	commandPrefix = "*"; -- self explanatory
	commandNameEnd = ';'; -- to stop the command name and start the arguments (or just to stop it i guess)

	--[[ special globals so you can do like
		"*say; position" and it says the vector3 character position
		you can also do obj:game.Players.LocalPlayer.Character.HumanoidRootPart.Position
			but that shit is too much work
	]]
	specialGlobals = {
		position = function(self, source)
			return math.round(
				LocalPlayer.Character:GetPivot().Position
			*10)/10
		end;
	};

	typeConverters = {
		-- player name selector
		player = function(source: Player, name: string): Player?
			local allPlayers = game:GetService("Players"):GetPlayers()
			if name == "$random" then
				local randomPlayer;

				if #allPlayers == 1 then return end;

				while not randomPlayer or (randomPlayer == source) or (permissions.getPlayerPermissions(randomPlayer)) do
					randomPlayer = allPlayers[math.random(1, #allPlayers)]
				end;

				return randomPlayer;
			elseif name == "$me" then
				return source;
			elseif name == "$client" or name == "$self" then
				return LocalPlayer;
			elseif name == "$n" or name == "$near" then
				local nearestPlayer, dst = nil, math.huge;
				
				for i, v in Players:GetPlayers() do
					if v == LocalPlayer then continue; end;
					local c = v.Character;
					if not c then continue; end;

					local thisDistance = (LocalPlayer.Character:GetPivot().Position - c:GetPivot().Position).Magnitude

					if thisDistance < dst then
						nearestPlayer, dst = v, thisDistance;
					end;
				end;

				return nearestPlayer;
			end;

			for i, v in allPlayers do
				if v.Name:lower() == name:lower() then
					return v;
				end;
			end;
			return;
		end;
		-- player display selector
		playerd = function(source: Player, displayName: string): Player?
			for i, v in game:GetService("Players"):GetPlayers() do
				if v.DisplayName:lower() == displayName:lower() then
					return v;
				end;
			end;
			return;
		end;
		-- a mix of player & playerd
		autop = function(source: Player, user: string): Player?
			local players = game:GetService("Players"):GetPlayers();
			for i, v in players do
				for char=1, #v.Name do
					if user == v.Name:sub(1, char) then
						return v;
					end;
				end;

				for char=1, #v.DisplayName do
					if user == v.DisplayName:sub(1, char) then
						return v;
					end;
				end;
			end;
			return;
		end;
		--// "vec3:x,y,z -> Vector3.new(x,y,z)"
		vec3 = function(source: Player, vec3: string): Vector3?
			if vec3 == "$random" then

			end;
			local coordinates = vec3:gsub(" ", ""):split(',');
			return Vector3.new(
				coordinates[1],
				coordinates[2],
				coordinates[3]
			);
		end;

		-- just rounds a number
		int = function(source: Player, toInt: string): number?
			local integer = tonumber(toInt)
			if integer then
				integer = math.round(integer);
			end;
			return;
		end;

		-- just a number idk why this shit exists
		float = function(source: Player, toFloat: string): number?
			local float = tonumber(toFloat)
			return float;
		end;

		-- full enum directories/search
		enum = function(source: Player, enumDirectory: string)
			local arg = enumDirectory:split('.')
			return Enum[arg[1]][arg[2]];
		end;
		-- boolean ("true" -> true)
		bool = function(source: Player, str: string): number?
			local value;
			value = if str=="true" then true elseif str=="false" then false else nil;
			return value;
		end;
		--globals so you can save and load shit
		glb = function(source: Player, global: string): number?
			return _G[global];
		end;
		
		--/ instance dir (only supports reading instance and property of instance and no method retrieving)
		obj = function(source: Player, directory: string): number?
			local it = nil;

			for id, name in directory:split(".") do
				if not it then it = nameInstanceMap[name]; continue; end;
				it = it[name]
				if it then continue; end;
				warn(`obj: couldnt find {name} of {it and it.Name}`)
			end;

			return it;
		end;
	};

	-- instantiate the type:value into the actual thingy
	typeConvertString = function(source: Player, str: string): any?
		local tokens = str:split(':');

		local type = tokens[1];
		local rawValue = tokens[2];

		local value;
		for i, v in tokenizer.typeConverters do
			if i == type then
				value = v(source, rawValue);
				break;
			end;
		end;
		return value;
	end;


	tokenize = function(source: Player, rawCommandStr: string) 
		local tokenized = {
			modifiers = {};
			prefix = nil;
			command = nil;
			arguments = {};
		};

		local prefixStart, prefixEnd = rawCommandStr:find(tokenizer.commandPrefix);
		if not prefixStart then return end;

		do -- modifiers ( 	[something, something2] 	)
			local endBracketStart = rawCommandStr:find("]")
			if rawCommandStr:sub(1,1) == "[" and endBracketStart then
				local modifiers = rawCommandStr:sub(2, endBracketStart-1):gsub("%s+", ''):split(',')
				if #modifiers == 0 then
					table.insert(tokenized.modifiers, rawCommandStr:sub(2, endBracketStart-1))
				end;
				for i, v in modifiers do
					table.insert(tokenized.modifiers, v);
				end;
			end;
		end;

		--// char argument start: "*command>>;<<" to indicate the start of the argument passing
		local cArgStart, cArgEnd = rawCommandStr:find(tokenizer.commandNameEnd);

		tokenized.prefix = rawCommandStr:sub(prefixStart, prefixEnd);
		tokenized.command = rawCommandStr:sub(prefixEnd+1, cArgStart and cArgStart-1);

		if cArgStart then -- arguments
			local argumentSearch = rawCommandStr:gsub("%s+", " "):sub(cArgStart and (cArgEnd + 1), #rawCommandStr);
			do	-- clear the empty characters at start after the end of the command name
				while argumentSearch:sub(1, 1) == " " do
					argumentSearch = argumentSearch:sub(2, #argumentSearch);
				end;
			end;

			local characters = argumentSearch:split("")

			local lastSpaceIndex, spaceDb = 0, false;
			local lastQuoteIndex, insideQuote = 0, false;
			--[[
				i definitely over complicated the fuck out of this shit lmaooo
			]]
			for index, char in characters do
				local isStartOfString = index == 1;
				local isEndOfString = index == #characters;
				if char == `'` then
					insideQuote = not insideQuote;

					if not insideQuote then
						-- *say; 'hello is my' name even 'bob bro'
						local text = argumentSearch:sub(lastQuoteIndex + 1, index-1);
						table.insert(tokenized.arguments, text)
						warn("inserted text from quote: " .. text)
					end;
					lastQuoteIndex = index;
					lastSpaceIndex = index+1;
				end;
				if insideQuote then print("inside quote"); continue; end;
				if char == " " or index==#characters then 
					local text = argumentSearch:sub(lastSpaceIndex+1, isEndOfString and index or index-1)
					if text == "" then continue; end;
					warn("space text: " .. text)
					table.insert(tokenized.arguments, tokenizer.typeConvertString(source, text) or text)
					lastSpaceIndex = index;	
				end;
				
			end;
			
		end;

		print("finished command tokenization: result:");
		warn(tokenized);

		return tokenized;
	end;
}

runner = {

	commandChainingChar = '&amp;';
	specialArgChar = "$";

	ranCommandLog = {}; --// logs the commands you run (not doing shit rn)

	sendChatMessage = function(rawText)
		warn("Chat message sending: \n	"..rawText)
		TextChatService.TextChannels.RBXGeneral:SendAsync(rawText);
	end;

	executeCommandFromRaw = function(source, player, text)
		local tokenizedCommand = tokenizer.tokenize(player, text);
		if not tokenizedCommand then return; end; --// not trying to run a command

		if not permissions.getPlayerPermissions(source) then return end;

		local foundCommand = commands.findFromName(tokenizedCommand.command);
		if not foundCommand then
			runner.sendChatMessage(`unknown command "{tokenizedCommand.command}"`)
			return;
		end;


		-- table.insert(runner.ranCommandLog, tokenizedCommand);

		if tokenizedCommand.arguments[1] == "#stop" then
			foundCommand:closeActiveThread(source);
			return;
		end;

		local runs = true;
		for _, modifierStr in tokenizedCommand.modifiers do
			do
				local _, plrSpecifierEnd = modifierStr:find('p:');
				if not plrSpecifierEnd then continue end;
				local name = modifierStr:sub(plrSpecifierEnd+1, #modifierStr):lower();
				
				if name ~= LocalPlayer.Name:lower() then runs = false; return; end;
			end;
		end;

		if not runs then return end;

		--//needs fixing
		-- should yield until executed command finishes
		-- also probably errors i didnt test ts 
        if table.find(tokenizedCommand.modifiers, 'loop') then
            while foundCommand._alive and task.wait() do
                local success, error = foundCommand:execute(tokenizedCommand.modifiers, player, tokenizedCommand.arguments);
		        if not success then
                    warn(error)
                end
				foundCommand.onExecuted:Wait();
				task.wait();
            end;
        end;
		

		local success, error = foundCommand:execute(tokenizedCommand.modifiers, player, tokenizedCommand.arguments);
		if not success then
			 warn(error); return;
		end;

		if not _G.doOutput then return; end;
		local toChatArgsRan = {};
		local toChatArgTypes = {};
		for i, v in tokenizedCommand.arguments do
			local _type = typeof(v);
			toChatArgsRan[i] = tostring(v)
			toChatArgTypes[i] = _type == "Instance" and v.ClassName or _type
		end;
		runner.sendChatMessage(
		`executed: {tokenizedCommand.command}<{table.concat(toChatArgTypes, ", ")}>({table.concat(toChatArgsRan, ", ")})`		
		)
	end;

	incomingMessage = function(messageObject: TextChatMessage)
		if messageObject.Status ~= Enum.TextChatMessageStatus.Success then return; end;

		local source = messageObject.TextSource;
		if not source then return end;

		local player = game:GetService("Players"):GetPlayerByUserId(source.UserId);
		if not player then return end;


		local text = messageObject.Text;

		for i, v in retardedPhrases do
			if text == i then
				runner.sendChatMessage(v);
			end; 
		end;

		local chained = text:split(runner.commandChainingChar);

		if chained then
			for i, v in chained do
				runner.executeCommandFromRaw(source, player, v);
			end;
			return;
		end;

		runner.executeCommandFromRaw(source, player, text);
	end;
}

-- this prevents it from COMPLETELY exploding if you run it multiple times
if _G.msgRcCon then _G.msgRcCon:Disconnect() end;
_G.msgRcCon = TextChatService.MessageReceived:Connect(runner.incomingMessage);

task.wait(math.random()*2) --[[
	^^ this is required so that if there's multiple bots at once,
		it doesnt lag behind from multiple messages being sent at the same time
		appearing like there was not a chat from one or more
]]
runner.sendChatMessage "loaded"
-- ^^ notifies you when it's finished loading in chat
-- you could remove this its not relevant most of the time

task.spawn(function()
	-- anti afk shit cause im NOT fucking make that bro
	-- this shit doesnt even work either so wtv
	loadstring(game:HttpGet("https://raw.githubusercontent.com/juywvm/-Roblox-Projects-/main/____Anti_Afk_Remastered_______"))()
end)

return {
	["command"] = command;
	["commands"] = commands;

	['permission'] = permission;
	['permissions'] = permissions;

	['tokenizer'] = tokenizer;
	['runner'] = runner;
}
