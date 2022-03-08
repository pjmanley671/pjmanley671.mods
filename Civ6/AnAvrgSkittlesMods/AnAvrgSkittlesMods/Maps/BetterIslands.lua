-- BetterIslands
-- Author: AnAvrgSkittle
-- DateCreated: 3/4/2022 1:57:50 PM
--------------------------------------------------------------
include "MapEnums"
include "MapUtilities"
include "MountainsCliffs"
include "RiversLakes"
include "FeatureGenerator"
include "TerrainGenerator"
include "NaturalWonderGenerator"
include "ResourceGenerator"
include "AssignStartingPlots"

-------------------------------------------------------------------------------
function GenerateMap()
	local pPlot;

	-- Set globals
	g_iW, g_iH = Map.GetGridSize();
	g_iFlags = TerrainBuilder.GetFractalFlags();
	local temperature = MapConfiguration.GetValue("temperature"); -- Default setting is Temperate.
	if temperature == 4 then
		temperature  =  1 + TerrainBuilder.GetRandomNumber(3, "Random Temperature- Lua");
	end

	plotTypes = GeneratePlotTypes();
	terrainTypes = GenerateTerrainTypes(plotTypes, g_iW, g_iH, g_iFlags, true, temperature);

	for i = 0, (g_iW * g_iH) - 1, 1 do
		pPlot = Map.GetPlotByIndex(i);
		if (plotTypes[i] == g_PLOT_TYPE_HILLS) then
			terrainTypes[i] = terrainTypes[i] + 1;
		end
		TerrainBuilder.SetTerrainType(pPlot, terrainTypes[i]);
	end

	-- Temp
	AreaBuilder.Recalculate();
	-- River generation is affected by plot types, originating from highlands and preferring to traverse lowlands.
	AddRivers();

	-- Lakes would interfere with rivers, causing them to stop and not reach the ocean, if placed any sooner.
	local numLargeLakes = math.ceil(GameInfo.Maps[Map.GetMapSize()].Continents / 2);
	AddLakes(numLargeLakes);

	AddFeatures();

	AddCliffs(plotTypes, terrainTypes);

	local args = { numberToPlace = GameInfo.Maps[Map.GetMapSize()].NumNaturalWonders };
	NaturalWonderGenerator.Create(args);

	AreaBuilder.Recalculate();
	TerrainBuilder.AnalyzeChokepoints();
	TerrainBuilder.StampContinents();

	local startConfig = MapConfiguration.GetValue("start");-- Get the start config
	local args = {
		iWaterLux = 4,
		resources = MapConfiguration.GetValue("resources"),
		START_CONFIG = startConfig
	};

	ResourceGenerator.Create(args);
	-- START_MIN_Y and START_MAX_Y is the percent of the map ignored for major civs' starting positions.

	local args = {
		MIN_MAJOR_CIV_FERTILITY = 50,
		MIN_MINOR_CIV_FERTILITY = 5,
		MIN_BARBARIAN_FERTILITY = 1,
		START_MIN_Y = 15,
		START_MAX_Y = 15,
		WATER = true,
		START_CONFIG = startConfig
	};
	AssignStartingPlots.Create(args)

	AddGoodies(g_iW, g_iH);
end

