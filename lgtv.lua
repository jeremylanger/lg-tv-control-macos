local LGTVController = {}
LGTVController.__index = LGTVController

-- Configuration
local config = {
    tv_ip = "192.168.0.80",
    tv_mac_address = "6C:15:DB:7C:AC:E2",
    tv_input = "HDMI_4", -- Input to which your Mac is connected
    switch_input_on_wake = true, -- When computer wakes, switch to `tv_input`
    debug = true, -- Enable debug messages
    control_audio = false, -- Control audio volume/mute with keyboard
    prevent_sleep_when_using_other_input = true, -- Prevent TV sleep if TV is on an input other than `tv_input`
    disable_lgtv = false, -- Disable this script entirely by setting this to true
    -- You can also disable it by creating an empty file  at `~/.disable_lgtv`.

    -- Govee backlight settings
    govee_ip = "192.168.0.81",
    govee_control_port = 4003,
    govee_enabled = true, -- Toggle Govee backlight with TV

    -- You likely will not need to change anything below this line
    screen_off_command = "power_off",
    key_file_path = "~/.aiopylgtv.sqlite",
    connected_tv_identifiers = {"LG TV", "LG TV SSCR2"},
    bin_path = "~/bin/bscpylgtvcommand",
    wakeonlan_path = "~/bin/wakeonlan",
    app_id = "com.webos.app." .. ("HDMI_4"):lower():gsub("_", ""),
    set_pc_mode_on_wake = true,
    tv_device_name = "Mac",
    debounce_seconds = 30,
    before_sleep_command = nil,
    after_sleep_command = nil,
    before_wake_command = nil,
    after_wake_command = nil,
}

if config.tv_ip == "" or config.tv_mac_address == "" then
  print("TV IP and MAC address not set. Please set them first.")
  return
end

-- Utility Functions
local function log_debug(message)
    if config.debug then print(message) end
end

local function file_exists(path)
    local file = io.open(path, "r")
    if not file then return false end
    file:close()
    return true
end

local function dump_table(o)
    if type(o) ~= 'table' then return tostring(o) end
    local s = '{ '
    for k, v in pairs(o) do
        s = s .. "[" .. tostring(k) .. "] = " .. dump_table(v) .. ", "
    end
    return s .. '} '
end

-- LGTVController Methods
function LGTVController:new()
    local obj = setmetatable({}, self)
    obj.bin_cmd = config.bin_path .. " -p " .. config.key_file_path .. " " .. config.tv_ip .. " "
    obj.last_wake_execution = 0
    obj.last_sleep_execution = 0
    obj.last_wake_completed = 0
    obj.tv_was_connected = obj:is_connected()
    obj.is_powering_off = false
    return obj
end

function LGTVController:execute_command(command, strip)
    strip = strip or false
    local full_command = self.bin_cmd .. command

    local function try_execute()
        log_debug("Executing command: " .. full_command)
        local output, status, _, rc = hs.execute(full_command, 5)
        if rc == 0 then return output end
        log_debug("Command failed or timed out (exit code: " .. rc .. "): " .. full_command)
        log_debug("Command stdout: " .. output)
        return nil
    end

    local output = try_execute()
    if not output then
        hs.timer.usleep(1000000) -- 1 second in microseconds
        log_debug("Retrying command after 1 second delay...")
        output = try_execute()
        if not output then
            return nil
        end
    end

    if strip then
        return output:match("^(.-)%s*$")
    end
    return output
end

function LGTVController:is_connected()
    for _, identifier in ipairs(config.connected_tv_identifiers) do
        if hs.screen.find(identifier) then
            return true
        end
    end
    return false
end

function LGTVController:disabled()
    return config.disable_lgtv or file_exists("./disable_lgtv") or file_exists(os.getenv('HOME') .. "/.disable_lgtv")
end

function LGTVController:current_app_id()
    return self:execute_command("get_current_app", true)
end

