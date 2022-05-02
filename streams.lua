-- ~~~ streams ~~~
-- multi playhead
-- sequencer
--
-- 0.9.2 @sonocircuit
--
-- llllllll.co/t/?????
--
-- for docs goto:
--
--

engine.name = "Thebangs"

thebangs = include('lib/thebangs_engine')
sc_delay = include('lib/halfsync')

mu = require "musicutil"

g = grid.connect()

-------- set variables --------

local pageNum = 1
local edit = 1
local p_set = 1
local t_set = 1
local focus = 1

local alt = false
local mod = false
local set_start = false
local set_end = false
local set_loop = false
local set_rate = false
local set_oct = false
local set_trsp = false
local altgrid = false

local shift = false
local ledview = 1
local viewinfo = 0

local transport = 1 -- 1 is off, 0 is on
local transport_tog = 0

local v8_std_1 = 12
local v8_std_2 = 12
local env1_amp = 8
local env1_a = 0
local env1_r = 0.05
local env2_a = 0
local env2_r = 0.05
local env2_amp = 8

-------- set tables --------

scale_names = {}
scale_notes = {}

options = {}
options.rate_val = {"2", "1", "3/4", "2/3", "1/2", "3/8", "1/3", "1/4", "3/16", "1/6", "1/8", "3/32", "1/12", "1/16", "3/64", "1/32"}
options.rate_num = {2, 1, 3/4, 2/3, 1/2, 3/8, 1/3, 1/4, 3/16, 1/6, 1/8, 3/32, 1/12, 1/16, 3/64, 1/32}
options.direction = {"fwd", "rev"}
options.dir_mode = {"normal", "pendulum", "random"}
options.gbl_out = {"per track", "thebangs", "midi", "crow ii jf"}
options.ind_out = {"thebangs", "midi", "crow 1+2", "crow 3+4", "crow ii jf"}
options.octave = {-3, -2, -1, 0, 1, 2, 3}
options.pages = {"SEQUENCE", "TRACK", "DELAY", "SYNTH"}

pattern = {}
pattern.notes = {}
pattern.rests = {}
for i = 1, 8 do -- 8 note and rest presets
  pattern.notes[i] = {}
  pattern.rests[i] = {}
  for j = 1, 16 do
    table.insert(pattern.notes[i], j, math.random(1, 20))
    table.insert(pattern.rests[i], j, 0)
  end
end

track = {}
for i = 1, 4 do -- 4 tracks
  track[i] = {}
  track[i].loop_start = 1
  track[i].loop_end = 16
  track[i].loop_len = 16
  track[i].pos = 1
  track[i].prob = 100
  track[i].rate = 1
  track[i].dir = 0
  track[i].dir_mode = 0
  track[i].octave = 0
  track[i].transpose = 0
  track[i].running = false
  track[i].track_out = 1
end

set_midi = {}
for i = 1, 4 do -- 4 tracks
  set_midi[i] = {}
  set_midi[i].ch = 1
  set_midi[i].vel = 100
  set_midi[i].vel_hi = 120
  set_midi[i].vel_lo = 80
  set_midi[i].vel_range = 20
  set_midi[i].velocity = 100
  set_midi[i].active_notes = {}
end

set_crow = {}
for i = 1, 4 do -- 4 tracks
  set_crow[i] = {}
  set_crow[i].jf_ch = i
  set_crow[i].jf_amp = 5
end

m = {}
for i = 0, 4 do
  m[i] = midi.connect()
end


-------- pre init functions --------

function build_scale()
  scale_notes = mu.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), 20)
  local num_to_add = 20 - #scale_notes
  for i = 1, num_to_add do
    table.insert(scale_notes, scale_notes[20 - num_to_add]) -- understand why this is needed
  end
end

function set_track_output()
  local glb_out = params:get("global_out")
  for i = 1, 4 do
    if params:get("global_out") == 1 then
      track[i].track_out = params:get("track_out"..i)
    elseif glb_out == 2 then
      track[i].track_out = 1
    elseif glb_out == 3 then
      track[i].track_out = 2
    elseif glb_out == 4 then
      track[i].track_out = 5
    end
  end
  if glb_out == 4 then
    crow.ii.pullup(true)
    crow.ii.jf.mode(1)
  else
    local count = 0
    for i = 1, 4 do
      if params:get("track_out"..i) == 5 then
        count = count + 1
      end
    end
    if count > 0 then
      crow.ii.pullup(true)
      crow.ii.jf.mode(1)
    else
      crow.ii.jf.mode(0)
    end
  end
