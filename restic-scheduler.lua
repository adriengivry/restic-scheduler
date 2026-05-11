-- restic-scheduler: runs restic backup/check jobs on a cron schedule.

io.stdout:setvbuf("line")
io.stderr:setvbuf("line")

-- Returns the value of an environment variable, or a default if unset/empty.
local function env(name, default)
	local v = os.getenv(name)
	return (v ~= nil and v ~= "") and v or default
end

-- Returns the value of an env var (nil and "" are distinct: nil → default, "" → "").
local function env_or_default(name, default)
	local v = os.getenv(name)
	if v == nil then
		return default
	end
	return v
end

-- Validate required variables (restic reads them from env automatically).
for _, name in ipairs({ "RESTIC_REPOSITORY", "RESTIC_PASSWORD" }) do
	if not os.getenv(name) or os.getenv(name) == "" then
		io.stderr:write("Missing required environment variable: " .. name .. "\n")
		os.exit(1)
	end
end

local BACKUP_CRON = env_or_default("BACKUP_CRON", "0 3 * * *")
local CHECK_CRON = env_or_default("CHECK_CRON", "0 6 * * *")
local AUTO_INIT = env("RESTIC_AUTO_INIT", "true")
local BACKUP_PATH = env("BACKUP_PATH", "/data")
local BACKUP_ARGS = env("RESTIC_BACKUP_ARGS", "--verbose --one-file-system")
local FORGET_ARGS = env("RESTIC_FORGET_ARGS", "--keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune")
local CHECK_ARGS = env("CHECK_ARGS", "--read-data-subset=10%")
local RETRY_LOCK = env("RESTIC_RETRY_LOCK", "35m")
local PING_BACKUP = os.getenv("PING_URL_BACKUP")
local PING_CHECK = os.getenv("PING_URL_CHECK")

local function timestamp()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- Execute a command (output streams to container stdout/stderr). Returns true on success.
local function exec(cmd)
	return os.execute(cmd) == true
end

-- Execute a command and capture all output. Returns (output, success).
local function capture(cmd)
	local f = assert(io.popen(cmd .. " 2>&1"))
	local out = f:read("*a")
	local ok = f:close()
	return out, ok == true
end

local function repository_ready()
	local _, ok = capture("restic cat config --no-lock")
	return ok
end

local function unlock_repository()
	local out, ok = capture("restic unlock")
	if ok then
		out = out:match("^%s*(.-)%s*$")
		if out ~= "" then
			print(out)
		end
		return
	end
	if
		out:find("config file does not exist", 1, true)
		or out:find("unable to open config file", 1, true)
		or out:find("Is there a repository at the following location", 1, true)
	then
		return
	end
	io.stderr:write(out .. "\n")
	os.exit(1)
end

local function ensure_repository_exists()
	for i = 1, 5 do
		if repository_ready() then
			return
		end
		if i < 5 then
			exec("sleep 2")
		end
	end

	if AUTO_INIT ~= "true" then
		io.stderr:write("Restic repository is not accessible and RESTIC_AUTO_INIT is disabled.\n")
		os.exit(1)
	end

	print("Initializing restic repository")
	local out, ok = capture("restic init")
	if not ok and not out:find("already initialized", 1, true) then
		io.stderr:write(out .. "\n")
		os.exit(1)
	end
	io.write(out)

	for _ = 1, 10 do
		if repository_ready() then
			return
		end
		exec("sleep 2")
	end

	io.stderr:write("Restic repository is not ready after initialization.\n")
	os.exit(1)
end

-- Cron field matching: supports *, numbers, ranges (1-5), steps (*/2, 1-5/2), lists (1,2,3).
local function field_matches(field, value)
	if field == "*" then
		return true
	end
	for part in field:gmatch("[^,]+") do
		local base, step = part:match("^(.+)/(%d+)$")
		if not base then
			base, step = part, "1"
		end
		step = tonumber(step)
		local lo, hi
		if base == "*" then
			lo, hi = 0, 99
		else
			local a, b = base:match("^(%d+)-(%d+)$")
			if a then
				lo, hi = tonumber(a), tonumber(b)
			else
				lo = tonumber(base)
				hi = lo
			end
		end
		if lo and value >= lo and value <= hi and (value - lo) % step == 0 then
			return true
		end
	end
	return false
end

-- Returns true if the cron expression matches the given os.time() value.
local function matches_cron(expr, t)
	local d = os.date("*t", t)
	local f = {}
	for part in expr:gmatch("%S+") do
		f[#f + 1] = part
	end
	if #f ~= 5 then
		return false
	end
	local dow = d.wday - 1 -- Lua: 1=Sun → cron: 0=Sun
	return field_matches(f[1], d.min)
		and field_matches(f[2], d.hour)
		and field_matches(f[3], d.day)
		and field_matches(f[4], d.month)
		and (field_matches(f[5], dow) or (dow == 0 and field_matches(f[5], 7)))
end

local function run_backup()
	print("### BEGIN BACKUP " .. timestamp() .. " ###")
	local ok = exec("restic --retry-lock " .. RETRY_LOCK .. " backup " .. BACKUP_PATH .. " " .. BACKUP_ARGS)
	if ok and FORGET_ARGS ~= "" then
		ok = exec("restic --retry-lock " .. RETRY_LOCK .. " forget " .. FORGET_ARGS)
	end
	if ok and PING_BACKUP then
		ok = exec("curl -fsS --retry 3 --max-time 30 " .. PING_BACKUP .. " >/dev/null")
	end
	if ok then
		print("### END BACKUP " .. timestamp() .. " ###")
	else
		io.stderr:write("### FAILED backup " .. timestamp() .. " ###\n")
	end
end

local function run_check()
	print("### BEGIN CHECK " .. timestamp() .. " ###")
	local ok = exec("restic --retry-lock " .. RETRY_LOCK .. " check " .. CHECK_ARGS)
	if ok and PING_CHECK then
		ok = exec("curl -fsS --retry 3 --max-time 30 " .. PING_CHECK .. " >/dev/null")
	end
	if ok then
		print("### END CHECK " .. timestamp() .. " ###")
	else
		io.stderr:write("### FAILED check " .. timestamp() .. " ###\n")
	end
end

-- Startup
unlock_repository()
ensure_repository_exists()

if BACKUP_CRON == "" and CHECK_CRON == "" then
	io.stderr:write("No jobs configured. Set BACKUP_CRON and/or CHECK_CRON.\n")
	os.exit(1)
end

print("Scheduled jobs:")
if BACKUP_CRON ~= "" then
	print("  backup: " .. BACKUP_CRON)
end
if CHECK_CRON ~= "" then
	print("  check:  " .. CHECK_CRON)
end
print("restic-scheduler ready")

-- Main loop: check due jobs for the current minute, then sleep until the next one.
-- Tracking the last fired minute ensures each minute fires at most once, even if a
-- job runs longer than 60 seconds (the loop catches up without double-firing).
local last_minute = -1
while true do
	local now = os.time()
	local t = now - now % 60  -- current minute boundary
	if t ~= last_minute then
		last_minute = t
		if BACKUP_CRON ~= "" and matches_cron(BACKUP_CRON, t) then
			run_backup()
		end
		if CHECK_CRON ~= "" and matches_cron(CHECK_CRON, t) then
			run_check()
		end
	end
	exec("sleep " .. (60 - os.time() % 60))
end