-------------------------------------------------------------------------------
function GeneratePlotTypes()
	print("Generating Plot Types");
	local plotTypes = {};
	local extra_mountains = 0;
	local grain_amount = 3;
	local adjust_plates = 1.0;
	local shift_plot_types = true;
	local tectonic_islands = true;
	local hills_ridge_flags = g_iFlags;
	local peaks_ridge_flags = g_iFlags;
	local has_center_rift = false;
	local sea_level = 1;
	local world_age = 1;

	local water_percent_modifier = 0;

	for x = 0, g_iW - 1 do
		for y = 0, g_iH - 1 do
			local index = (y * g_iW) + x + 1; -- Lua Array starts at 1
			plotTypes[index] = g_PLOT_TYPE_OCEAN;
		end
	end

	--	local sea_level
	local sea_level = MapConfiguration.GetValue("sea_level"); -- results expected 1, 2, 3
	if sea_level == nil then
		sea_level = 1 + TerrainBuilder.GetRandomNumber(3, "Random Sea Level - Lua");
	end

	water_percent_modifier = (sea_level - 2) * 4 -- {Values: -4=low, 0=normal, 4=high}

	--	local world_age
	local world_age = MapConfiguration.GetValue("world_age"); -- results expected 1, 2, 3
	if world_age == nil then
		world_age = 1 + TerrainBuilder.GetRandomNumber(3, "Random World Age - Lua");
	end

	world_age = 4 - world_age; -- {Values: 3=old, 2=normal, 1=new}

	-- Generate Medium Islands
	local args = {};
	args.iWaterPercent = 80 + water_percent_modifier;
	args.iRegionWidth = math.ceil(g_iW);
	args.iRegionHeight = math.ceil(g_iH);
	args.iRegionWestX = math.floor(0);
	args.iRegionSouthY = math.floor(0);
	args.iRegionGrain = 4;
	args.iRegionHillsGrain = 4;
	args.iRegionPlotFlags = g_iFlags;
	args.iRegionFracXExp = 7;
	args.iRegionFracYExp = 6;
	plotTypes = GenerateFractalLayerWithoutHills(args, plotTypes);
	islands = plotTypes;

	-- Generate Small Islands
	local args = {};
	args.iWaterPercent = 85 + water_percent_modifier;
	args.iRegionWidth = math.ceil(g_iW);
	args.iRegionHeight = math.ceil(g_iH);
	args.iRegionWestX = math.floor(0);
	args.iRegionSouthY = math.floor(0);
	args.iRegionGrain = 5;
	args.iRegionHillsGrain = 4;
	args.iRegionPlotFlags = g_iFlags;
	args.iRegionFracXExp = 7;
	args.iRegionFracYExp = 6;
	plotTypes = GenerateFractalLayerWithoutHills(args, plotTypes);
	islands = plotTypes;

	-- Land and water are set. Apply hills and mountains.
	local args = {};
	args.iW = g_iW;
	args.iH = g_iH
	args.iFlags = g_iFlags;
	args.blendRidge = 5;
	args.blendFract = 5;
	args.world_age = world_age + 0.25;
	mountainRatio = 4 + world_age * 2;
	plotTypes = ApplyTectonics(args, plotTypes);
	plotTypes = AddLonelyMountains(plotTypes, mountainRatio);

	return  plotTypes;
end
-------------------------------------------------------------------------------
function AddFeatures()
	print("Adding Features");

	-- Get Rainfall setting input by user.
	local rainfall = MapConfiguration.GetValue("rainfall");
	if rainfall == 4 then
		rainfall = 1 + TerrainBuilder.GetRandomNumber(3, "Random Rainfall - Lua");
	end

	local args = {rainfall = rainfall}
	local featuregen = FeatureGenerator.Create(args);

	featuregen:AddFeatures();
end


