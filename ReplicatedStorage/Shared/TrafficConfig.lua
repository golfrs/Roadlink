-- Tuning values for the traffic simulation. Distances are studs, speeds studs/second.
local TrafficConfig = {}

TrafficConfig.DriveOnLeft = false -- false = vehicles keep to the right-hand side of the road

-- How many vehicles a city gets
TrafficConfig.MaxVehicles = 36
TrafficConfig.VehiclesPerPlace = 2 -- per connected building / road end
TrafficConfig.SpawnInterval = 0.35 -- seconds between spawn attempts

-- Road surface heights (must match WorldService road geometry)
TrafficConfig.RoadY = 0.3
TrafficConfig.BridgeY = 0.56
TrafficConfig.MaxJunctionInset = 3.9 -- lanes stop this far (max) from a junction centre

-- Driving behaviour (Intelligent Driver Model)
TrafficConfig.Speed = { Basic = 9, Highway = 14 }
TrafficConfig.LateralAccel = 5 -- limits speed on turns
TrafficConfig.MinTurnSpeed = 3.2
TrafficConfig.Accel = 4
TrafficConfig.ComfortDecel = 5
TrafficConfig.MaxDecel = 18
TrafficConfig.TimeHeadway = 0.9
TrafficConfig.MinGap = 1.3 -- bumper-to-bumper gap when queued
TrafficConfig.StopLineGap = 0.25
TrafficConfig.LookAhead = 45
TrafficConfig.SharedEntryLength = 3.5 -- distance into a junction where different turns still share space
TrafficConfig.CommitMargin = 3 -- extra distance before the stop line where drivers decide to go or stop

-- Safety nets
TrafficConfig.StuckTimeout = 45 -- a vehicle that cannot move for this long drives "home" (fades out)
TrafficConfig.FadeTime = 0.5
TrafficConfig.ConflictDistance = 2.3 -- two turning paths closer than this cannot share a junction

-- Traffic light timing (seconds)
TrafficConfig.Signal = { Green = 9, Yellow = 2.5, AllRed = 1.5 }

return TrafficConfig
