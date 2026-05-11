-- Simple HTTP server that logs GET requests to /state/{endpoint}.log and responds 204.

local socket = require("socket")

os.execute("mkdir -p /state")

local server = assert(socket.bind("*", 8080))
server:settimeout(nil)

while true do
	local client = server:accept()
	if client then
		client:settimeout(5)
		local line = client:receive("*l")
		local path = line and line:match("^%u+ (/[^ ]*)")
		repeat
			local hdr, err = client:receive("*l")
			if err then
				break
			end
		until not hdr or hdr == "" or hdr == "\r"
		if path then
			local name = path:gsub("^/+", ""):gsub("/", "_")
			if name == "" then
				name = "root"
			end
			local f = io.open("/state/" .. name .. ".log", "a")
			if f then
				f:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. path .. "\n")
				f:close()
			end
		end
		client:send("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
		client:close()
	end
end
