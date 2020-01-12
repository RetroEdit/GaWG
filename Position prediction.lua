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

carriage = 0x3C334
trampoline = 0x3C42C

local next = next


--[[ 
    'fc_' is short for 'Falling Character'
    I may change/remove the prefix in the future,
    once I switch to a generalized falling character format
    (I may also make it more like OOP)
--]]

function fc_x(base_address)
    return bit.bor(bit.lshift(memory.read_u16_le(base_address + 0x10), 8), memory.readbyte(base_address + 0x13))
end

function fc_x_pixel(base_address)
    return memory.read_u16_le(base_address + 0x10)
end

function fc_y(base_address)
    return bit.bor(bit.lshift(memory.readbyte(base_address + 0x12), 8), memory.readbyte(base_address + 0x14))
end

function fc_y_pixel(base_address)
    return memory.readbyte(base_address + 0x12)
end



function fc_draw_hitbox(base_address, color, background)
    local x = fc_x_pixel(base_address)
    local y = fc_y_pixel(base_address)
    local left = memory.readbyte(base_address + 0x15)
    local right = memory.readbyte(base_address + 0x16)
    local top = memory.readbyte(base_address + 0x17)
    local bottom = memory.readbyte(base_address + 0x18)
    gui.drawRectangle(
        x - left,
        y - top,
        left + right + 1,
        top + bottom + 1,
        color,
        background
    )
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

-- local TOAD = 0; local YOSHI = 1; local BABY_DK = 2; local EGG = 3; local MOON = 4; local BOM_OMB = 5
local fc_type_names = {[0] = "Toad", "Yoshi", "Baby DK", "Egg", "Moon", "Bob-omb"}
local fc_type_colors = {[0] = 0xFFFF0000, 0xFF008000, 0xFFA52A2A, 0xFFFFFFFF, 0xFFFFFF00, 0xFF000000}

function fc_move_timer(base_address)
    return memory.read_u16_le(base_address + 0x5C)
end

function fc_is_active(base_address)
    return bit.band(memory.readbyte(base_address + 0x64), 2) ~= 0
end


--[[
    Fire score-dependent variables.
--]]

function fire_speed()
    return memory.readbyte(0x3CAC3)
end

function fire_characters_max()
    return memory.readbyte(0x3CAC4)
end

function fire_characters_in_play()
    return memory.readbyte(0x3CAC5)
end

function fire_yoshi_chance()
    return memory.readbyte(0x3CAC6)
end

function fire_baby_dk_chance()
    return memory.readbyte(0x3CAC7)
end

function fire_egg_chance()
    return memory.readbyte(0x3CAC8)
end

--[[
function fire_unknown()
    return memory.readbyte(0x3CAC9)
end
--]]