end


function set_loop_start(i, startpoint)
  track[i].loop_start = startpoint
  if track[i].loop_start >= track[i].loop_end then
    params:set("loop_end"..i, track[i].loop_start)
  end
  dirtygrid = true
end

function set_loop_end(i, endpoint)
  track[i].loop_end = endpoint
  if track[i].loop_end <= track[i].loop_start then
    params:set("loop_start"..i, track[i].loop_end)
  end
  dirtygrid = true
end

------------------------ midi -------------------------

function build_midi_device_list()
  midi_devices = {}
  for i = 1, #midi.vports do
    local long_name = midi.vports[i].name
    local short_name = string.len(long_name) > 15 and util.acronym(long_name) or long_name
    table.insert(midi_devices, i..": "..short_name)
  end
end

function midi.add() -- this gets called when a MIDI device is registered
  build_midi_device_list()
end

function midi.remove() -- this gets called when a MIDI device is removed
  clock.run(
    function()
      clock.sleep(0.2)
        build_midi_device_list()
    end
  )
end

function clock.transport.start()
  if params:get("midi_trnsp") == 3 then
    for i = 1, 4 do
      track[i].running = true
    end
  end
end

function clock.transport.stop()
  if params:get("midi_trnsp") == 3 then
    for i = 1, 4 do
      track[i].running = false
      reset_pos()
      notes_off(i)
    end
  end
end

function notes_off(i)
  for _, a in pairs(set_midi[i].active_notes) do
    m[i]:note_off(a, nil, set_midi[i].ch)
  end
  set_midi[i].active_notes = {}
end

function all_notes_off()
  for i = 1, 4 do
    for _, a in pairs(set_midi[i].active_notes) do
      m[i]:note_off(a, nil, set_midi[i].ch)
    end
    set_midi[i].active_notes = {}
  end
end

function set_velocity(i)
  set_midi[i].vel_hi = util.clamp(set_midi[i].vel + set_midi[i].vel_range, 1, 127)
  set_midi[i].vel_lo = util.clamp(set_midi[i].vel - set_midi[i].vel_range, 1, 127)
end

-------- init function --------

