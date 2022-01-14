-- Set the 3D noise parameters for the terrain.

local np_terrain = {
	offset = 0,
	scale = 1,
	spread = {x = 384, y = 192, z = 384},
	seed = 5900033,
	octaves = 5,
	persist = 0.63,
	lacunarity = 2.0,
	--flags = ""
}

-- Filler depth is needed for biome generation
local np_filler_depth = {
	offset = 0,
	scale = 1.2,
	spread = {x=150, y=150, z=150},
	seed = 261,
	octaves = 3,
	persistence = 0.7,
	lacunarity = 2.0,
	flags = "eased",
}

-- Set singlenode mapgen (air nodes only).
-- Disable the engine lighting calculation since that will be done for a
-- mapchunk of air nodes and will be incorrect after we place nodes.

minetest.set_mapgen_params({mgname = "singlenode", flags = "nolight"})


-- Get the content IDs for the nodes used.

local c_stone = minetest.get_content_id("default:stone")
local c_water     = minetest.get_content_id("default:water_source")
local c_air = minetest.get_content_id("air")
local c_ignore = minetest.get_content_id("ignore")


-- Initialize noise object to nil. It will be created once only during the
-- generation of the first mapchunk, to minimise memory use.

local nobj_terrain = nil
local nobj_filler_depth = nil


-- Localise noise buffer table outside the loop, to be re-used for all
-- mapchunks, therefore minimising memory use.

local nvals_terrain = {}


-- Localise data buffer table outside the loop, to be re-used for all
-- mapchunks, therefore minimising memory use.

local data = {}


-- On generated function.

-- 'minp' and 'maxp' are the minimum and maximum positions of the mapchunk that
-- define the 3D volume.
minetest.register_on_generated(function(minp, maxp, seed)
	-- Start time of mapchunk generation.
	local t0 = os.clock()
	
	-- Noise stuff.

	-- Side length of mapchunk.
	local sidelen = maxp.x - minp.x + 1
	-- Required dimensions of the 3D noise perlin map.
	local permapdims3d = {x = sidelen, y = sidelen, z = sidelen}
	-- Same but allowing 1-node overgeneration up and down
	local permapdims3d_1u1d = {x = sidelen, y = sidelen+2, z = sidelen}
	-- Create the perlin map noise object once only, during the generation of
	-- the first mapchunk when 'nobj_terrain' is 'nil'.
	nobj_terrain = nobj_terrain or
		minetest.get_perlin_map(np_terrain, permapdims3d_1u1d)
	nobj_filler_depth = nobj_filler_depth or
		minetest.get_perlin_map(np_filler_depth, permapdims3d)
	-- Create a flat array of noise values from the perlin map, with the
	-- minimum point being 'minp'.
	-- Set the buffer parameter to use and reuse 'nvals_terrain' for this.
	nobj_terrain:get3dMap_flat({x=minp.x, y=minp.y-1, z=minp.z}, nvals_terrain)

	-- Voxelmanip stuff.

	-- Load the voxelmanip with the result of engine mapgen. Since 'singlenode'
	-- mapgen is used this will be a mapchunk of air nodes.
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	-- 'area' is used later to get the voxelmanip indexes for positions.
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	-- Get the content ID data from the voxelmanip in the form of a flat array.
	-- Set the buffer parameter to use and reuse 'data' for this.
	vm:get_data(data)

	-- Generation loop.

	-- Noise index for the flat array of noise values.
	local ni = 1
	-- Process the content IDs in 'data'.
	-- The most useful order is a ZYX loop because:
	-- 1. This matches the order of the 3D noise flat array.
	-- 2. This allows a simple +1 incrementing of the voxelmanip index along x
	-- rows.

	for z = minp.z, maxp.z do
	for y = minp.y-1, maxp.y+1 do
		-- Voxelmanip index for the flat array of content IDs.
		-- Initialise to first node in this x row.
		local vi = area:index(minp.x, y, z)
		for x = minp.x, maxp.x do
			local c = data[vi]
			if c == c_air or c == c_ignore then -- Do not replace existing solid nodes
				-- Consider a 'solidness' value for each node,
				-- let's call it 'density', where
				-- density = density noise + density gradient.
				local density_noise = nvals_terrain[ni]
				-- Density gradient is a value that is 0 at water level (y = 1)
				-- and falls in value with increasing y. This is necessary to
				-- create a 'world surface' with only solid nodes deep underground
				-- and only air high above water level.
				-- Here '128' determines the typical maximum height of the terrain.
				local density_gradient = (1 - y) / 128
				-- Place solid nodes when 'density' > 0.
				if density_noise + density_gradient > 0 then
					data[vi] = c_stone
				-- Otherwise if at or below water level place water.
				elseif y <= 1 then
					data[vi] = c_water
				end
			end

			-- Increment noise index.
			ni = ni + 1
			-- Increment voxelmanip index along x row.
			-- The voxelmanip index increases by 1 when
			-- moving by 1 node in the +x direction.
			vi = vi + 1
		end
	end
	end

	-- After processing, write content ID data back to the voxelmanip.
	vm:set_data(data)

	-- Generate biomes
	minetest.generate_biomes(vm, {x=minp.x, y=minp.y-1, z=minp.z}, maxp, nobj_filler_depth)

	-- Generate ores
	minetest.generate_ores(vm, minp, maxp)

	-- Generate decorations (plants...)
	minetest.generate_decorations(vm, minp, maxp)

	-- Calculate lighting for what has been created.
	vm:calc_lighting()
	-- Write what has been created to the world.
	vm:write_to_map()
	-- Liquid nodes were placed so set them flowing.
	vm:update_liquids()

	-- Print generation time of this mapchunk.
	local chugent = math.ceil((os.clock() - t0) * 1000)
	print ("[lvm_example] Mapchunk generation time " .. chugent .. " ms")
end)
