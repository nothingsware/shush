--> [[ Load Services ]] <--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--> [[ Variables ]] <--

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

local Dependencies = {
    Variables = {
        UpVector = Vector3.new(0, 500, 0),
        RaycastParams = RaycastParams.new(),
        Path = PathfindingService:CreatePath({ WaypointSpacing = 3 }),
        PlayerSpeed = 50, -- Reduced speed to avoid anti-cheat
        VehicleSpeed = 150, -- Reduced speed to avoid anti-cheat
        Teleporting = false,
        StopVelocity = false
    },
    Modules = {
        UI = require(ReplicatedStorage.Module.UI),
        Store = require(ReplicatedStorage.App.store),
        PlayerUtils = require(ReplicatedStorage.Game.PlayerUtils),
        VehicleData = require(ReplicatedStorage.Game.Garage.VehicleData),
        CharacterUtil = require(ReplicatedStorage.Game.CharacterUtil),
        Paraglide = require(ReplicatedStorage.Game.Paraglide)
    },
    Helicopters = { Heli = true }, -- Helicopters
    Motorcycles = { Volt = true }, -- Motorcycles
    FreeVehicles = { Camaro = true }, -- Free vehicles
    UnsupportedVehicles = { SWATVan = true }, -- Unsupported vehicles
    DoorPositions = {} -- Positions near doors with no collision above
}

local Movement = {}
local Utilities = {}

--> [[ Utility Functions ]] <--

-- Toggle door collision
function Utilities:ToggleDoorCollision(door, toggle)
    for _, child in pairs(door.Model:GetChildren()) do
        if child:IsA("BasePart") then
            child.CanCollide = toggle
        end
    end
end

-- Get the nearest vehicle that can be entered
function Utilities:GetNearestVehicle(tried)
    local nearest
    local distance = math.huge

    for _, action in pairs(Dependencies.Modules.UI.CircleAction.Specs) do
        if action.IsVehicle and action.ShouldAllowEntry and action.Enabled and action.Name == "Enter Driver" then
            local vehicle = action.ValidRoot

            if not table.find(tried, vehicle) and workspace.VehicleSpawns:FindFirstChild(vehicle.Name) then
                if not Dependencies.UnsupportedVehicles[vehicle.Name] and
                    (Dependencies.Modules.Store._state.garageOwned.Vehicles[vehicle.Name] or Dependencies.FreeVehicles[vehicle.Name]) and
                    not vehicle.Seat.Player.Value then
                    if not workspace:Raycast(vehicle.Seat.Position, Dependencies.Variables.UpVector, Dependencies.Variables.RaycastParams) then
                        local magnitude = (vehicle.Seat.Position - HumanoidRootPart.Position).Magnitude

                        if magnitude < distance then
                            distance = magnitude
                            nearest = action
                        end
                    end
                end
            end
        end
    end

    return nearest
end

--> [[ Movement Functions ]] <--

-- Pathfind to a position with no collision above
function Movement:Pathfind(tried)
    local distance = math.huge
    local nearest

    tried = tried or {}

    for _, value in pairs(Dependencies.DoorPositions) do
        if not table.find(tried, value) then
            local magnitude = (value.position - HumanoidRootPart.Position).Magnitude

            if magnitude < distance then
                distance = magnitude
                nearest = value
            end
        end
    end

    table.insert(tried, nearest)

    Utilities:ToggleDoorCollision(nearest.instance, false)

    local path = Dependencies.Variables.Path
    path:ComputeAsync(HumanoidRootPart.Position, nearest.position)

    if path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()

        for _, waypoint in pairs(waypoints) do
            HumanoidRootPart.CFrame = CFrame.new(waypoint.Position + Vector3.new(0, 2.5, 0))

            if not workspace:Raycast(HumanoidRootPart.Position, Dependencies.Variables.UpVector, Dependencies.Variables.RaycastParams) then
                Utilities:ToggleDoorCollision(nearest.instance, true)
                return
            end

            task.wait(0.1) -- Slower movement to avoid anti-cheat
        end
    end

    Utilities:ToggleDoorCollision(nearest.instance, true)
    Movement:Pathfind(tried)
end