-------------------------------------------------------------------------------
function GenerateFractalLayerWithoutHills (args, plotTypes)
	--[[ This function is intended to be paired with ApplyTectonics. If all the hills and
	mountains plots are going to be overwritten by the tectonics results, then why waste
	calculations generating them? ]]--
	local args = args or {};
	local plotTypes2 = {};

	-- Handle args or assign defaults.
	local iWaterPercent = args.iWaterPercent or 55;
	local iRegionWidth = args.iRegionWidth; -- Mandatory Parameter, no default
	local iRegionHeight = args.iRegionHeight; -- Mandatory Parameter, no default
	local iRegionWestX = args.iRegionWestX; -- Mandatory Parameter, no default
	local iRegionSouthY = args.iRegionSouthY; -- Mandatory Parameter, no default
	local iRegionGrain = args.iRegionGrain or 1;
	local iRegionPlotFlags = args.iRegionPlotFlags or g_iFlags;
	local iRegionTerrainFlags = g_iFlags; -- Removed from args list.
	local iRegionFracXExp = args.iRegionFracXExp or 6;
	local iRegionFracYExp = args.iRegionFracYExp or 5;
	local iRiftGrain = args.iRiftGrain or -1;
	local bShift = args.bShift or true;

	--print("Received Region Data");
	--print(iRegionWidth, iRegionHeight, iRegionWestX, iRegionSouthY, iRegionGrain);
	--print("- - -");
	
	--print("Filled regional table.");
	-- Loop through the region's plots
	for x = 0, iRegionWidth - 1, 1 do
		for y = 0, iRegionHeight - 1, 1 do
			local i = y * iRegionWidth + x + 1; -- Lua arrays start at 1.
			plotTypes2[i] = g_PLOT_TYPE_OCEAN;
		end
	end

	-- Init the land/water fractal
	local regionContinentsFrac;
	if(iRiftGrain > 0 and iRiftGrain < 4) then
		local riftsFrac = Fractal.Create(g_iW, g_iH, rift_grain, {}, iRegionFracXExp, iRegionFracYExp);
		regionContinentsFrac = Fractal.CreateRifts(g_iW, g_iH, iRegionGrain, iRegionPlotFlags, riftsFrac, iRegionFracXExp, iRegionFracYExp);
	else
		regionContinentsFrac = Fractal.Create(g_iW, g_iH, iRegionGrain, iRegionPlotFlags, iRegionFracXExp, iRegionFracYExp);
	end
	--print("Initialized main fractal");
	local iWaterThreshold = regionContinentsFrac:GetHeight(iWaterPercent);

	-- Loop through the region's plots
	for x = 0, iRegionWidth - 1, 1 do
		for y = 0, iRegionHeight - 1, 1 do
			local i = y * iRegionWidth + x + 1; -- Lua arrays start at 1.
			local val = regionContinentsFrac:GetHeight(x,y);
			if val > iWaterThreshold and Adjacent(i) == false then plotTypes2[i] = g_PLOT_TYPE_LAND end
		end
	end

	if bShift then ShiftPlotTypes(plotTypes); end -- Shift plots to obtain a more natural shape.

	print("Shifted Plots - Width: ", iRegionWidth, "Height: ", iRegionHeight);

	-- Apply the region's plots to the global plot array.
	for x = 0, iRegionWidth - 1, 1 do
		local wholeworldX = x + iRegionWestX;
		for y = 0, iRegionHeight - 1, 1 do
			local index = y * iRegionWidth + x + 1
			if plotTypes2[index] ~= g_PLOT_TYPE_OCEAN then
				local wholeworldY = y + iRegionSouthY;
				local i = wholeworldY * g_iW + wholeworldX + 1
				plotTypes[i] = plotTypes2[index];
			end
		end
	end
	--print("Generated Plot Types");

	return plotTypes;
end

-------------------------------------------------------------------------------------------
function Adjacent(index)
	aIslands = islands;
	index = index -1;

	if(aIslands == nil) then return false; end
	if(index < 0) then return false; end

	local plot = Map.GetPlotByIndex(index);
	if(aIslands[index] ~= nil and aIslands[index] == g_PLOT_TYPE_LAND) then return true; end

	for direction = 0, DirectionTypes.NUM_DIRECTION_TYPES - 1, 1 do
		local adjacentPlot = Map.GetAdjacentPlot(plot:GetX(), plot:GetY(), direction);
		if(adjacentPlot ~= nil) then
			local newIndex = adjacentPlot:GetIndex();
			if(aIslands[newIndex] == g_PLOT_TYPE_LAND) then return true; end
		end
	end

	return false;
end