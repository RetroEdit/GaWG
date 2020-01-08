--[[
Author(s): RetroEdit

A position physics simulation script.

Currently, it's strongly tied to Fire, but it might be worthwhile to generalize.
--]]


-- I'm not sure I entirely like this, but I'll stick with it for now.
memory.usememorydomain("Combined WRAM")

local CHARACTER_START = 0x3bfd0
local NUM_CHARACTER_SLOTS = 7
local CHARACTER_SIZE = 0x7C

-- 'fc_' is short for 'Falling Character'
-- I may change/remove the prefix in the future,
-- once I switch to a generalized falling character format
-- (I may also make it more like OOP)

-- This seems off... maybe read_u16_be (?)
function fc_x(base_address)
    return bit.bor(bit.lshift(memory.read_u16_le(base_address + 0x10), 8), memory.readbyte(base_address + 0x13))
end

function fc_x_pixel(base_address)
    return memory.readbyte(base_address + 0x10)
end

function fc_y(base_address)
    return bit.bor(bit.lshift(memory.readbyte(base_address + 0x12), 8), memory.readbyte(base_address + 0x14))
end

function fc_y_pixel(base_address)
    return memory.readbyte(base_address + 0x12)
end

function fc_x_vel(base_address)
    return memory.read_s16_le(base_address + 0x28)
end

function fc_y_vel(base_address)
    return memory.read_s16_le(base_address + 0x2A)
end

function fc_x_vel_max(base_address)
    return memory.read_s16_le(base_address + 0x2C)
end

function fc_y_vel_max(base_address)
    return memory.read_s16_le(base_address + 0x2E)
end

function fc_accel(base_address)
    return memory.read_s16_le(base_address + 0x32)
end

-- Could optimize this out for narrow purposes,
-- but I'll definitely keep it for general use.
function fc_accel_flags(base_address)
    return memory.readbyte(base_address + 0x34)
end

function fc_type(base_address)
    return memory.readbyte(base_address + 0x58)
end

-- local TOAD = 0
-- local YOSHI = 1
-- local BABY_DK = 2
-- local EGG = 3
-- local MOON = 4
-- local BOM_OMB = 5
local fc_type_names = {[0] = "Toad", "Yoshi", "Baby DK", "Egg", "Moon", 
"Bob-omb"}
local fc_type_colors = {[0] = "red", "green", "brown", "white", "yellow", "black"}

function fc_move_timer(base_address)
    return memory.read_u16_le(base_address + 0x5C)
end

function fc_is_active(base_address)
    return bit.band(memory.readbyte(base_address + 0x64), 2) ~= 0
end

local next = next
local prediction = {}

print("[Started position comparing]")
-- May be temporary
if client.ispaused() then
    client.unpause()
end
local continue_loop = true
while continue_loop do
    for slot_num = 0, NUM_CHARACTER_SLOTS - 1 do
        -- I currently do a precheck that this slot is being used;
        -- in the future it might be more efficient to
        -- use a set list of active characters and update that separately
        
        -- The address where the character of interest begins.
        local c = CHARACTER_START + slot_num * CHARACTER_SIZE
        
        if fc_is_active(c) then
            -- TODO: Draw the actual hitbox, probably name it "fc_draw_hitbox" or similar
            local x = fc_x_pixel(c)
            local y = fc_y_pixel(c)
            local c_type = fc_type(c)
            gui.drawEllipse(x - 6, y - 6, 12, 12, 0xFFFFFFFF, fc_type_colors[c_type])
            gui.drawText(x - 5, y - 7, slot_num, (c_type == 5 and 0xFFFFFFFF) or 0xFF000000, 0)
            
            -- Check if movement prediction is correct
            if prediction[slot_num] ~= nil and next(prediction[slot_num]) ~= nil then
                -- A stricter check would compare the velocities, which almost certainly fail currently.
                -- (That's partially because I haven't implemented bounce-collisions, which affect velocity).
                if fc_x(c) ~= prediction[slot_num].x or fc_y(c) ~= prediction[slot_num].y or not continue_loop then
                    gui.drawEllipse(x - 6, y - 6, 12, 12, 0xFFFF0000)
                    print("Character " .. slot_num .. " (" .. fc_type_names[c_type] .. ")")
                    print("x, y: " .. fc_x(c) .. ", " .. fc_y(c) .. " (" .. x .. ", " .. y .. ")")
                    print("x_vel: " .. fc_x_vel(c) .. ", " .. fc_y_vel(c))
                    print("x_vel_max, y_vel_max: " .. fc_x_vel_max(c) .. ", " .. fc_y_vel_max(c))
                    for t in prediction do
                        console.log(t .. ": " .. prediction)
                    end
                    continue_loop = false
                    break
                end
            else
                prediction[slot_num] = {}
            end
            
            --[[
                Try to predict where the character will be in the next frame:
            ]]--
            
            -- TODO: check for bounce, and adjust velocities accordingly.
            
            -- Check if the character will be moving next frame:
            local move_timer = fc_move_timer(c)
            if move_timer >= 180 then
                -- Part 1: calculate velocity due to acceleration
                -- Since the velocities are not directly affected
                -- by the max velocities, there's probably
                -- overflow/underflow protection elsewhere.
                local x_vel = fc_x_vel(c)
                local y_vel = fc_y_vel(c)
                if bit.band(memory.readbyte(0x35), 8) ~= 0 then
                    local accel = fc_accel(c)
                    local accel_flags = fc_accel_flags(c)
                    if x_vel ~= 0 then
                        if bit.band(accel_flags, 0x20) ~= 0 then
                            x_vel = x_vel - accel
                        end
                        if bit.band(accel_flags, 0x10) ~= 0 then
                            x_vel = x_vel + accel
                        end
                        if x_vel == 0 then
                            x_vel = 1
                        end
                        -- x_vel = bit.band(x_vel, 0xFFFF)
                    end
                    if y_vel ~= 0 then
                        if bit.band(accel_flags, 0x40) ~= 0 then
                            y_vel = y_vel - accel
                        end
                        if bit.band(accel_flags, 0x80) ~= 0 then
                            y_vel = y_vel + accel
                        end
                        if y_vel == 0 then
                            y_vel = 1
                        end
                    end
                end
                prediction[slot_num].x_vel = x_vel
                prediction[slot_num].y_vel = y_vel
                
                -- Part 2: calculate position due to velocity
                -- This first processes the velocities and uses
                -- the max velocities if they are less in magnitude
                local x_vel_max = fc_x_vel_max(c)
                local y_vel_max = fc_y_vel_max(c)
                prediction[slot_num].x_vel_max = x_vel_max
                prediction[slot_num].y_vel_max = y_vel_max
                if x_vel_max ~= 0 then
                    if x_vel < 0 then
                        x_vel_max = x_vel_max * -1
                        if x_vel < x_vel_max then
                            x_vel = x_vel_max
                        end
                    else
                        if x_vel > x_vel_max then
                            x_vel = x_vel_max
                        end
                    end
                end
                if y_vel_max ~= 0 then
                    if y_vel < 0 then
                        y_vel_max = y_vel_max * -1
                        if y_vel < y_vel_max then
                            y_vel = y_vel_max
                        end
                    else
                        if y_vel > y_vel_max then
                            y_vel = y_vel_max
                        end
                    end
                end
                
                prediction[slot_num].x = fc_x(c) + x_vel
                prediction[slot_num].y = fc_y(c) + y_vel
            end
        else
            prediction[slot_num] = nil
        end
    end
	emu.frameadvance()
end
print("[Terminated position comparing]\n")
client.pause()