-- Move to a position smoothly
function Movement:MoveToPosition(part, cframe, speed, car, targetVehicle, triedVehicles)
    local vectorPosition = cframe.Position

    if not car and workspace:Raycast(part.Position, Dependencies.Variables.UpVector, Dependencies.Variables.RaycastParams) then
        Movement:Pathfind()
        task.wait(0.5)
    end

    local yLevel = 500
    local higherPosition = Vector3.new(vectorPosition.X, yLevel, vectorPosition.Z)

    repeat
        local velocityUnit = (higherPosition - part.Position).Unit * speed
        part.Velocity = Vector3.new(velocityUnit.X, 0, velocityUnit.Z)

        task.wait(0.1) -- Slower movement to avoid anti-cheat

        part.CFrame = CFrame.new(part.CFrame.X, yLevel, part.CFrame.Z)

        if targetVehicle and targetVehicle.Seat.Player.Value then
            table.insert(triedVehicles, targetVehicle)
            local nearestVehicle = Utilities:GetNearestVehicle(triedVehicles)
            local vehicleObject = nearestVehicle and nearestVehicle.ValidRoot

            if vehicleObject then
                Movement:MoveToPosition(HumanoidRootPart, vehicleObject.Seat.CFrame, Dependencies.Variables.PlayerSpeed, false, vehicleObject)
            end

            return
        end
    until (part.Position - higherPosition).Magnitude < 10

    part.CFrame = CFrame.new(part.Position.X, vectorPosition.Y, part.Position.Z)
    part.Velocity = Vector3.zero
end

--> [[ Raycast Filter Setup ]] <--

Dependencies.Variables.RaycastParams.FilterType = Enum.RaycastFilterType.Blacklist
Dependencies.Variables.RaycastParams.FilterDescendantsInstances = { Character, workspace.Vehicles, workspace:FindFirstChild("Rain") }

workspace.ChildAdded:Connect(function(child)
    if child.Name == "Rain" then
        table.insert(Dependencies.Variables.RaycastParams.FilterDescendantsInstances, child)
    end
end)

Player.CharacterAdded:Connect(function(character)
    table.insert(Dependencies.Variables.RaycastParams.FilterDescendantsInstances, character)
end)

--> [[ Main Teleport Function ]] <--

local function Teleport(cframe, tried)
    local relativePosition = (cframe.Position - HumanoidRootPart.Position)
    local targetDistance = relativePosition.Magnitude

    if targetDistance <= 20 and not workspace:Raycast(HumanoidRootPart.Position, relativePosition.Unit * targetDistance, Dependencies.Variables.RaycastParams) then
        HumanoidRootPart.CFrame = cframe
        return
    end

    tried = tried or {}
    local nearestVehicle = Utilities:GetNearestVehicle(tried)
    local vehicleObject = nearestVehicle and nearestVehicle.ValidRoot

    Dependencies.Variables.Teleporting = true

    if vehicleObject then
        local vehicleDistance = (vehicleObject.Seat.Position - HumanoidRootPart.Position).Magnitude

        if targetDistance < vehicleDistance then
            Movement:MoveToPosition(HumanoidRootPart, cframe, Dependencies.Variables.PlayerSpeed)
        else
            if vehicleObject.Seat.PlayerName.Value ~= Player.Name then
                Movement:MoveToPosition(HumanoidRootPart, vehicleObject.Seat.CFrame, Dependencies.Variables.PlayerSpeed, false, vehicleObject, tried)

                Dependencies.Variables.StopVelocity = true

                local enterAttempts = 1

                repeat
                    nearestVehicle:Callback(true)
                    enterAttempts = enterAttempts + 1
                    task.wait(0.1)
                until enterAttempts == 10 or vehicleObject.Seat.PlayerName.Value == Player.Name

                Dependencies.Variables.StopVelocity = false

                if vehicleObject.Seat.PlayerName.Value ~= Player.Name then
                    table.insert(tried, vehicleObject)
                    return Teleport(cframe, tried)
                end
            end

            Movement:MoveToPosition(vehicleObject.Engine, cframe, Dependencies.Variables.VehicleSpeed, true)

            repeat
                task.wait(0.15)
                Dependencies.Modules.CharacterUtil.OnJump()
            until vehicleObject.Seat.PlayerName.Value ~= Player.Name
        end
    else
        Movement:MoveToPosition(HumanoidRootPart, cframe, Dependencies.Variables.PlayerSpeed)
    end

    task.wait(0.5)
    Dependencies.Variables.Teleporting = false
end

return Teleport
