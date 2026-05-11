-- Integration test suite for restic-scheduler.

io.stdout:setvbuf("line")
io.stderr:setvbuf("line")

local IMAGE = "restic-scheduler:local"
local ENV_FILE = "test/.env"
local COMPOSE_FILE = "test/docker-compose.yml"

local function exec(cmd)
	return os.execute(cmd) == true
end

local function capture(cmd)
	local f = assert(io.popen(cmd .. " 2>&1"))
	local out = f:read("*a")
	local ok = f:close()
	return out, ok == true
end

-- Detect docker compose (v2 plugin or standalone).
local compose_bin
if exec("docker compose version >/dev/null 2>&1") then
	compose_bin = "docker compose"
elseif exec("docker-compose version >/dev/null 2>&1") then
	compose_bin = "docker-compose"
else
	io.stderr:write("docker compose or docker-compose is required\n")
	os.exit(1)
end

local COMPOSE = "TEST_IMAGE=" .. IMAGE .. " " .. compose_bin .. " --env-file " .. ENV_FILE .. " -f " .. COMPOSE_FILE

-- Build and run a docker compose command, optionally prepending extra env vars.
local function compose(extra_env, args)
	if extra_env then
		return extra_env .. " " .. COMPOSE .. " " .. args
	end
	return COMPOSE .. " " .. args
end

local function restic_logs()
	local id = capture(compose(nil, "ps -q restic")):match("^%s*(.-)%s*$")
	if id == "" then
		return ""
	end
	return (capture("docker logs " .. id .. " 2>&1"))
end

local function ping_log_nonempty(name)
	return exec(compose(nil, "exec -T ping test -s /state/" .. name .. ".log"))
end

local function reset_ping_logs()
	exec(compose(nil, "exec -T ping sh -c ': > /state/backup.log && : > /state/check.log'"))
end

local function wait_for(label, attempts, predicate)
	print("Waiting for " .. label)
	for i = 1, attempts do
		if predicate() then
			return
		end
		if i == attempts then
			error(label .. " did not complete in time\n" .. restic_logs())
		end
		exec("sleep 2")
	end
end

local function cleanup()
	exec(compose(nil, "down -v --remove-orphans >/dev/null 2>&1"))
end

local ok, err = pcall(function()
	print("Building images")
	assert(exec("docker build -t " .. IMAGE .. " ."), "docker build failed")
	assert(exec(compose(nil, "build ping")), "ping image build failed")

	print("Starting ping receiver")
	assert(exec(compose(nil, "up -d ping")), "failed to start ping service")

	-- Phase 1: test backup cron
	print("\nTesting scheduled backup configuration")
	reset_ping_logs()
	assert(exec(compose("BACKUP_CRON='* * * * *' CHECK_CRON=''", "up -d --force-recreate restic")))

	wait_for("scheduler startup", 30, function()
		return restic_logs():find("restic-scheduler ready", 1, true) ~= nil
	end)

	wait_for("scheduled backup job", 40, function()
		return restic_logs():find("### END BACKUP", 1, true) ~= nil and ping_log_nonempty("backup")
	end)

	assert(exec(compose(nil, "exec -T restic restic ls latest >/dev/null")), "restic ls latest failed")
	print("--- backup restic logs ---")
	io.write(restic_logs())
	print("--- backup ping callbacks ---")
	exec(compose(nil, "exec -T ping cat /state/backup.log"))

	-- Phase 2: test that an existing repo isn't re-initialised, then test check cron
	print("\nTesting existing repository startup and scheduled check")
	reset_ping_logs()
	assert(exec(compose("BACKUP_CRON='' CHECK_CRON='* * * * *'", "up -d --force-recreate restic")))

	wait_for("scheduler startup", 30, function()
		return restic_logs():find("restic-scheduler ready", 1, true) ~= nil
	end)

	local logs = restic_logs()
	if logs:find("created restic repository", 1, true) then
		error("Container recreated an existing repository\n" .. logs)
	end
	if logs:find("Fatal:", 1, true) then
		error("Container hit a fatal error when starting with an existing repository\n" .. logs)
	end

	wait_for("scheduled check job", 40, function()
		return restic_logs():find("### END CHECK", 1, true) ~= nil and ping_log_nonempty("check")
	end)

	print("--- check restic logs ---")
	io.write(restic_logs())
	print("--- check ping callbacks ---")
	exec(compose(nil, "exec -T ping cat /state/check.log"))
end)

cleanup()

if not ok then
	io.stderr:write(tostring(err) .. "\n")
	os.exit(1)
end

print("\nTest stack passed")
