#!/bin/lua

-- Generated copies pin one immutable Maintainer bundle. This bootstrap stays
-- out of the managed 173-file set so it can repair a mixed installation.
local EXPECTED_RELEASE = "maintainer-c0.1.2-a0.1.56-g0.1.0-d0.1.59-x0.1.8-24feb3ca9cdd"
local EXPECTED_BUNDLE_SHA256 = "86b62e165722eb20ea9e63b0f7fba67154111cac6b43dbbddbe3de34da821f27"
local EXPECTED_FILE_COUNT = 173
local EXPECTED_TARGET_CONTRACT_SHA256 = "ca6f8844ffc6ee916f70063990560ad15eddd381f65e88a24894e245407b533f"
local EXPECTED_PERSISTED_MANIFEST_SHA256 = "d60bcd7c79fd959a511062919179d578fadd92e5c4c4c63cb0f3dffb7a7b31ba"

local filesystem = require("filesystem")
local computer = require("computer")

local ROOT = "/var/oc/releases/maintainer"
local STATE_PATH = ROOT .. "/state"
local FILES_PATH = ROOT .. "/files.tsv"
local INVENTORY_PATH = ROOT .. "/inventory.tsv"
local LOCK_PATH = ROOT .. "/lock"
local LOCK_OWNER_PATH = LOCK_PATH .. "/owner"
local INHIBIT_PATH = ROOT .. "/inhibit"
local RECEIPT_PATH = ROOT .. "/last-release"
local POWER_CYCLE_MARKER = "/tmp/oc-release-stage-" .. EXPECTED_BUNDLE_SHA256:sub(1, 12)
local RELEASE_KEY = EXPECTED_BUNDLE_SHA256:sub(1, 12)
local ARTIFACT_PREFIX = ".oc-release-" .. RELEASE_KEY
local MAX_LINE = 512
local MAX_FILE_BYTES = 24576
local HEADROOM_BYTES = 262144
local CONNECT_TIMEOUT = 30
local IDLE_TIMEOUT = 30
local TOTAL_TIMEOUT = 600
local MASK = 0xffffffff

local api = {}

local function fail(message)
  error(tostring(message or "unknown failure"), 0)
end

local function checked(condition, message)
  if not condition then fail(message) end
  return condition
end

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitTabs(line)
  local values = {}
  for value in (tostring(line) .. "\t"):gmatch("(.-)\t") do
    values[#values + 1] = value
  end
  return values
end

local function canonicalUnsigned(value)
  value = tostring(value or "")
  return value == "0" or value:match("^[1-9][0-9]*$") ~= nil
end

local function allowedTarget(path)
  if type(path) ~= "string" or #path < 2 or #path > 240 or path:sub(1, 1) ~= "/" then return false end
  if path:find("\\", 1, true) or path:find("..", 1, true) or path:find("//", 1, true) or path:find("[%z\1-\31\127]") then return false end
  if path:match("^/usr/lib/oc/[%w_./%-]+$") then return true end
  if path:match("^/usr/bin/[%w_.%-]+$") then return true end
  if path:match("^/etc/rc%.d/[%w_.%-]+$") then return true end
  return path == "/home/dashboard.lua" or path == "/home/.shrc"
end

local function artifactPaths(target)
  return target .. ARTIFACT_PREFIX .. ".new",
    target .. ARTIFACT_PREFIX .. ".part",
    target .. ARTIFACT_PREFIX .. ".old",
    target .. ARTIFACT_PREFIX .. ".replaced"
end

local function requirePlainPath(path, label)
  checked(type(filesystem.canonical) == "function" and type(filesystem.isLink) == "function" and
    type(filesystem.realPath) == "function", "OpenOS filesystem link inspection is unavailable")
  local canonical, canonicalReason = filesystem.canonical(path)
  checked(type(canonical) == "string", "cannot canonicalize " .. label .. ": " .. tostring(canonicalReason))
  checked(canonical == path, label .. " path is not canonical: " .. tostring(path))
  local prefix = ""
  local parentExists = true
  for segment in path:gmatch("[^/]+") do
    prefix = prefix .. "/" .. segment
    if parentExists then
      local linked, linkReason = filesystem.isLink(prefix)
      checked(linked ~= nil, "cannot inspect link " .. prefix .. ": " .. tostring(linkReason))
      checked(linked == false, label .. " traverses a symbolic link: " .. prefix)
      parentExists = filesystem.exists(prefix)
    end
  end
  local real, realReason = filesystem.realPath(path)
  checked(type(real) == "string", "cannot resolve " .. label .. ": " .. tostring(realReason))
  local realCanonical = filesystem.canonical(real)
  checked(realCanonical == canonical, label .. " resolves outside its canonical path: " .. tostring(real))
end

local function requirePlainManagedPaths(entry)
  requirePlainPath(entry.target, "managed target")
  local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
  requirePlainPath(newPath, "release new artifact")
  requirePlainPath(partPath, "release partial artifact")
  requirePlainPath(oldPath, "release rollback artifact")
  requirePlainPath(replacedPath, "release quarantine artifact")
end

local function requirePlainReleasePaths()
  for _, path in ipairs({
    ROOT, STATE_PATH, STATE_PATH .. ".next", FILES_PATH, FILES_PATH .. ".next",
    INVENTORY_PATH, INVENTORY_PATH .. ".next", LOCK_PATH, LOCK_OWNER_PATH,
    LOCK_OWNER_PATH .. ".next", INHIBIT_PATH, INHIBIT_PATH .. ".next",
    RECEIPT_PATH, RECEIPT_PATH .. ".next", POWER_CYCLE_MARKER,
    POWER_CYCLE_MARKER .. ".next",
  }) do
    requirePlainPath(path, "release metadata")
  end
end

local function ror(value, count)
  return ((value >> count) | ((value << (32 - count)) & MASK)) & MASK
end

local SHA_K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function shaNew()
  return {
    h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 },
    buffer = "",
    bytes = 0,
    blocks = 0,
  }
end

local function shaBlock(context, block)
  local words = {}
  for index = 0, 15 do
    local offset = index * 4 + 1
    local a, b, c, d = block:byte(offset, offset + 3)
    words[index + 1] = (((a << 24) | (b << 16) | (c << 8) | d) & MASK)
  end
  for index = 17, 64 do
    local x, y = words[index - 15], words[index - 2]
    local s0 = (ror(x, 7) ~ ror(x, 18) ~ (x >> 3)) & MASK
    local s1 = (ror(y, 17) ~ ror(y, 19) ~ (y >> 10)) & MASK
    words[index] = (words[index - 16] + s0 + words[index - 7] + s1) & MASK
  end
  local a, b, c, d = context.h[1], context.h[2], context.h[3], context.h[4]
  local e, f, g, h = context.h[5], context.h[6], context.h[7], context.h[8]
  for index = 1, 64 do
    local sum1 = (ror(e, 6) ~ ror(e, 11) ~ ror(e, 25)) & MASK
    local choice = ((e & f) ~ ((~e) & g)) & MASK
    local temp1 = (h + sum1 + choice + SHA_K[index] + words[index]) & MASK
    local sum0 = (ror(a, 2) ~ ror(a, 13) ~ ror(a, 22)) & MASK
    local majority = ((a & b) ~ (a & c) ~ (b & c)) & MASK
    local temp2 = (sum0 + majority) & MASK
    h, g, f, e, d, c, b, a = g, f, e, (d + temp1) & MASK, c, b, a, (temp1 + temp2) & MASK
  end
  context.h[1] = (context.h[1] + a) & MASK
  context.h[2] = (context.h[2] + b) & MASK
  context.h[3] = (context.h[3] + c) & MASK
  context.h[4] = (context.h[4] + d) & MASK
  context.h[5] = (context.h[5] + e) & MASK
  context.h[6] = (context.h[6] + f) & MASK
  context.h[7] = (context.h[7] + g) & MASK
  context.h[8] = (context.h[8] + h) & MASK
  context.blocks = context.blocks + 1
  if context.blocks % 64 == 0 then os.sleep(0) end
