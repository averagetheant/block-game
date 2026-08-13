local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Loader = require(ReplicatedStorage.Packages.Loader)
local LoadOrdered = require(ReplicatedStorage.Shared.utils.LoadOrdered)

local ServerFeatures = ServerScriptService:WaitForChild("Features")

-- Only load modules whose name ends in "Service" — skips anything else
-- that might happen to live under a feature folder.
local modules = Loader.LoadDescendants(ServerFeatures, Loader.MatchesName("Service$"))
Loader.SpawnAll(LoadOrdered(modules), "Start")

-- Discover server-realm presentations — required for their side effect (they
-- self-register). No Start lifecycle; a feature adds one with no edit here.
--
-- Cmdr commands are NOT discovered from here: their definitions have to exist on
-- both realms or the client console won't accept the name, so they live in a
-- shared `Commands.luau` per feature that the Cmdr feature registers on each
-- realm. See src/features/Cmdr/CommandRegistry.luau.
Loader.LoadDescendants(ServerFeatures, Loader.MatchesName("Command$"))