function init()

  -- populate scale_names table
  for i = 1, #mu.SCALES do
    table.insert(scale_names, string.lower(mu.SCALES[i].name))
  end

  -- scale settings
  params:add_separator("global settings")

  params:add_option("global_out", "output", options.gbl_out, 1)
  params:set_action("global_out", function() set_track_output() build_menu() end)

  params:add_option("scale_mode", "scale", scale_names, 5)
  params:set_action("scale_mode", function() build_scale() end)

  params:add_number("root_note", "root note", 24, 84, 48, function(param) return mu.note_num_to_name(param:get(), true) end)
  params:set_action("root_note", function() build_scale() end)

  -- midi settings
  build_midi_device_list()

  params:add_option("set_midi_device", "midi device", midi_devices, 1)
  params:set_action("set_midi_device", function(val) m[0] = midi.connect(val) end)

  params:add_option("midi_trnsp", "midi transport", {"off", "send", "receive"}, 1)

  -- track settings
  params:add_separator("tracks")
  for i = 1, 4 do
    params:add_group("track "..i, 19)

    params:add_separator("output settings")
    params:add_option("track_out"..i, "output", options.ind_out, 1)
    params:set_action("track_out"..i, function() set_track_output() build_menu() end)

    --midi settings

    params:add_option("set_midi_device"..i, "midi device", midi_devices, 1)
    params:set_action("set_midi_device"..i, function(val) m[i] = midi.connect(val) end)
    params:hide("set_midi_device"..i)

    params:add_number("midi_out_channel"..i, "midi channel", 1, 16, 1)
    params:set_action("midi_out_channel"..i, function(val) notes_off(i) set_midi[i].ch = val end)
    params:hide("midi_out_channel"..i)

    params:add_option("vel_mode"..i, "velocity mode", {"fixed", "random"}, 1)
    params:set_action("vel_mode"..i, function() set_velocity(i) end)
    params:hide("vel_mode"..i)

    params:add_number("midi_vel_val"..i, "velocity value", 1, 127, 100)
    params:set_action("midi_vel_val"..i, function(val) set_midi[i].vel = val set_velocity(i) end) --set_vel_range()
    params:hide("midi_vel_val"..i)

    params:add_number("midi_vel_range"..i, "velocity range ±", 1, 127, 20)
    params:set_action("midi_vel_range"..i, function(val) set_midi[i].vel_range = val set_velocity(i) end)
    params:hide("midi_vel_range"..i)

    -- jf settings
    params:add_option("jf_mode"..i, "jf_mode", {"vox", "note"}, 1)
    params:set_action("jf_mode"..i, function() build_menu() end)
    params:hide("jf_mode"..i)

    params:add_number("jf_voice"..i, "jf voice", 1, 6, i)
    params:set_action("jf_voice"..i, function(vox) set_crow[i].jf_ch = vox end)
    params:hide("jf_voice"..i)

    params:add_control("jf_amp"..i, "jf level", controlspec.new(0.1, 5, "lin", 0.1, 5.0, "vpp"))
    params:set_action("jf_amp"..i, function(level) set_crow[i].jf_amp = level end)
    params:hide("jf_amp"..i)

    params:add_separator("track parameters")
    params:add_number("probability"..i, "probability", 0, 100, 100, function(param) return (param:get().." %") end)
    params:set_action("probability"..i, function(x) track[i].prob = x end)

    params:add_option("rate"..i, "rate", options.rate_val, 8)
    params:set_action("rate"..i, function(idx) track[i].rate = options.rate_num[idx] * 4 end)

    params:add_option("octave"..i, "octave",  options.octave, 4)
    params:set_action("octave"..i, function(idx) track[i].octave = options.octave[idx] end)

    params:add_number("transpose"..i, "transpose", -7, 7, 0, function(param) return (param:get().." deg") end)
    params:set_action("transpose"..i, function(x) track[i].transpose = x end)

    params:add_option("step_mode"..i, "step mode", options.dir_mode, 1)
    params:set_action("step_mode"..i, function(x) track[i].dir_mode = x - 1 end)

    params:add_option("direction"..i, "direction", options.direction, 1)
    params:set_action("direction"..i, function(x) track[i].dir = x - 1 end)

    params:add_number("loop_start"..i, "start position", 1, 16, 1)
    params:set_action("loop_start"..i, function(x) set_loop_start(i, x) end)

    params:add_number("loop_end"..i, "end position", 1, 16, 16)
    params:set_action("loop_end"..i, function(x) set_loop_end(i, x) end)

  end

  params:add_separator("sound")

  -- delay params
  params:add_group("delay", 4)
  sc_delay.init()

  -- engine params
  params:add_group("thebangs", 8)
  thebangs.synth_params()

  -- crow params
  params:add_separator("crow")

  params:add_group("out 1+2", 4)
  params:add_option("v8_type_1", "v/oct type", {"1 v/oct", "1.2 v/oct"}, 1)
  params:set_action("v8_type_1", function(x) if x == 1 then v8_std_1 = 12 else v8_std_1 = 10 end end)

  params:add_control("env1_amplitude", "amplitude", controlspec.new(0.1, 10, "lin", 0.1, 8, "v"))
  params:set_action("env1_amplitude", function(value) env1_amp = value end)

  params:add_control("env1_attack", "attack", controlspec.new(0.00, 1, "lin", 0.01, 0.00, "s"))
  params:set_action("env1_attack", function(value) env1_a = value end)

  params:add_control("env1_release", "release", controlspec.new(0.01, 1, "lin", 0.01, 0.05, "s"))
  params:set_action("env1_release", function(value) env1_r = value end)

  params:add_group("out 3+4", 4)
  params:add_option("v8_type_2", "v/oct type", {"1 v/oct", "1.2 v/oct"}, 1)
  params:set_action("v8_type_2", function(x) if x == 1 then v8_std_2 = 12 else v8_std_2 = 10 end end)

  params:add_control("env2_amplitude", "amplitude", controlspec.new(0.1, 10, "lin", 0.1, 8, "v"))
  params:set_action("env2_amplitude", function(value) env2_amp = value end)

  params:add_control("env2_attack", "attack", controlspec.new(0.00, 1, "lin", 0.01, 0.00, "s"))
  params:set_action("env2_attack", function(value) env2_a = value end)

  params:add_control("env2_release", "release", controlspec.new(0.01, 1, "lin", 0.01, 0.05, "s"))
  params:set_action("env2_release", function(value) env2_r = value end)

  -- metros
  ledcounter = metro.init(ledpulse, 0.1, -1) -- 100ms timer
  ledcounter:start()

  redrawtimer = metro.init(redraw_fun, 0.02, -1) -- refresh rate at 50hz
  redrawtimer:start()
  dirtygrid = true
  dirtyscreen = true

  params:bang()

  -- clocks
  for i = 1, 4 do
    clock.run(step, i)
  end

  set_defaults()
  transport_all()
  reset_pos()

  grid.add = drawgrid_connect