function LGTVController:is_current_audio_device()
    local current_time = os.time()
    if not self.last_audio_device_check or current_time - self.last_audio_device_check >= 10 then
        self.last_audio_device_check = current_time
        self.last_audio_device = false

        local current_audio = hs.audiodevice.current().name
        for _, identifier in ipairs(config.connected_tv_identifiers) do
            if current_audio == identifier then
                log_debug(identifier .. " is the current audio device")
                self.last_audio_device = true
                break
            end
        end
        log_debug(current_audio .. " is the current audio device.")
    end
    return self.last_audio_device
end

function LGTVController:get_muted()
    return self:execute_command("get_muted"):trim() == "True"
end

function LGTVController:toggle_mute()
    local muted = self:get_muted()
    local new_muted = not muted
    if self:execute_command("set_mute " .. tostring(new_muted):lower()) then
        log_debug("Set muted to: " .. tostring(new_muted) .. " (was " .. tostring(muted) .. ")")
    end
end

function LGTVController:log_init()
    log_debug("\n\n-------------------- LGTV DEBUG INFO --------------------")
    log_debug("TV input: " .. config.tv_input)
    log_debug("Binary path: " .. config.bin_path)
    log_debug("Binary command: " .. self.bin_cmd)
    log_debug("App ID: " .. config.app_id)
    log_debug("LGTV Disabled: " .. tostring(self:disabled()))
    if not self:disabled() then
        log_debug(self:execute_command("get_software_info"))
        log_debug("Current app ID: " .. tostring(self:current_app_id()))
        log_debug("Connected screens: " .. dump_table(hs.screen.allScreens()))
        log_debug("TV is connected? " .. tostring(self:is_connected()))
    end
    log_debug("------------------------------------------------------------\n\n")
end

-- Govee Control
function LGTVController:govee_command(cmd, data)
    if not config.govee_enabled or config.govee_ip == "" then return end
    local json = hs.json.encode({msg = {cmd = cmd, data = data}})
    local udp = hs.socket.udp.new()
    udp:send(json, config.govee_ip, config.govee_control_port)
    hs.timer.doAfter(0.5, function() udp:close() end)
    log_debug("Govee command sent: " .. cmd .. " -> " .. json)
end

-- Event Handlers
function LGTVController:ping_tv()
    local ping_cmd = "ping -c 1 -W 1 " .. config.tv_ip .. " > /dev/null 2>&1"
    local _, _, _, rc = hs.execute(ping_cmd)
    return rc == 0
end

function LGTVController:try_command(command)
    local full_command = self.bin_cmd .. command
    log_debug("Trying command: " .. full_command)
    local output, _, _, rc = hs.execute(full_command)
    if rc == 0 then return output end
    return nil
end