function predict_positions(EXIT_ON_MISPREDICTION, PRINT_ON_MISPREDICTION) 
    if EXIT_ON_MISPREDICTION == nil then
        EXIT_ON_MISPREDICTION = false
    end
    if PRINT_ON_MISPREDICTION == nil then
        -- Having the console print 1000 errors is not particularly user-friendly.
        -- TODO: Add an option for redirecting the output stream to a file.
        -- PRINT_ON_MISPREDICTION = true
        PRINT_ON_MISPREDICTION = false
    end
    local prediction = {}
    print("[Started position comparing]")
    -- May be temporary
    if client.ispaused() then
        client.unpause()
    end
    local continue_loop = true
    while continue_loop do
        for slot_num = 0, NUM_CHARACTER_SLOTS - 1 do
            -- The address where the character of interest begins.
            local curr_character = CHARACTER_START + slot_num * CHARACTER_SIZE
            
            if fc_is_active(curr_character) then
                local curr_prediction = prediction[slot_num]
            
                local x = fc_x_pixel(curr_character)
                local y = fc_y_pixel(curr_character)
                local c_type = fc_type(curr_character)
                -- gui.drawEllipse(x - 6, y - 6, 12, 12, 0xFFFFFFFF, fc_type_colors[c_type])
                -- gui.drawText(x - 5, y - 7, slot_num, (c_type == 5 and 0xFFFFFFFF) or 0xFF000000, 0)
                
                fc_draw_hitbox(carriage, 0xFFFFFFFF, 0)
                fc_draw_hitbox(trampoline, 0xFFFFFFFF, 0)
                fc_draw_hitbox(curr_character, 0xFFFFFFFF, fc_type_colors[c_type])
                
                -- Check if movement prediction is correct
                if curr_prediction ~= nil and next(curr_prediction) ~= nil then
                    -- The checks here will keep becoming more abstract.
                    if fc_x(curr_character) ~= curr_prediction.x
                        or fc_y(curr_character) ~= curr_prediction.y
                        -- or fc_x_vel(curr_character) ~= curr_prediction.x_vel
                        -- or fc_y_vel(curr_character) ~= curr_prediction.y_vel
                    then
                        -- gui.drawEllipse(x - 6, y - 6, 12, 12, 0xFFFF0000)
                        if PRINT_ON_MISPREDICTION then
                            print("Character " .. slot_num .. " (" .. fc_type_names[c_type] .. ")")
                            print("x, y: " .. fc_x(curr_character) .. ", " .. fc_y(curr_character) .. " (" .. x .. ", " .. y .. ")")
                            print("x_vel, y_vel: " .. fc_x_vel(curr_character) .. ", " .. fc_y_vel(curr_character))
                            print("x_vel_max, y_vel_max: " .. fc_x_vel_max(curr_character) .. ", " .. fc_y_vel_max(curr_character))
                            for k,v in pairs(prediction) do
                                console.log("    " .. k .. ": ")
                                console.log(v)
                            end
                        end
                        if EXIT_ON_MISPREDICTION then
                            continue_loop = false
                            break
                        end
                    end
                else
                    curr_prediction = {}
                end
                
                --[[
                    Try to predict where the character will be in the next frame:
                ]]--
                
                -- TODO: check for bounce, and adjust velocities accordingly.
                --[[
                character_type = fc_type(curr_character)
                if character_type == TOAD then
                    -- TODO: Finish.
                end
                --]]
                
                -- FIXME: There's a missing skip condition;
                -- I have a savestate that shows some consecutive fails.
                -- It could even be more meta than I realize.

                -- Check if the character will be moving next frame:
                local move_timer_result = fc_move_timer(curr_character) + fire_speed()
                if move_timer_result >= 180 then
                    -- Part 1: calculate velocity due to acceleration
                    -- Since the velocities are not directly affected
                    -- by the max velocities, there's probably
                    -- overflow/underflow protection elsewhere (?)
                    local x_vel = nil
                    local y_vel = nil
                    if curr_prediction.x_vel == nil then
                        x_vel = fc_x_vel(curr_character)
                        y_vel = fc_y_vel(curr_character)
                    else
                        x_vel = curr_prediction.x_vel
                        y_vel = curr_prediction.y_vel
                    end
                    if bit.band(memory.readbyte(0x35), 8) ~= 0 then
                        local accel = fc_accel(curr_character)
                        local accel_flags = fc_accel_flags(curr_character)
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
                    else
                        print("0x35 vel precheck failed.")
                    end
                    curr_prediction.x_vel = x_vel
                    curr_prediction.y_vel = y_vel
                    
                    -- Part 2: calculate position due to velocity
                    -- This first processes the velocities and uses
                    -- the max velocities if they are less in magnitude
                    local x_vel_max = nil
                    local y_vel_max = nil
                    if curr_prediction.x_vel_max == nil then
                        x_vel_max = fc_x_vel_max(curr_character)
                        y_vel_max = fc_y_vel_max(curr_character)
                        curr_prediction.x_vel_max = x_vel_max
                        curr_prediction.y_vel_max = y_vel_max
                    else
                        x_vel_max = curr_prediction.x_vel_max
                        y_vel_max = curr_prediction.y_vel_max
                    end
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
                    
                    curr_prediction.x = fc_x(curr_character) + x_vel
                    curr_prediction.y = fc_y(curr_character) + y_vel
                end
                
                prediction[slot_num] = curr_prediction
            else
                prediction[slot_num] = nil
            end
        end
        emu.frameadvance()
    end
    print("[Terminated position comparing]\n")
    client.pause()
 end
 
 -- FIXME: currently broken for general use if false
 local START_ON_LOAD = true
 
 if START_ON_LOAD then
    predict_positions()
 end