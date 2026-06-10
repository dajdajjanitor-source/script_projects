--!nocheck
local s = DateTime.now().UnixTimestampMillis;

local running = ((getgenv and getgenv()) or _G).cmdRunner == true;
if running then
    return;
end;

local _metadata = {
    ['_VERSION'] = {1, 0};
}

local CoreGuiConfiguration = game:GetService("CoreGuiConfiguration")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService");

local LocalPlayer = Players.LocalPlayer;
--//preallocate or sum shit wtv u call it for the stuff so you can call it globally while having optimizations
local runner;
local permissions;

--// object --------- on execution passes: self:command, source:player, ...:any (the args)
local command = {} do
    function command.new(commandInfo)
	    local self = setmetatable({}, {__index = command});
        self.name = commandInfo.name;
        self.callback = commandInfo.callback;
        self.cleanup = commandInfo.cleanup;
        self.clientLocked = commandInfo.clientLocked;

        self._activeThread = nil;

        return self;
    end;

    function command:execute(modifiers: {string}, source: Player, args: {[number]: any})
        print("executing command")

        self:closeActiveThread();
        local perms = permissions.getPlayerPermissions(source);
        if not perms then warn("invalid permissions"); return; end;

        local thread = task.spawn(
            self.callback, self, source, table.unpack(args)
        )

        self._activeThread = thread;
    end;

    function command:closeActiveThread()
        if not self._activeThread then return; end;
        coroutine.close(self._activeThread);
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

--// array of player permission objects who can execute non client locked commands
permissions = setmetatable({
    permission.new(game:GetService("Players").LocalPlayer.Name, true);
    permission.new("vvhereelse", true);
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
    }
})

local commands;