end

-------- post init functions / polls --------

function step(i)
  while true do
    clock.sync(track[i].rate)
    notes_off(i)
    if track[i].running then
      -- step playhead
      if track[i].dir_mode == 2 then
        track[i].pos = math.random(track[i].loop_start, track[i].loop_end)
      else
        if track[i].dir == 0 then
          track[i].pos = track[i].pos + 1
          if track[i].pos > track[i].loop_end then
            if track[i].dir_mode == 1 then
              params:set("direction"..i, 2)
              track[i].pos = track[i].loop_end - 1
            else
              track[i].pos = track[i].loop_start
            end
          end
        elseif track[i].dir == 1 then
          track[i].pos = track[i].pos - 1
          if track[i].pos < track[i].loop_start then
            if track[i].dir_mode == 1 then
              params:set("direction"..i, 1)
              track[i].pos = track[i].loop_start + 1
            else
              track[i].pos = track[i].loop_end
            end
          end
        end
      end
      -- send midi start msg
      if params:get("midi_trnsp") == 2 and transport_tog == 0 then
        m[0]:start()
        transport_tog = 1
      end
      -- play notes
      -- probability
      if math.random(100) <= track[i].prob then
        -- play notes if not rest
        if pattern.rests[p_set][track[i].pos] < 1 then
          local note_num = scale_notes[util.clamp(pattern.notes[p_set][track[i].pos] + track[i].transpose,1, 20)] + track[i].octave * 12
          local freq = mu.note_num_to_freq(note_num)
          -- engine output
          if track[i].track_out == 1 then
            engine.hz(freq)
          -- midi output
          elseif track[i].track_out == 2 then
            if params:get("vel_mode"..i) == 2 then
              set_midi[i].velocity = math.random(set_midi[i].vel_lo, set_midi[i].vel_hi)
            else
              set_midi[i].velocity = set_midi[i].vel
            end
            m[i]:note_on(note_num, set_midi[i].velocity, set_midi[i].ch)
            table.insert(set_midi[i].active_notes, note_num)
          -- crow output 1+2
          elseif track[i].track_out == 3 then
            crow.output[1].volts = ((note_num - 60) / v8_std_1)
            crow.output[2].action = "{ to(0, 0), to("..env1_amp..", "..env1_a.."), to(0, "..env1_r..", 'log') }"
            crow.output[2]()
          -- crow output 3+4
          elseif track[i].track_out == 4 then
            crow.output[3].volts = ((note_num - 60) / v8_std_2)
            crow.output[4].action = "{ to(0, 0), to("..env2_amp..", "..env2_a.."), to(0, "..env2_r..", 'log') }"
            crow.output[4]()
          -- crow ii jf
          elseif track[i].track_out == 5 then
            if params:get("jf_mode"..i) == 1 then
              crow.ii.jf.play_voice(set_crow[i].jf_ch, ((note_num - 60) / 12), set_crow[i].jf_amp)
            else
              crow.ii.jf.play_note(((note_num - 60) / 12), set_crow[i].jf_amp)
            end
          end
        end
      end
    end
    dirtygrid = true
    dirtyscreen = true
  end
end

function transport_all()
  if transport == 0 then
    for i = 1, 4 do
      track[i].running = true
    end
  else
    if params:get("midi_trnsp") == 2 then m[0]:stop() transport_tog = 0 end
    for i = 1, 4 do
      track[i].running = false
      notes_off(i)
    end
  end
end