end

local function shaUpdate(context, value)
  value = tostring(value or "")
  if #value == 0 then return context end
  context.bytes = context.bytes + #value
  local data = context.buffer .. value
  local offset = 1
  while #data - offset + 1 >= 64 do
    shaBlock(context, data:sub(offset, offset + 63))
    offset = offset + 64
  end
  context.buffer = data:sub(offset)
  return context
end

local function shaFinal(context)
  local byteCount = context.bytes
  local paddingCount = 56 - ((byteCount + 1) % 64)
  if paddingCount < 0 then paddingCount = paddingCount + 64 end
  local high = math.floor(byteCount / 536870912) & MASK
  local low = (byteCount * 8) & MASK
  local lengthBytes = string.char(
    (high >> 24) & 255, (high >> 16) & 255, (high >> 8) & 255, high & 255,
    (low >> 24) & 255, (low >> 16) & 255, (low >> 8) & 255, low & 255)
  shaUpdate(context, "\128" .. string.rep("\0", paddingCount) .. lengthBytes)
  checked(#context.buffer == 0, "SHA-256 finalization error")
  local out = {}
  for index = 1, 8 do out[index] = string.format("%08x", context.h[index]) end
  return table.concat(out)
end

function api.sha256(value)
  return shaFinal(shaUpdate(shaNew(), value))
end

local function closeRead(handle)
  if handle then pcall(handle.close, handle) end
end

local function finishWrite(handle)
  local ok, value, reason = pcall(handle.flush, handle)
  if not ok or not value then
    closeRead(handle)
    fail("file flush failed: " .. tostring(reason or value))
  end
  local closeOk, closeValue, closeReason = pcall(handle.close, handle)
  if not closeOk or closeValue == false then fail("file close failed: " .. tostring(closeReason or closeValue)) end
end

local function writeChunk(handle, value)
  local ok, result, reason = pcall(handle.write, handle, value)
  if not ok or not result then fail("file write failed: " .. tostring(reason or result)) end
end

local function ensureDirectory(path)
  if filesystem.exists(path) then
    checked(not filesystem.isDirectory or filesystem.isDirectory(path), "expected directory: " .. path)
    return
  end
  local ok, reason = filesystem.makeDirectory(path)
  checked(ok, "cannot create directory " .. path .. ": " .. tostring(reason))
end

local function ensureParent(path)
  local parent = filesystem.path(path)
  checked(type(parent) == "string" and parent ~= "", "cannot resolve parent for " .. path)
  ensureDirectory(parent)
end

local function removeFile(path)
  if not filesystem.exists(path) then return true end
  checked(not filesystem.isDirectory or not filesystem.isDirectory(path), "refusing to remove directory: " .. path)
  local ok, reason = filesystem.remove(path)
  checked(ok, "cannot remove " .. path .. ": " .. tostring(reason))
  return true
end

local function renameFile(fromPath, toPath)
  local ok, reason = filesystem.rename(fromPath, toPath)
  checked(ok, "rename failed " .. fromPath .. " -> " .. toPath .. ": " .. tostring(reason))
end

local function writeTextAtomic(path, text)
  ensureParent(path)
  local nextPath = path .. ".next"
  removeFile(nextPath)
  local handle, reason = io.open(nextPath, "wb")
  checked(handle ~= nil, "cannot open " .. nextPath .. ": " .. tostring(reason))
  local ok, writeReason = pcall(function()
    writeChunk(handle, text)
    finishWrite(handle)
    handle = nil
  end)
  if handle then closeRead(handle) end
  if not ok then removeFile(nextPath); fail(writeReason) end
  renameFile(nextPath, path)
end

local function readAll(path, limit)
  local handle, reason = io.open(path, "rb")
  if not handle then return nil, reason end
  local chunks, count = {}, 0
  while true do
    local ok, chunk, readReason = pcall(handle.read, handle, 4096)
    if not ok then closeRead(handle); return nil, chunk end
    if not chunk then
      if readReason then closeRead(handle); return nil, readReason end
      break
    end
    count = count + #chunk
    if limit and count > limit then closeRead(handle); return nil, "file exceeds limit" end
    chunks[#chunks + 1] = chunk
  end
  closeRead(handle)
  return table.concat(chunks)
end

local function hashFile(path)
  local handle, reason = io.open(path, "rb")
  if not handle then return nil, reason end
  local context = shaNew()
  while true do
    local ok, chunk, readReason = pcall(handle.read, handle, 8192)
    if not ok then closeRead(handle); return nil, chunk end
    if not chunk then
      if readReason then closeRead(handle); return nil, readReason end
      break
    end
    shaUpdate(context, chunk)
  end
  closeRead(handle)
  return shaFinal(context)
end

local function fileHash(path)
  if not filesystem.exists(path) then return nil end
  checked(not filesystem.isDirectory or not filesystem.isDirectory(path), "managed path became a directory: " .. path)
  local digest, reason = hashFile(path)
  checked(digest ~= nil, "cannot hash " .. path .. ": " .. tostring(reason))
  return digest
end

local function armPowerCycleGate(nextAction)
  requirePlainPath(POWER_CYCLE_MARKER, "power-cycle marker")
  requirePlainPath(POWER_CYCLE_MARKER .. ".next", "power-cycle marker staging path")
  local body = "release=" .. EXPECTED_RELEASE .. "\nnext_action=" .. tostring(nextAction) .. "\n"
  writeTextAtomic(POWER_CYCLE_MARKER, body)
  local stored, reason = readAll(POWER_CYCLE_MARKER, 4096)
  checked(stored == body, "cannot verify power-cycle marker: " .. tostring(reason or "content mismatch"))
  checked(not filesystem.exists(POWER_CYCLE_MARKER .. ".next"), "power-cycle marker promotion is incomplete")
end

local function consumeFreshPowerCycle(action)
  requirePlainPath(POWER_CYCLE_MARKER, "power-cycle marker")
  requirePlainPath(POWER_CYCLE_MARKER .. ".next", "power-cycle marker staging path")
  checked(not filesystem.exists(POWER_CYCLE_MARKER) and not filesystem.exists(POWER_CYCLE_MARKER .. ".next"),
    action .. " requires: run shutdown, wait until visibly OFF, then power on manually; a soft reboot does not qualify")
  -- Consume the proof before inspecting config/process state. Any failed gate can
  -- therefore be retried only after another full shutdown kills detached threads.
  armPowerCycleGate(action)
end

local function syntaxCheck(path, target)
  if target == "/home/.shrc" then return true end
  local source, reason = readAll(path, MAX_FILE_BYTES + 1)
  checked(source ~= nil, "cannot read staged Lua " .. target .. ": " .. tostring(reason))
  if target:match("^/usr/bin/") then
    checked(source:match("^#!/bin/lua[\r]?\n") ~= nil, "OpenOS command lacks #!/bin/lua: " .. target)
  end
  if source:sub(1, 2) == "#!" then source = source:match("^[^\r\n]*[\r]?\n(.*)$") or "" end
  local chunk, compileReason = load(source, "=" .. target, "t", {})
  checked(chunk ~= nil, "Lua syntax check failed for " .. target .. ": " .. tostring(compileReason))
  return true
end

local function parseState()
  local sourcePath = filesystem.exists(STATE_PATH) and STATE_PATH or
    (filesystem.exists(STATE_PATH .. ".next") and STATE_PATH .. ".next" or nil)
  if not sourcePath then return nil end
  local text, reason = readAll(sourcePath, 4096)
  checked(text ~= nil, "cannot read release state: " .. tostring(reason))
  local state = {}
  for rawLine in (text .. "\n"):gmatch("([^\n]*)\n") do
    local line = rawLine:gsub("\r$", "")
    if line ~= "" then
      local key, value = line:match("^([a-z_]+)=(.*)$")
      checked(key ~= nil and state[key] == nil, "invalid release state line")
      state[key] = value
    end
  end
  checked(state.format == "1", "unsupported release state")
  checked(state.release == EXPECTED_RELEASE and state.bundle == EXPECTED_BUNDLE_SHA256,
    "another release owns the transaction; use its pinned installer")
  local phases = {
    staging = true, staged = true, applying = true, applied = true,
    rolling_back = true, rolled_back = true, finalizing = true,
  }
  checked(phases[state.phase], "invalid release phase")
  checked(canonicalUnsigned(state.index), "invalid release cursor")
  state.index = tonumber(state.index)
  checked(state.index >= 0 and state.index <= EXPECTED_FILE_COUNT, "release cursor is out of range")
  state.recovered_from_next = sourcePath ~= STATE_PATH
  return state
end

local function writeState(phase, index, url)
  checked(type(phase) == "string" and phase:match("^[a-z_]+$"), "invalid release phase")
  url = tostring(url or "")
  checked(not url:find("[\r\n]"), "invalid state URL")
  writeTextAtomic(STATE_PATH, table.concat({
    "format=1",
    "release=" .. EXPECTED_RELEASE,
    "bundle=" .. EXPECTED_BUNDLE_SHA256,
    "phase=" .. phase,
    "index=" .. tostring(tonumber(index) or 0),
    "url=" .. url,
    "",
  }, "\n"))
end

local function canonicalizeState(state)
  if state and state.recovered_from_next then
    checked(not filesystem.exists(STATE_PATH) and filesystem.exists(STATE_PATH .. ".next"), "release state recovery evidence changed")
    renameFile(STATE_PATH .. ".next", STATE_PATH)
    state.recovered_from_next = false
  end
  return state
end

local function canonicalEntryLine(index, system, digest, size, target)
  return table.concat({ tostring(index), system, digest, tostring(size), target }, "\t") .. "\n"
end

local function newPersistedManifestDigest()
  local digest = shaNew()
  shaUpdate(digest, "OC-MAINTAINER-PERSISTED-MANIFEST\t1\n")
  shaUpdate(digest, "FILES\t" .. tostring(EXPECTED_FILE_COUNT) .. "\n")
  return digest
end

local function encodeEntries(entries)
  local lines = {}
  for index, entry in ipairs(entries) do
    lines[index] = canonicalEntryLine(entry.index, entry.system, entry.sha256, entry.size, entry.target)
  end
  return table.concat(lines)
end

local function parseEntries()
  local text, reason = readAll(FILES_PATH, 65536)
  checked(text ~= nil, "release file inventory is unavailable: " .. tostring(reason))
  local entries, seen = {}, {}
  local allowedSystems = { core = true, ae2 = true, gt_power = true, dashboard = true, commands = true }
  local contractDigest, manifestDigest = shaNew(), newPersistedManifestDigest()
  for rawLine in (text .. "\n"):gmatch("([^\n]*)\n") do
    local line = rawLine:gsub("\r$", "")
    if line ~= "" then
      local fields = splitTabs(line)
      checked(#fields == 5, "invalid staged file row")
      checked(canonicalUnsigned(fields[1]) and canonicalUnsigned(fields[4]), "noncanonical staged file integer")
      local index, size = tonumber(fields[1]), tonumber(fields[4])
      checked(index == #entries + 1 and size and size >= 0 and size <= MAX_FILE_BYTES, "invalid staged file index or size")
      checked(fields[3]:match("^[0-9a-f]+$") and #fields[3] == 64, "invalid staged file digest")
      checked(allowedSystems[fields[2]], "invalid staged system")
      checked(allowedTarget(fields[5]) and not seen[fields[5]], "invalid or duplicate staged target")
      seen[fields[5]] = true
      shaUpdate(contractDigest, fields[2] .. "\t" .. fields[5] .. "\n")
      shaUpdate(manifestDigest, canonicalEntryLine(index, fields[2], fields[3], size, fields[5]))
      entries[index] = { index = index, system = fields[2], sha256 = fields[3], size = size, target = fields[5] }
    end
  end
  checked(#entries == EXPECTED_FILE_COUNT, "staged file count mismatch")
  checked(shaFinal(contractDigest) == EXPECTED_TARGET_CONTRACT_SHA256, "persisted target contract mismatch")
  checked(shaFinal(manifestDigest) == EXPECTED_PERSISTED_MANIFEST_SHA256, "persisted manifest mismatch")
  return entries
end

local function encodeInventory(inventory)
  local lines = {}
  for index, item in ipairs(inventory) do
    lines[index] = table.concat({ index, item.present and "P" or "A", item.size or 0, item.sha256 or "-" }, "\t")
  end
  return table.concat(lines, "\n") .. "\n"
end

local function parseInventory(expectedCount)
  local text, reason = readAll(INVENTORY_PATH, 65536)
  checked(text ~= nil, "prior-file inventory is unavailable: " .. tostring(reason))
  local inventory = {}
  for rawLine in (text .. "\n"):gmatch("([^\n]*)\n") do
    local line = rawLine:gsub("\r$", "")
    if line ~= "" then
      local fields = splitTabs(line)
      local index, size = tonumber(fields[1]), tonumber(fields[3])
      checked(#fields == 4 and index == #inventory + 1 and size and size >= 0, "invalid prior-file row")
      if fields[2] == "P" then
        checked(fields[4]:match("^[0-9a-f]+$") and #fields[4] == 64, "invalid prior-file digest")
        inventory[index] = { present = true, size = size, sha256 = fields[4] }
      else
        checked(fields[2] == "A" and fields[4] == "-", "invalid absent-file marker")
        inventory[index] = { present = false, size = 0 }
      end
    end
  end
  checked(#inventory == expectedCount, "prior-file count mismatch")
  return inventory
end

local function openReader(url)
  local internet = require("internet")
  local request, reason = internet.request(url)
  checked(request ~= nil, "network request failed: " .. tostring(reason))
  local reader = {
    request = request,
    buffer = "",
    eof = false,
    digest = shaNew(),
    started = computer.uptime(),
    progress = computer.uptime(),
  }
  while true do
    local ok, connected = pcall(request.finishConnect)
    if not ok then pcall(request.close); fail("network connect failed: " .. tostring(connected)) end
    if connected then break end
    if computer.uptime() - reader.started > CONNECT_TIMEOUT then pcall(request.close); fail("network connect timeout") end
    os.sleep(0)
  end
  local ok, code, message = pcall(request.response)
  if not ok then pcall(request.close); fail("HTTP response failed: " .. tostring(code)) end
  if tonumber(code) ~= 200 then pcall(request.close); fail("HTTP " .. tostring(code) .. " " .. tostring(message)) end
  return reader
end

local function closeReader(reader)
  if reader and reader.request then pcall(reader.request.close) end
end

local function pullReader(reader)
  while true do
    if computer.uptime() - reader.started > TOTAL_TIMEOUT then fail("network total timeout") end
    local ok, chunk, reason = pcall(reader.request.read)
    if not ok then fail("network read failed: " .. tostring(chunk)) end
    if chunk == nil then
      if reason then fail("network read failed: " .. tostring(reason)) end
      reader.eof = true
      return nil
    end
    if #chunk == 0 then
      if computer.uptime() - reader.progress > IDLE_TIMEOUT then fail("network idle timeout") end
      os.sleep(0)
    else
      reader.progress = computer.uptime()
      shaUpdate(reader.digest, chunk)
      return chunk
    end
  end
end

local function fillReader(reader)
  if #reader.buffer == 0 and not reader.eof then reader.buffer = pullReader(reader) or "" end
  return #reader.buffer > 0
end

local function readLine(reader)
  local parts, count = {}, 0
  while true do
    local newline = reader.buffer:find("\n", 1, true)
    if newline then
      local piece = reader.buffer:sub(1, newline - 1)
      reader.buffer = reader.buffer:sub(newline + 1)
      parts[#parts + 1], count = piece, count + #piece
      checked(count <= MAX_LINE, "bundle header line exceeds limit")
      return table.concat(parts):gsub("\r$", "")
    end
    if #reader.buffer > 0 then
      parts[#parts + 1], count = reader.buffer, count + #reader.buffer
      reader.buffer = ""
      checked(count <= MAX_LINE, "bundle header line exceeds limit")
    end
    checked(fillReader(reader), "bundle ended before a complete header line")
  end
end

local function readExact(reader, count, handle, digest)
  local remaining = count
  while remaining > 0 do
    checked(fillReader(reader), "bundle payload ended early")
    local take = math.min(remaining, #reader.buffer)
    local piece = reader.buffer:sub(1, take)
    reader.buffer = reader.buffer:sub(take + 1)
    writeChunk(handle, piece)
    shaUpdate(digest, piece)
    remaining = remaining - take
  end
end

local function parseBundleHeaders(reader)
  checked(readLine(reader) == "OC-MAINTAINER-BUNDLE\t1", "unsupported bundle format")
  local release = splitTabs(readLine(reader))
  checked(#release == 2 and release[1] == "RELEASE" and release[2] == EXPECTED_RELEASE, "bundle release ID mismatch")
  local openos = splitTabs(readLine(reader))
  checked(#openos == 2 and openos[1] == "OPENOS" and openos[2] == "1.8.9", "bundle OpenOS baseline mismatch")
  local contract = splitTabs(readLine(reader))
  checked(#contract == 2 and contract[1] == "CONTRACT" and contract[2] == EXPECTED_TARGET_CONTRACT_SHA256, "bundle target contract mismatch")
  local manifest = splitTabs(readLine(reader))
  checked(#manifest == 2 and manifest[1] == "MANIFEST" and manifest[2] == EXPECTED_PERSISTED_MANIFEST_SHA256, "bundle persisted manifest mismatch")
  local systemHeader = splitTabs(readLine(reader))
  checked(#systemHeader == 2 and systemHeader[1] == "SYSTEMS" and tonumber(systemHeader[2]) == 5, "bundle system count mismatch")
  local allowedSystems = { core = true, ae2 = true, gt_power = true, dashboard = true, commands = true }
  local systemCounts, seenSystems = {}, {}
  for _ = 1, 5 do
    local fields = splitTabs(readLine(reader))
    local count = tonumber(fields[4])
    checked(#fields == 4 and fields[1] == "SYSTEM" and allowedSystems[fields[2]] and not seenSystems[fields[2]], "invalid bundle system row")
    checked(fields[3]:match("^%d+%.%d+%.%d+$") and count and count > 0, "invalid bundle system version/count")
    seenSystems[fields[2]], systemCounts[fields[2]] = true, count
  end
  local filesHeader = splitTabs(readLine(reader))
  local fileCount, totalBytes = tonumber(filesHeader[2]), tonumber(filesHeader[3])
  checked(#filesHeader == 3 and filesHeader[1] == "FILES" and fileCount == EXPECTED_FILE_COUNT, "bundle file count mismatch")
  checked(totalBytes and totalBytes > 0 and totalBytes <= EXPECTED_FILE_COUNT * MAX_FILE_BYTES, "invalid bundle payload size")
  local entries, seenTargets, actualCounts = {}, {}, {}
  local actualBytes, contractDigest, manifestDigest = 0, shaNew(), newPersistedManifestDigest()
  for index = 1, fileCount do
    local fields = splitTabs(readLine(reader))
    checked(canonicalUnsigned(fields[2]) and canonicalUnsigned(fields[5]), "noncanonical bundle entry integer")
    local rowIndex, size = tonumber(fields[2]), tonumber(fields[5])
    checked(#fields == 6 and fields[1] == "ENTRY" and rowIndex == index, "invalid bundle entry index")
    checked(allowedSystems[fields[3]], "bundle contains an unowned system")
    checked(fields[4]:match("^[0-9a-f]+$") and #fields[4] == 64, "invalid bundle entry digest")
    checked(size and size >= 0 and size <= MAX_FILE_BYTES, "invalid bundle entry size")
    checked(allowedTarget(fields[6]) and not seenTargets[fields[6]], "invalid or duplicate bundle target: " .. tostring(fields[6]))
    seenTargets[fields[6]], actualCounts[fields[3]] = true, (actualCounts[fields[3]] or 0) + 1
    actualBytes = actualBytes + size
    shaUpdate(contractDigest, fields[3] .. "\t" .. fields[6] .. "\n")
    shaUpdate(manifestDigest, canonicalEntryLine(rowIndex, fields[3], fields[4], size, fields[6]))
    entries[index] = { index = index, system = fields[3], sha256 = fields[4], size = size, target = fields[6] }
  end
  checked(actualBytes == totalBytes, "bundle payload total mismatch")
  checked(shaFinal(contractDigest) == EXPECTED_TARGET_CONTRACT_SHA256, "bundle target contract digest mismatch")
  checked(shaFinal(manifestDigest) == EXPECTED_PERSISTED_MANIFEST_SHA256, "bundle persisted manifest digest mismatch")
  for name, expected in pairs(systemCounts) do checked(actualCounts[name] == expected, "bundle system file count mismatch: " .. name) end
  checked(readLine(reader) == "DATA", "bundle DATA boundary is missing")
  return entries
end

local function cleanupStage(entries, owned)
  for _, entry in ipairs(entries or {}) do
    requirePlainManagedPaths(entry)
    local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
    checked(not filesystem.exists(oldPath), "rollback backup already exists for " .. entry.target)
    if owned then
      removeFile(newPath)
      removeFile(partPath)
      removeFile(replacedPath)
    else
      checked(not filesystem.exists(newPath) and not filesystem.exists(partPath) and not filesystem.exists(replacedPath),
        "unowned release artifact collision: " .. entry.target)
    end
  end
end

local function inventoryAndPreflight(entries)
  local inventory, groups = {}, {}
  local rootProxy = select(1, filesystem.get(ROOT))
  checked(rootProxy and rootProxy.address, "cannot identify release journal filesystem")
  local rootAddress = tostring(rootProxy.address)
  for index, entry in ipairs(entries) do
    requirePlainManagedPaths(entry)
    checked(not filesystem.exists(entry.target) or not filesystem.isDirectory or not filesystem.isDirectory(entry.target), "managed target is a directory: " .. entry.target)
    local digest = fileHash(entry.target)
    local size = digest and filesystem.size(entry.target) or 0
    inventory[index] = { present = digest ~= nil, sha256 = digest, size = size }
    local proxy = select(1, filesystem.get(filesystem.path(entry.target)))
    -- GTNH component callbacks are callable tables, not plain Lua functions.
    -- The protected numeric calls below verify behavior without rejecting them.
    checked(proxy and proxy.address and proxy.spaceTotal ~= nil and proxy.spaceUsed ~= nil, "cannot inspect target filesystem: " .. entry.target)
    local key = tostring(proxy.address)
    checked(key == rootAddress, "multi-filesystem release is unsupported; journal and target differ: " .. entry.target)
    local group = groups[key]
    if not group then group = { proxy = proxy, entries = {}, totalNew = 0 }; groups[key] = group end
    group.entries[#group.entries + 1] = { newSize = entry.size, oldSize = size }
    group.totalNew = group.totalNew + entry.size
  end
  for key, group in pairs(groups) do
    local remaining, backups, peak = group.totalNew, 0, group.totalNew
    for _, sizes in ipairs(group.entries) do
      backups = backups + sizes.oldSize
      peak = math.max(peak, remaining + backups)
      remaining = remaining - sizes.newSize
    end
    local okTotal, total = pcall(group.proxy.spaceTotal)
    local okUsed, used = pcall(group.proxy.spaceUsed)
    checked(okTotal and okUsed and tonumber(total) and tonumber(used), "cannot read filesystem capacity: " .. key)
    local free = total == math.huge and math.huge or total - used
    checked(free >= peak + HEADROOM_BYTES, "insufficient filesystem space: need " .. tostring(peak + HEADROOM_BYTES) .. ", free " .. tostring(free))
  end
  return inventory
end

local function stage(url, backupAcknowledgement)
  checked(backupAcknowledgement == "NO_BACKUP", "stage requires: stage <https-url> NO_BACKUP")
  url = trim(url)
  checked(url:match("^https://[^%s%z\1-\31]+$") ~= nil, "stage requires a direct immutable HTTPS bundle URL")
  local current = canonicalizeState(parseState())
  checked(not current or current.phase == "staging", "release transaction is " .. tostring(current and current.phase) .. "; finish it before staging")
  if current and filesystem.exists(FILES_PATH) then cleanupStage(parseEntries(), true) end
  removeFile(FILES_PATH)
  removeFile(INVENTORY_PATH)
  if current then
    removeFile(POWER_CYCLE_MARKER)
    removeFile(POWER_CYCLE_MARKER .. ".next")
  else
    checked(not filesystem.exists(POWER_CYCLE_MARKER) and not filesystem.exists(POWER_CYCLE_MARKER .. ".next"),
      "unowned power-cycle marker collision")
  end
  writeState("staging", 0, url)

  local reader
  local ok, reason = xpcall(function()
    reader = openReader(url)
    local entries = parseBundleHeaders(reader)
    cleanupStage(entries, current ~= nil)
    local inventory = inventoryAndPreflight(entries)
    writeTextAtomic(FILES_PATH, encodeEntries(entries))
    writeTextAtomic(INVENTORY_PATH, encodeInventory(inventory))
    for _, entry in ipairs(entries) do
      local newPath, partPath = artifactPaths(entry.target)
      ensureParent(partPath)
      requirePlainManagedPaths(entry)
      removeFile(partPath)
      local handle, openReason = io.open(partPath, "wb")
      checked(handle ~= nil, "cannot stage " .. entry.target .. ": " .. tostring(openReason))
      local fileDigest = shaNew()
      local fileOk, fileReason = pcall(function()
        readExact(reader, entry.size, handle, fileDigest)
        finishWrite(handle)
        handle = nil
      end)
      if handle then closeRead(handle) end
      if not fileOk then removeFile(partPath); fail(fileReason) end
      checked(shaFinal(fileDigest) == entry.sha256, "download hash mismatch: " .. entry.target)
      local storedDigest, storedReason = hashFile(partPath)
      checked(storedDigest == entry.sha256, "stored hash mismatch for " .. entry.target .. ": " .. tostring(storedReason or storedDigest))
      syntaxCheck(partPath, entry.target)
      removeFile(newPath)
      renameFile(partPath, newPath)
    end
    local ending = splitTabs(readLine(reader))
    checked(#ending == 2 and ending[1] == "END" and ending[2] == EXPECTED_RELEASE, "bundle END boundary mismatch")
    checked(#reader.buffer == 0, "bundle has trailing bytes")
    checked(pullReader(reader) == nil, "bundle has trailing payload")
    checked(shaFinal(reader.digest) == EXPECTED_BUNDLE_SHA256, "bundle digest mismatch")
    armPowerCycleGate("apply")
    writeState("staged", 0, url)
  end, function(message) return tostring(message) end)
  closeReader(reader)
  if not ok then return nil, "stage failed: " .. tostring(reason) end
  return true, "STAGED: 173 files verified; live targets unchanged; run shutdown, wait until visibly OFF, then power on manually"
end

local function activeProcess()
  local ok, process = pcall(require, "process")
  if not ok or type(process) ~= "table" or type(process.list) ~= "table" then return "process list unavailable" end
  local listed = process.list
  local function inspect(pid, value)
    local info = type(value) == "table" and value or nil
    if not info and type(process.info) == "function" then
      local infoOk, result = pcall(process.info, pid)
      if infoOk then info = result end
    end
    local text = type(info) == "table" and table.concat({ tostring(info.path or ""), tostring(info.command or ""), tostring(info.name or "") }, " "):lower() or tostring(value or ""):lower()
    if text:find("oc%-dashboard") or text:find("dashboard%.lua") or text:find("ae2%-maintainer") then return text end
  end
  for pid, value in pairs(listed) do local found = inspect(pid, value); if found then return found end end
  return nil
end

local function daemonIsOff()
  local path = "/etc/oc/ae2-maintainer-daemon.cfg"
  requirePlainPath(path, "daemon configuration")
  requirePlainPath(path .. ".new", "daemon staged configuration")
  requirePlainPath(path .. ".previous", "daemon recovery configuration")
  if filesystem.exists(path .. ".new") or filesystem.exists(path .. ".previous") then
    return nil, "cannot prove daemon OFF while configuration recovery artifacts exist"
  end
  local source, reason = readAll(path, 16384)
  if not source then return nil, "cannot prove daemon OFF: " .. tostring(reason) end
  local chunk = load("return " .. source, "=" .. path, "t", {})
  if chunk then
    local ok, value = pcall(chunk)
    if ok and type(value) == "table" and value.enabled == false then return true end
    if ok and type(value) == "table" and value.enabled == true then return nil, "daemon desired state is ON" end
  end
  return nil, "cannot prove daemon desired state is OFF"
end

local function verifyPrior(entry, prior)
  local digest = fileHash(entry.target)
  if prior.present then return digest == prior.sha256 end
  return digest == nil
end

local function promoteNew(entry, prior, newPath, oldPath)
  local ok, reason = pcall(renameFile, newPath, entry.target)
  if not ok then
    -- A reported I/O failure that happened before promotion can be contained
    -- immediately. A power loss after promotion is reconciled on the next run.
    if prior.present and not filesystem.exists(entry.target) and fileHash(oldPath) == prior.sha256 then
      local restored = pcall(renameFile, oldPath, entry.target)
      if restored then checked(fileHash(entry.target) == prior.sha256, "failed promotion restore mismatch: " .. entry.target) end
    end
    fail(reason)
  end
  checked(fileHash(entry.target) == entry.sha256, "live verification failed: " .. entry.target)
end

local function applyEntry(entry, prior, url)
  requirePlainManagedPaths(entry)
  local newPath, _, oldPath = artifactPaths(entry.target)
  local liveHash, newHash, oldHash = fileHash(entry.target), fileHash(newPath), fileHash(oldPath)
  if liveHash == entry.sha256 and newHash == nil then
    checked((prior.present and oldHash == prior.sha256) or (not prior.present and oldHash == nil), "rollback evidence missing after apply: " .. entry.target)
    return
  end
  if prior.present and liveHash == nil and newHash == entry.sha256 and oldHash == prior.sha256 then
    writeState("applying", entry.index, url)
    promoteNew(entry, prior, newPath, oldPath)
    return
  end
  checked(verifyPrior(entry, prior), "live target changed after staging: " .. entry.target)
  checked(newHash == entry.sha256, "verified stage is missing or changed: " .. entry.target)
  checked(oldHash == nil, "unexpected rollback artifact: " .. entry.target)
  writeState("applying", entry.index, url)
  if prior.present then
    renameFile(entry.target, oldPath)
    checked(fileHash(oldPath) == prior.sha256, "backup verification failed: " .. entry.target)
  end
  writeState("applying", entry.index, url)
  promoteNew(entry, prior, newPath, oldPath)
end

local function applyRelease(offline, backup, confirmation)
  checked(offline == "OFFLINE" and backup == "NO_BACKUP" and confirmation == "CONFIRM",
    "apply requires: apply OFFLINE NO_BACKUP CONFIRM")
  local state = canonicalizeState(parseState())
  checked(state and (state.phase == "staged" or state.phase == "applying"), "apply requires a STAGED or recoverable APPLYING transaction")
  consumeFreshPowerCycle("apply")
  local running = activeProcess()
  checked(not running, "active Maintainer/Dashboard process blocks apply: " .. tostring(running))
  local off, offReason = daemonIsOff()
  checked(off, offReason)
  local entries, inventory = parseEntries(), parseInventory(EXPECTED_FILE_COUNT)
  writeTextAtomic(INHIBIT_PATH, "release=" .. EXPECTED_RELEASE .. "\nphase=applying\n")
  writeState("applying", state.index, state.url)
  for index, entry in ipairs(entries) do
    applyEntry(entry, inventory[index], state.url)
  end
  for _, entry in ipairs(entries) do checked(fileHash(entry.target) == entry.sha256, "post-apply hash mismatch: " .. entry.target) end
  writeState("applied", EXPECTED_FILE_COUNT, state.url)
  return true, "APPLIED: all 173 live hashes verified; Maintainer remains OFF; full shutdown + manual power-on is required before rollback or finalize"
end

local function rollbackEntry(entry, prior, url)
  requirePlainManagedPaths(entry)
  local newPath, _, oldPath, replacedPath = artifactPaths(entry.target)
  local liveHash, oldHash, replacedHash = fileHash(entry.target), fileHash(oldPath), fileHash(replacedPath)
  local function cleanKnownReplacement()
    if fileHash(replacedPath) == entry.sha256 then removeFile(replacedPath) end
  end
  if prior.present and liveHash == prior.sha256 and oldHash == nil then cleanKnownReplacement(); return end
  if not prior.present and liveHash == nil and oldHash == nil then cleanKnownReplacement(); return end
  writeState("rolling_back", entry.index, url)
  if prior.present then
    checked(oldHash == prior.sha256, "cannot prove rollback source for " .. entry.target)
    if liveHash ~= nil then
      checked(replacedHash == nil, "unexpected replaced artifact: " .. entry.target)
      renameFile(entry.target, replacedPath)
      liveHash, replacedHash = nil, fileHash(replacedPath)
    end
    checked(liveHash == nil, "cannot clear live target for rollback: " .. entry.target)
    renameFile(oldPath, entry.target)
    checked(fileHash(entry.target) == prior.sha256, "rollback verification failed: " .. entry.target)
  else
    checked(oldHash == nil, "unexpected backup for formerly absent target: " .. entry.target)
    if liveHash ~= nil then
      checked(replacedHash == nil, "unexpected replaced artifact: " .. entry.target)
      renameFile(entry.target, replacedPath)
    end
  end
  removeFile(newPath)
  cleanKnownReplacement()
end

local function rollbackRelease(offline, backup, confirmation)
  checked(offline == "OFFLINE" and backup == "NO_BACKUP" and confirmation == "CONFIRM",
    "rollback requires: rollback OFFLINE NO_BACKUP CONFIRM")
  local state = canonicalizeState(parseState())
  checked(state and (state.phase == "applying" or state.phase == "applied" or state.phase == "rolling_back"), "rollback requires APPLYING, APPLIED, or ROLLING_BACK state")
  consumeFreshPowerCycle("rollback")
  local running = activeProcess()
  checked(not running, "active Maintainer/Dashboard process blocks rollback: " .. tostring(running))
  local off, offReason = daemonIsOff()
  checked(off, offReason)
  local entries, inventory = parseEntries(), parseInventory(EXPECTED_FILE_COUNT)
  writeState("rolling_back", state.index, state.url)
  for index = #entries, 1, -1 do rollbackEntry(entries[index], inventory[index], state.url) end
  for index, entry in ipairs(entries) do checked(verifyPrior(entry, inventory[index]), "post-rollback mismatch: " .. entry.target) end
  for _, entry in ipairs(entries) do
    requirePlainManagedPaths(entry)
    local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
    removeFile(newPath); removeFile(partPath)
    if fileHash(replacedPath) == entry.sha256 then removeFile(replacedPath) end
    checked(not filesystem.exists(oldPath), "rollback backup remains: " .. entry.target)
  end
  writeState("rolled_back", 0, state.url)
  removeFile(INHIBIT_PATH)
  removeFile(POWER_CYCLE_MARKER); removeFile(POWER_CYCLE_MARKER .. ".next")
  return true, "ROLLED_BACK: exact prior bytes restored; unknown replaced bytes remain quarantined until discard"
end

local function discardRelease(backup, confirmation)
  checked(backup == "NO_BACKUP" and confirmation == "CONFIRM", "discard requires: discard NO_BACKUP CONFIRM")
  local state = canonicalizeState(parseState())
  checked(state and (state.phase == "staging" or state.phase == "staged" or state.phase == "rolled_back"), "discard is allowed only before apply or after rollback")
  local entries = filesystem.exists(FILES_PATH) and parseEntries() or {}
  for _, entry in ipairs(entries) do
    requirePlainManagedPaths(entry)
    local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
    checked(not filesystem.exists(oldPath), "cannot discard while rollback evidence exists")
    removeFile(newPath); removeFile(partPath); removeFile(replacedPath)
  end
  removeFile(INHIBIT_PATH); removeFile(INHIBIT_PATH .. ".next")
  removeFile(POWER_CYCLE_MARKER); removeFile(POWER_CYCLE_MARKER .. ".next")
  removeFile(FILES_PATH); removeFile(FILES_PATH .. ".next")
  removeFile(INVENTORY_PATH); removeFile(INVENTORY_PATH .. ".next")
  removeFile(STATE_PATH); removeFile(STATE_PATH .. ".next")
  return true, "IDLE: installer-owned staged evidence discarded"
end

local function hasFinalizedReceipt()
  if not filesystem.exists(RECEIPT_PATH) then return false end
  local text = readAll(RECEIPT_PATH, 4096)
  return type(text) == "string" and
    text:find("release=" .. EXPECTED_RELEASE .. "\n", 1, true) ~= nil and
    text:find("bundle=" .. EXPECTED_BUNDLE_SHA256 .. "\n", 1, true) ~= nil and
    text:find("status=finalized\n", 1, true) ~= nil
end

local function cleanupFinalizedMetadata()
  requirePlainReleasePaths()
  removeFile(RECEIPT_PATH .. ".next")
  removeFile(INHIBIT_PATH); removeFile(INHIBIT_PATH .. ".next")
  removeFile(POWER_CYCLE_MARKER); removeFile(POWER_CYCLE_MARKER .. ".next")
  removeFile(FILES_PATH); removeFile(FILES_PATH .. ".next")
  removeFile(INVENTORY_PATH); removeFile(INVENTORY_PATH .. ".next")
  removeFile(STATE_PATH); removeFile(STATE_PATH .. ".next")
end

local function finalizeRelease(offline, backup, verified, confirmation)
  checked(offline == "OFFLINE" and backup == "NO_BACKUP" and verified == "VERIFIED" and confirmation == "CONFIRM",
    "finalize requires: finalize OFFLINE NO_BACKUP VERIFIED CONFIRM")
  local state = canonicalizeState(parseState())
  checked(state and (state.phase == "applied" or state.phase == "finalizing"), "finalize requires APPLIED or recoverable FINALIZING state")
  consumeFreshPowerCycle("finalize")
  local running = activeProcess()
  checked(not running, "active Maintainer/Dashboard process blocks finalize: " .. tostring(running))
  local off, offReason = daemonIsOff()
  checked(off, offReason)
  if state.phase == "finalizing" and state.index == EXPECTED_FILE_COUNT and hasFinalizedReceipt() then
    cleanupFinalizedMetadata()
    return true, "FINALIZED: completed interrupted metadata cleanup"
  end

  local entries, inventory = parseEntries(), parseInventory(EXPECTED_FILE_COUNT)
  if state.phase == "applied" then
    for index, entry in ipairs(entries) do
      requirePlainManagedPaths(entry)
      checked(fileHash(entry.target) == entry.sha256, "final live hash mismatch: " .. entry.target)
      local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
      checked(not filesystem.exists(newPath) and not filesystem.exists(partPath) and not filesystem.exists(replacedPath), "unexpected finalization artifact: " .. entry.target)
      if inventory[index].present then
        checked(fileHash(oldPath) == inventory[index].sha256, "rollback backup mismatch: " .. entry.target)
      else
        checked(not filesystem.exists(oldPath), "unexpected backup for formerly absent target: " .. entry.target)
      end
    end
    -- This durable phase is the irreversible operator authorization boundary.
    writeState("finalizing", 0, state.url)
    state.phase = "finalizing"
  end

  for index, entry in ipairs(entries) do
    requirePlainManagedPaths(entry)
    checked(fileHash(entry.target) == entry.sha256, "final live hash mismatch: " .. entry.target)
    local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
    checked(not filesystem.exists(newPath) and not filesystem.exists(partPath) and not filesystem.exists(replacedPath), "unexpected finalization artifact: " .. entry.target)
    if filesystem.exists(oldPath) then
      checked(inventory[index].present and fileHash(oldPath) == inventory[index].sha256, "rollback backup mismatch: " .. entry.target)
      removeFile(oldPath)
    end
    writeState("finalizing", index, state.url)
  end

  for _, entry in ipairs(entries) do
    requirePlainManagedPaths(entry)
    checked(fileHash(entry.target) == entry.sha256, "final live hash mismatch: " .. entry.target)
    local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
    checked(not filesystem.exists(newPath) and not filesystem.exists(partPath) and
      not filesystem.exists(oldPath) and not filesystem.exists(replacedPath),
      "release artifact remains after finalization: " .. entry.target)
  end

  writeTextAtomic(RECEIPT_PATH, table.concat({
    "format=1", "release=" .. EXPECTED_RELEASE, "bundle=" .. EXPECTED_BUNDLE_SHA256,
    "files=" .. tostring(EXPECTED_FILE_COUNT), "operator_verification=attested",
    "installed_hashes=verified", "status=finalized", "",
  }, "\n"))
  cleanupFinalizedMetadata()
  return true, "FINALIZED: rollback files removed; verified release receipt retained"
end

local function status()
  if filesystem.exists(ROOT) then requirePlainReleasePaths() end
  local state = parseState()
  if not state then
    if hasFinalizedReceipt() then return true, "FINALIZED: no active transaction; verified release receipt retained" end
    return true, "IDLE: no active release transaction"
  end
  local locked = filesystem.exists(LOCK_PATH) and "yes" or "no"
  local inhibited = filesystem.exists(INHIBIT_PATH) and "yes" or "no"
  local powerCycleRequired = (filesystem.exists(POWER_CYCLE_MARKER) or
    filesystem.exists(POWER_CYCLE_MARKER .. ".next")) and "yes" or "no"
  return true, table.concat({
    "release: " .. EXPECTED_RELEASE,
    "state: " .. tostring(state.phase):upper(),
    "cursor: " .. tostring(state.index) .. "/" .. tostring(EXPECTED_FILE_COUNT),
    "lock: " .. locked,
    "deployment recovery marker: " .. inhibited,
    "full shutdown required before live transition: " .. powerCycleRequired,
  }, "\n")
end

local function plan()
  return true, table.concat({
    "MAINTAINER IMMUTABLE RELEASE PLAN",
    "release: " .. EXPECTED_RELEASE,
    "files: " .. tostring(EXPECTED_FILE_COUNT),
    "stage: downloads, hashes, syntax-checks; live targets remain unchanged; requires a no-backup window",
    "live-transition gate: apply, rollback, and finalize each consume a fresh full shutdown + manual power-on proof; a soft reboot never qualifies",
    "quiescence: remain at shell, daemon config exactly OFF with no recovery artifacts, no Dashboard/Maintainer process, admin-confirmed no backup",
    "apply: lua oc-release.lua apply OFFLINE NO_BACKUP CONFIRM",
    "verify before finalize: onboarding API, oc-config-migrate status, ae2-probe, fresh Dashboard smoke test",
  }, "\n")
end

local function acquireLock(action)
  requirePlainPath(ROOT, "release root")
  ensureDirectory(ROOT)
  requirePlainReleasePaths()
  checked(not filesystem.exists(LOCK_PATH), "another or interrupted installer holds the lock; after proving it stopped, run unlock NO_BACKUP CONFIRM")
  local made, makeReason = filesystem.makeDirectory(LOCK_PATH)
  checked(made, "another installer won the lock: " .. tostring(makeReason))
  requirePlainReleasePaths()
  local address = type(computer.address) == "function" and computer.address() or "unknown-computer"
  local token = tostring(address) .. ":" .. tostring(computer.uptime()) .. ":" .. tostring(action)
  local ok, reason = pcall(writeTextAtomic, LOCK_OWNER_PATH, token .. "\n")
  if not ok then
    pcall(removeFile, LOCK_OWNER_PATH)
    pcall(removeFile, LOCK_OWNER_PATH .. ".next")
    pcall(filesystem.remove, LOCK_PATH)
    fail(reason)
  end
  return token
end

local function releaseLock(token)
  if not token or not filesystem.exists(LOCK_PATH) then return end
  requirePlainPath(LOCK_PATH, "installer lock")
  requirePlainPath(LOCK_OWNER_PATH, "installer lock owner")
  requirePlainPath(LOCK_OWNER_PATH .. ".next", "installer lock owner staging path")
  local owner = readAll(LOCK_OWNER_PATH, 1024)
  if owner ~= token .. "\n" then return end
  removeFile(LOCK_OWNER_PATH)
  removeFile(LOCK_OWNER_PATH .. ".next")
  local removed, reason = filesystem.remove(LOCK_PATH)
  checked(removed, "cannot remove installer lock directory: " .. tostring(reason))
end

local function withLock(action, callback)
  local token
  local ok, first, second = pcall(function()
    token = acquireLock(action)
    return callback()
  end)
  if token then pcall(releaseLock, token) end
  if not ok then return nil, tostring(first) end
  return first, second
end

function api.run(command, ...)
  command = trim(command)
  local arguments = { ... }
  if command == "plan" then return plan() end
  if command == "status" then return status() end
  if command == "stage" then
    if arguments[2] ~= "NO_BACKUP" then return nil, "stage requires: stage <https-url> NO_BACKUP" end
    return withLock("stage", function() return stage(table.unpack(arguments)) end)
  end
  if command == "apply" then
    if arguments[1] ~= "OFFLINE" or arguments[2] ~= "NO_BACKUP" or arguments[3] ~= "CONFIRM" then return nil, "apply requires: apply OFFLINE NO_BACKUP CONFIRM" end
    return withLock("apply", function() return applyRelease(table.unpack(arguments)) end)
  end
  if command == "rollback" then
    if arguments[1] ~= "OFFLINE" or arguments[2] ~= "NO_BACKUP" or arguments[3] ~= "CONFIRM" then return nil, "rollback requires: rollback OFFLINE NO_BACKUP CONFIRM" end
    return withLock("rollback", function() return rollbackRelease(table.unpack(arguments)) end)
  end
  if command == "discard" then
    if arguments[1] ~= "NO_BACKUP" or arguments[2] ~= "CONFIRM" then return nil, "discard requires: discard NO_BACKUP CONFIRM" end
    return withLock("discard", function() return discardRelease(table.unpack(arguments)) end)
  end
  if command == "finalize" then
    if arguments[1] ~= "OFFLINE" or arguments[2] ~= "NO_BACKUP" or arguments[3] ~= "VERIFIED" or arguments[4] ~= "CONFIRM" then return nil, "finalize requires: finalize OFFLINE NO_BACKUP VERIFIED CONFIRM" end
    return withLock("finalize", function() return finalizeRelease(table.unpack(arguments)) end)
  end
  if command == "unlock" then
    if arguments[1] ~= "NO_BACKUP" or arguments[2] ~= "CONFIRM" then return nil, "unlock requires: unlock NO_BACKUP CONFIRM" end
    if filesystem.exists(ROOT) then requirePlainReleasePaths() end
    if not filesystem.exists(LOCK_PATH) then return nil, "no installer lock exists" end
    local unlocked, unlockReason = pcall(function()
      if filesystem.exists(LOCK_OWNER_PATH) then removeFile(LOCK_OWNER_PATH) end
      if filesystem.exists(LOCK_OWNER_PATH .. ".next") then removeFile(LOCK_OWNER_PATH .. ".next") end
      local removed, reason = filesystem.remove(LOCK_PATH)
      checked(removed, "cannot remove installer lock directory: " .. tostring(reason))
    end)
    if not unlocked then return nil, tostring(unlockReason) end
    return true, "installer lock removed; run status before continuing"
  end
  return nil, "usage: plan | status | stage <https-url> NO_BACKUP | apply OFFLINE NO_BACKUP CONFIRM | rollback OFFLINE NO_BACKUP CONFIRM | discard NO_BACKUP CONFIRM | finalize OFFLINE NO_BACKUP VERIFIED CONFIRM | unlock NO_BACKUP CONFIRM"
end

local first = ...
if first == "__module" then return api end

local ok, message = api.run(...)
if ok then
  print(message or "ok")
else
  io.stderr:write("oc-release: " .. tostring(message) .. "\n")
  os.exit(1)
end