commands = setmetatable({
    --//help
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
                if pageCharSize > 50 then
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

    --//permission
    command.new {
        name = "perms/permission/permissions";
        callback = function(self, source: Player, giving: boolean, name: string)
            if giving then
                local perms = permission.new(name, false);
                table.insert(permissions, perms);

                runner.sendChatMessage(`{name} now has command permissions`)
                return;
            end;
            for i, v in permissions do
                if v.playerName == name then
                    runner.sendChatMessage(`{name} no longer command permissions`)
                    table.remove(permissions, i);
                    break;
                end;
            end;
        end;
        cleanup = function()

        end;
    };

    --//print
    command.new {
        name = "print";
        callback = function(self, source, ...)
            print(...);
        end;
        cleanup = function(self, source, ...)


        end;
    };

    --//takedamage
    command.new {
        name = "damage/takedamage";
        callback = function(self, source, damage: number)
            pcall(function(...)
                game.Players.LocalPlayer.Character.Humanoid:TakeDamage(damage); 
            end)
        end;
        cleanup = function(self, source, ...)


        end;
    };

    --//tp
    command.new {
        name = "goto/teleport";
        callback = function(self, source, target: Player)
            pcall(function(...)
                local targetChar = target.Character;
                game.Players.LocalPlayer.Character:PivotTo(targetChar:GetPivot());
            end)
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
                if RootPart.Velocity.Magnitude < 50 then
                    getgenv().OldPos = RootPart.CFrame
                end
                if THumanoid and THumanoid.Sit and not AllBool then
                    return Message("Error Occurred", "Targeting is sitting", 5) -- u can remove dis part if u want lol
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
                    Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
                    RootPart.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
                    RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
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
								x.Velocity, x.RotVelocity = Vector3.new(), Vector3.new()
							end
						end
                    task.wait()
                until (RootPart.Position - getgenv().OldPos.p).Magnitude < 25
                    workspace.FallenPartsDestroyHeight = getgenv().FPDH
            end
        end;
    };

    --//chat
    command.new {
        name = "say/chat";
        callback = function(self, source, ...)
            TextChatService.TextChannels.RBXGeneral:SendAsync(
                table.concat(table.pack(...), " ")
            );
        end;
    };

    --//spam
    command.new {
        name = "spam/spammer";
        callback = function(self, source, delay, ...)
            while task.wait(delay) do
                runner.sendChatMessage(table.concat(table.pack(...), ' '));
            end;
        end;
    };

    --//follow
    command.new {
        name = "follow/chase";
        callback = function(self, source, targetPlayer: Player)
            while task.wait(0.1) do
                local localCharacter = LocalPlayer.Character;
                local targetCharacter = targetPlayer.Character;

                localCharacter.Humanoid:MoveTo(targetCharacter.HumanoidRootPart.Position)
            end;
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

runner = {

    commandPrefix = "*";
    commandNameEnd = ';';

    ranCommandLog = {}; --// logs the commands you run

    typeConverters = {
        player = function(source: Player, name: string): Player?
            local allPlayers = game:GetService("Players"):GetPlayers()

            if name == "_random" then
                local randomPlayer;

                if #allPlayers == 1 then return end;
                
                while not randomPlayer or (randomPlayer == source) do
                    randomPlayer = allPlayers[math.random(1, #allPlayers)]
                end;

                return randomPlayer;
            end;

            for i, v in allPlayers do
                if v.Name:lower() == name:lower() then
                    return v;
                end;
            end;
            return;
        end;
        playerd = function(source: Player, displayName: string): Player?
            for i, v in game:GetService("Players"):GetPlayers() do
                if v.DisplayName:lower() == displayName:lower() then
                    return v;
                end;
            end;
            return;
        end;
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
        --// "vec3:0,0,0"
        vec3 = function(source: Player, vec3: string): Vector3?
            local coordinates = vec3:gsub(" ", ""):split(',');
            return Vector3.new(
                coordinates[1],
                coordinates[2],
                coordinates[3]
            );
        end;

        int = function(source: Player, toInt: string): number?
            local integer = tonumber(toInt)
            if integer then
                integer = math.round(integer);
            end;
            return;
        end;

        float = function(source: Player, toFloat: string): number?
            local float = tonumber(toFloat)
            return float;
        end;
    };

    typeConvertString = function(source: Player, str: string): any?
        local tokens = str:split(':');

        local type = tokens[1];
        local rawValue = tokens[2];

        local value;
        for i, v in runner.typeConverters do
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

        local prefixStart, prefixEnd = rawCommandStr:find(runner.commandPrefix);
        if not prefixStart then return end;

        --// char argument start: "*command>>;<<" to indicate the start of the argument passing
        local cArgStart, cArgEnd = rawCommandStr:find(runner.commandNameEnd);

        tokenized.prefix = rawCommandStr:sub(prefixStart, prefixEnd);
        tokenized.command = rawCommandStr:sub(prefixEnd+1, cArgStart and cArgStart-1);
        
        if cArgStart then
            local argumentSearch = rawCommandStr:sub(cArgStart and (cArgEnd + 1), #rawCommandStr);
            while argumentSearch:sub(1, 1) == " " do
                argumentSearch = argumentSearch:sub(2, #argumentSearch);
            end;
            for i, v in string.split(argumentSearch, ' ') do
                local rawArgString = v;
                tokenized.arguments[i] = runner.typeConvertString(source, rawArgString) or rawArgString;
            end;
        end;

        return tokenized
    end;

    sendChatMessage = function(rawText)
        TextChatService.TextChannels.RBXGeneral:SendAsync(rawText);
    end;

    incomingMessage = function(messageObject: TextChatMessage)
        if messageObject.Status ~= Enum.TextChatMessageStatus.Success then return; end;

        local source = messageObject.TextSource;
        if not source then return end;

        local player = game:GetService("Players"):GetPlayerByUserId(source.UserId);
		if not player then return end;

        local text = messageObject.Text;
        local tokenizedCommand = runner.tokenize(player, text);
        if not tokenizedCommand then return; end; --// not trying to run a command
        
        local foundCommand = commands.findFromName(tokenizedCommand.command);
        if not foundCommand then
            runner.sendChatMessage(`unknown command "{tokenizedCommand.command}"`)
            return;
        end;
    

        -- table.insert(runner.ranCommandLog, tokenizedCommand);

        if tokenizedCommand.arguments[1] == "#stop" then
            foundCommand:stop();
            return;
        end;

        foundCommand:execute(tokenizedCommand.modifiers, player, tokenizedCommand.arguments);

    end;
}

TextChatService.MessageReceived:Connect(runner.incomingMessage);

local loadTime = math.round(((DateTime.now().UnixTimestampMillis-s)/1000) * 100) / 100
runner.sendChatMessage(`loaded in {loadTime}s`)
