--[[
wave-amp version 1.0.0

The MIT License (MIT)
Copyright (c) 2016 CrazedProgrammer

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local wave = dofile("wave/wave.lua")

local cmdHelp = [[
-l                   lists all outputs connected to the computer.
-c <config file>     loads the parameters from a file.
parameters are separated by newlines.
-t <theme file>      loads the theme from a file.
-f <filter[:second]> sets the note filter for the outputs.
examples:
 -f 10111            sets the filter for all outputs to remove the bass instrument.
 -f 10011:01100      sets the filter so the bass and basedrum instruments only come out of the second output
-v <volume[:second]> sets the volume for the outputs.
--nrm --stp --rep --shf   sets the play mode.
--noui --noinput     disables the ui/keyboard input]]


local trackMode = 1
-- 1 = normal (go to next song on finish)
-- 2 = stop (stop on finish)
-- 3 = repeat (restart song on finish)
-- 4 = shuffle (go to random song on finish)

local files = { }
local tracks = { }
local context, track, instance

-- ui stuff
local noUI = false
local noInput = false
local screenWidth, screenHeight = term.getSize()
local trackScroll = 0
local currentTrack = 1
local vsEasings = {0, 0, 0, 0, 0}
local vsStep = 5
local vsDecline = 0.25

-- theme
local theme = term.isColor() and 
{
	topBar = colors.lime,
	topBarTitle = colors.white,
	topBarOption = colors.white,
	topBarOptionSelected = colors.lightGray,
	topBarClose = colors.white,
	song = colors.black,
	songBackground = colors.white,
	songSelected = colors.black,
	songSelectedBackground = colors.lightGray,
	scrollBackground = colors.lightGray,
	scrollBar = colors.gray,
	scrollButton = colors.black,
	visualiserBar = colors.lime,
	visualiserBackground = colors.green,
	progressTime = colors.white,
	progressBackground = colors.lightGray,
	progressLine = colors.gray,
	progressNub = colors.gray,
	progressNubBackground = colors.gray,
	progressNubChar = "=",
	progressButton = colors.white
}
or
{
	topBar = colors.lightGray,
	topBarTitle = colors.white,
	topBarOption = colors.white,
	topBarOptionSelected = colors.gray,
	topBarClose = colors.white,
	song = colors.black,
	songBackground = colors.white,
	songSelected = colors.black,
	songSelectedBackground = colors.lightGray,
	scrollBackground = colors.lightGray,
	scrollBar = colors.gray,
	scrollButton = colors.black,
	visualiserBar = colors.black,
	visualiserBackground = colors.gray,
	progressTime = colors.white,
	progressBackground = colors.lightGray,
	progressLine = colors.gray,
	progressNub = colors.gray,
	progressNubBackground = colors.gray,
	progressNubChar = "=",
	progressButton = colors.white
}

local running = true



local function addFiles(path)
	local dirstack = {path}
	while #dirstack > 0 do
		local dir = dirstack[1]
		table.remove(dirstack, 1)
		if dir ~= "rom" then
			for _, v in pairs(fs.list(dir)) do
				local path = (dir == "") and v or dir.."/"..v
				if fs.isDir(path) then
					dirstack[#dirstack + 1] = path
				elseif path:sub(#path - 3, #path) == ".nbs" then
					files[#files + 1] = path
				end
			end
		end
	end
end

local function init(args)
	local volumes = { }
	local filters = { }
	local outputs = wave.scanOutputs()
	local timestamp = 0

	if #outputs == 0 then
		error("no outputs found")
	end

	local i, argtype = 1
	while i <= #args do
		if not argtype then
			if args[i] == "-h" then
				print(cmdHelp)
				noUI = true
				running = false
				return
			elseif args[i] == "-c" or args[i] == "-v" or args[i] == "-f" or args[i] == "-t" then
				argtype = args[i]
			elseif args[i] == "-l" then
				print(#outputs.." outputs detected:")
				for i = 1, #outputs do
					print(i..":", outputs[i].type, type(outputs[i].native) == "string" and outputs[i].native or "")
				end
				noUI = true
				running = false
				return
			elseif args[i] == "--noui" then
				noUI = true
			elseif args[i] == "--noinput" then
				noInput = true
			elseif args[i] == "--nrm" then
				trackMode = 1
			elseif args[i] == "--stp" then
				trackMode = 2
			elseif args[i] == "--rep" then
				trackMode = 3
			elseif args[i] == "--shf" then
				trackMode = 4
			else
				local path = shell.resolve(args[i])
				if fs.isDir(path) then
					addFiles(path)
				elseif fs.exists(path) then
					files[#files + 1] = path
				end
			end
		else
			if argtype == "-c" then
				local path = shell.resolve(args[i])
				local handle = fs.open(path, "r")
				if not handle then
					error("config file does not exist: "..path)
				end
				local line = handle.readLine()
				while line do
					args[#args + 1] = line
					line = handle.readLine()
				end
				handle.close()
			elseif argtype == "-t" then
				local path = shell.resolve(args[i])
				local handle = fs.open(path, "r")
				if not handle then
					error("theme file does not exist: "..path)
				end
				local data = handle.readAll()
				handle.close()
				for k, v in pairs(colors) do
					data = data:gsub("colors."..k, tostring(v))
				end
				for k, v in pairs(colours) do
					data = data:gsub("colours."..k, tostring(v))
				end
				local newtheme = textutils.unserialize(data)
				for k, v in pairs(newtheme) do
					theme[k] = v
				end
			elseif argtype == "-v" then
				for str in args[i]:gmatch("([^:]+)") do
					local vol = tonumber(str)
					if vol then
						if vol >= 0 and vol <= 1 then
							volumes[#volumes + 1] = vol
						else
							error("invalid volume value: "..str)
						end
					else
						error("invalid volume value: "..str)
					end
				end
			elseif argtype == "-f" then
				for str in args[i]:gmatch("([^:]+)") do
					if #str == 5 then
						local filter = { }
						for i = 1, 5 do
							if str:sub(i, i) == "1" then
								filter[i] = true
							elseif str:sub(i, i) == "0" then
								filter[i] = false
							else
								error("invalid filter value: "..str)
							end
						end
						filters[#filters + 1] = filter
					else
						error("invalid filter value: "..str)
					end
				end
			end
			argtype = nil
		end
		i = i + 1
	end

	if #files == 0 then
		addFiles("")
	end

	i = 1
	print("loading tracks...")
	while i <= #files do
		local track
		pcall(function () track = wave.loadTrack(files[i]) end)
		if not track then
			print("failed to load "..files[i])
			os.sleep(0.2)
			table.remove(files, i)
		else
			tracks[i] = track
			print("loaded "..files[i])
			i = i + 1
		end
		if i % 10 == 0 then
			os.sleep(0)
		end
	end
	if #files == 0 then
		error("no tracks found")
	end

	if #volumes == 0 then
		volumes[1] = 1
	end
	if #filters == 0 then
		filters[1] = {true, true, true, true, true}
	end
	if #volumes == 1 then
		for i = 2, #outputs do
			volumes[i] = volumes[1]
		end
	end
	if #filters == 1 then
		for i = 2, #outputs do
			filters[i] = filters[1]
		end
	end
	if #volumes ~= #outputs then
		error("invalid amount of volume values: "..#volumes.." (must be 1 or "..#outputs..")")
	end
	if #filters ~= #outputs then
		error("invalid amount of filter values: "..#filters.." (must be 1 or "..#outputs..")")
	end

	for i = 1, #outputs do
		outputs[i].volume = volumes[i]
		outputs[i].filter = filters[i]
	end

	context = wave.createContext()
	context:addOutputs(outputs)
end




local function formatTime(secs)
	local mins = math.floor(secs / 60)
	secs = secs - mins * 60
	return string.format("%01d:%02d", mins, secs)
end

local function drawStatic()
	if noUI then return end
	term.setCursorPos(1, 1)
	term.setBackgroundColor(theme.topBar)
	term.setTextColor(theme.topBarTitle)
	term.write("wave-amp")
	term.write((" "):rep(screenWidth - 25))
	term.setTextColor(trackMode == 1 and theme.topBarOptionSelected or theme.topBarOption)
	term.write("nrm ")
	term.setTextColor(trackMode == 2 and theme.topBarOptionSelected or theme.topBarOption)
	term.write("stp ")
	term.setTextColor(trackMode == 3 and theme.topBarOptionSelected or theme.topBarOption)
	term.write("rep ")
	term.setTextColor(trackMode == 4 and theme.topBarOptionSelected or theme.topBarOption)
	term.write("shf ")
	term.setTextColor(theme.topBarClose)
	term.write("X")

	local scrollnub = math.floor(trackScroll / (#tracks - screenHeight + 7) * (screenHeight - 10) + 0.5) 

	term.setTextColor(theme.song)
	term.setBackgroundColor(theme.songBackground)
	for i = 1, screenHeight - 7 do
		local index = i + trackScroll
		term.setCursorPos(1, i + 1)
		term.setTextColor(index == currentTrack and theme.songSelected or theme.song)
		term.setBackgroundColor(index == currentTrack and theme.songSelectedBackground or theme.songBackground)
		local str = ""
		if tracks[index] then
			local track = tracks[index]
			str = formatTime(track.length / track.tempo).." "
			if #track.name > 0 then
				str = str..(#track.originalAuthor == 0 and track.author or track.originalAuthor).." - "..track.name
			else
				local name = fs.getName(files[index])
				str = str..name:sub(1, #name - 4)
			end
		end
		if #str > screenWidth - 1 then
			str = str:sub(1, screenWidth - 3)..".."
		end
		term.write(str)
		term.write((" "):rep(screenWidth - 1 - #str))
		term.setBackgroundColor((i >= scrollnub + 1 and i <= scrollnub + 3) and theme.scrollBar or theme.scrollBackground)
		if i == 1 then
			term.setTextColor(theme.scrollButton)
			term.write(_HOST and "\30" or "^")
		elseif i == screenHeight - 7 then
			term.setTextColor(theme.scrollButton)
			term.write(_HOST and "\31" or "v")
		else
			term.write(" ")
		end
	end
end

local function drawDynamic()
	if noUI then return end
	for i = 1, 5 do
		vsEasings[i] = vsEasings[i] - vsDecline
		if vsEasings[i] < 0 then
			vsEasings[i] = 0
		end
		local part = context.vs[i] > vsStep and vsStep or context.vs[i]
		if vsEasings[i] < part then
			vsEasings[i] = part
		end
		local full = math.floor(part / vsStep * screenWidth + 0.5)
		local easing = math.floor(vsEasings[i] / vsStep * screenWidth + 0.5)
		term.setCursorPos(1, screenHeight - 6 + i)
		term.setBackgroundColor(theme.visualiserBar)
		term.setTextColor(theme.visualiserBackground)
		term.write((" "):rep(full))
		term.write((_HOST and "\127" or "#"):rep(math.floor((easing - full) / 2)))
		term.setBackgroundColor(theme.visualiserBackground)
		term.setTextColor(theme.visualiserBar)
		term.write((_HOST and "\127" or "#"):rep(math.ceil((easing - full) / 2)))
		term.write((" "):rep(screenWidth - easing))
	end

	local progressnub = math.floor((instance.tick / track.length) * (screenWidth - 14) + 0.5)

	term.setCursorPos(1, screenHeight)
	term.setTextColor(theme.progressTime)
	term.setBackgroundColor(theme.progressBackground)
	term.write(formatTime(instance.tick / track.tempo))

	term.setTextColor(theme.progressLine)
	term.write("\136")
	term.write(("\140"):rep(progressnub))
	term.setTextColor(theme.progressNub)
	term.setBackgroundColor(theme.progressNubBackground)
	term.write(theme.progressNubChar)
	term.setTextColor(theme.progressLine)
	term.setBackgroundColor(theme.progressBackground)
	term.write(("\140"):rep(screenWidth - 14 - progressnub))
	term.write("\132")

	term.setTextColor(theme.progressTime)
	term.write(formatTime(track.length / track.tempo).." ")
	term.setTextColor(theme.progressButton)
	term.write(instance.playing and (_HOST and "|\016" or "|>") or "||")
end

local function playSong(index)
	if index >= 1 and index <= #tracks then
		currentTrack = index
		track = tracks[currentTrack]
		context:removeInstance(1)
		instance = context:addInstance(track, 1, trackMode ~= 2, trackMode == 3)
		if currentTrack <= trackScroll then
			trackScroll = currentTrack - 1
		end
		if currentTrack > trackScroll + screenHeight - 7 then
			trackScroll = currentTrack - screenHeight + 7
		end 
		drawStatic()
	end
end

local function nextSong()
	if trackMode == 1 then
		playSong(currentTrack + 1)
	elseif trackMode == 4 then
		playSong(math.random(#tracks))
	end
end

local function setScroll(scroll)
	trackScroll = scroll
	if trackScroll > #tracks - screenHeight + 7 then
		trackScroll = #tracks - screenHeight + 7 
	end
	if trackScroll < 0 then
		trackScroll = 0
	end
	drawStatic()
end

local function handleClick(x, y)
	if noUI then return end
	if y == 1 then
		if x == screenWidth then
			running = false
		elseif x >= screenWidth - 16 and x <= screenWidth - 2 and (x - screenWidth + 1) % 4 ~= 0 then
			trackMode = math.floor((x - screenWidth + 16) / 4) + 1
			instance.loop = trackMode == 3
			drawStatic()
		end
	elseif x < screenWidth and y >= 2 and y <= screenHeight - 6 then
		playSong(y - 1 + trackScroll)
	elseif x == screenWidth and y == 2 then
		setScroll(trackScroll - 2)
	elseif x == screenWidth and y == screenHeight - 6 then
		setScroll(trackScroll + 2)
	elseif x == screenWidth and y >= 3 and y <= screenHeight - 7 then
		setScroll(math.floor((y - 3) / (screenHeight - 10) * (#tracks - screenHeight + 7 ) + 0.5))
	elseif y == screenHeight then
		if x >= screenWidth - 1 and x <= screenWidth then
			instance.playing = not instance.playing
		elseif x >= 6 and x <= screenWidth - 8 then
			instance.tick = ((x - 6) / (screenWidth - 14)) * track.length
		end
	end
end

local function handleScroll(x, y, scroll)
	if noUI then return end
	if y >= 2 and y <= screenHeight - 6 then
		setScroll(trackScroll + scroll * 2)
	end
end

local function handleKey(key)
	if noInput then return end
	if key == keys.space then
		instance.playing = not instance.playing
	elseif key == keys.n then
		nextSong()
	elseif key == keys.p then
		playSong(currentTrack - 1)
	elseif key == keys.m then
		context.volume = (context.volume == 0) and 1 or 0
	elseif key == keys.left then
		instance.tick = instance.tick - track.tempo * 10
		if instance.tick < 1 then
			instance.tick = 1
		end
	elseif key == keys.right then
		instance.tick = instance.tick + track.tempo * 10
	elseif key == keys.up then
		context.volume = (context.volume == 1) and 1 or context.volume + 0.1
	elseif key == keys.down then
		context.volume = (context.volume == 0) and 0 or context.volume - 0.1
	elseif key == keys.j then
		setScroll(trackScroll + 2)
	elseif key == keys.k then
		setScroll(trackScroll - 2)
	elseif key == keys.pageUp then
		setScroll(trackScroll - 5)
	elseif key == keys.pageDown then
		setScroll(trackScroll + 5)
	elseif key == keys.leftShift then
		trackMode = trackMode % 4 + 1
		drawStatic()
	elseif key == keys.backspace then
		running = false
	end
end

local function run()
	playSong(1)
	drawStatic()
	drawDynamic()
	local timer = os.startTimer(0.05)
	while running do
		local e = {os.pullEventRaw()}
		if e[1] == "timer" and e[2] == timer then
			timer = os.startTimer(0)
			local prevtick = instance.tick
			context:update()
			if prevtick > 1 and instance.tick == 1 then
				nextSong()
			end
			drawDynamic()
		elseif e[1] == "terminate" then
			running = false
		elseif e[1] == "term_resize" then
			screenWidth, screenHeight = term.getSize()
		elseif e[1] == "mouse_click" then
			handleClick(e[3], e[4])
		elseif e[1] == "mouse_scroll" then
			handleScroll(e[3], e[4], e[2])
		elseif e[1] == "key" then
			handleKey(e[2])
		end
	end
end

local function exit()
	if noUI then return end
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
	term.setCursorPos(1, 1)
	term.clear()
end

init({...})
run()
exit()