function reset_pos()
  for i = 1, 4 do
    if track[i].dir == 0 then
      track[i].pos = track[i].loop_start
    elseif track[i].dir == 1 then
      track[i].pos = track[i].loop_end
    end
  end
end

function randomize_notes()
  for i = 1, 16 do
    table.insert(pattern.notes[p_set], i, math.random(1, 20))
    table.insert(pattern.rests[p_set], i, 0)
  end
end

function set_defaults()
  -- track 1
  params:set("loop_start"..1, 4)
  params:set("loop_end"..1, 9)
  params:set("rate"..2, 14)
  -- track 2
  params:set("loop_start"..2, 6)
  params:set("loop_end"..2, 12)
  params:set("rate"..2, 13)
  params:set("octave"..2, 5)
  params:set("transpose"..2, 7)
  -- track 3
  params:set("loop_start"..3, 2)
  params:set("loop_end"..3, 9)
  params:set("rate"..3, 6)
  -- track 4
  params:set("loop_start"..4, 7)
  params:set("loop_end"..4, 15)
  params:set("rate"..4, 9)
  params:set("octave"..4, 2)
end

-------- norns interface --------

function enc(n, d)
  if n == 1 then
    pageNum = util.clamp(pageNum + d, 1, #options.pages)
  end
  if pageNum == 1 then
    if n == 2 then
      edit = util.clamp(edit + d, 1, 16)
    elseif n == 3 then
      pattern.notes[p_set][edit] = util.clamp(pattern.notes[p_set][edit] + d, 1, 20)
    end
  elseif pageNum == 2 then
    if viewinfo == 0 then
      if n == 2 then
        params:delta("rate"..focus, d)
      elseif n == 3 then
        params:delta("probability"..focus, d)
      end
    else
      if n == 2 then
        params:delta("octave"..focus, d)
      elseif n == 3 then
        params:delta("transpose"..focus, d)
      end
    end
  elseif pageNum == 3 then
        if viewinfo == 0 then
      if n == 2 then
        params:delta("delay_level", d)
      elseif n == 3 then
        params:delta("delay_length", d)
      end
    else
      if n == 2 then
        params:delta("delay_feedback", d)
      elseif n == 3 then
        params:delta("delay_length_ft", d)
      end
    end
  elseif pageNum == 4 then
        if viewinfo == 0 then
      if n == 2 then
        params:delta("bangs_cutoff", d)
      elseif n == 3 then
        params:delta("bangs_pw", d)
      end
    else
      if n == 2 then
        params:delta("bangs_attack", d)
      elseif n == 3 then
        params:delta("bangs_release", d)
      end
    end
  else
    -- other page
  end
  dirtyscreen = true
  dirtygrid = true
end

function key(n, z)
  if n == 1 then
    shift = z == 1 and true or false
  end
  if pageNum == 1 then
    if n == 2 and z == 1 then
      if not shift then
        transport = 1 - transport
        transport_all()
      elseif shift then
        reset_pos()
      end
    elseif n == 3 and z == 1 then
      if not shift then
        pattern.rests[p_set][edit] = 1 - pattern.rests[p_set][edit]
      elseif shift then
        randomize_notes()
      end
    end
  elseif (pageNum == 2 or pageNum == 3 or pageNum == 4) then
    if n == 2 then
      if z == 1 then
        viewinfo = 1 - viewinfo
      end
    end
  else
    -- other page
  end
  dirtyscreen = true
  dirtygrid = true
end

function redraw()
  screen.clear()
  for i = 1, #options.pages do
    screen.move(i * 6 + 97, 6)
    screen.line_rel(4, 0)
    screen.line_width(4)
    if i == pageNum then
      screen.level(15)
    else
      screen.level(2)
    end
    screen.stroke()
  end
  screen.move(1, 8)
  screen.level(6)
  screen.font_size(8)
  screen.text(options.pages[pageNum])
  local sel = viewinfo == 0
  if pageNum == 1 then
    -- draw notes
    for i = 1, 16 do
      screen.move(i * 8 - 8 + 1, 44 - ((pattern.notes[p_set][i]) * 2) + 8) -- lowest note at y = 22 + clearance (10). tweek val
      -- note visibility
      if pattern.rests[p_set][i] == 1 then
        screen.level(0)
      else
        screen.level((i == edit) and 15 or 3)
      end
      screen.line_width(2)
      screen.line_rel(4, 0)
      screen.stroke()
    end
    -- draw playhead indicators below notes
    for i = 1, 4 do
      screen.level(1)
      screen.move(track[i].loop_start * 8 - 8 + 1, 51 + i * 3)
      screen.line_rel(track[i].loop_end * 8 - 4 - (track[i].loop_start * 8 - 8), 0)
      screen.stroke()
      screen.level(15)
      screen.move(track[i].pos * 8 - 8 + 1, 51 + i * 3) -- at y = 54, 56, 58, 60
      screen.line_rel(4, 0)
      screen.stroke()
    end
  elseif pageNum == 2 then
    local a = 10
    screen.level(6)
    screen.move(28, 8)
    screen.font_size(8)
    screen.text(focus)
    screen.level(sel and 15 or 4)
    screen.move(4 + a, 24)
    screen.text(params:string("rate"..focus))
    screen.move(64 + a, 24)
    screen.text(params:string("probability"..focus))
    screen.level(3)
    screen.move(4 + a, 32)
    screen.text("rate")
    screen.move(64 + a, 32)
    screen.text("prob")
    screen.level(not sel and 15 or 4)
    screen.move(4 + a, 48)
    screen.text(params:string("octave"..focus))
    screen.move(64 + a, 48)
    screen.text(params:string("transpose"..focus))
    screen.level(3)
    screen.move(4 + a, 56)
    screen.text("octave")
    screen.move(64 + a, 56)
    screen.text("transpose")
  elseif pageNum == 3 then
    local a = 10
    --screen.font_size(16)
    screen.level(sel and 15 or 4)
    screen.move(4 + a, 24)
    screen.text(params:string("delay_level"))
    screen.move(64 + a, 24)
    screen.text(params:string("delay_length"))
    screen.level(3)
    screen.move(4 + a, 32)
    --screen.font_size(12)
    screen.text("level")
    screen.move(64 + a, 32)
    screen.text("rate")
    screen.level(not sel and 15 or 4)
    screen.move(4 + a, 48)
    --screen.font_size(16)
    screen.text(params:string("delay_feedback"))
    screen.move(64 + a, 48)
    screen.text(params:string("delay_length_ft"))
    screen.level(3)
    screen.move(4 + a, 56)
    --screen.font_size(12)
    screen.text("feedback")
    screen.move(64 + a, 56)
    screen.text("adjust rate")
  elseif pageNum == 4 then
    local a = 10
    --screen.font_size(16)
    screen.level(sel and 15 or 4)
    screen.move(4 + a, 24)
    screen.text(params:string("bangs_cutoff"))
    screen.move(64 + a, 24)
    screen.text(params:string("bangs_pw"))
    screen.level(3)
    screen.move(4 + a, 32)
    --screen.font_size(12)
    screen.text("cutoff")
    screen.move(64 + a, 32)
    screen.text("pw")
    screen.level(not sel and 15 or 4)
    screen.move(4 + a, 48)
    --screen.font_size(16)
    screen.text(params:string("bangs_attack"))
    screen.move(64 + a, 48)
    screen.text(params:string("bangs_release"))
    screen.level(3)
    screen.move(4 + a, 56)
    --screen.font_size(12)
    screen.text("attack")
    screen.move(64 + a, 56)
    screen.text("release")
  else
    -- other page
  end
  screen.update()
end

-------- grid interface --------

function g.key(x, y, z)
  -- loop modifier keys
  if x == 15 then
    if y == 5 then
      set_start = z == 1 and true or false
    elseif y == 6 then
      set_end = z == 1 and true or false
    elseif y == 7 then
      set_loop = z == 1 and true or false
    end
  end
  -- grid page keys
  if x == 16 then
    if y == 5 then
      set_rate = z == 1 and true or false
    elseif y == 6 then
      set_oct = z == 1 and true or false
    elseif y == 7 then
      set_trsp = z == 1 and true or false
    end
    if y > 4 and y < 8 then
      altgrid = z == 1 and true or false
    end
  end
  -- mod and alt keys
  if x == 15 and y == 8 then
    mod = z == 1 and true or false
  end
  if x == 16 and y == 8 then
    alt = z == 1 and true or false
  end
  -- rest
  if z == 1 then
    if y < 5 then
      local i = y
      if focus ~= i then focus = i end
      if not altgrid then
        if set_start then
          params:set("loop_start"..i, x)
          if mod then track[i].pos = track[i].loop_end end
        elseif set_end then
          params:set("loop_end"..i, x)
          if mod then track[i].pos = x end
        elseif set_loop then
          track[i].loop_len = track[i].loop_end - track[i].loop_start
          params:set("loop_start"..i, x)
          params:set("loop_end"..i, x + track[i].loop_len)
          if mod then track[i].pos = x end
        elseif alt then
          reset_pos()
        elseif mod then
          for i = 1, 4 do
            track[i].pos = x
          end
        else
          track[i].pos = x
        end
      elseif set_rate then
        params:set("rate"..i, x)
      elseif set_oct then
        if x < 9 then
          params:set("octave"..i, x - 4)
        elseif x > 8 then
          params:set("octave"..i, x - 5)
        end
      elseif set_trsp then
        if x < 9 then
          params:set("transpose"..i, x - 8)
        elseif x > 8 then
          params:set("transpose"..i, x - 9)
        end
      end
      dirtyscreen = true
    end
    -- track focus
    if y > 4 then
      local i = y - 4
      if x == 1 then
        if focus ~= i then focus = i end
      end
    -- run/stop
      if x == 3 and not alt then
        track[i].running = not track[i].running
      elseif x == 3 and alt then
        if track[i].running then
          if params:get("midi_trnsp") == 2 then m[0]:stop() transport_tog = 0 end
          for j = 1, 4 do
            track[j].running = false
            notes_off(j)
            reset_pos()
          end
        elseif not track[i].running then
          for j = 1, 4 do
            track[j].running = true
          end
        end
      end
    -- direction
      if x == 5 then
        params:set("direction"..i, x - 3)
      elseif x == 8 then
        params:set("direction"..i, x - 7)
      end
    -- step mode
      if x == 6 then
        if params:get("step_mode"..i) == 2 then
          params:set("step_mode"..i, 1)
        else
          params:set("step_mode"..i, 2)
        end
      elseif x == 7 then
        if params:get("step_mode"..i) == 3 then
          params:set("step_mode"..i, 1)
        else
          params:set("step_mode"..i, 3)
        end
      end
      dirtyscreen = true
    end
    -- note preset
    if x > 9 and x < 12 then
      if y > 4 then
        local n = (y - 4)
        local i = n + (x - 10) * 4
        if alt then
          pattern.notes[i] = {table.unpack(pattern.notes[p_set])}
          pattern.rests[i] = {table.unpack(pattern.rests[p_set])}
        elseif not alt then
          p_set = i
        end
        dirtyscreen = true
      end
    end
    -- track presets
    if x == 13 then
      local i = y - 4
      if alt then
        for j = 1, 4 do
        --pattern.notes[i] = {table.unpack(pattern.notes[p_set])}
        --pattern.rests[i] = {table.unpack(pattern.rests[p_set])}
        end
      elseif not alt then
        t_set = i
        --track_params()
      end
      dirtyscreen = true
    end
  elseif z == 0 then
    -- morestuff
  end
  dirtygrid = true
end

function gridredraw()
  g:all(0)
  if not altgrid then
    -- loop windows
    for i = 1, 4 do
      track[i].len = track[i].loop_end - track[i].loop_start
      for j = 1, track[i].len + 1 do
        g:led(track[i].loop_start + j - 1, i, set_loop and 5 or 4)
      end
      if set_start then
        g:led(track[i].loop_start, i, 6)
      end
      if set_end then
        g:led(track[i].loop_end, i, 6)
      end
    end
    -- playhead
    for i = 1, 4 do
      g:led(track[i].pos, i, 12)
    end
  elseif altgrid and set_rate then
    for i = 1, 4 do
      g:led(2, i, 2)
      g:led(5, i, 2)
      g:led(8, i, 2)
      g:led(11, i, 2)
      g:led(14, i, 2)
      g:led(16, i, 2)
      g:led(params:get("rate"..i), i, 8)
    end
  elseif altgrid and set_oct then
    for i = 1, 4 do
      g:led(8, i, 4) -- params:get("octave"..i) == 4 and 8 or
      g:led(9, i, 4) -- params:get("octave"..i) == 4 and 8 or

      if params:get("octave"..i) < 4 then
        g:led(params:get("octave"..i) + 4, i, 8)
      elseif params:get("octave"..i) > 4 then
        g:led(params:get("octave"..i) + 5, i, 8)
      end
    end
  elseif altgrid and set_trsp then
    for i = 1, 4 do
      g:led(8, i, 4)
      g:led(9, i, 4)
      if params:get("transpose"..i) < 0 then
        g:led(params:get("transpose"..i) + 8, i, 8)
      elseif params:get("transpose"..i) > 0 then
        g:led(params:get("transpose"..i) + 9, i, 8)
      end
    end
  end
  -- alt keys
  g:led(15, 5, set_start and 15 or 3)
  g:led(15, 6, set_end and 15 or 3)
  g:led(15, 7, set_loop and 15 or 3)
  g:led(15, 8, mod and 15 or 8)

  g:led(16, 5, set_rate and 15 or 3)
  g:led(16, 6, set_oct and 15 or 3)
  g:led(16, 7, set_trsp and 15 or 3)
  g:led(16, 8, alt and 15 or 8)
  -- functions
  for i = 1, 4 do
    g:led(1, i + 4, focus == i and 10 or 4) -- focus
    g:led(3, i + 4, track[i].running and 10 or 4)
    g:led(5, i + 4, track[i].dir == 1 and 10 or 4)
    g:led(6, i + 4, track[i].dir_mode == 1 and 6 or 2)
    g:led(7, i + 4, track[i].dir_mode == 2 and 6 or 2)
    g:led(8, i + 4, track[i].dir == 0 and 10 or 4)
  end
  -- presets
  for i = 1, 4 do
    g:led(10, i + 4, 3)
    g:led(11, i + 4, 3)
  end
  if p_set < 5 then
    g:led(10, p_set + 4, 8)
  else
    g:led(11, p_set, 8)
  end
  -- patterns
  for i = 1, 4 do
    g:led(13, i + 4, 3)
  end
  g:refresh()
end

-------- menu and redraw functions --------

function build_menu()
  for i = 1, 4 do
    if track[i].track_out == 2 then
      params:show("set_midi_device"..i)
      params:show("midi_out_channel"..i)
      params:show("vel_mode"..i)
      params:show("midi_vel_val"..i)
      params:show("midi_vel_range"..i)
    else
      params:hide("set_midi_device"..i)
      params:hide("midi_out_channel"..i)
      params:hide("vel_mode"..i)
      params:hide("midi_vel_val"..i)
      params:hide("midi_vel_range"..i)
    end
    if track[i].track_out == 3 then
      if (params:get("clock_crow_out") == 2 or params:get("clock_crow_out") == 3) then
        params:set("clock_crow_out", 1)
        params:hide("clock_crow_out")
        params:hide("clock_crow_out_div")
        params:hide("clock_crow_in_div")
      else
        params:show("clock_crow_out")
        params:show("clock_crow_out_div")
        params:show("clock_crow_in_div")
      end
    end
    if track[i].track_out == 4 then
      if (params:get("clock_crow_out") == 4 or params:get("clock_crow_out") == 5) then
        params:set("clock_crow_out", 1)
        params:hide("clock_crow_out")
        params:hide("clock_crow_out_div")
        params:hide("clock_crow_in_div")
      else
        params:show("clock_crow_out")
        params:show("clock_crow_out_div")
        params:show("clock_crow_in_div")
      end
    end
    if track[i].track_out == 5 then
      if params:get("jf_mode"..i) == 1 then
        params:show("jf_voice"..i)
      else
        params:hide("jf_voice"..i)
      end
      params:show("jf_amp"..i)
      params:show("jf_mode"..i)
    else
      params:hide("jf_mode"..i)
      params:hide("jf_voice"..i)
      params:hide("jf_amp"..i)
    end
  end
  _menu.rebuild_params()
  dirtyscreen = true
end

function redraw_fun()
 if dirtygrid == true then
   gridredraw()
   dirtygrid = false
 end
 if dirtyscreen == true then
   redraw()
   dirtyscreen = false
 end
end

function ledpulse()
 ledview = (ledview % 8) + 4 -- define range (1-15)
end

function drawgrid_connect()
 dirtygrid = true
 gridredraw()
end

function cleanup()
  grid.add = function() end
  crow.ii.jf.mode(0)
end