function LGTVController:handle_wake_event()
    local current_time = os.time()
    if current_time - self.last_wake_execution < config.debounce_seconds then
        log_debug("Skipping wake execution - debounced.")
        return
    end
    self.last_wake_execution = current_time
    self.is_powering_off = false

    -- Cancel any in-progress async wake polling
    if self.wake_timer then
        self.wake_timer:stop()
        self.wake_timer = nil
    end

    self:govee_command("turn", {value = 1})

    if config.before_wake_command then
        log_debug("Executing before wake command: " .. config.before_wake_command)
        hs.execute(config.before_wake_command)
    end

    -- Synchronous: wait for network + send WOL. This is fast (~3 seconds)
    -- and must complete before we can do anything else.
    log_debug("Waiting for Mac network interface...")
    for i = 1, 10 do
        local _, _, _, rc = hs.execute("ifconfig en0 | grep 'status: active' > /dev/null 2>&1")
        if rc == 0 then
            log_debug("Network interface ready (attempt " .. i .. ")")
            break
        end
        log_debug("Network not ready (attempt " .. i .. "/10)")
        hs.timer.usleep(1000000)
    end

    if config.tv_mac_address ~= "" then
        local command = config.wakeonlan_path .. " " .. config.tv_mac_address
        for i = 1, 3 do
            hs.execute(command)
            log_debug("Wake on LAN packet " .. i .. "/3 sent to " .. config.tv_mac_address)
            if i < 3 then hs.timer.usleep(500000) end
        end
    end

    -- Everything after WOL is async so we don't block Hammerspoon's
    -- run loop. Blocking it prevents macOS from processing display
    -- configuration callbacks, which is why is_connected() never
    -- returns true during synchronous polling loops.
    local phase = "ping"
    local attempt = 0
    local max_attempts = 60

    local function poll()
        attempt = attempt + 1

        if phase == "ping" then
            if self:ping_tv() then
                log_debug("TV responded to ping (attempt " .. attempt .. ")")
                phase = "screen_on"
                attempt = 0
                self.wake_timer = hs.timer.doAfter(0.5, poll)
            elseif attempt < max_attempts then
                log_debug("Ping attempt " .. attempt .. "/" .. max_attempts .. " - no response")
                self.wake_timer = hs.timer.doAfter(1, poll)
            else
                log_debug("Timed out waiting for TV ping")
                self.wake_timer = nil
            end

        elseif phase == "screen_on" then
            if self:try_command("turn_screen_on") then
                log_debug("TV ready - screen on (attempt " .. attempt .. ")")
                phase = "hdmi"
                attempt = 0
                self.wake_timer = hs.timer.doAfter(0.5, poll)
            elseif attempt < max_attempts then
                log_debug("WebSocket not ready (attempt " .. attempt .. "/" .. max_attempts .. ")")
                self.wake_timer = hs.timer.doAfter(1, poll)
            else
                log_debug("Timed out waiting for WebSocket, switching input anyway")
                self:finish_wake()
            end

        elseif phase == "hdmi" then
            if self:is_connected() then
                log_debug("HDMI connected (attempt " .. attempt .. "), switching input")
                self:finish_wake()
            elseif attempt < max_attempts then
                log_debug("Waiting for HDMI signal (attempt " .. attempt .. "/" .. max_attempts .. ")")
                self.wake_timer = hs.timer.doAfter(1, poll)
            else
                log_debug("Timed out waiting for HDMI, switching input anyway")
                self:finish_wake()
            end
        end
    end

    self.wake_timer = hs.timer.doAfter(1, poll)
end

function LGTVController:finish_wake()
    self.wake_timer = nil

    if config.switch_input_on_wake then
        if self:execute_command("launch_app " .. config.app_id) then
            log_debug("Switched TV input to " .. config.app_id)
        end
    end

    if config.set_pc_mode_on_wake then
        if self:execute_command("set_device_info " .. config.tv_input .. " pc '" .. config.tv_device_name .. "'") then
            log_debug("Set TV to PC mode")
        end
    end

    if config.after_wake_command then
        log_debug("Executing after wake command: " .. config.after_wake_command)
        hs.execute(config.after_wake_command)
    end

    self.last_wake_completed = os.time()
end

function LGTVController:handle_sleep_event()
    local current_time = os.time()
    if current_time - self.last_sleep_execution < config.debounce_seconds then
        log_debug("Skipping sleep execution - debounced.")
        return
    end
    -- Don't sleep right after a wake completed - this catches transient
    -- screensDidSleep events that macOS fires during display reconfiguration
    if current_time - self.last_wake_completed < config.debounce_seconds then
        log_debug("Skipping sleep execution - too soon after wake completed.")
        return
    end

    self.last_sleep_execution = current_time

    -- Cancel any in-progress async wake polling
    if self.wake_timer then
        self.wake_timer:stop()
        self.wake_timer = nil
    end

    self:govee_command("turn", {value = 0})

    local current_app = tostring(self:current_app_id())

    log_debug("TV is connected and going to sleep")
    log_debug("Current TV input: " .. current_app)
    log_debug("Prevent sleep on other input: " .. tostring(config.prevent_sleep_when_using_other_input))
    log_debug("Expected computer input: " .. config.tv_input)

    if current_app ~= config.app_id and config.prevent_sleep_when_using_other_input then
        log_debug("TV is on another input (" .. current_app .. "). Skipping power off.")
        return
    end

    if config.before_sleep_command then
        log_debug("Executing before sleep command: " .. config.before_sleep_command)
        hs.execute(config.before_sleep_command)
    end

    -- Prevent screen watcher from clearing tv_was_connected when
    -- WE are the ones powering off the TV
    self.is_powering_off = true
    if self:execute_command(config.screen_off_command) then
        log_debug("TV screen turned off with command: " .. config.screen_off_command)
    else
        self.is_powering_off = false
    end

    if config.after_sleep_command then
        log_debug("Executing after sleep command: " .. config.after_sleep_command)
        hs.execute(config.after_sleep_command)
    end
