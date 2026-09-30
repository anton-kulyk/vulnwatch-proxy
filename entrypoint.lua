#!/bin/lua
-- Custom entrypoint for tarampampam/3proxy: generates a two-listener config:
--   * 3128  HTTP proxy WITH basic auth (PROXY_LOGIN / PROXY_PASSWORD)
--   * 3129  HTTP proxy WITHOUT auth, ACL-locked to PROXY_BROWSER_ALLOW_IP
--           (for Chrome/Puppeteer, which cannot send proxy basic-auth)
-- Secrets come only from the environment; nothing is stored in the image/repo.

local CFG_PATH = "/etc/3proxy/3proxy.cfg"
local PROXY_BIN = "/bin/3proxy"

local function getenv(name, default)
  local val = os.getenv(name)
  if val == nil or val == "" then return default end
  return val
end

local function die(msg)
  io.stderr:write("entrypoint: " .. msg .. "\n")
  os.exit(1)
end

local log_output       = getenv("LOG_OUTPUT", "/dev/stdout")
local primary_resolver = getenv("PRIMARY_RESOLVER", "1.0.0.1")
local secondary_resolv = getenv("SECONDARY_RESOLVER", "8.8.4.4")
local max_connections  = getenv("MAX_CONNECTIONS", "512")
local dns_cache_size   = getenv("DNS_CACHE_SIZE", "65536")
local proxy_login      = getenv("PROXY_LOGIN", "")
local proxy_password   = getenv("PROXY_PASSWORD", "")
local proxy_port       = getenv("PROXY_PORT", "3128")
local browser_port     = getenv("PROXY_BROWSER_PORT", "3129")
local browser_allow_ip = getenv("PROXY_BROWSER_ALLOW_IP", "0.0.0.0/0")

local lines = {}
local function add(s) lines[#lines + 1] = s end

add("log " .. log_output)
add("logformat \"-\\\"\\\"+_G{\\\"\\\"time_unix\\\"\\\":%t, \\\"\\\"error\\\"\\\":{\\\"\\\"code\\\"\\\":\\\"\\\"%E\\\"\\\"}}\"")
add("nserver " .. primary_resolver)
add("nserver " .. secondary_resolv)
add("nscache " .. dns_cache_size)
add("maxconn " .. max_connections)
add("timeouts 1 5 30 60 180 1800 15 60")
add("")

-- Listener 1: authenticated HTTP proxy for curl / Nuclei / WPScan / Guzzle
if proxy_login == "" or proxy_password == "" then
  die("PROXY_LOGIN and PROXY_PASSWORD are required")
end
add("users " .. proxy_login .. ":CL:" .. proxy_password)
add("auth strong")
add("allow " .. proxy_login)
add("proxy -p" .. proxy_port .. " -n -a -i0.0.0.0 -e0.0.0.0")
add("")

-- Listener 2: unauthenticated HTTP proxy for Chrome/Puppeteer,
-- reachable only from the allowed source IP/subnet
add("auth none")
add("allow * * " .. browser_allow_ip)
add("proxy -p" .. browser_port .. " -n -a -i0.0.0.0 -e0.0.0.0")
add("")

local f = io.open(CFG_PATH, "w")
if not f then die("cannot write " .. CFG_PATH) end
f:write(table.concat(lines, "\n") .. "\n")
f:close()

-- os.exec replaces the current process image with 3proxy (POSIX exec).
-- The official image does the same; it never returns on success.
local _, exec_err, exec_code = os.exec(PROXY_BIN, CFG_PATH)
die(PROXY_BIN .. ": " .. tostring(exec_err) .. " (errno " .. tostring(exec_code) .. ")")