end

function LGTVController:setup_watchers()
    self.watcher = hs.caffeinate.watcher.new(function(eventType)
        local event_names = {
            "systemDidWake",
            "systemWillSleep",
            "systemWillPowerOff",
            "screensDidSleep",
            "screensDidWake",
            "sessionDidResignActive",
            "sessionDidBecomeActive",
            "screensaverDidStart",
            "screensaverWillStop",
            "screensaverDidStop",
            "screensDidLock",
            "screensDidUnlock"
        }
        local event_name = eventType and event_names[eventType + 1] or "unknown"
        log_debug("Received event: " .. tostring(eventType) .. " (" .. tostring(event_name) .. ")")

        if self:disabled() then
            log_debug("LGTV feature disabled. Skipping event handling.")
            return
        end

        -- We can't use is_connected() here because during clamshell
        -- transitions, the HDMI display link may not be visible to
        -- hs.screen.find(). Instead, we use tv_was_connected which is
        -- tracked by the screen watcher while the system is awake.
        if eventType == hs.caffeinate.watcher.screensDidWake or
           eventType == hs.caffeinate.watcher.systemDidWake or
           eventType == hs.caffeinate.watcher.screensDidUnlock then
            if self.tv_was_connected then
                self:handle_wake_event()
            else
                log_debug("TV was not connected before sleep. Skipping wake.")
            end
        elseif eventType == hs.caffeinate.watcher.screensDidSleep or
               eventType == hs.caffeinate.watcher.systemWillPowerOff then
            if self.tv_was_connected then
                self:handle_sleep_event()
            else
                log_debug("TV is not connected. Skipping sleep.")
            end
        end
    end)

    -- Track HDMI connection state so we know whether the TV was
    -- connected before sleep/wake transitions (when hs.screen.find()
    -- is unreliable due to HDMI link timing).
    self.screen_watcher = hs.screen.watcher.new(function()
        local connected = self:is_connected()
        log_debug("Screen configuration changed. TV connected: " .. tostring(connected))
        if connected then
            self.tv_was_connected = true
            self.is_powering_off = false
        elseif not self.is_powering_off then
            -- Only clear the flag if WE didn't cause the disconnect
            self.tv_was_connected = false
        else
            log_debug("Ignoring TV disconnect - we powered it off")
        end
    end)

    self.audio_event_tap = hs.eventtap.new(
        {hs.eventtap.event.types.keyDown, hs.eventtap.event.types.systemDefined},
        function(event)
            local system_key = event:systemKey()
            local key_actions = {['SOUND_UP'] = "volume_up", ['SOUND_DOWN'] = "volume_down"}
            local pressed_key = tostring(system_key.key)

            if system_key.down then
                if pressed_key == 'MUTE' then
                    if not self:is_current_audio_device() then return end
                    self:toggle_mute()
                elseif key_actions[pressed_key] then
                    if not self:is_current_audio_device() then return end
                    self:execute_command(key_actions[pressed_key])
                end
            end
        end
    )
end

function LGTVController:start()
    self:log_init()
    print("Starting LGTV watcher...")
    self.watcher:start()
    self.screen_watcher:start()

    if config.control_audio then
        print("Starting LGTV audio events watcher...")
        self.audio_event_tap:start()
    end
end

-- Initialize and start the controller
local controller = LGTVController:new()
controller:setup_watchers()
controller:start()
