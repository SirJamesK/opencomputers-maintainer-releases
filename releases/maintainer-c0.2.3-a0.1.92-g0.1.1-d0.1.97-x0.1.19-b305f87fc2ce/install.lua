#!/bin/lua

-- Generated copies pin one immutable Maintainer bundle. This bootstrap stays
-- out of the managed release target set so it can repair a mixed installation.
local EXPECTED_RELEASE = "maintainer-c0.2.3-a0.1.92-g0.1.1-d0.1.97-x0.1.19-b305f87fc2ce"
local EXPECTED_BUNDLE_SHA256 = "2fff6000ad14793204efdad3350d5f90f94ec73651b3a878557869eb404f1f55"
local EXPECTED_FILE_COUNT = 256
local EXPECTED_TARGET_CONTRACT_SHA256 = "2f9770bc86dbbe4085bcb02b6cff1a00e79b42fc2cc6e170966c4b919ed81977"
local EXPECTED_PERSISTED_MANIFEST_SHA256 = "2e7eee3057728cf8bb51f5a231f744a9019fe1d77df24ae0b14a859e15394c0e"

local filesystem = require("filesystem")
local computer = require("computer")

local ROOT = "/var/oc/releases/maintainer"
local SELECTOR_PATH = "/etc/oc/maintainer-runtime.cfg"
local EXTERNAL_BASE = "/.oc-platform/maintainer"
local EXTERNAL_MARKER_SUFFIX = "/.oc-platform/maintainer/active"
local ROOT_MARKER_PATH = EXTERNAL_MARKER_SUFFIX
local STATE_PATH = ROOT .. "/state"
local FILES_PATH = ROOT .. "/files.tsv"
local INVENTORY_PATH = ROOT .. "/inventory.tsv"
local SELECTOR_PRIOR_PATH = ROOT .. "/selector.prior"
local MARKER_PRIOR_PATH = ROOT .. "/marker.prior"
local ROOT_MARKER_PRIOR_PATH = ROOT .. "/root-marker.prior"
-- Compatibility cleanup only. This installer never creates these paths.
local LEGACY_LOCK_PATH = ROOT .. "/lock"
local LEGACY_LOCK_OWNER_PATH = LEGACY_LOCK_PATH .. "/owner"
local INHIBIT_PATH = ROOT .. "/inhibit"
local RECEIPT_PATH = ROOT .. "/last-release"
local DAEMON_CONTROL_PATH = "/etc/oc/ae2-maintainer-daemon.cfg"
local DAEMON_CONTROL_PRIOR_PATH = ROOT .. "/daemon-control.prior"
local DAEMON_CONTROL_MAX_BYTES = 16384
local DAEMON_CONTROL_LOCK_MAX_BYTES = 4096
local DAEMON_CONTROL_PRIOR_MAX_BYTES = 57344
local DAEMON_CONTROL_SCHEMA = 1
local DAEMON_CONTROL_RECOVERY_ACTION = "recover-control OFFLINE NO_BACKUP CONFIRM"
local POST_INSTALL_CONTRACT = "ae2_profile_converge_v1"
local AE2_RC_PATH = "/etc/rc.d/oc-ae2.lua"
local POWER_CYCLE_MARKER = "/tmp/oc-release-stage-" .. EXPECTED_BUNDLE_SHA256:sub(1, 12)
local RELEASE_KEY = EXPECTED_BUNDLE_SHA256:sub(1, 12)
local ARTIFACT_PREFIX = ".oc-release-" .. RELEASE_KEY
local MAX_LINE = 512
local MAX_FILE_BYTES = 24576
local MAX_MOUNT_ROWS = 32
local MAX_PROCESS_ROWS = 64
local MAX_PROCESS_INSTANCES = 64
local HEADROOM_BYTES = 262144
local MIN_EXTERNAL_BYTES = 4 * 1024 * 1024
local CONNECT_TIMEOUT = 30
local IDLE_TIMEOUT = 30
local TOTAL_TIMEOUT = 600
local MASK = 0xffffffff
local PROCESS_AUTHORITY_KEY = "__oc_maintainer_release_authority_v1"
local DAEMON_CONTROL_CLEAN_OFF = table.concat({
  "{",
  "  enabled = false,",
  "  interval = 600,",
  "  pollInterval = 600,",
  "  generation = 0,",
  "  forcePlanningSerial = 0,",
  "  maintenanceBrake = false,",
  "  maintenanceBrakeSerial = 0,",
  "  identityReconcileSerial = 0,",
  "  identityReconcileState = \"idle\",",
  "  identityReconcileAddObserved = true,",
  "  identityCaptureUntil = 0,",
  "  identityCaptureGeneration = 0,",
  "  commissioningState = \"idle\",",
  "  commissioningSerial = 0,",
  "}", "",
}, "\n")

local api = {}
local recovery = {
  path = ROOT .. "/installer-recovery.prior",
  previousPath = ROOT .. "/installer-recovery.previous",
  stagePath = ROOT .. "/installer-recovery.stage",
  action = "recover-installer OFFLINE NO_BACKUP CONFIRM",
  maxBytes = 393216,
  indexMaxBytes = 65536,
  stateMaxBytes = 16384,
  smallMaxBytes = 4096,
  treeFileMaxBytes = 65536,
  maxTreeRows = 128,
  maxTreeDepth = 4,
}

local function fail(message)
  error(tostring(message or "unknown failure"), 0)
end

local function checked(condition, message)
  if not condition then fail(message) end
  return condition
end

-- OpenComputers/OpenOS runs Lua 5.2, where bitwise operators are supplied by
-- bit32 rather than by Lua 5.3+ syntax. Keeping the installer itself parseable
-- by Lua 5.2 matters more than accepting a newer host Lua silently.
local bits = rawget(_G, "bit32")
if type(bits) ~= "table" then
  local loaded, library = pcall(require, "bit32")
  if loaded then bits = library end
end
checked(type(bits) == "table" and type(bits.band) == "function" and
  type(bits.bor) == "function" and type(bits.bxor) == "function" and
  type(bits.bnot) == "function" and type(bits.rshift) == "function" and
  type(bits.lshift) == "function" and type(bits.rrotate) == "function",
  "OpenOS bit32 support is unavailable")
local band, bor, bxor, bnot = bits.band, bits.bor, bits.bxor, bits.bnot
local rshift, lshift, ror = bits.rshift, bits.lshift, bits.rrotate

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
  return path == "/lib/oc_bootstrap.lua" or path == "/home/dashboard.lua" or path == "/home/.shrc"
end

local function isRuntimeTarget(path)
  return type(path) == "string" and path:match("^/usr/lib/oc/") ~= nil
end

local function safeRelease(value)
  value = tostring(value or "")
  return #value >= 1 and #value <= 128 and not value:find("..", 1, true) and
    value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$") ~= nil
end

local function safeAddress(value)
  value = tostring(value or "")
  local a, b, c, d, e = value:match("^([0-9a-f]+)%-([0-9a-f]+)%-([0-9a-f]+)%-([0-9a-f]+)%-([0-9a-f]+)$")
  return a ~= nil and #a == 8 and #b == 4 and #c == 4 and #d == 4 and #e == 12
end

local function safeInstallId(value)
  value = tostring(value or "")
  return #value >= 8 and #value <= 96 and not value:find("..", 1, true) and
    value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$") ~= nil
end

local function safeDigest(value)
  return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil
end

local transactionTopology

function recovery.artifactPrefix(topology)
  topology = topology or transactionTopology
  local slot = topology and topology.artifactSlot or "a"
  checked(slot == "a" or slot == "b" or slot == "pending",
    "invalid release artifact slot")
  if slot == "b" then return ARTIFACT_PREFIX .. ".recovery-b" end
  return ARTIFACT_PREFIX
end

local function artifactPaths(target, topology)
  local prefix = recovery.artifactPrefix(topology)
  return target .. prefix .. ".new",
    target .. prefix .. ".part",
    target .. prefix .. ".old",
    target .. prefix .. ".replaced"
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

local function requirePlainManagedPaths(entry, topology)
  requirePlainPath(entry.target, "managed target")
  local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target, topology)
  requirePlainPath(newPath, "release new artifact")
  requirePlainPath(partPath, "release partial artifact")
  requirePlainPath(oldPath, "release rollback artifact")
  requirePlainPath(replacedPath, "release quarantine artifact")
end

local function requirePlainReleasePaths()
  for _, path in ipairs({
    ROOT, STATE_PATH, STATE_PATH .. ".next", FILES_PATH, FILES_PATH .. ".next",
    INVENTORY_PATH, INVENTORY_PATH .. ".next", LEGACY_LOCK_PATH,
    INHIBIT_PATH, INHIBIT_PATH .. ".next",
    RECEIPT_PATH, RECEIPT_PATH .. ".next", SELECTOR_PRIOR_PATH,
    SELECTOR_PRIOR_PATH .. ".next", MARKER_PRIOR_PATH, MARKER_PRIOR_PATH .. ".next",
    ROOT_MARKER_PRIOR_PATH, ROOT_MARKER_PRIOR_PATH .. ".next", POWER_CYCLE_MARKER,
    POWER_CYCLE_MARKER .. ".next", DAEMON_CONTROL_PRIOR_PATH,
    DAEMON_CONTROL_PRIOR_PATH .. ".next", recovery.path,
    recovery.path .. ".next", recovery.previousPath,
    recovery.previousPath .. ".next", recovery.stagePath,
    recovery.stagePath .. ".next",
  }) do
    requirePlainPath(path, "release metadata")
  end
  if filesystem.exists(LEGACY_LOCK_PATH) and filesystem.isDirectory and
      filesystem.isDirectory(LEGACY_LOCK_PATH) then
    requirePlainPath(LEGACY_LOCK_OWNER_PATH, "legacy installer lock owner")
    requirePlainPath(LEGACY_LOCK_OWNER_PATH .. ".next", "legacy installer lock owner")
  end
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
    words[index + 1] = bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)
  end
  for index = 17, 64 do
    local x, y = words[index - 15], words[index - 2]
    local s0 = bxor(ror(x, 7), ror(x, 18), rshift(x, 3))
    local s1 = bxor(ror(y, 17), ror(y, 19), rshift(y, 10))
    words[index] = band(words[index - 16] + s0 + words[index - 7] + s1, MASK)
  end
  local a, b, c, d = context.h[1], context.h[2], context.h[3], context.h[4]
  local e, f, g, h = context.h[5], context.h[6], context.h[7], context.h[8]
  for index = 1, 64 do
    local sum1 = bxor(ror(e, 6), ror(e, 11), ror(e, 25))
    local choice = bxor(band(e, f), band(bnot(e), g))
    local temp1 = band(h + sum1 + choice + SHA_K[index] + words[index], MASK)
    local sum0 = bxor(ror(a, 2), ror(a, 13), ror(a, 22))
    local majority = bxor(band(a, b), band(a, c), band(b, c))
    local temp2 = band(sum0 + majority, MASK)
    h, g, f, e, d, c, b, a = g, f, e, band(d + temp1, MASK), c, b, a, band(temp1 + temp2, MASK)
  end
  context.h[1] = band(context.h[1] + a, MASK)
  context.h[2] = band(context.h[2] + b, MASK)
  context.h[3] = band(context.h[3] + c, MASK)
  context.h[4] = band(context.h[4] + d, MASK)
  context.h[5] = band(context.h[5] + e, MASK)
  context.h[6] = band(context.h[6] + f, MASK)
  context.h[7] = band(context.h[7] + g, MASK)
  context.h[8] = band(context.h[8] + h, MASK)
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
  local high = band(math.floor(byteCount / 536870912), MASK)
  local low = band(byteCount * 8, MASK)
  local lengthBytes = string.char(
    band(rshift(high, 24), 255), band(rshift(high, 16), 255), band(rshift(high, 8), 255), band(high, 255),
    band(rshift(low, 24), 255), band(rshift(low, 16), 255), band(rshift(low, 8), 255), band(low, 255))
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

local function callProxy(proxy, name)
  local callback = type(proxy) == "table" and proxy[name] or nil
  if callback == nil then return nil, "missing " .. tostring(name) end
  local ok, value = pcall(callback)
  if not ok then ok, value = pcall(callback, proxy) end
  if not ok then return nil, value end
  return value
end

local function mountPathSafe(path)
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" or path:find("[%z\1-\31\127\\]") then return false end
  local canonical = filesystem.canonical(path)
  return type(canonical) == "string" and canonical == path
end

local function mountedFilesystems()
  local rows, observed = {}, 0
  local ok, reason = pcall(function()
    for proxy, mountPath in filesystem.mounts() do
      observed = observed + 1
      checked(observed <= MAX_MOUNT_ROWS, "mounted filesystem enumeration exceeds " .. tostring(MAX_MOUNT_ROWS) .. " entries")
      if type(proxy) == "table" and proxy.address ~= nil and mountPathSafe(mountPath) then
        rows[#rows + 1] = {
          proxy = proxy,
          address = tostring(proxy.address),
          mount = mountPath,
        }
      end
    end
  end)
  checked(ok, "cannot enumerate mounted filesystems: " .. tostring(reason))
  table.sort(rows, function(a, b)
    if #a.mount ~= #b.mount then return #a.mount < #b.mount end
    if a.mount ~= b.mount then return a.mount < b.mount end
    return a.address < b.address
  end)
  return rows
end

local function externalMountSafe(row, allRows)
  local path = row and row.mount or ""
  if not safeAddress(row and row.address) then return false, "noncanonical filesystem UUID" end
  if path == "/" or path == "/dev" or path:match("^/dev/") or
    path == "/tmp" or path:match("^/tmp/") then return false, "system mount" end
  for _, other in ipairs(allRows or {}) do
    if other.mount ~= path and other.mount ~= "/" and
      path:sub(1, #other.mount + 1) == other.mount .. "/" then
      return false, "nested mount"
    end
  end
  local proxy = select(1, filesystem.get(path))
  if not proxy or tostring(proxy.address) ~= row.address then return false, "mount ownership mismatch" end
  return true
end

local function mountForAddress(address, requireExternal)
  address = tostring(address or "")
  local rows, aliases = mountedFilesystems(), {}
  for _, row in ipairs(rows) do
    local safe = not requireExternal or externalMountSafe(row, rows)
    if row.address == address and safe then aliases[#aliases + 1] = row end
  end
  if #aliases == 0 then return nil, "filesystem " .. address .. " is not mounted at a safe path" end
  -- Aliases expose the same proxy and bytes. The shortest canonical alias is
  -- only a path resolver; authority remains the full selected address.
  return aliases[1]
end

local BINDING_KEYS = { "format", "product", "address", "install_id", "release", "bundle", "contract", "manifest" }

local function parseBindingText(text)
  if type(text) ~= "string" or #text > 2048 or text:sub(-1) ~= "\n" then return nil, "binding is unreadable, oversized, or unterminated" end
  if text:find("\r", 1, true) or text:find("[%z\1-\9\11-\31\127]") then return nil, "binding contains control bytes" end
  local values, count = {}, 0
  for line in text:gmatch("([^\n]*)\n") do
    if line == "" then return nil, "binding contains a blank line" end
    count = count + 1
    local key, value = line:match("^([a-z_]+)=([^%s]+)$")
    if not key or key ~= BINDING_KEYS[count] or values[key] ~= nil then return nil, "binding fields/order are invalid" end
    values[key] = value
  end
  if count ~= #BINDING_KEYS or values.format ~= "1" or values.product ~= "maintainer" or
    not safeAddress(values.address) or not safeInstallId(values.install_id) or not safeRelease(values.release) or
    not safeDigest(values.bundle) or not safeDigest(values.contract) or not safeDigest(values.manifest) then
    return nil, "binding values are invalid"
  end
  local exact = {}
  for index, key in ipairs(BINDING_KEYS) do exact[index] = key .. "=" .. values[key] end
  if table.concat(exact, "\n") .. "\n" ~= text then return nil, "binding encoding is not canonical" end
  return values
end

local function bindingBody(address, installId)
  checked(safeAddress(address), "runtime filesystem address is invalid")
  checked(safeInstallId(installId), "runtime installation ID is invalid")
  return table.concat({
    "format=1",
    "product=maintainer",
    "address=" .. tostring(address),
    "install_id=" .. tostring(installId),
    "release=" .. EXPECTED_RELEASE,
    "bundle=" .. EXPECTED_BUNDLE_SHA256,
    "contract=" .. EXPECTED_TARGET_CONTRACT_SHA256,
    "manifest=" .. EXPECTED_PERSISTED_MANIFEST_SHA256,
    "",
  }, "\n")
end

local function bindingMatchesExpected(binding)
  return binding and binding.release == EXPECTED_RELEASE and binding.bundle == EXPECTED_BUNDLE_SHA256 and
    binding.contract == EXPECTED_TARGET_CONTRACT_SHA256 and binding.manifest == EXPECTED_PERSISTED_MANIFEST_SHA256
end

local function derivedInstallId(volumeAddress)
  local ok, hostAddress = pcall(computer.address)
  checked(ok and safeAddress(hostAddress), "computer address is not a canonical lowercase UUID")
  checked(safeAddress(volumeAddress), "runtime filesystem address is not a canonical lowercase UUID")
  return "oc-" .. hostAddress .. "-" .. volumeAddress
end

local function readBinding(path)
  if not filesystem.exists(path) then return nil, "missing" end
  local text, reason = readAll(path, 2048)
  if not text then return nil, tostring(reason) end
  local parsed, parseReason = parseBindingText(text)
  if not parsed then return nil, parseReason end
  parsed.body = text
  return parsed
end

local function externalMarkerPath(mountPath)
  return filesystem.concat(mountPath, EXTERNAL_MARKER_SUFFIX)
end

local function externalReleaseRoot(mountPath)
  checked(safeRelease(EXPECTED_RELEASE), "generated release ID is unsafe")
  return filesystem.concat(mountPath, EXTERNAL_BASE, "releases", EXPECTED_RELEASE, "root")
end

local function bindEntries(entries, topology)
  checked(type(topology) == "table" and (topology.kind == "root" or topology.kind == "external"), "runtime topology is unavailable")
  for _, entry in ipairs(entries or {}) do
    entry.logicalTarget = entry.logicalTarget or entry.target
    if topology.kind == "external" and isRuntimeTarget(entry.logicalTarget) then
      entry.target = externalReleaseRoot(topology.mount) .. entry.logicalTarget
      entry.external = true
    else
      entry.target = entry.logicalTarget
      entry.external = false
    end
  end
  return entries
end


local function transactionOrder(entries, topology)
  if not topology or topology.kind ~= "external" then return entries end
  local ordered = {}
  for _, entry in ipairs(entries) do if entry.external then ordered[#ordered + 1] = entry end end
  for _, entry in ipairs(entries) do if not entry.external then ordered[#ordered + 1] = entry end end
  return ordered
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
  -- Presence means the fresh boot has been consumed for this live transition.
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

local function ownedFilesystemAddress(path, expected, label)
  local proxy = select(1, filesystem.get(path))
  checked(proxy and proxy.address, "cannot resolve filesystem ownership for " .. label .. ": " .. path)
  local actual = tostring(proxy.address)
  checked(actual == expected, label .. " resolved to replacement filesystem " .. actual ..
    " instead of " .. tostring(expected) .. ": " .. path)
end

local function requireOwnedPath(path, expected, label)
  ownedFilesystemAddress(path, expected, label)
  local parent = filesystem.path(path)
  checked(type(parent) == "string" and parent:sub(1, 1) == "/", "cannot resolve parent for " .. label .. ": " .. path)
  ownedFilesystemAddress(parent, expected, label .. " parent")
end

local function rootFilesystemAddress()
  local proxy = select(1, filesystem.get("/"))
  checked(proxy and proxy.address and safeAddress(tostring(proxy.address)), "boot filesystem address is unavailable or noncanonical")
  return tostring(proxy.address)
end

local function verifyEntryOwnership(entry, topology)
  topology = topology or transactionTopology
  checked(type(topology) == "table", "runtime topology is unavailable for ownership verification")
  local expected = entry.external and topology.address or rootFilesystemAddress()
  local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target, topology)
  for _, path in ipairs({ entry.target, newPath, partPath, oldPath, replacedPath }) do
    requireOwnedPath(path, expected, "managed release path")
  end
  return true
end

local function verifyBindingOwnership(topology)
  local rootAddress = rootFilesystemAddress()
  requireOwnedPath(SELECTOR_PATH, rootAddress, "runtime selector")
  requireOwnedPath(ROOT_MARKER_PATH, rootAddress, "root runtime marker")
  if topology.kind == "external" then
    requireOwnedPath(externalMarkerPath(topology.mount), topology.address, "external runtime marker")
  end
  return true
end

local function topologyFromState(state)
  checked(type(state) == "table", "release topology state is unavailable")
  if state.topology == "root" then
    local proxy = select(1, filesystem.get("/"))
    checked(proxy and proxy.address and tostring(proxy.address) == state.runtime_address,
      "boot filesystem address changed during the release transaction")
    return {
      kind = "root", address = state.runtime_address, installId = state.install_id,
      selectorPresent = state.selector_present, markerPresent = state.marker_present,
      rootMarkerPresent = state.root_marker_present, recovery = state.recovery,
      artifactSlot = state.artifact_slot,
    }
  end
  local row, reason = mountForAddress(state.runtime_address, true)
  checked(row ~= nil, "external runtime unavailable: " .. tostring(reason))
  return {
    kind = "external", address = state.runtime_address, installId = state.install_id,
    mount = row.mount, proxy = row.proxy,
    selectorPresent = state.selector_present, markerPresent = state.marker_present,
    rootMarkerPresent = state.root_marker_present, recovery = state.recovery,
    artifactSlot = state.artifact_slot,
  }
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
  checked(state.topology == "root" or state.topology == "external", "invalid release topology")
  checked(type(state.runtime_address) == "string" and #state.runtime_address >= 1 and #state.runtime_address <= 64 and
    state.runtime_address:match("^[A-Za-z0-9_.%-]+$") ~= nil, "invalid runtime filesystem address")
  checked(safeAddress(state.runtime_address), "invalid runtime filesystem address")
  checked(safeInstallId(state.install_id), "invalid runtime installation ID")
  checked(state.install_id == derivedInstallId(state.runtime_address), "runtime installation ID belongs to another computer or filesystem")
  checked(state.selector_present == "0" or state.selector_present == "1", "invalid prior selector state")
  checked(state.marker_present == "0" or state.marker_present == "1", "invalid prior marker state")
  checked(state.root_marker_present == "0" or state.root_marker_present == "1", "invalid prior root marker state")
  checked(state.recovery == nil or state.recovery == "0" or state.recovery == "1",
    "invalid installer recovery state")
  checked(state.artifact_slot == nil or state.artifact_slot == "a" or
      state.artifact_slot == "b" or state.artifact_slot == "pending",
    "invalid release artifact slot")
  state.selector_present = state.selector_present == "1"
  state.marker_present = state.marker_present == "1"
  state.root_marker_present = state.root_marker_present == "1"
  state.recovery = state.recovery == "1"
  state.artifact_slot = state.artifact_slot or "a"
  state.recovered_from_next = sourcePath ~= STATE_PATH
  transactionTopology = topologyFromState(state)
  return state
end

local function writeState(phase, index, url, topology)
  checked(type(phase) == "string" and phase:match("^[a-z_]+$"), "invalid release phase")
  topology = topology or transactionTopology
  checked(type(topology) == "table" and (topology.kind == "root" or topology.kind == "external"), "release topology is unavailable")
  topology.artifactSlot = topology.artifactSlot or "a"
  checked(topology.artifactSlot == "a" or topology.artifactSlot == "b" or
      topology.artifactSlot == "pending", "invalid release artifact slot")
  url = tostring(url or "")
  checked(not url:find("[\r\n]"), "invalid state URL")
  writeTextAtomic(STATE_PATH, table.concat({
    "format=1",
    "release=" .. EXPECTED_RELEASE,
    "bundle=" .. EXPECTED_BUNDLE_SHA256,
    "phase=" .. phase,
    "index=" .. tostring(tonumber(index) or 0),
    "url=" .. url,
    "topology=" .. topology.kind,
    "runtime_address=" .. tostring(topology.address),
    "install_id=" .. tostring(topology.installId),
    "selector_present=" .. (topology.selectorPresent and "1" or "0"),
    "marker_present=" .. (topology.markerPresent and "1" or "0"),
    "root_marker_present=" .. (topology.rootMarkerPresent and "1" or "0"),
    "recovery=" .. (topology.recovery and "1" or "0"),
    "artifact_slot=" .. topology.artifactSlot,
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
    lines[index] = canonicalEntryLine(entry.index, entry.system, entry.sha256, entry.size, entry.logicalTarget or entry.target)
  end
  return table.concat(lines)
end

local function parseEntries(topology)
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
      entries[index] = { index = index, system = fields[2], sha256 = fields[3], size = size,
        target = fields[5], logicalTarget = fields[5] }
    end
  end
  checked(#entries == EXPECTED_FILE_COUNT, "staged file count mismatch")
  checked(shaFinal(contractDigest) == EXPECTED_TARGET_CONTRACT_SHA256, "persisted target contract mismatch")
  checked(shaFinal(manifestDigest) == EXPECTED_PERSISTED_MANIFEST_SHA256, "persisted manifest mismatch")
  if topology then bindEntries(entries, topology) end
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
    entries[index] = { index = index, system = fields[3], sha256 = fields[4], size = size,
      target = fields[6], logicalTarget = fields[6] }
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
    verifyEntryOwnership(entry, transactionTopology)
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

local function bindingSame(left, right)
  if not left or not right then return false end
  for _, key in ipairs(BINDING_KEYS) do if left[key] ~= right[key] then return false end end
  return true
end

local function proxyCapacity(proxy)
  local total, totalReason = callProxy(proxy, "spaceTotal")
  local used, usedReason = callProxy(proxy, "spaceUsed")
  if not tonumber(total) or not tonumber(used) then
    return nil, "capacity unavailable: " .. tostring(totalReason or usedReason)
  end
  total, used = tonumber(total), tonumber(used)
  return { total = total, used = used, free = total == math.huge and math.huge or total - used }
end

local function proxyWritable(proxy)
  local readOnly, reason = callProxy(proxy, "isReadOnly")
  if type(readOnly) ~= "boolean" then return nil, "read-only state unavailable: " .. tostring(reason) end
  if readOnly then return false, "read-only" end
  return true
end

local function requiredPeak(entries)
  local remaining, backups, peak = 0, 0, 0
  for _, item in ipairs(entries) do remaining = remaining + item.newSize end
  peak = remaining
  for _, item in ipairs(entries) do
    backups = backups + item.oldSize
    peak = math.max(peak, remaining + backups)
    remaining = remaining - item.newSize
  end
  return peak + HEADROOM_BYTES
end

local function capacityPlan(entries, topology, collectInventory)
  bindEntries(entries, topology)
  local rootProxy = select(1, filesystem.get(ROOT))
  checked(rootProxy and rootProxy.address, "cannot identify release journal filesystem")
  local rootAddress, groups, inventory = tostring(rootProxy.address), {}, {}
  for index, entry in ipairs(entries) do
    checked(not filesystem.exists(entry.target) or not filesystem.isDirectory or not filesystem.isDirectory(entry.target),
      "managed target is a directory: " .. entry.logicalTarget)
    local digest = fileHash(entry.target)
    local size = digest and filesystem.size(entry.target) or 0
    if collectInventory then inventory[index] = { present = digest ~= nil, sha256 = digest, size = size } end
    local proxy = select(1, filesystem.get(filesystem.path(entry.target)))
    checked(proxy and proxy.address, "cannot inspect target filesystem: " .. entry.logicalTarget)
    local key = tostring(proxy.address)
    local expected = entry.external and topology.address or rootAddress
    checked(key == expected, "target resolved to the wrong filesystem: " .. entry.logicalTarget)
    local group = groups[key]
    if not group then group = { proxy = proxy, items = {} }; groups[key] = group end
    group.items[#group.items + 1] = { newSize = entry.size, oldSize = size }
  end
  local reports, fits = {}, true
  for address, group in pairs(groups) do
    local capacity, reason = proxyCapacity(group.proxy)
    checked(capacity ~= nil, "cannot read filesystem capacity " .. address .. ": " .. tostring(reason))
    local need = requiredPeak(group.items)
    reports[address] = { need = need, free = capacity.free, total = capacity.total }
    if capacity.free < need then fits = false end
  end
  return fits, reports, inventory
end

local function rootRuntimePresence()
  -- Stable cross-release sentinels distinguish a coherent older runtime from
  -- a torn installation. Comparing every new-release target would misclassify
  -- ordinary upgrades whenever a release adds or removes a library.
  local sentinels = {
    "/usr/lib/oc/core/config.lua",
    "/usr/lib/oc/dashboard/app.lua",
  }
  local present, total = 0, #sentinels
  for _, path in ipairs(sentinels) do
    if filesystem.exists(path) then present = present + 1 end
  end
  if present == 0 then return "absent", present, total end
  if present == total then return "complete", present, total end
  return "partial", present, total
end

local function validatedMarker(row, expectedOnly)
  local safe, safeReason = externalMountSafe(row, mountedFilesystems())
  if not safe then return nil, safeReason end
  local markerPath = externalMarkerPath(row.mount)
  requirePlainPath(markerPath, "external runtime marker")
  local proxy = select(1, filesystem.get(markerPath))
  if not proxy or tostring(proxy.address) ~= row.address then return nil, "marker filesystem mismatch" end
  local marker, reason = readBinding(markerPath)
  if not marker then return nil, reason end
  if marker.address ~= row.address then return nil, "marker address does not match mounted filesystem" end
  if marker.install_id ~= derivedInstallId(row.address) then return nil, "marker belongs to another computer" end
  if expectedOnly and not bindingMatchesExpected(marker) then return nil, "marker is for another release" end
  return marker
end

local function validatedRootMarker()
  if not filesystem.exists(ROOT_MARKER_PATH) then return nil, "missing", false end
  requirePlainPath(ROOT_MARKER_PATH, "root runtime marker")
  local address = rootFilesystemAddress()
  local marker, reason = readBinding(ROOT_MARKER_PATH)
  if not marker then return nil, reason, true end
  if marker.address ~= address then return nil, "marker address does not match boot filesystem", true end
  if marker.install_id ~= derivedInstallId(address) then return nil, "marker belongs to another computer", true end
  return marker, nil, true
end

local function topologyFromSelector(rootMarkerPresent)
  if not filesystem.exists(SELECTOR_PATH) then return nil, "missing" end
  requirePlainPath(SELECTOR_PATH, "runtime selector")
  local selector, selectorReason = readBinding(SELECTOR_PATH)
  checked(selector ~= nil, "runtime selector is invalid: " .. tostring(selectorReason))
  local row, mountReason = mountForAddress(selector.address, true)
  checked(row ~= nil, "runtime selector is authoritative but unavailable: " .. tostring(mountReason))
  local marker, markerReason = validatedMarker(row, false)
  checked(marker ~= nil and bindingSame(selector, marker),
    "runtime selector marker mismatch: " .. tostring(markerReason or "fields differ"))
  return {
    kind = "external", address = selector.address, installId = selector.install_id,
    mount = row.mount, proxy = row.proxy, selectorPresent = true, markerPresent = true,
    rootMarkerPresent = rootMarkerPresent == true,
  }
end

local function uniqueMaintainerMarker()
  local rows, byAddress, matches, rejected = mountedFilesystems(), {}, {}, {}
  for _, row in ipairs(rows) do
    local safe = externalMountSafe(row, rows)
    if safe and not byAddress[row.address] then
      byAddress[row.address] = true
      local marker, markerReason = validatedMarker(row, false)
      if marker then matches[#matches + 1] = { row = row, marker = marker } end
      if not marker and filesystem.exists(externalMarkerPath(row.mount)) then
        rejected[#rejected + 1] = row.address .. ": " .. tostring(markerReason)
      end
    end
  end
  if #matches > 1 then return nil, "multiple external Maintainer runtime markers; run " .. recovery.action ..
    " EXTERNAL <full-uuid> after proving all OpenComputers control processes stopped" end
  if #matches == 0 and #rejected > 0 then
    return nil, "external Maintainer runtime marker rejected: " .. table.concat(rejected, ", ")
  end
  return matches[1]
end

local function chooseTopology(entries)
  local rootMarker, rootMarkerReason, rootMarkerExists = validatedRootMarker()
  checked(rootMarker ~= nil or not rootMarkerExists,
    "root runtime marker rejected: " .. tostring(rootMarkerReason))
  local rootMarkerPresent = rootMarker ~= nil
  local selectorTopology = topologyFromSelector(rootMarkerPresent)
  if selectorTopology then return selectorTopology end

  local presence, present, total = rootRuntimePresence()
  checked(presence ~= "partial", "local runtime is partial (" .. tostring(present) .. "/" .. tostring(total) ..
    "); run " .. recovery.action .. " ROOT " .. rootFilesystemAddress() ..
    " after proving all OpenComputers control processes stopped")
  checked(not rootMarkerPresent or presence == "complete",
    "root runtime marker exists without a complete local runtime")

  local marked, markerReason = uniqueMaintainerMarker()
  checked(marked ~= nil or markerReason == nil, markerReason)
  if marked then
    return {
      kind = "external", address = marked.row.address, installId = marked.marker.install_id,
      mount = marked.row.mount, proxy = marked.row.proxy, selectorPresent = false, markerPresent = true,
      rootMarkerPresent = rootMarkerPresent,
    }
  end

  local rootProxy = select(1, filesystem.get("/"))
  checked(rootProxy and rootProxy.address, "cannot identify boot filesystem")
  local rootTopology = {
    kind = "root", address = tostring(rootProxy.address),
    installId = derivedInstallId(tostring(rootProxy.address)),
    selectorPresent = false, markerPresent = false, rootMarkerPresent = rootMarkerPresent,
  }
  local rootFits, rootReports = capacityPlan(entries, rootTopology, false)
  if rootFits then return rootTopology end

  local rows, seen, eligible, diagnostics = mountedFilesystems(), {}, {}, {}
  for _, row in ipairs(rows) do
    local safe, safeReason = externalMountSafe(row, rows)
    if safe and row.address ~= rootTopology.address and not seen[row.address] then
      seen[row.address] = true
      local writable, writableReason = proxyWritable(row.proxy)
      local capacity, capacityReason = proxyCapacity(row.proxy)
      local markerExists = filesystem.exists(externalMarkerPath(row.mount))
      local candidate = {
        kind = "external", address = row.address,
        installId = derivedInstallId(row.address),
        mount = row.mount, proxy = row.proxy, selectorPresent = false, markerPresent = false,
        rootMarkerPresent = rootMarkerPresent,
        free = capacity and capacity.free or nil, total = capacity and capacity.total or nil,
      }
      local candidateFits, candidateReports
      if writable and capacity and capacity.total > MIN_EXTERNAL_BYTES and not markerExists then
        candidateFits, candidateReports = capacityPlan(entries, candidate, false)
      end
      if writable and capacity and capacity.total > MIN_EXTERNAL_BYTES and not markerExists and candidateFits then
        eligible[#eligible + 1] = candidate
      else
        diagnostics[#diagnostics + 1] = row.address .. "=" .. tostring(safeReason or writableReason or capacityReason or
          (markerExists and "existing nonmatching marker") or
          (capacity and capacity.total <= MIN_EXTERNAL_BYTES and "capacity <=4MiB") or
          (candidateReports and "insufficient capacity") or "ineligible")
      end
    end
  end
  local rootAddress = rootTopology.address
  local rootReport = rootReports[rootAddress] or {}
  local prefix = "boot filesystem lacks capacity (need " .. tostring(rootReport.need or "?") ..
    ", free " .. tostring(rootReport.free or "?") .. ")"
  if #eligible == 0 then
    fail(prefix .. "; no unique writable external filesystem can fit the runtime; " .. table.concat(diagnostics, ", "))
  end
  if #eligible > 1 then
    local details = {}
    for _, candidate in ipairs(eligible) do
      details[#details + 1] = candidate.address .. " mount=" .. candidate.mount ..
        " free=" .. tostring(candidate.free) .. " total=" .. tostring(candidate.total)
    end
    fail(prefix .. "; multiple eligible external filesystems: " .. table.concat(details, "; ") ..
      "; create one matching marker/selector or disconnect extras")
  end
  return eligible[1]
end

local function inventoryAndPreflight(entries, topology)
  if topology.kind == "external" then
    local writable, writableReason = proxyWritable(topology.proxy)
    checked(writable == true, "external runtime filesystem is not writable: " .. tostring(writableReason))
    local capacity, capacityReason = proxyCapacity(topology.proxy)
    checked(capacity and capacity.total > MIN_EXTERNAL_BYTES,
      "external runtime filesystem must be larger than 4MiB: " .. tostring(capacityReason))
  end
  local fits, reports, inventory = capacityPlan(entries, topology, true)
  if not fits then
    local details = {}
    for address, report in pairs(reports) do
      if report.free < report.need then details[#details + 1] = address .. " need=" .. report.need .. " free=" .. report.free end
    end
    fail("insufficient filesystem space: " .. table.concat(details, ", "))
  end
  for _, entry in ipairs(entries) do requirePlainManagedPaths(entry) end
  return inventory
end

local function preservePrior(path, priorPath, present, label)
  if not present then removeFile(priorPath); removeFile(priorPath .. ".next"); return end
  if filesystem.exists(priorPath) then return end
  local text, reason = readAll(path, 2048)
  checked(text ~= nil and parseBindingText(text) ~= nil, "cannot preserve prior " .. label .. ": " .. tostring(reason))
  writeTextAtomic(priorPath, text)
end

local function preserveBindingInventory(topology)
  preservePrior(SELECTOR_PATH, SELECTOR_PRIOR_PATH, topology.selectorPresent, "runtime selector")
  preservePrior(ROOT_MARKER_PATH, ROOT_MARKER_PRIOR_PATH,
    topology.rootMarkerPresent, "root runtime marker")
  if topology.kind == "external" then
    preservePrior(externalMarkerPath(topology.mount), MARKER_PRIOR_PATH, topology.markerPresent, "runtime marker")
  else
    removeFile(MARKER_PRIOR_PATH); removeFile(MARKER_PRIOR_PATH .. ".next")
  end
end

local function priorBinding(path, present, label)
  if not present then return nil end
  local text, reason = readAll(path, 2048)
  checked(text ~= nil, "prior " .. label .. " is unavailable: " .. tostring(reason))
  local parsed, parseReason = parseBindingText(text)
  checked(parsed ~= nil, "prior " .. label .. " is invalid: " .. tostring(parseReason))
  parsed.body = text
  return parsed
end

local function currentOrPrior(path, expected, prior, label)
  if not filesystem.exists(path) then return prior == nil end
  local current, reason = readBinding(path)
  checked(current ~= nil, label .. " changed into invalid data: " .. tostring(reason))
  checked(bindingSame(current, expected) or bindingSame(current, prior), label .. " changed after staging")
  return true
end

local function commitRuntimeBinding(topology)
  local markerPath = topology.kind == "external" and externalMarkerPath(topology.mount) or ROOT_MARKER_PATH
  requirePlainPath(SELECTOR_PATH, "runtime selector")
  requirePlainPath(markerPath, "runtime marker")
  local expectedBody = bindingBody(topology.address, topology.installId)
  local expected = assert(parseBindingText(expectedBody))
  local priorSelector = priorBinding(SELECTOR_PRIOR_PATH, topology.selectorPresent, "runtime selector")
  local priorMarkerPath = topology.kind == "external" and MARKER_PRIOR_PATH or ROOT_MARKER_PRIOR_PATH
  local priorMarkerPresent
  if topology.kind == "external" then priorMarkerPresent = topology.markerPresent
  else priorMarkerPresent = topology.rootMarkerPresent end
  local priorMarker = priorBinding(priorMarkerPath, priorMarkerPresent, "runtime marker")
  verifyBindingOwnership(topology)
  if topology.kind == "external" and filesystem.exists(ROOT_MARKER_PATH) then
    local priorRootMarker = priorBinding(ROOT_MARKER_PRIOR_PATH,
      topology.rootMarkerPresent, "root runtime marker")
    checked(currentOrPrior(ROOT_MARKER_PATH, expected, priorRootMarker, "root runtime marker"),
      "unexpected root runtime marker appeared after staging")
  end
  checked(currentOrPrior(markerPath, expected, priorMarker, "runtime marker"),
    "runtime marker disappeared after staging")
  checked(currentOrPrior(SELECTOR_PATH, expected, priorSelector, "runtime selector"),
    "runtime selector disappeared after staging")
  writeTextAtomic(markerPath, expectedBody)
  verifyBindingOwnership(topology)
  checked(readAll(markerPath, 2048) == expectedBody, "runtime marker verification failed")
  if topology.kind == "root" then
    if filesystem.exists(SELECTOR_PATH) then
      -- Explicit metadata recovery may deliberately return from an older
      -- external selector to the boot filesystem. Its exact prior bytes were
      -- staged above and remain rollback authority until finalization.
      removeFile(SELECTOR_PATH); removeFile(SELECTOR_PATH .. ".next")
    end
    checked(not filesystem.exists(SELECTOR_PATH), "root topology cannot retain an external runtime selector")
    return
  end
  writeTextAtomic(SELECTOR_PATH, expectedBody)
  verifyBindingOwnership(topology)
  checked(readAll(SELECTOR_PATH, 2048) == expectedBody, "runtime selector verification failed")
  removeFile(ROOT_MARKER_PATH); removeFile(ROOT_MARKER_PATH .. ".next")
  checked(not filesystem.exists(ROOT_MARKER_PATH), "external topology cannot retain a root runtime marker")
end

local function verifyRuntimeBinding(topology)
  verifyBindingOwnership(topology)
  if topology.kind ~= "external" then
    checked(not filesystem.exists(SELECTOR_PATH), "root topology cannot retain an external runtime selector")
    local marker, markerReason = readBinding(ROOT_MARKER_PATH)
    checked(marker and bindingMatchesExpected(marker) and marker.address == topology.address and
      marker.install_id == topology.installId,
      "root runtime binding verification failed: " .. tostring(markerReason or "fields differ"))
    return true
  end
  local selector, selectorReason = readBinding(SELECTOR_PATH)
  local marker, markerReason = readBinding(externalMarkerPath(topology.mount))
  checked(selector and marker and bindingSame(selector, marker) and bindingMatchesExpected(selector) and
    selector.address == topology.address and selector.install_id == topology.installId,
    "active runtime binding verification failed: " .. tostring(selectorReason or markerReason or "fields differ"))
  checked(not filesystem.exists(ROOT_MARKER_PATH), "external topology retained a root runtime marker")
  return true
end

local function restoreRuntimeBinding(topology)
  local expected = assert(parseBindingText(bindingBody(topology.address, topology.installId)))
  local priorSelector = priorBinding(SELECTOR_PRIOR_PATH, topology.selectorPresent, "runtime selector")
  local priorRootMarker = priorBinding(ROOT_MARKER_PRIOR_PATH,
    topology.rootMarkerPresent, "root runtime marker")
  verifyBindingOwnership(topology)
  if filesystem.exists(ROOT_MARKER_PATH) then
    checked(currentOrPrior(ROOT_MARKER_PATH, expected, priorRootMarker, "root runtime marker"),
      "root runtime marker changed before rollback")
  end
  if topology.kind == "external" then
    local markerPath = externalMarkerPath(topology.mount)
    local priorMarker = priorBinding(MARKER_PRIOR_PATH, topology.markerPresent, "runtime marker")
    currentOrPrior(SELECTOR_PATH, expected, priorSelector, "runtime selector")
    currentOrPrior(markerPath, expected, priorMarker, "external runtime marker")
    if not topology.selectorPresent then removeFile(SELECTOR_PATH) end
    if topology.markerPresent then writeTextAtomic(markerPath, priorMarker.body) else removeFile(markerPath) end
    if topology.selectorPresent then writeTextAtomic(SELECTOR_PATH, priorSelector.body) end
    checked(filesystem.exists(markerPath) == topology.markerPresent and
      (not topology.markerPresent or readAll(markerPath, 2048) == priorMarker.body),
      "prior external runtime marker restoration failed")
    checked(filesystem.exists(SELECTOR_PATH) == topology.selectorPresent and
      (not topology.selectorPresent or readAll(SELECTOR_PATH, 2048) == priorSelector.body),
      "prior runtime selector restoration failed")
  else
    currentOrPrior(ROOT_MARKER_PATH, expected, priorRootMarker, "root runtime marker")
    currentOrPrior(SELECTOR_PATH, expected, priorSelector, "runtime selector")
    if topology.selectorPresent then writeTextAtomic(SELECTOR_PATH, priorSelector.body)
    else removeFile(SELECTOR_PATH); removeFile(SELECTOR_PATH .. ".next") end
    checked(filesystem.exists(SELECTOR_PATH) == topology.selectorPresent and
      (not topology.selectorPresent or readAll(SELECTOR_PATH, 2048) == priorSelector.body),
      "prior runtime selector restoration failed")
  end
  if topology.rootMarkerPresent then
    writeTextAtomic(ROOT_MARKER_PATH, priorRootMarker.body)
  else
    removeFile(ROOT_MARKER_PATH); removeFile(ROOT_MARKER_PATH .. ".next")
  end
  verifyBindingOwnership(topology)
  checked(filesystem.exists(ROOT_MARKER_PATH) == topology.rootMarkerPresent and
    (not topology.rootMarkerPresent or readAll(ROOT_MARKER_PATH, 2048) == priorRootMarker.body),
    "prior root runtime marker restoration failed")
end

local function cleanupBindingInventory()
  removeFile(SELECTOR_PRIOR_PATH); removeFile(SELECTOR_PRIOR_PATH .. ".next")
  removeFile(MARKER_PRIOR_PATH); removeFile(MARKER_PRIOR_PATH .. ".next")
  removeFile(ROOT_MARKER_PRIOR_PATH); removeFile(ROOT_MARKER_PRIOR_PATH .. ".next")
end

local function stage(url, backupAcknowledgement)
  checked(backupAcknowledgement == "NO_BACKUP", "stage requires: stage <https-url> NO_BACKUP")
  url = trim(url)
  checked(url:match("^https://[^%s%z\1-\31]+$") ~= nil, "stage requires a direct immutable HTTPS bundle URL")
  local current = canonicalizeState(parseState())
  checked(not current or current.phase == "staging", "release transaction is " .. tostring(current and current.phase) .. "; finish it before staging")
  if current and filesystem.exists(FILES_PATH) then
    local priorEntries = parseEntries(transactionTopology)
    if current.recovery then
      recovery.reserveArtifactSlot(priorEntries, transactionTopology)
      -- The fixed A/B choice is durable before touching either namespace.
      -- A crash after this write therefore retries the same slot instead of
      -- accumulating another rollback history.
      writeState("staging", 0, url, transactionTopology)
    end
    cleanupStage(priorEntries, true)
  end
  removeFile(FILES_PATH)
  removeFile(INVENTORY_PATH)
  if current then
    removeFile(POWER_CYCLE_MARKER)
    removeFile(POWER_CYCLE_MARKER .. ".next")
  else
    checked(not filesystem.exists(POWER_CYCLE_MARKER) and not filesystem.exists(POWER_CYCLE_MARKER .. ".next"),
      "unowned power-cycle marker collision")
  end
  local reader
  local ok, reason = xpcall(function()
    reader = openReader(url)
    local entries = parseBundleHeaders(reader)
    local topology = current and transactionTopology or chooseTopology(entries)
    transactionTopology = topology
    bindEntries(entries, topology)
    if current and current.recovery then
      recovery.reserveArtifactSlot(entries, topology)
    end
    -- This persists a recovered transaction's bounded artifact slot before
    -- any stage-residue cleanup or payload write can occur.
    writeState("staging", 0, url, topology)
    preserveBindingInventory(topology)
    cleanupStage(entries, current ~= nil)
    local inventory = inventoryAndPreflight(entries, topology)
    writeTextAtomic(FILES_PATH, encodeEntries(entries))
    writeTextAtomic(INVENTORY_PATH, encodeInventory(inventory))
    for _, entry in ipairs(entries) do
      verifyEntryOwnership(entry, topology)
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
      syntaxCheck(partPath, entry.logicalTarget)
      verifyEntryOwnership(entry, topology)
      removeFile(newPath)
      renameFile(partPath, newPath)
    end
    local ending = splitTabs(readLine(reader))
    checked(#ending == 2 and ending[1] == "END" and ending[2] == EXPECTED_RELEASE, "bundle END boundary mismatch")
    checked(#reader.buffer == 0, "bundle has trailing bytes")
    checked(pullReader(reader) == nil, "bundle has trailing payload")
    checked(shaFinal(reader.digest) == EXPECTED_BUNDLE_SHA256, "bundle digest mismatch")
    -- Persist the execution-plane brake before the one required apply boot.
    -- Desired daemon policy stays intact; old RC/Dashboard code sees this
    -- stable root-local inhibit and cannot reacquire submit authority.
    writeTextAtomic(INHIBIT_PATH,
      "release=" .. EXPECTED_RELEASE .. "\nphase=staged\n")
    armPowerCycleGate("apply")
    -- A verified full stage is the first point at which cancellation can
    -- safely retire a metadata-recovery fence.
    topology.recovery = false
    writeState("staged", 0, url)
  end, function(message) return tostring(message) end)
  closeReader(reader)
  if not ok then return nil, "stage failed: " .. tostring(reason) end
  return true, "STAGED: " .. tostring(EXPECTED_FILE_COUNT)
    .. " files verified; topology=" .. tostring(transactionTopology.kind)
    .. (transactionTopology.kind == "external" and " address=" .. transactionTopology.address or "")
    .. "; live targets unchanged; deployment inhibit armed; run shutdown, wait until visibly OFF, then power on manually"
end

local function activeProcess(recovery)
  local ok, process = pcall(require, "process")
  if not ok or type(process) ~= "table" or type(process.list) ~= "table" then return "process list unavailable" end
  local count = 0
  local listed = process.list
  local function inspect(pid, value)
    local info = type(value) == "table" and value or nil
    if not info and type(process.info) == "function" then
      local infoOk, result = pcall(process.info, pid)
      if infoOk then info = result end
    end
    -- The caller owns the in-memory installer token. Every other matching
    -- OpenComputers command is a peer that can still execute installed bytes
    -- while recovery is deciding which topology those bytes belong to.
    if info and rawget(info, PROCESS_AUTHORITY_KEY) ~= nil then return nil end
    local text = type(info) == "table" and table.concat({ tostring(info.path or ""), tostring(info.command or ""), tostring(info.name or "") }, " "):lower() or tostring(value or ""):lower()
    if text:find("oc%-dashboard") or text:find("dashboard%.lua") or text:find("ae2%-maintainer") or
        (recovery and (text:find("oc%-ae2%.lua") or text:find("ae2%-workflow") or
          text:find("oc%-config%-migrate") or text:find("/usr/bin/oc%-") or
          text:find("/etc/rc%.d/oc%-") or text:find("waterline%-grade5") or
          text:find("gt%-probe") or text:find("power%-status") or
          text:find("/usr/lib/oc/"))) then return text end
  end
  for pid, value in pairs(listed) do
    count = count + 1
    if count > MAX_PROCESS_ROWS then return "process list exceeds the installer recovery bound" end
    local found = inspect(pid, value)
    if found then return found end
  end
  return nil
end

function recovery.pathObservation(name, path, limit)
  requirePlainPath(path, "installer recovery evidence")
  if not filesystem.exists(path) then
    return { name = name, path = path, kind = "missing", limit = limit }
  end
  if filesystem.isDirectory and filesystem.isDirectory(path) then
    return { name = name, path = path, kind = "directory", limit = limit }
  end
  local raw, reason = readAll(path, limit)
  checked(raw ~= nil, "cannot preserve " .. name .. " recovery evidence: " .. tostring(reason))
  return { name = name, path = path, kind = "file", raw = raw, limit = limit }
end

function recovery.appendTree(snapshot, rootName, name, path, limit, depth)
  checked(depth <= recovery.maxTreeDepth,
    "installer recovery evidence tree exceeds depth " .. tostring(recovery.maxTreeDepth) .. ": " .. rootName)
  checked(#snapshot.observations < recovery.maxTreeRows,
    "installer recovery evidence tree exceeds " .. tostring(recovery.maxTreeRows) .. " rows")
  local observed = recovery.pathObservation(name, path, limit)
  snapshot.observations[#snapshot.observations + 1] = observed
  snapshot.byName[name] = observed
  snapshot.treeMembers[rootName] = snapshot.treeMembers[rootName] or {}
  snapshot.treeMembers[rootName][#snapshot.treeMembers[rootName] + 1] = observed
  if observed.kind ~= "directory" then return end
  checked(type(filesystem.list) == "function", "OpenOS directory enumeration is unavailable for installer recovery")
  local iterator, listReason = filesystem.list(path)
  checked(type(iterator) == "function", "cannot enumerate corrupt recovery directory " .. path .. ": " .. tostring(listReason))
  local children, seen = {}, {}
  for rawName in iterator do
    local child = tostring(rawName or ""):gsub("/$", "")
    checked(child ~= "" and child ~= "." and child ~= ".." and
        child:match("^[A-Za-z0-9_.%-]+$") ~= nil and not seen[child],
      "unsafe or duplicate child in corrupt recovery directory: " .. tostring(rawName))
    seen[child] = true
    children[#children + 1] = child
    checked(#children <= recovery.maxTreeRows,
      "corrupt recovery directory exceeds the bounded row count: " .. path)
  end
  table.sort(children)
  for index, child in ipairs(children) do
    recovery.appendTree(snapshot, rootName, name .. "_child_" .. tostring(index),
      filesystem.concat(path, child), math.max(limit or 0, recovery.treeFileMaxBytes), depth + 1)
  end
end

function recovery.evidence()
  local specs = {
    { "state", STATE_PATH, recovery.stateMaxBytes },
    { "state_next", STATE_PATH .. ".next", recovery.stateMaxBytes },
    { "files", FILES_PATH, recovery.indexMaxBytes },
    { "files_next", FILES_PATH .. ".next", recovery.indexMaxBytes },
    { "inventory", INVENTORY_PATH, recovery.indexMaxBytes },
    { "inventory_next", INVENTORY_PATH .. ".next", recovery.indexMaxBytes },
    { "inhibit", INHIBIT_PATH, recovery.smallMaxBytes },
    { "inhibit_next", INHIBIT_PATH .. ".next", recovery.smallMaxBytes },
    { "power", POWER_CYCLE_MARKER, recovery.smallMaxBytes },
    { "power_next", POWER_CYCLE_MARKER .. ".next", recovery.smallMaxBytes },
    { "legacy_lock", LEGACY_LOCK_PATH, recovery.smallMaxBytes },
    { "selector", SELECTOR_PATH, recovery.smallMaxBytes },
    { "root_marker", ROOT_MARKER_PATH, recovery.smallMaxBytes },
    { "selector_prior", SELECTOR_PRIOR_PATH, recovery.smallMaxBytes },
    { "selector_prior_next", SELECTOR_PRIOR_PATH .. ".next", recovery.smallMaxBytes },
    { "marker_prior", MARKER_PRIOR_PATH, recovery.smallMaxBytes },
    { "marker_prior_next", MARKER_PRIOR_PATH .. ".next", recovery.smallMaxBytes },
    { "root_marker_prior", ROOT_MARKER_PRIOR_PATH, recovery.smallMaxBytes },
    { "root_marker_prior_next", ROOT_MARKER_PRIOR_PATH .. ".next", recovery.smallMaxBytes },
    { "prior_archive", recovery.path, recovery.maxBytes },
    { "prior_archive_next", recovery.path .. ".next", recovery.maxBytes },
    { "previous_archive", recovery.previousPath, recovery.maxBytes },
    { "previous_archive_next", recovery.previousPath .. ".next", recovery.maxBytes },
    { "recovery_stage", recovery.stagePath, recovery.maxBytes },
    { "recovery_stage_next", recovery.stagePath .. ".next", recovery.maxBytes },
  }
  local externalRows, seen = {}, {}
  local rows = mountedFilesystems()
  for _, row in ipairs(rows) do
    local safe = externalMountSafe(row, rows)
    if safe and not seen[row.address] then
      seen[row.address] = true
      row.recoveryName = "external_marker_" .. tostring(#externalRows + 1)
      row.recoveryPath = externalMarkerPath(row.mount)
      externalRows[#externalRows + 1] = row
      specs[#specs + 1] = { row.recoveryName, row.recoveryPath, recovery.smallMaxBytes }
    end
  end
  local snapshot = { observations = {}, byName = {}, treeMembers = {}, externalRows = externalRows }
  for _, spec in ipairs(specs) do
    recovery.appendTree(snapshot, spec[1], spec[1], spec[2], spec[3], 0)
  end
  return snapshot
end

function recovery.sameObservation(left, right)
  return left and right and left.name == right.name and left.path == right.path and
    left.kind == right.kind and left.raw == right.raw
end

function recovery.sameEvidence(left, right, ignoredName, ignoredPath)
  if not left or not right or #left.externalRows ~= #right.externalRows then return false end
  ignoredPath = ignoredPath or
    (ignoredName and left.byName[ignoredName] and left.byName[ignoredName].path)
  local leftByPath, rightByPath = {}, {}
  for _, observed in ipairs(left.observations) do leftByPath[observed.path] = observed end
  for _, observed in ipairs(right.observations) do rightByPath[observed.path] = observed end
  for path, observed in pairs(leftByPath) do
    local other = rightByPath[path]
    if path ~= ignoredPath and (not other or observed.kind ~= other.kind or
        observed.raw ~= other.raw) then return false end
  end
  for path in pairs(rightByPath) do
    if path ~= ignoredPath and not leftByPath[path] then return false end
  end
  for index, row in ipairs(left.externalRows) do
    local other = right.externalRows[index]
    if not other or row.address ~= other.address or row.mount ~= other.mount then return false end
  end
  return true
end

function recovery.checkStateSchema(snapshot)
  for _, name in ipairs({ "state", "state_next" }) do
    local observed = snapshot.byName[name]
    if observed and observed.kind == "file" then
      for rawLine in (observed.raw .. "\n"):gmatch("([^\n]*)\n") do
        local line = rawLine:gsub("\r$", "")
        local format = line:match("^format=(%d+)$")
        checked(not format or tonumber(format) <= 1,
          "newer installer state schema " .. tostring(format) .. " requires its matching pinned installer")
      end
    end
  end
end

function recovery.stateArtifactSlot(snapshot)
  local selected
  for _, name in ipairs({ "state", "state_next" }) do
    local observed = snapshot.byName[name]
    if observed and observed.kind == "file" then
      for rawLine in (observed.raw .. "\n"):gmatch("([^\n]*)\n") do
        local slot = rawLine:gsub("\r$", ""):match("^artifact_slot=([a-z]+)$")
        if slot == "pending" or slot == "a" or slot == "b" then
          checked(selected == nil or selected == slot,
            "installer state copies disagree about their reserved artifact slot")
          selected = slot
        end
      end
    end
  end
  return selected
end

function recovery.slotRollbackCollision(entries, topology, slot)
  checked(slot == "a" or slot == "b", "invalid bounded recovery artifact slot")
  local prior = topology.artifactSlot
  topology.artifactSlot = slot
  local collision
  for _, entry in ipairs(entries or {}) do
    verifyEntryOwnership(entry, topology)
    requirePlainManagedPaths(entry, topology)
    local _, _, oldPath = artifactPaths(entry.target, topology)
    if filesystem.exists(oldPath) then collision = oldPath; break end
  end
  topology.artifactSlot = prior
  return collision
end

function recovery.reserveArtifactSlot(entries, topology)
  checked(topology and topology.recovery == true,
    "artifact-slot recovery reservation requires canonical recovery ownership")
  local reserved = topology.artifactSlot
  if reserved == "a" or reserved == "b" then
    local collision = recovery.slotRollbackCollision(entries, topology, reserved)
    checked(not collision, "reserved recovery artifact slot " .. reserved:upper() ..
      " retains rollback payload: " .. tostring(collision) ..
      "; rerun " .. recovery.action .. " to archive the new state and reselect the opposite fixed slot")
    return reserved
  end
  checked(reserved == nil or reserved == "pending", "invalid pending recovery artifact slot")
  local aCollision = recovery.slotRollbackCollision(entries, topology, "a")
  local bCollision = recovery.slotRollbackCollision(entries, topology, "b")
  checked(not (aCollision and bCollision),
    "both fixed artifact slots retain rollback payloads (A=" .. tostring(aCollision) ..
      ", B=" .. tostring(bCollision) ..
      "); automatic NO_BACKUP recovery cannot preserve a third history: take an out-of-band backup and use the matching pinned installer to finish one rollback; no payload was changed")
  topology.artifactSlot = aCollision and "b" or "a"
  return topology.artifactSlot
end

function recovery.hostBinding(observed, expectedAddress)
  if not observed or observed.kind ~= "file" then return nil end
  local parsed = parseBindingText(observed.raw)
  if not parsed or (expectedAddress and parsed.address ~= expectedAddress) then return nil end
  local ok, installId = pcall(derivedInstallId, parsed.address)
  if not ok or parsed.install_id ~= installId then return nil end
  parsed.body = observed.raw
  return parsed
end

function recovery.externalRow(snapshot, address)
  for _, row in ipairs(snapshot.externalRows) do
    if row.address == address then return row end
  end
end

function recovery.externalTopology(row)
  checked(row ~= nil, "explicit external recovery filesystem is not mounted at a safe path")
  local writable, reason = proxyWritable(row.proxy)
  checked(writable == true, "explicit external recovery filesystem is not writable: " .. tostring(reason))
  return {
    kind = "external", address = row.address, installId = derivedInstallId(row.address),
    mount = row.mount, proxy = row.proxy,
  }
end

function recovery.selectTopology(snapshot, explicitKind, explicitAddress)
  local rootAddress = rootFilesystemAddress()
  local selector = recovery.hostBinding(snapshot.byName.selector)
  local rootMarker = recovery.hostBinding(snapshot.byName.root_marker, rootAddress)
  local markerCandidates, markerByAddress = {}, {}
  if rootMarker then
    markerCandidates[#markerCandidates + 1] = { kind = "root", address = rootAddress, binding = rootMarker }
  end
  for _, row in ipairs(snapshot.externalRows) do
    local binding = recovery.hostBinding(snapshot.byName[row.recoveryName], row.address)
    if binding then
      local candidate = { kind = "external", address = row.address, binding = binding, row = row }
      markerCandidates[#markerCandidates + 1] = candidate
      markerByAddress[row.address] = candidate
    end
  end

  local topology, selectedMarker
  if explicitKind then
    checked(explicitKind == "ROOT" or explicitKind == "EXTERNAL",
      recovery.action .. " accepts only ROOT <full-uuid> or EXTERNAL <full-uuid>")
    checked(safeAddress(explicitAddress), "installer recovery requires a full lowercase filesystem UUID")
    if explicitKind == "ROOT" then
      checked(explicitAddress == rootAddress, "explicit ROOT UUID does not match the boot filesystem")
      topology = { kind = "root", address = rootAddress, installId = derivedInstallId(rootAddress) }
    else
      local row = recovery.externalRow(snapshot, explicitAddress)
      topology = recovery.externalTopology(row)
      selectedMarker = snapshot.byName[row.recoveryName]
      if selectedMarker.kind == "file" then
        local structurallyValid = parseBindingText(selectedMarker.raw)
        checked(not structurallyValid or recovery.hostBinding(selectedMarker, row.address) ~= nil,
          "explicit external runtime marker is valid authority for another host or filesystem")
      end
    end
  elseif selector then
    local selected = markerByAddress[selector.address]
    checked(selected and bindingSame(selector, selected.binding),
      "runtime selector authority is unavailable or mismatched; rerun recovery with an explicit topology and full UUID")
    topology = recovery.externalTopology(selected.row)
    selectedMarker = snapshot.byName[selected.row.recoveryName]
  elseif #markerCandidates == 1 then
    local selected = markerCandidates[1]
    if selected.kind == "root" then
      topology = { kind = "root", address = rootAddress, installId = derivedInstallId(rootAddress) }
    else
      topology = recovery.externalTopology(selected.row)
      selectedMarker = snapshot.byName[selected.row.recoveryName]
    end
  else
    if #markerCandidates > 1 then
      local choices = {}
      for _, candidate in ipairs(markerCandidates) do
        choices[#choices + 1] = candidate.kind:upper() .. " " .. candidate.address
      end
      fail("installer recovery topology is ambiguous across valid host-bound markers: " ..
        table.concat(choices, ", ") .. "; rerun with one displayed kind and full UUID")
    end
    local presence = rootRuntimePresence()
    checked(presence ~= "absent",
      "no provable installed runtime root; rerun recovery with ROOT or EXTERNAL and the full UUID")
    topology = { kind = "root", address = rootAddress, installId = derivedInstallId(rootAddress) }
  end

  topology.selectorPresent = selector ~= nil
  topology.rootMarkerPresent = rootMarker ~= nil
  if topology.kind == "external" then
    selectedMarker = selectedMarker or snapshot.byName[recovery.externalRow(snapshot, topology.address).recoveryName]
    topology.markerPresent = recovery.hostBinding(selectedMarker, topology.address) ~= nil
    topology.recoveryMarkerName = selectedMarker.name
  else
    topology.markerPresent = false
  end
  topology.recoverySelectorValid = selector ~= nil
  topology.recoveryRootMarkerValid = rootMarker ~= nil
  topology.recovery = true
  -- A recognized old slot is evidence about the damaged transaction, not
  -- authority to overwrite that slot. Restage re-proves both fixed slots from
  -- the immutable bundle target set and persists the free choice before use.
  topology.priorArtifactSlot = recovery.stateArtifactSlot(snapshot)
  topology.artifactSlot = "pending"
  return topology
end

function recovery.hex(value)
  return (tostring(value or ""):gsub(".", function(character)
    return string.format("%02x", string.byte(character))
  end))
end

function recovery.archiveBody(snapshot, topology)
  local header, payload = {
    "format=1",
    "release=" .. EXPECTED_RELEASE,
    "bundle=" .. EXPECTED_BUNDLE_SHA256,
    "topology=" .. topology.kind,
    "runtime_address=" .. topology.address,
    "artifact_slot=" .. tostring(topology.artifactSlot or "pending"),
    "prior_artifact_slot=" .. tostring(topology.priorArtifactSlot or "unknown"),
    "entries=" .. tostring(#snapshot.observations),
  }, {}
  for _, observed in ipairs(snapshot.observations) do
    local size, digest = 0, "-"
    if observed.kind == "file" then
      size, digest = #observed.raw, api.sha256(observed.raw)
      payload[#payload + 1] = observed.raw
    end
    header[#header + 1] = "e=" .. observed.name .. "\t" .. observed.kind .. "\t" ..
      tostring(size) .. "\t" .. digest .. "\t" .. recovery.hex(observed.path)
  end
  local body = table.concat(header, "\n") .. "\nDATA\n" .. table.concat(payload)
  checked(#body <= recovery.maxBytes,
    "installer recovery evidence exceeds the bounded archive; preserve it out of band before review")
  return body
end

function recovery.preserveArchive(snapshot, body)
  local candidates = {
    { "recovery_stage", "recovery_stage_next" },
    { "previous_archive", "previous_archive_next" },
    { "prior_archive", "prior_archive_next" },
  }
  local selected
  for _, candidate in ipairs(candidates) do
    local target, nextTarget = snapshot.byName[candidate[1]], snapshot.byName[candidate[2]]
    if target.kind ~= "directory" and nextTarget.kind == "missing" then selected = target; break end
  end
  local targetPath, insideDirectory
  if selected then
    targetPath = selected.path
  else
    -- A corrupt nonempty directory cannot authorize recovery, but it also
    -- cannot be allowed to dead-end recovery-of-recovery. The bounded source
    -- tree guarantees a free fixed-form child name within maxTreeRows + 1.
    checked(#snapshot.observations < recovery.maxTreeRows,
      "installer recovery directory anchor needs one bounded evidence row of headroom")
    for _, candidate in ipairs(candidates) do
      local target = snapshot.byName[candidate[1]]
      if target.kind == "directory" then
        for index = 1, recovery.maxTreeRows + 1 do
          local path = filesystem.concat(target.path,
            ".installer-recovery-envelope-" .. tostring(index))
          if not filesystem.exists(path) and not filesystem.exists(path .. ".next") then
            requirePlainPath(path, "installer recovery directory anchor")
            requirePlainPath(path .. ".next", "installer recovery directory anchor")
            selected, targetPath, insideDirectory = target, path, true
            break
          end
        end
      end
      if selected then break end
    end
  end
  checked(selected ~= nil and targetPath ~= nil,
    "all bounded installer recovery archive slots are unavailable")
  writeTextAtomic(targetPath, body)
  local stored, reason = readAll(targetPath, recovery.maxBytes)
  checked(stored == body, "installer recovery archive readback failed: " .. tostring(reason or "content mismatch"))
  return selected.name, targetPath, insideDirectory == true
end

function recovery.removeTree(snapshot, rootName)
  local members = snapshot.treeMembers[rootName] or {}
  for index = #members, 1, -1 do
    local observed = members[index]
    local current = recovery.pathObservation(observed.name, observed.path, observed.limit)
    checked(recovery.sameObservation(observed, current),
      "installer recovery evidence changed before removal: " .. observed.name)
    if observed.kind == "directory" then
      local removed, reason = filesystem.remove(observed.path)
      checked(removed, "cannot remove archived recovery directory " .. observed.path .. ": " .. tostring(reason))
    elseif observed.kind == "file" then
      removeFile(observed.path)
    end
    checked(not filesystem.exists(observed.path), "installer recovery evidence survived removal: " .. observed.name)
  end
  return true
end

function recovery.removeTreeExceptAnchor(snapshot, rootName, anchorPath)
  local members = snapshot.treeMembers[rootName] or {}
  for index = #members, 1, -1 do
    local observed = members[index]
    if observed.path ~= snapshot.byName[rootName].path then
      local current = recovery.pathObservation(observed.name, observed.path, observed.limit)
      checked(recovery.sameObservation(observed, current),
        "installer recovery evidence changed before removal: " .. observed.name)
      if observed.kind == "directory" then
        local removed, reason = filesystem.remove(observed.path)
        checked(removed, "cannot remove archived recovery directory " .. observed.path .. ": " .. tostring(reason))
      elseif observed.kind == "file" then
        removeFile(observed.path)
      end
    end
  end
  local iterator, reason = filesystem.list(snapshot.byName[rootName].path)
  checked(type(iterator) == "function",
    "cannot verify installer recovery directory anchor: " .. tostring(reason))
  local count, expectedName = 0, anchorPath:match("([^/]+)$")
  for rawName in iterator do
    count = count + 1
    checked(count == 1 and tostring(rawName):gsub("/$", "") == expectedName,
      "installer recovery directory gained a successor before canonicalization")
  end
  checked(count == 1 and readAll(anchorPath, recovery.maxBytes) ~= nil,
    "installer recovery directory anchor is unavailable")
end

function recovery.finishArchive(snapshot, anchorName, anchorPath, insideDirectory, body)
  if insideDirectory then
    local safetyName = anchorName == "recovery_stage" and
      "previous_archive" or "recovery_stage"
    local safetyNextName = safetyName .. "_next"
    local safetyPath = snapshot.byName[safetyName].path
    recovery.removeTree(snapshot, safetyNextName)
    recovery.removeTree(snapshot, safetyName)
    writeTextAtomic(safetyPath, body)
    checked(readAll(safetyPath, recovery.maxBytes) == body,
      "installer recovery safety archive readback failed")

    for _, name in ipairs({
      "prior_archive_next", "previous_archive_next", "recovery_stage_next",
      "prior_archive", "previous_archive", "recovery_stage",
    }) do
      if name ~= anchorName and name ~= safetyName and name ~= safetyNextName then
        recovery.removeTree(snapshot, name)
      end
    end
    recovery.removeTreeExceptAnchor(snapshot, anchorName, anchorPath)
    checked(readAll(anchorPath, recovery.maxBytes) == body,
      "installer recovery directory anchor changed before retirement")
    removeFile(anchorPath)
    local removed, reason = filesystem.remove(snapshot.byName[anchorName].path)
    checked(removed, "cannot retire installer recovery anchor directory: " .. tostring(reason))
    writeTextAtomic(recovery.path, body)
    checked(readAll(recovery.path, recovery.maxBytes) == body,
      "canonical installer recovery archive readback failed")
    if safetyPath ~= recovery.path then removeFile(safetyPath) end
    return
  end

  if anchorName ~= "prior_archive" then
    recovery.removeTree(snapshot, "prior_archive_next")
    recovery.removeTree(snapshot, "prior_archive")
    writeTextAtomic(recovery.path, body)
    checked(readAll(recovery.path, recovery.maxBytes) == body,
      "canonical installer recovery archive readback failed")
  end
  for _, name in ipairs({
    "previous_archive_next", "previous_archive", "recovery_stage_next", "recovery_stage",
  }) do
    if name == anchorName then
      checked(readAll(anchorPath, recovery.maxBytes) == body,
        "installer recovery archive anchor changed before retirement")
      removeFile(anchorPath)
    else
      recovery.removeTree(snapshot, name)
    end
  end
end

function recovery.run(offline, backup, confirmation, explicitKind, explicitAddress)
  checked(offline == "OFFLINE" and backup == "NO_BACKUP" and confirmation == "CONFIRM",
    "recover-installer requires: " .. recovery.action ..
      " [ROOT <full-uuid>|EXTERNAL <full-uuid>]")
  checked((explicitKind == nil and explicitAddress == nil) or
      (type(explicitKind) == "string" and type(explicitAddress) == "string"),
    "recover-installer topology requires both kind and full UUID")
  local running = activeProcess(true)
  checked(not running, "active OpenComputers control process blocks installer recovery: " .. tostring(running))
  local snapshot = recovery.evidence()
  recovery.checkStateSchema(snapshot)
  local topology = recovery.selectTopology(snapshot, explicitKind, explicitAddress)
  local archive = recovery.archiveBody(snapshot, topology)
  running = activeProcess(true)
  checked(not running, "OpenComputers control process appeared before installer recovery archive: " .. tostring(running))
  local archiveAnchor, archiveAnchorPath, archiveInsideDirectory =
    recovery.preserveArchive(snapshot, archive)
  running = activeProcess(true)
  checked(not running, "OpenComputers control process appeared after installer recovery archive: " .. tostring(running))
  local current = recovery.evidence()
  checked(recovery.sameEvidence(snapshot, current, archiveAnchor, archiveAnchorPath),
    "installer recovery evidence changed after archival; successor bytes were preserved")

  for _, name in ipairs({
    "files", "files_next", "inventory", "inventory_next", "state_next", "inhibit_next",
    "power", "power_next", "selector_prior", "selector_prior_next", "marker_prior",
    "marker_prior_next", "root_marker_prior", "root_marker_prior_next",
  }) do recovery.removeTree(snapshot, name) end
  recovery.removeTree(snapshot, "legacy_lock")

  if not topology.recoverySelectorValid then recovery.removeTree(snapshot, "selector") end
  if not topology.recoveryRootMarkerValid then recovery.removeTree(snapshot, "root_marker") end
  if topology.kind == "external" and not topology.markerPresent then
    recovery.removeTree(snapshot, topology.recoveryMarkerName)
  end
  if snapshot.byName.state.kind == "directory" then recovery.removeTree(snapshot, "state") end
  if snapshot.byName.inhibit.kind == "directory" then recovery.removeTree(snapshot, "inhibit") end

  local recoveryInhibit = "release=" .. EXPECTED_RELEASE .. "\nphase=recovery\n"
  writeTextAtomic(INHIBIT_PATH, recoveryInhibit)
  checked(readAll(INHIBIT_PATH, recovery.smallMaxBytes) == recoveryInhibit,
    "installer recovery inhibit readback failed")
  transactionTopology = topology
  writeState("staging", 0, "", topology)
  checked(not filesystem.exists(STATE_PATH .. ".next") and not filesystem.exists(POWER_CYCLE_MARKER) and
      not filesystem.exists(POWER_CYCLE_MARKER .. ".next") and not filesystem.exists(LEGACY_LOCK_PATH),
    "installer recovery cleanup did not reach its canonical boundary")
  recovery.finishArchive(snapshot, archiveAnchor, archiveAnchorPath,
    archiveInsideDirectory, archive)
  running = activeProcess(true)
  checked(not running, "OpenComputers control process appeared during installer recovery: " .. tostring(running))
  return true, "RECOVERED: exact installer evidence archived; topology=" .. topology.kind ..
    " address=" .. topology.address ..
    "; artifact_slot=" .. topology.artifactSlot ..
    "; canonical STAGING ownership and recovery inhibit installed; rerun stage with the immutable bundle URL"
end

local function deploymentInhibitOwned()
  if not filesystem.exists(INHIBIT_PATH) then return false end
  local text = readAll(INHIBIT_PATH, 4096)
  return type(text) == "string" and text:match("^release=" .. EXPECTED_RELEASE:gsub("([^%w])", "%%%1") .. "\n") ~= nil
end

local function stagedDeploymentInhibitOwned()
  if not filesystem.exists(INHIBIT_PATH) then return false, "staged deployment inhibit is missing" end
  local text, reason = readAll(INHIBIT_PATH, 4096)
  if not text then return false, "cannot read staged deployment inhibit: " .. tostring(reason) end
  local expected = "release=" .. EXPECTED_RELEASE .. "\nphase=staged\n"
  if text ~= expected then return false, "staged deployment inhibit is not owned exactly by this release" end
  return true
end

-- Compile policy text, but never execute it. A malformed control file may
-- contain arbitrary Lua, including a non-yielding loop; status and recovery
-- must remain bounded even when the input is hostile or damaged.
local function luaCodeWithoutStrings(source)
  local output, index, length = {}, 1, #source
  while index <= length do
    local character = source:sub(index, index)
    local pair = source:sub(index, index + 1)
    if character == "\"" or character == "'" then
      local quote, closed = character, false
      output[#output + 1] = " "
      index = index + 1
      while index <= length do
        character = source:sub(index, index)
        if character == "\\" then
          index = index + 2
        elseif character == quote then
          closed = true
          index = index + 1
          break
        else
          index = index + 1
        end
      end
      if not closed then return nil, "unterminated string" end
    elseif pair == "--" then
      if source:sub(index + 2, index + 2) == "[" then
        return nil, "long comments are not accepted in daemon control recovery"
      end
      local newline = source:find("\n", index + 2, true)
      if not newline then break end
      output[#output + 1] = "\n"
      index = newline + 1
    else
      output[#output + 1] = character
      index = index + 1
    end
  end
  return table.concat(output)
end

local function daemonSchemaReason(code)
  if type(code) ~= "string" then return "daemon policy schema cannot be inspected" end
  for _, key in ipairs({ "schemaVersion", "formatVersion", "schema", "format" }) do
    local assignment = "%f[%w_]" .. key .. "%f[^%w_]%s*=%s*"
    local assigned = 0
    code:gsub(assignment, function() assigned = assigned + 1; return "" end)
    if assigned > 0 then
      local parsed = 0
      for token in code:gmatch(assignment .. "([^,%s}%]]+)") do
        parsed = parsed + 1
        local value = tonumber(token)
        if not value or value < 0 or value ~= math.floor(value) then
          return "daemon policy has an unsupported schema marker"
        end
        if value > DAEMON_CONTROL_SCHEMA then
          return "daemon policy uses a newer schema than this installer"
        end
      end
      if parsed ~= assigned then return "daemon policy has an unsupported schema marker" end
    end
  end
end

local function inspectDaemonPolicySource(source)
  local result = { source = source, readable = false, safeLiteral = false, off = false, on = false }
  if type(source) ~= "string" then
    result.reason = "daemon policy bytes are unavailable"
    return result
  end
  local text = trim(source)
  local chunk, syntaxReason = load("return " .. source, "=daemon-control", "t", {})
  result.readable = chunk ~= nil and text:sub(1, 1) == "{" and text:sub(-1) == "}"
  local code, scrubReason = luaCodeWithoutStrings(source)
  result.schemaReason = daemonSchemaReason(code)
  if not code then
    result.reason = tostring(scrubReason)
    return result
  end
  if code:find("[^%w_%s%{%}%[%]=,%+%-%.]") then
    result.reason = "daemon policy is not a bounded literal table"
    return result
  end
  local valuesOnly = code:gsub("%f[%w_][%a_][%w_]*%f[^%w_]%s*=", "=")
  for word in valuesOnly:gmatch("%f[%w_][%a_][%w_]*%f[^%w_]") do
    if word ~= "true" and word ~= "false" and word ~= "nil" and word ~= "e" and word ~= "E" then
      result.reason = "daemon policy contains a non-literal value"
      return result
    end
  end
  result.safeLiteral = result.readable
  local falseCount, trueCount, otherCount = 0, 0, 0
  local enabledAssignment = "%f[%w_]enabled%f[^%w_]%s*=%s*([%a_][%w_]*)"
  for value in code:gmatch(enabledAssignment) do
    if value == "false" then falseCount = falseCount + 1
    elseif value == "true" then trueCount = trueCount + 1
    else otherCount = otherCount + 1 end
  end
  result.off = result.safeLiteral and falseCount == 1 and trueCount == 0 and otherCount == 0
  result.on = result.safeLiteral and trueCount == 1 and falseCount == 0 and otherCount == 0
  if not result.readable then result.reason = tostring(syntaxReason or "daemon policy is unreadable") end
  return result
end

local function daemonIsOff(allowInhibitedDesired)
  local path = DAEMON_CONTROL_PATH
  requirePlainPath(path, "daemon configuration")
  requirePlainPath(path .. ".new", "daemon staged configuration")
  requirePlainPath(path .. ".previous", "daemon recovery configuration")
  if filesystem.exists(path .. ".new") or filesystem.exists(path .. ".previous") then
    return nil, "cannot prove daemon OFF while configuration recovery artifacts exist"
  end
  local source, reason = readAll(path, 16384)
  if not source then return nil, "cannot prove daemon OFF: " .. tostring(reason) end
  local policy = inspectDaemonPolicySource(source)
  if policy.off then return true end
  if policy.on then
    if allowInhibitedDesired and deploymentInhibitOwned() then return true end
    return nil, "daemon desired state is ON"
  end
  return nil, "cannot prove daemon desired state is OFF"
end

local function readControlEvidence(path, label, limit)
  requirePlainPath(path, label)
  if not filesystem.exists(path) then return { path = path, present = false } end
  if filesystem.isDirectory and filesystem.isDirectory(path) then
    return { path = path, present = true, reason = label .. " is a directory" }
  end
  local raw, reason = readAll(path, limit or DAEMON_CONTROL_MAX_BYTES)
  if raw == nil then
    return { path = path, present = true, reason = "cannot read " .. label .. ": " .. tostring(reason) }
  end
  return { path = path, present = true, raw = raw, policy = inspectDaemonPolicySource(raw) }
end

local CONTROL_EVIDENCE_ROWS = {
  { key = "primary", path = DAEMON_CONTROL_PATH, label = "daemon control primary",
    limit = DAEMON_CONTROL_MAX_BYTES },
  { key = "new", path = DAEMON_CONTROL_PATH .. ".new", label = "daemon control .new evidence",
    limit = DAEMON_CONTROL_MAX_BYTES },
  { key = "previous", path = DAEMON_CONTROL_PATH .. ".previous",
    label = "daemon control .previous evidence", limit = DAEMON_CONTROL_MAX_BYTES },
  { key = "lock", path = DAEMON_CONTROL_PATH .. ".lock",
    label = "daemon control legacy lock evidence", limit = DAEMON_CONTROL_LOCK_MAX_BYTES },
}

local function captureControlEvidence()
  local snapshot = {}
  for _, row in ipairs(CONTROL_EVIDENCE_ROWS) do
    local evidence = readControlEvidence(row.path, row.label, row.limit)
    if evidence.reason then return nil, evidence.reason end
    snapshot[row.key] = evidence
  end
  if snapshot.primary.present ~= true then return nil, "daemon control primary is missing" end
  return snapshot
end

local function controlPriorBody(snapshot)
  local header, payload = { "format=1", "release=" .. EXPECTED_RELEASE }, {}
  for _, row in ipairs(CONTROL_EVIDENCE_ROWS) do
    local evidence = snapshot[row.key]
    checked(type(evidence) == "table", "daemon control snapshot is incomplete")
    if evidence.present then
      checked(type(evidence.raw) == "string" and #evidence.raw <= row.limit,
        "daemon control snapshot exceeds the " .. row.key .. " bound")
      header[#header + 1] = row.key .. "=" .. tostring(#evidence.raw)
      payload[#payload + 1] = evidence.raw
    else
      header[#header + 1] = row.key .. "=-1"
    end
  end
  return table.concat(header, "\n") .. "\n\n" .. table.concat(payload)
end

local function parseControlPrior(body)
  if type(body) ~= "string" or #body > DAEMON_CONTROL_PRIOR_MAX_BYTES then
    return nil, "daemon control rollback artifact exceeds its bound"
  end
  local boundary = body:find("\n\n", 1, true)
  if not boundary then return nil, "daemon control rollback artifact header is incomplete" end
  local values, rows = {}, 0
  for line in (body:sub(1, boundary - 1) .. "\n"):gmatch("(.-)\n") do
    rows = rows + 1
    local key, value = line:match("^([a-z]+)=(.*)$")
    if not key or values[key] ~= nil then
      return nil, "daemon control rollback artifact header is invalid"
    end
    values[key] = value
  end
  if rows ~= 6 or values.format ~= "1" or values.release ~= EXPECTED_RELEASE then
    return nil, "daemon control rollback artifact is foreign or unsupported"
  end
  local snapshot, cursor = {}, boundary + 2
  for _, row in ipairs(CONTROL_EVIDENCE_ROWS) do
    local token = values[row.key]
    if token == "-1" then
      snapshot[row.key] = { path = row.path, present = false }
    else
      if not canonicalUnsigned(token) then
        return nil, "daemon control rollback artifact length is noncanonical"
      end
      local length = tonumber(token)
      if not length or length > row.limit then
        return nil, "daemon control rollback artifact length exceeds the " .. row.key .. " bound"
      end
      local ending = cursor + length - 1
      local raw = length == 0 and "" or body:sub(cursor, ending)
      if #raw ~= length then return nil, "daemon control rollback artifact payload is truncated" end
      snapshot[row.key] = { path = row.path, present = true, raw = raw,
        policy = inspectDaemonPolicySource(raw) }
      cursor = ending + 1
    end
  end
  if cursor ~= #body + 1 then return nil, "daemon control rollback artifact has trailing bytes" end
  return snapshot
end

local function readControlPrior()
  requirePlainPath(DAEMON_CONTROL_PRIOR_PATH, "daemon control rollback artifact")
  if not filesystem.exists(DAEMON_CONTROL_PRIOR_PATH) then return nil end
  if filesystem.isDirectory and filesystem.isDirectory(DAEMON_CONTROL_PRIOR_PATH) then
    return nil, "daemon control rollback artifact is a directory"
  end
  local body, reason = readAll(DAEMON_CONTROL_PRIOR_PATH, DAEMON_CONTROL_PRIOR_MAX_BYTES)
  if not body then return nil, "cannot read daemon control rollback artifact: " .. tostring(reason) end
  local snapshot, parseReason = parseControlPrior(body)
  if not snapshot then return nil, parseReason end
  return snapshot, nil, body
end

local function sameControlSnapshot(first, second)
  for _, row in ipairs(CONTROL_EVIDENCE_ROWS) do
    local a, b = first[row.key], second[row.key]
    if not a or not b or a.present ~= b.present
        or (a.present and a.raw ~= b.raw) then return false end
  end
  return true
end

local function cleanupMatchesArchived(current, archived)
  for _, row in ipairs(CONTROL_EVIDENCE_ROWS) do
    if row.key ~= "primary" then
      local observed, prior = current[row.key], archived[row.key]
      if observed.present and (not prior.present or observed.raw ~= prior.raw) then return false end
    end
  end
  return true
end

local function controlCleanupEvidenceRemains(snapshot)
  return snapshot.new.present or snapshot.previous.present or snapshot.lock.present
end

local function inspectControlRecovery(state)
  if not state or state.phase ~= "staged" then
    return { eligible = false, reason = "control recovery is available only for a STAGED transaction" }
  end
  local inhibited, inhibitReason = stagedDeploymentInhibitOwned()
  if not inhibited then return { eligible = false, reason = inhibitReason } end
  local running = activeProcess()
  if running then
    return { eligible = false, reason = "active Maintainer/Dashboard process blocks control recovery: " .. tostring(running) }
  end
  local snapshot, snapshotReason = captureControlEvidence()
  if not snapshot then return { eligible = false, reason = snapshotReason } end
  local primary = snapshot.primary
  if primary.policy.schemaReason then
    return { eligible = false, reason = primary.policy.schemaReason }
  end
  for _, key in ipairs({ "new", "previous" }) do
    local evidence = snapshot[key]
    if evidence.present and evidence.policy.schemaReason then
      return { eligible = false, reason = key .. " evidence rejected: " .. evidence.policy.schemaReason }
    end
  end
  local archived, archiveReason, archiveBody = readControlPrior()
  if archiveReason then return { eligible = false, reason = archiveReason } end

  if primary.policy.readable then
    local archivedPrimary = archived and archived.primary or nil
    local supportedPrimary = primary.policy.safeLiteral and (primary.policy.off or primary.policy.on)
    if archivedPrimary and archivedPrimary.present then
      local exactReadablePrimary = archivedPrimary.policy.readable
        and archivedPrimary.raw == primary.raw and supportedPrimary
      local recoveredPrimary = not archivedPrimary.policy.readable
        and not archivedPrimary.policy.schemaReason
        and primary.raw == DAEMON_CONTROL_CLEAN_OFF and primary.policy.off
      if exactReadablePrimary or recoveredPrimary then
        if not cleanupMatchesArchived(snapshot, archived) then
          return { eligible = false,
            reason = "daemon control side/lock evidence changed; successor retained" }
        end
        if controlCleanupEvidenceRemains(snapshot) then
          return { eligible = true, mode = "cleanup", primary = primary, snapshot = archived,
            candidate = primary.raw, archiveBody = archiveBody }
        end
      else
        return { eligible = false,
          reason = "daemon control rollback artifact conflicts with readable primary" }
      end
    elseif supportedPrimary and controlCleanupEvidenceRemains(snapshot) then
      -- The stronger recovery acknowledgement may retire stale/corrupt side and
      -- legacy-lock evidence, but the readable desired policy is immutable.
      return { eligible = true, mode = "archive_cleanup", primary = primary,
        snapshot = snapshot, candidate = primary.raw }
    end
    return { eligible = false, reason = "daemon control policy is readable; recovery is forbidden" }
  end

  local candidatePolicy = inspectDaemonPolicySource(DAEMON_CONTROL_CLEAN_OFF)
  if candidatePolicy.schemaReason or not candidatePolicy.readable or not candidatePolicy.off then
    return { eligible = false, reason = "no unique verified daemon-OFF recovery result exists" }
  end
  local recoverySnapshot = snapshot
  if archived then
    local samePrimary = primary.raw == archived.primary.raw
    local interruptedPrefix = #primary.raw < #DAEMON_CONTROL_CLEAN_OFF
      and DAEMON_CONTROL_CLEAN_OFF:sub(1, #primary.raw) == primary.raw
    if (not samePrimary and not interruptedPrefix)
        or not cleanupMatchesArchived(snapshot, archived) then
      return { eligible = false, reason = "daemon control rollback artifact conflicts with current evidence" }
    end
    recoverySnapshot = archived
  end
  return { eligible = true, mode = "replace", primary = primary,
    snapshot = recoverySnapshot, observed = snapshot,
    candidate = DAEMON_CONTROL_CLEAN_OFF, archiveBody = archiveBody }
end

local function writeDirectExact(path, body)
  ensureParent(path)
  local handle, reason = io.open(path, "wb")
  if not handle then return nil, "cannot open " .. path .. ": " .. tostring(reason) end
  local ok, writeReason = pcall(function()
    writeChunk(handle, body)
    finishWrite(handle)
    handle = nil
  end)
  if handle then closeRead(handle) end
  if not ok then return nil, tostring(writeReason) end
  return true
end

local function retainControlPrior(snapshot)
  local body = controlPriorBody(snapshot)
  checked(#body <= DAEMON_CONTROL_PRIOR_MAX_BYTES,
    "daemon control rollback artifact exceeds its aggregate bound")
  local _, reason, priorBody = readControlPrior()
  checked(not reason, reason)
  if priorBody then
    checked(priorBody == body, "daemon control rollback artifact conflicts with current evidence")
    return body
  end
  writeTextAtomic(DAEMON_CONTROL_PRIOR_PATH, body)
  local _, verifyReason, verifiedBody = readControlPrior()
  checked(not verifyReason and verifiedBody == body,
    "daemon control rollback artifact exact-byte verification failed")
  return body
end

local function cleanupControlEvidence(snapshot)
  for _, row in ipairs(CONTROL_EVIDENCE_ROWS) do
    if row.key ~= "primary" and filesystem.exists(row.path) then
      local current = readControlEvidence(row.path, row.label, row.limit)
      local expected = snapshot[row.key]
      checked(not current.reason and expected.present and current.raw == expected.raw,
        row.label .. " changed; successor retained")
      removeFile(row.path)
    end
  end
end

local function recoverDaemonControl(offline, backup, confirmation)
  checked(offline == "OFFLINE" and backup == "NO_BACKUP" and confirmation == "CONFIRM",
    "recover-control requires: " .. DAEMON_CONTROL_RECOVERY_ACTION)
  local state = canonicalizeState(parseState())
  local inspection = inspectControlRecovery(state)
  checked(inspection.eligible, inspection.reason)
  if inspection.mode == "cleanup" then
    cleanupControlEvidence(inspection.snapshot)
    return true, "RECOVERED: interrupted daemon control cleanup completed; primary remained byte-exact; "
      .. "staged cold-boot proof and maintainer heartbeat were untouched"
  end

  if inspection.mode == "archive_cleanup" then
    retainControlPrior(inspection.snapshot)
    local current = inspectControlRecovery(canonicalizeState(parseState()))
    checked(current.eligible and current.mode == "cleanup"
        and current.primary.raw == inspection.primary.raw,
      current.reason or "daemon control evidence changed before cleanup")
    cleanupControlEvidence(current.snapshot)
    return true, "RECOVERED: readable daemon policy preserved byte-for-byte; exact stale side/lock "
      .. "evidence archived and removed; staged cold-boot proof and maintainer heartbeat were untouched"
  end

  retainControlPrior(inspection.snapshot)
  -- Re-read every authority and evidence input after the rollback artifact is
  -- durable. This closes the only pre-primary mutation boundary with an exact
  -- raw compare rather than trusting an earlier classification.
  local current = inspectControlRecovery(canonicalizeState(parseState()))
  checked(current.eligible and current.mode == "replace"
      and sameControlSnapshot(current.snapshot, inspection.snapshot)
      and sameControlSnapshot(current.observed, inspection.observed)
      and current.candidate == inspection.candidate,
    current.reason or "daemon control evidence changed before recovery")

  local wrote, writeReason = writeDirectExact(DAEMON_CONTROL_PATH, inspection.candidate)
  local final = readControlEvidence(DAEMON_CONTROL_PATH, "daemon control primary",
    DAEMON_CONTROL_MAX_BYTES)
  local verified = wrote and not final.reason and final.present
    and final.raw == inspection.candidate and final.policy.safeLiteral and final.policy.off
    and not final.policy.schemaReason
  if not verified then
    local reason = writeReason or final.reason or "daemon control exact recovery verification failed"
    local observedRaw = inspection.observed.primary.raw
    local originalRaw = inspection.snapshot.primary.raw
    local successor = final.present and not final.reason
      and final.raw ~= inspection.candidate and final.raw ~= observedRaw
      and final.raw ~= originalRaw
      and (wrote or inspection.candidate:sub(1, #final.raw) ~= final.raw)
    if successor then
      fail("daemon control changed during recovery; successor retained")
    end
    if not (final.present and not final.reason and final.raw == originalRaw) then
      local restored, restoreReason = writeDirectExact(DAEMON_CONTROL_PATH, originalRaw)
      local restoredEvidence = readControlEvidence(DAEMON_CONTROL_PATH, "daemon control primary",
        DAEMON_CONTROL_MAX_BYTES)
      checked(restored and not restoredEvidence.reason and restoredEvidence.present
          and restoredEvidence.raw == originalRaw,
        tostring(reason) .. "; exact prior-byte restoration failed: " .. tostring(restoreReason))
    end
    fail(reason)
  end

  cleanupControlEvidence(current.snapshot)
  return true, "RECOVERED: daemon control is verified clean OFF; exact original primary/side/lock bytes retained at "
    .. DAEMON_CONTROL_PRIOR_PATH .. "; staged cold-boot proof and maintainer heartbeat were untouched"
end

local function verifyPrior(entry, prior)
  local digest = fileHash(entry.target)
  if prior.present then return digest == prior.sha256 end
  return digest == nil
end

local function promoteNew(entry, prior, newPath, oldPath)
  verifyEntryOwnership(entry, transactionTopology)
  local ok, reason = pcall(renameFile, newPath, entry.target)
  if not ok then
    -- A reported I/O failure that happened before promotion can be contained
    -- immediately. A power loss after promotion is reconciled on the next run.
    if prior.present and not filesystem.exists(entry.target) and fileHash(oldPath) == prior.sha256 then
      verifyEntryOwnership(entry, transactionTopology)
      local restored = pcall(renameFile, oldPath, entry.target)
      if restored then checked(fileHash(entry.target) == prior.sha256, "failed promotion restore mismatch: " .. entry.target) end
    end
    fail(reason)
  end
  checked(fileHash(entry.target) == entry.sha256, "live verification failed: " .. entry.target)
end

local function applyDisposition(entry, prior)
  verifyEntryOwnership(entry, transactionTopology)
  requirePlainManagedPaths(entry)
  local newPath, _, oldPath = artifactPaths(entry.target)
  local liveHash, newHash, oldHash = fileHash(entry.target), fileHash(newPath), fileHash(oldPath)
  if liveHash == entry.sha256 and newHash == nil then
    checked((prior.present and oldHash == prior.sha256) or (not prior.present and oldHash == nil), "rollback evidence missing after apply: " .. entry.target)
    return "applied", newPath, oldPath
  end
  if prior.present and liveHash == nil and newHash == entry.sha256 and oldHash == prior.sha256 then
    return "promote", newPath, oldPath
  end
  checked(verifyPrior(entry, prior), "live target changed after staging: " .. entry.target)
  checked(newHash == entry.sha256, "verified stage is missing or changed: " .. entry.target)
  checked(oldHash == nil, "unexpected rollback artifact: " .. entry.target)
  return "fresh", newPath, oldPath
end

local function applyEntry(entry, prior, url)
  local disposition, newPath, oldPath = applyDisposition(entry, prior)
  if disposition == "applied" then return end
  if disposition == "promote" then
    writeState("applying", entry.index, url)
    promoteNew(entry, prior, newPath, oldPath)
    return
  end
  writeState("applying", entry.index, url)
  if prior.present then
    verifyEntryOwnership(entry, transactionTopology)
    renameFile(entry.target, oldPath)
    checked(fileHash(oldPath) == prior.sha256, "backup verification failed: " .. entry.target)
  end
  writeState("applying", entry.index, url)
  promoteNew(entry, prior, newPath, oldPath)
end

local function appliedRecoveryRequired(state)
  return state and state.phase == "applied" and filesystem.exists(INHIBIT_PATH)
end

local function applyRelease(offline, backup, confirmation)
  checked(offline == "OFFLINE" and backup == "NO_BACKUP" and confirmation == "CONFIRM",
    "apply requires: apply OFFLINE NO_BACKUP CONFIRM")
  local state = canonicalizeState(parseState())
  local recoveringApplied = appliedRecoveryRequired(state)
  checked(state and (state.phase == "staged" or state.phase == "applying" or recoveringApplied),
    "apply requires a STAGED, recoverable APPLYING, or inhibited APPLIED transaction")
  local running = activeProcess()
  checked(not running, "active Maintainer/Dashboard process blocks apply: " .. tostring(running))
  local off, offReason = daemonIsOff(true)
  checked(off, offReason)
  local entries, inventory = parseEntries(transactionTopology), parseInventory(EXPECTED_FILE_COUNT)
  if recoveringApplied then
    for _, entry in ipairs(entries) do
      verifyEntryOwnership(entry, transactionTopology)
      checked(fileHash(entry.target) == entry.sha256,
        "recovered apply hash mismatch: " .. entry.target)
    end
    verifyRuntimeBinding(transactionTopology)
  else
    for _, entry in ipairs(transactionOrder(entries, transactionTopology)) do
      applyDisposition(entry, inventory[entry.index])
    end
  end
  -- Consume the cold-boot proof only after every correctable read-only gate.
  -- A typo, live process, daemon recovery artifact, or corrupt inventory no
  -- longer charges the operator another physical shutdown cycle.
  consumeFreshPowerCycle("apply")
  if recoveringApplied then
    writeState("applied", EXPECTED_FILE_COUNT, state.url)
    removeFile(INHIBIT_PATH); removeFile(INHIBIT_PATH .. ".next")
    return true, "APPLIED: interrupted activation fence cleared after complete hash and runtime-binding verification"
  end
  writeTextAtomic(INHIBIT_PATH, "release=" .. EXPECTED_RELEASE .. "\nphase=applying\n")
  writeState("applying", state.index, state.url)
  for _, entry in ipairs(transactionOrder(entries, transactionTopology)) do
    applyEntry(entry, inventory[entry.index], state.url)
  end
  for _, entry in ipairs(entries) do
    verifyEntryOwnership(entry, transactionTopology)
    checked(fileHash(entry.target) == entry.sha256, "post-apply hash mismatch: " .. entry.target)
  end
  commitRuntimeBinding(transactionTopology)
  verifyRuntimeBinding(transactionTopology)
  writeState("applied", EXPECTED_FILE_COUNT, state.url)
  removeFile(INHIBIT_PATH); removeFile(INHIBIT_PATH .. ".next")
  return true, "APPLIED: all " .. tostring(EXPECTED_FILE_COUNT)
    .. " live hashes verified; topology=" .. transactionTopology.kind
    .. (transactionTopology.kind == "external" and " address=" .. transactionTopology.address or "")
    .. (transactionTopology.kind == "external" and "; root runtime duplicates remain only as rollback data until finalize" or "")
    .. "; prior desired daemon policy was preserved; finalize is online after verification, while rollback still requires a full shutdown"
end

local function rollbackEntry(entry, prior, url)
  verifyEntryOwnership(entry, transactionTopology)
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
      verifyEntryOwnership(entry, transactionTopology)
      renameFile(entry.target, replacedPath)
      liveHash, replacedHash = nil, fileHash(replacedPath)
    end
    checked(liveHash == nil, "cannot clear live target for rollback: " .. entry.target)
    verifyEntryOwnership(entry, transactionTopology)
    renameFile(oldPath, entry.target)
    checked(fileHash(entry.target) == prior.sha256, "rollback verification failed: " .. entry.target)
  else
    checked(oldHash == nil, "unexpected backup for formerly absent target: " .. entry.target)
    if liveHash ~= nil then
      checked(replacedHash == nil, "unexpected replaced artifact: " .. entry.target)
      verifyEntryOwnership(entry, transactionTopology)
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
  local running = activeProcess()
  checked(not running, "active Maintainer/Dashboard process blocks rollback: " .. tostring(running))
  local off, offReason = daemonIsOff()
  checked(off, offReason)
  local entries, inventory = parseEntries(transactionTopology), parseInventory(EXPECTED_FILE_COUNT)
  consumeFreshPowerCycle("rollback")
  writeTextAtomic(INHIBIT_PATH, "release=" .. EXPECTED_RELEASE .. "\nphase=rolling_back\n")
  writeState("rolling_back", state.index, state.url)
  restoreRuntimeBinding(transactionTopology)
  local ordered = transactionOrder(entries, transactionTopology)
  for index = #ordered, 1, -1 do
    local entry = ordered[index]
    rollbackEntry(entry, inventory[entry.index], state.url)
  end
  for index, entry in ipairs(entries) do
    verifyEntryOwnership(entry, transactionTopology)
    checked(verifyPrior(entry, inventory[index]), "post-rollback mismatch: " .. entry.target)
  end
  for _, entry in ipairs(entries) do
    verifyEntryOwnership(entry, transactionTopology)
    requirePlainManagedPaths(entry)
    local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
    removeFile(newPath); removeFile(partPath)
    if fileHash(replacedPath) == entry.sha256 then removeFile(replacedPath) end
    checked(not filesystem.exists(oldPath), "rollback backup remains: " .. entry.target)
  end
  writeState("rolled_back", 0, state.url)
  removeFile(INHIBIT_PATH)
  removeFile(POWER_CYCLE_MARKER); removeFile(POWER_CYCLE_MARKER .. ".next")
  return true, "ROLLED_BACK: exact prior bytes and runtime binding restored; unknown replaced bytes remain quarantined until discard"
end

local function discardRelease(backup, confirmation)
  checked(backup == "NO_BACKUP" and confirmation == "CONFIRM", "discard requires: discard NO_BACKUP CONFIRM")
  local state = canonicalizeState(parseState())
  checked(state and (state.phase == "staging" or state.phase == "staged" or state.phase == "rolled_back"), "discard is allowed only before apply or after rollback")
  checked(not state.recovery,
    "metadata recovery STAGING cannot be discarded before a complete verified restage; rerun stage with the immutable bundle URL")
  local entries = filesystem.exists(FILES_PATH) and parseEntries(transactionTopology) or {}
  for _, entry in ipairs(entries) do
    verifyEntryOwnership(entry, transactionTopology)
    requirePlainManagedPaths(entry)
    local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
    checked(not filesystem.exists(oldPath), "cannot discard while rollback evidence exists")
    removeFile(newPath); removeFile(partPath); removeFile(replacedPath)
  end
  removeFile(INHIBIT_PATH); removeFile(INHIBIT_PATH .. ".next")
  removeFile(POWER_CYCLE_MARKER); removeFile(POWER_CYCLE_MARKER .. ".next")
  removeFile(DAEMON_CONTROL_PRIOR_PATH); removeFile(DAEMON_CONTROL_PRIOR_PATH .. ".next")
  removeFile(FILES_PATH); removeFile(FILES_PATH .. ".next")
  removeFile(INVENTORY_PATH); removeFile(INVENTORY_PATH .. ".next")
  cleanupBindingInventory()
  removeFile(STATE_PATH); removeFile(STATE_PATH .. ".next")
  return true, "IDLE: installer-owned staged evidence discarded"
end

local function finalizedReceiptBody(topology)
  checked(type(topology) == "table" and (topology.kind == "root" or topology.kind == "external"),
    "release topology is unavailable for finalized receipt")
  checked(safeAddress(topology.address), "runtime filesystem address is invalid for finalized receipt")
  return table.concat({
    "format=1", "release=" .. EXPECTED_RELEASE, "bundle=" .. EXPECTED_BUNDLE_SHA256,
    "topology=" .. topology.kind, "runtime_address=" .. topology.address,
    "root_runtime=" .. (topology.kind == "external" and "duplicates_removed" or "active"),
    "files=" .. tostring(EXPECTED_FILE_COUNT), "operator_verification=attested",
    "installed_hashes=verified", "status=finalized",
    "post_install=" .. POST_INSTALL_CONTRACT, "",
  }, "\n")
end

local function hasFinalizedReceipt(topology)
  if not filesystem.exists(RECEIPT_PATH) then return false end
  local text = readAll(RECEIPT_PATH, 4096)
  return type(text) == "string" and text == finalizedReceiptBody(topology)
end

local function cleanupFinalizedMetadata()
  requirePlainReleasePaths()
  removeFile(RECEIPT_PATH .. ".next")
  removeFile(INHIBIT_PATH); removeFile(INHIBIT_PATH .. ".next")
  removeFile(POWER_CYCLE_MARKER); removeFile(POWER_CYCLE_MARKER .. ".next")
  removeFile(DAEMON_CONTROL_PRIOR_PATH); removeFile(DAEMON_CONTROL_PRIOR_PATH .. ".next")
  removeFile(FILES_PATH); removeFile(FILES_PATH .. ".next")
  removeFile(INVENTORY_PATH); removeFile(INVENTORY_PATH .. ".next")
  cleanupBindingInventory()
  removeFile(STATE_PATH); removeFile(STATE_PATH .. ".next")
end

-- Run the deployed RC surface rather than acquiring worker authority here.
-- The stage-time inhibit prevented this service from starting during the one
-- apply boot, so online finalization must establish the sole RC-owned broker
-- before it can truthfully complete the release transaction.
local function startPostInstallBroker()
  requirePlainPath(AE2_RC_PATH, "AE2 RC service")
  local loaded, shell = pcall(require, "shell")
  if not loaded or type(shell) ~= "table" or type(shell.execute) ~= "function" then
    return false, "OpenOS shell execution is unavailable: " .. tostring(shell)
  end
  -- shell.execute uses process.load, so the detached broker remains owned by
  -- the `oc-ae2` service process rather than inheriting installer authority.
  local called, result, reason = pcall(shell.execute, AE2_RC_PATH .. " start", _ENV)
  if not called or result ~= true then
    return false, "AE2 RC start failed: " .. tostring(called and (reason or result) or result)
  end
  local loaded, commissioning = pcall(require, "oc.ae2.maintainer_commissioning")
  if not loaded or type(commissioning) ~= "table" or type(commissioning.status) ~= "function" then
    return false, "commissioning status unavailable after AE2 RC start: " .. tostring(commissioning)
  end
  local statusCalled, status = pcall(commissioning.status)
  if not statusCalled or type(status) ~= "table" or status.workerRunning ~= true then
    local detail = status
    if statusCalled and type(status) == "table" then
      detail = status.reason or status.state or "workerRunning=false"
    end
    return false, "AE2 RC returned without a running commissioning broker: "
      .. tostring(detail)
  end
  return true
end

-- Once the RC-owned broker exists, persist the selected desired profile and
-- wake that broker. Boot replay remains an idempotent fallback after a later
-- restart, but it is no longer required to finish this one-boot update.
local function requestPostInstallConvergence()
  local called, ok, reason, status = pcall(function()
    local bootstrap = require("oc_bootstrap")
    local active, activeReason = bootstrap.activate()
    if active ~= true then return false, tostring(activeReason or "runtime activation failed") end
    local verified, verifyReason = bootstrap.verifyActive()
    if verified ~= true then
      return false, tostring(verifyReason or "active runtime verification failed")
    end
    local commissioning = require("oc.ae2.maintainer_commissioning")
    return commissioning.request({ source = "release_finalize" })
  end)
  if not called or ok ~= true then return false, tostring(called and reason or ok) end
  if type(status) == "table" and status.brokerWake == false then
    return true, "request persisted; broker wake deferred: "
      .. tostring(status.brokerWakeReason or "event unavailable")
  end
  return true
end

local function finishPostInstall()
  local started, startReason = startPostInstallBroker()
  if not started then return false, startReason end
  local requested, reason = requestPostInstallConvergence()
  if not requested then return false, reason end
  return true, "; AE2 RC broker online; desired-profile convergence persisted"
    .. (reason and (" (" .. tostring(reason):sub(1, 100) .. ")") or "")
end

local function removeRootRuntimeDuplicates(entries, topology)
  if topology.kind ~= "external" then return end
  local rootAddress = rootFilesystemAddress()
  for _, entry in ipairs(entries) do
    if entry.external then
      local logical = entry.logicalTarget
      requireOwnedPath(logical, rootAddress, "root runtime duplicate")
      if filesystem.exists(logical) then
        requirePlainPath(logical, "root runtime duplicate")
        checked(not filesystem.isDirectory or not filesystem.isDirectory(logical),
          "root runtime duplicate became a directory: " .. logical)
        removeFile(logical)
      end
      checked(not filesystem.exists(logical), "root runtime duplicate remains after removal: " .. logical)
    end
  end
end

function recovery.retireArtifactSlots(entries, topology)
  local originalSlot, observed = topology.artifactSlot, {}
  local ok, reason = xpcall(function()
    -- Finalization has already verified every live target and crossed the
    -- irreversible FINALIZING boundary. Inspect both fixed release-owned
    -- namespaces completely before deleting either, then use digest CAS at
    -- each removal so a successor is retained instead of guessed away.
    for _, slot in ipairs({ "a", "b" }) do
      topology.artifactSlot = slot
      for _, entry in ipairs(entries or {}) do
        verifyEntryOwnership(entry, topology)
        requirePlainManagedPaths(entry, topology)
        local newPath, partPath, oldPath, replacedPath =
          artifactPaths(entry.target, topology)
        for _, path in ipairs({ newPath, partPath, oldPath, replacedPath }) do
          if filesystem.exists(path) then
            checked(not filesystem.isDirectory or not filesystem.isDirectory(path),
              "release artifact became a directory before retirement: " .. path)
            local digest, hashReason = hashFile(path)
            checked(digest ~= nil,
              "cannot inspect release artifact before retirement: " .. tostring(hashReason))
            observed[#observed + 1] = { path = path, digest = digest,
              entry = entry, slot = slot }
          end
        end
      end
    end
    for _, row in ipairs(observed) do
      topology.artifactSlot = row.slot
      verifyEntryOwnership(row.entry, topology)
      requirePlainPath(row.path, "release artifact retirement")
      checked(fileHash(row.path) == row.digest,
        "release artifact changed before retirement: " .. row.path)
      removeFile(row.path)
    end
    for _, slot in ipairs({ "a", "b" }) do
      topology.artifactSlot = slot
      for _, entry in ipairs(entries or {}) do
        local newPath, partPath, oldPath, replacedPath =
          artifactPaths(entry.target, topology)
        checked(not filesystem.exists(newPath) and not filesystem.exists(partPath) and
            not filesystem.exists(oldPath) and not filesystem.exists(replacedPath),
          "release artifact survived fixed-slot retirement: " .. entry.target)
      end
    end
  end, function(message) return tostring(message) end)
  topology.artifactSlot = originalSlot
  checked(ok, reason)
  return true
end

local function finalizeRelease(backup, verified, confirmation)
  checked(backup == "NO_BACKUP" and verified == "VERIFIED" and confirmation == "CONFIRM",
    "finalize requires: finalize NO_BACKUP VERIFIED CONFIRM")
  local state = canonicalizeState(parseState())
  checked(state and (state.phase == "applied" or state.phase == "finalizing"), "finalize requires APPLIED or recoverable FINALIZING state")
  checked(not filesystem.exists(INHIBIT_PATH) and not filesystem.exists(INHIBIT_PATH .. ".next"),
    "activation is still inhibited; rerun apply after a fresh full shutdown before finalize")
  -- Finalization removes only verified rollback evidence (and inactive root
  -- duplicates for an external runtime). It does not replace live bytes, so a
  -- second cold boot and destroyed desired policy provide no safety benefit.
  if state.phase == "finalizing" and state.index == EXPECTED_FILE_COUNT and hasFinalizedReceipt(transactionTopology) then
    local finished, finishReason = finishPostInstall()
    checked(finished, "post-install convergence is not ready: " .. tostring(finishReason))
    cleanupFinalizedMetadata()
    return true, "FINALIZED: completed interrupted metadata cleanup" .. tostring(finishReason or "")
  end

  local entries, inventory = parseEntries(transactionTopology), parseInventory(EXPECTED_FILE_COUNT)
  verifyRuntimeBinding(transactionTopology)
  if state.phase == "applied" then
    for index, entry in ipairs(entries) do
      verifyEntryOwnership(entry, transactionTopology)
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

  if transactionTopology.kind == "external" then
    -- The selector is now durable, the external hashes and binding were
    -- verified, and FINALIZING is the irreversible operator boundary. Remove
    -- only declared logical duplicates so selector loss cannot silently boot a
    -- stale root runtime instead of rediscovering the uniquely marked RAID.
    for _, entry in ipairs(entries) do
      verifyEntryOwnership(entry, transactionTopology)
      checked(fileHash(entry.target) == entry.sha256, "external runtime hash mismatch before root duplicate removal: " .. entry.target)
    end
    verifyRuntimeBinding(transactionTopology)
    removeRootRuntimeDuplicates(entries, transactionTopology)
  end

  for index, entry in ipairs(entries) do
    verifyEntryOwnership(entry, transactionTopology)
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
    verifyEntryOwnership(entry, transactionTopology)
    requirePlainManagedPaths(entry)
    checked(fileHash(entry.target) == entry.sha256, "final live hash mismatch: " .. entry.target)
    local newPath, partPath, oldPath, replacedPath = artifactPaths(entry.target)
    checked(not filesystem.exists(newPath) and not filesystem.exists(partPath) and
      not filesystem.exists(oldPath) and not filesystem.exists(replacedPath),
      "release artifact remains after finalization: " .. entry.target)
  end

  recovery.retireArtifactSlots(entries, transactionTopology)

  writeTextAtomic(RECEIPT_PATH, finalizedReceiptBody(transactionTopology))
  local finished, finishReason = finishPostInstall()
  checked(finished, "post-install convergence is not ready: " .. tostring(finishReason))
  cleanupFinalizedMetadata()
  return true, "FINALIZED: rollback files removed; verified release receipt retained" ..
    (transactionTopology.kind == "external" and "; declared root /usr/lib/oc duplicates removed" or "") ..
    tostring(finishReason or "")
end

local function externalStorageStatus(proxy)
  local capacity, reason = proxyCapacity(proxy)
  local capacityLine = capacity and
    ("runtime storage: free=" .. tostring(capacity.free) .. " bytes total=" .. tostring(capacity.total) .. " bytes") or
    ("runtime storage: capacity unavailable (" .. tostring(reason) .. ")")
  return capacityLine .. "\nrelease-slot retention: older versioned slots are retained and not auto-pruned; monitor free bytes before upgrades"
end

local function phaseActions(state, appliedRecovery)
  local phase = tostring(state and state.phase or "idle")
  if phase == "staging" then
    if state and state.recovery then
      return "stage <same-immutable-https-url> NO_BACKUP",
        "unavailable until one complete verified restage retires the recovery fence"
    end
    return "stage " .. tostring(state.url or "<same-https-url>") .. " NO_BACKUP",
      "cancel NO_BACKUP CONFIRM"
  elseif phase == "staged" then
    return "next OFFLINE NO_BACKUP CONFIRM", "cancel NO_BACKUP CONFIRM"
  elseif phase == "applying" then
    return "next OFFLINE NO_BACKUP CONFIRM", "cancel OFFLINE NO_BACKUP CONFIRM"
  elseif phase == "applied" then
    if appliedRecovery then
      return "next OFFLINE NO_BACKUP CONFIRM", "cancel OFFLINE NO_BACKUP CONFIRM"
    end
    return "next NO_BACKUP VERIFIED CONFIRM", "cancel OFFLINE NO_BACKUP CONFIRM"
  elseif phase == "rolling_back" then
    return "next OFFLINE NO_BACKUP CONFIRM", "cancel OFFLINE NO_BACKUP CONFIRM"
  elseif phase == "rolled_back" then
    return "next NO_BACKUP CONFIRM", "cancel NO_BACKUP CONFIRM"
  elseif phase == "finalizing" then
    return "next NO_BACKUP VERIFIED CONFIRM",
      "unavailable after irreversible finalization began; resume next"
  end
  return "stage <immutable-https-bundle-url> NO_BACKUP", "none"
end

local function status()
  if filesystem.exists(ROOT) then requirePlainReleasePaths() end
  local legacyLocked = filesystem.exists(LEGACY_LOCK_PATH) and "yes" or "no"
  local state = parseState()
  if not state and legacyLocked == "yes" then
    local malformed = filesystem.isDirectory and not filesystem.isDirectory(LEGACY_LOCK_PATH)
    return true, table.concat({
      "BLOCKED: a legacy installer lock from an older release remains",
      "legacy installer lock: yes",
      malformed and ("recovery: close all OpenComputers control processes, then run " .. recovery.action) or
        "recovery: prove the older installer stopped, then run unlock NO_BACKUP CONFIRM",
    }, "\n")
  end
  if not state then
    local orphaned = filesystem.exists(FILES_PATH) or filesystem.exists(FILES_PATH .. ".next") or
      filesystem.exists(INVENTORY_PATH) or filesystem.exists(INVENTORY_PATH .. ".next") or
      filesystem.exists(INHIBIT_PATH) or filesystem.exists(INHIBIT_PATH .. ".next") or
      filesystem.exists(POWER_CYCLE_MARKER) or filesystem.exists(POWER_CYCLE_MARKER .. ".next")
    if orphaned then
      return true, "BLOCKED: installer transaction metadata exists without readable state\nrecovery action: " ..
        recovery.action .. " [ROOT <full-uuid>|EXTERNAL <full-uuid>]"
    end
    local topology, address, mount, source, runtimeProxy = "root", rootFilesystemAddress(), nil, "stable root sentinels", nil
    if filesystem.exists(SELECTOR_PATH) then
      local selected = topologyFromSelector()
      topology, address, mount = selected.kind, selected.address, selected.mount
      runtimeProxy = selected.proxy
      source = "authoritative root selector"
    else
      local presence, present, total = rootRuntimePresence()
      if presence == "partial" then
        return true, "BLOCKED: local runtime is partial (" .. tostring(present) .. "/" .. tostring(total) ..
          " stable sentinels)\nrecovery action: " .. recovery.action .. " ROOT " .. address
      end
      local rootMarker, rootMarkerReason, rootMarkerExists = validatedRootMarker()
      if rootMarkerExists and not rootMarker then
        return true, "BLOCKED: root runtime marker rejected: " .. tostring(rootMarkerReason) ..
          "\nrecovery action: " .. recovery.action .. " ROOT " .. address
      end
      if presence == "complete" and not rootMarker then
        return true, "BLOCKED: complete local runtime has no host-bound release marker; stage the matched release to repair identity"
      end
      if presence == "absent" and rootMarker then
        return true, "BLOCKED: root runtime marker exists without complete local sentinels\nrecovery action: " ..
          recovery.action .. " ROOT " .. address
      end
      if presence == "absent" then
        local marked, markerReason = uniqueMaintainerMarker()
        if markerReason then return true, "BLOCKED: " .. markerReason end
        if not marked then
          return true, "BLOCKED: runtime topology is unresolved; no root sentinels, authoritative selector, or unique host-bound external marker"
        end
        topology, address, mount = "external", marked.row.address, marked.row.mount
        runtimeProxy = marked.row.proxy
        source = "unique host-bound external marker scan"
      else
        source = "host-bound root active marker"
      end
    end
    local finalized = hasFinalizedReceipt({ kind = topology, address = address })
    local prefix = finalized and "FINALIZED: no active transaction; verified release receipt retained" or
      "IDLE: no active release transaction"
    return true, prefix .. "\ntopology: " .. topology .. "\nruntime address: " .. address ..
      "\ntopology source: " .. source ..
      (mount and "\nruntime mount: " .. mount .. "\nroot runtime: " ..
        (finalized and "declared duplicates removed" or "external selected; duplicate cleanup not attested") ..
        "\n" .. externalStorageStatus(runtimeProxy) or "") ..
      "\nlegacy installer lock: " .. legacyLocked
  end
  local inhibitPresent = filesystem.exists(INHIBIT_PATH)
  local inhibited = inhibitPresent and "yes" or "no"
  local powerCycleRequired = (filesystem.exists(POWER_CYCLE_MARKER) or
    filesystem.exists(POWER_CYCLE_MARKER .. ".next")) and "yes" or "no"
  local rootRuntimeStatus = "active"
  if state.topology == "external" then
    if state.phase == "finalizing" then
      rootRuntimeStatus = "declared duplicate removal in progress"
    elseif state.phase == "applied" then
      rootRuntimeStatus = "inactive rollback duplicates retained until finalize"
    else
      rootRuntimeStatus = "duplicates retained while external transition is reversible"
    end
  end
  local appliedRecovery = state.phase == "applied" and inhibitPresent
  local transitionRecovery = appliedRecovery
    and "APPLIED payload is complete but deployment inhibit cleanup was interrupted; apply recovery is required before finalize"
    or "none"
  local nextAction, cancelAction = phaseActions(state, appliedRecovery)
  local controlRecovery = inspectControlRecovery(state)
  local lines = {
    "release: " .. EXPECTED_RELEASE,
    "state: " .. tostring(state.phase):upper(),
    "cursor: " .. tostring(state.index) .. "/" .. tostring(EXPECTED_FILE_COUNT),
    "topology: " .. state.topology,
    "runtime address: " .. state.runtime_address,
    state.topology == "external" and "runtime mount: " .. transactionTopology.mount or "runtime mount: /",
    "root runtime: " .. rootRuntimeStatus,
    state.topology == "external" and externalStorageStatus(transactionTopology.proxy) or "runtime storage: boot filesystem",
    "legacy installer lock: " .. legacyLocked,
    "deployment recovery marker: " .. inhibited,
    "full shutdown required before live transition: " .. powerCycleRequired,
    "transition recovery: " .. transitionRecovery,
    "daemon control recovery: " .. (controlRecovery.eligible and
      "available for exact offline control repair" or tostring(controlRecovery.reason)),
    "next action: " .. nextAction,
    "cancel action: " .. cancelAction,
  }
  if controlRecovery.eligible then
    lines[#lines + 1] = "control recovery action: " .. DAEMON_CONTROL_RECOVERY_ACTION
  end
  return true, table.concat(lines, "\n")
end

local function plan()
  return true, table.concat({
    "MAINTAINER IMMUTABLE RELEASE PLAN",
    "release: " .. EXPECTED_RELEASE,
    "files: " .. tostring(EXPECTED_FILE_COUNT),
    "topology: an authoritative root selector wins; otherwise a matching external marker wins; otherwise complete root is used when it fits",
    "external provisioning: only after root capacity failure, exactly one writable non-system filesystem larger than 4MiB may qualify",
    "external layout: <mount>/.oc-platform/maintainer/releases/<release>/root; only /usr/lib/oc targets move",
    "activation: external marker is committed first and /etc/oc/maintainer-runtime.cfg last; labels and mount names never grant authority",
    "external finalize: irreversibly removes only declared root /usr/lib/oc duplicates so selector loss rediscovery cannot prefer stale local bytes",
    "external retention: older versioned release slots are retained and not auto-pruned; status reports free/total bytes for capacity planning",
    "stage: downloads, hashes, syntax-checks; live targets remain unchanged; requires a no-backup window",
    "concurrency: mutating commands use live OpenOS process authority and create no filesystem lock",
    "live-transition gate: apply and rollback consume one fresh full shutdown + manual power-on proof; a soft reboot never qualifies",
    "quiescence: stage arms a durable submit inhibit; apply preserves desired daemon policy and requires no Dashboard/Maintainer process",
    "corrupt daemon control: STAGED status advertises recover-control only when exact offline, release-owned recovery is provable",
    "apply: lua oc-release.lua next OFFLINE NO_BACKUP CONFIRM",
    "verify before finalize: onboarding API, oc-config-migrate status, ae2-probe, fresh Dashboard smoke test",
    "finalize: after verification, lua oc-release.lua next NO_BACKUP VERIFIED CONFIRM (online; no second cold boot)",
  }, "\n")
end

local function processRecordForCurrent(process)
  local running = coroutine.running()
  if type(process.findProcess) == "function" then
    local ok, current = pcall(process.findProcess, running)
    if ok and type(current) == "table" then return current end
  end
  local count = 0
  for main, candidate in pairs(process.list) do
    count = count + 1
    checked(count <= MAX_PROCESS_ROWS, "OpenOS process list exceeds the installer authority bound")
    if main == running then return candidate end
    local instances = type(candidate) == "table" and candidate.instances or nil
    if type(instances) == "table" then
      local instanceCount = 0
      for _, instance in pairs(instances) do
        instanceCount = instanceCount + 1
        checked(instanceCount <= MAX_PROCESS_INSTANCES,
          "OpenOS process instance list exceeds the installer authority bound")
        if instance == running then return candidate end
      end
    end
  end
end

local function installerProcessText(candidate)
  if type(candidate) ~= "table" then return tostring(candidate or ""):lower() end
  return table.concat({ tostring(candidate.path or ""), tostring(candidate.command or ""),
    tostring(candidate.name or "") }, " "):lower()
end

local function acquireProcessAuthority(action)
  local ok, process = pcall(require, "process")
  checked(ok and type(process) == "table" and type(process.list) == "table",
    "OpenOS process authority is unavailable; no release files changed")
  local current = processRecordForCurrent(process)
  checked(type(current) == "table",
    "OpenOS current-process authority is unavailable; no release files changed")
  checked(rawget(current, PROCESS_AUTHORITY_KEY) == nil,
    "another installer command is already active in this OpenOS process")
  local token = { action = tostring(action), release = EXPECTED_RELEASE }
  rawset(current, PROCESS_AUTHORITY_KEY, token)
  local scanOk, scanReason = pcall(function()
    local count = 0
    for _, candidate in pairs(process.list) do
      count = count + 1
      checked(count <= MAX_PROCESS_ROWS, "OpenOS process list exceeds the installer authority bound")
      if candidate ~= current then
        local tagged = type(candidate) == "table" and rawget(candidate, PROCESS_AUTHORITY_KEY) ~= nil
        local named = installerProcessText(candidate):find("oc%-release%.lua") ~= nil
        checked(not tagged and not named,
          "another Maintainer release installer process is active; wait for it to exit")
      end
    end
  end)
  if not scanOk then
    if rawget(current, PROCESS_AUTHORITY_KEY) == token then rawset(current, PROCESS_AUTHORITY_KEY, nil) end
    fail(scanReason)
  end
  return current, token
end

local function withInstallerAuthority(action, callback, allowLegacyLock)
  local acquired, current, token = pcall(acquireProcessAuthority, action)
  if not acquired then return nil, tostring(current) end
  local callbackOk, first, second = pcall(function()
    requirePlainPath(ROOT, "release root")
    if filesystem.exists(ROOT) then requirePlainReleasePaths() end
    if not allowLegacyLock then
      checked(not filesystem.exists(LEGACY_LOCK_PATH),
        "a legacy installer lock requires recovery; after proving its installer stopped, run unlock NO_BACKUP CONFIRM")
    end
    return callback()
  end)
  local owns = rawget(current, PROCESS_AUTHORITY_KEY) == token
  if owns then rawset(current, PROCESS_AUTHORITY_KEY, nil) end
  if not owns then return nil, "installer process authority changed during " .. tostring(action) end
  if not callbackOk then return nil, tostring(first) end
  return first, second
end

function api.run(command, ...)
  command = trim(command)
  local arguments = { ... }
  if command == "plan" then return plan() end
  if command == "status" then
    local ok, first, second = pcall(status)
    if not ok then return nil, tostring(first) .. "\ninstaller metadata recovery: " .. recovery.action ..
      " [ROOT <full-uuid>|EXTERNAL <full-uuid>] (newer schema requires its matching pinned installer)" end
    return first, second
  end
  if command == "next" then
    return withInstallerAuthority("next", function()
      local state = canonicalizeState(parseState())
      checked(state ~= nil, "next requires an active release transaction; run status")
      if state.phase == "staged" or state.phase == "applying" then
        return applyRelease(table.unpack(arguments))
      elseif state.phase == "applied" and appliedRecoveryRequired(state) then
        return applyRelease(table.unpack(arguments))
      elseif state.phase == "applied" or state.phase == "finalizing" then
        return finalizeRelease(table.unpack(arguments))
      elseif state.phase == "rolling_back" then
        return rollbackRelease(table.unpack(arguments))
      elseif state.phase == "rolled_back" then
        return discardRelease(table.unpack(arguments))
      end
      return nil, "next cannot infer a safe transition from " .. tostring(state.phase)
        .. "; run status for the exact action"
    end)
  end
  if command == "cancel" then
    return withInstallerAuthority("cancel", function()
      local state = canonicalizeState(parseState())
      checked(state ~= nil, "cancel requires an active release transaction; run status")
      if state.phase == "staging" or state.phase == "staged" or state.phase == "rolled_back" then
        return discardRelease(table.unpack(arguments))
      elseif state.phase == "applying" or state.phase == "applied" or state.phase == "rolling_back" then
        return rollbackRelease(table.unpack(arguments))
      elseif state.phase == "finalizing" then
        return nil, "cancel is unavailable after irreversible finalization began; use next to resume"
      end
      return nil, "cancel has no transition from " .. tostring(state.phase)
    end)
  end
  if command == "stage" then
    if arguments[2] ~= "NO_BACKUP" then return nil, "stage requires: stage <https-url> NO_BACKUP" end
    return withInstallerAuthority("stage", function() return stage(table.unpack(arguments)) end)
  end
  if command == "apply" then
    if arguments[1] ~= "OFFLINE" or arguments[2] ~= "NO_BACKUP" or arguments[3] ~= "CONFIRM" then return nil, "apply requires: apply OFFLINE NO_BACKUP CONFIRM" end
    return withInstallerAuthority("apply", function() return applyRelease(table.unpack(arguments)) end)
  end
  if command == "recover-installer" then
    if (#arguments ~= 3 and #arguments ~= 5) or arguments[1] ~= "OFFLINE" or
        arguments[2] ~= "NO_BACKUP" or arguments[3] ~= "CONFIRM" then
      return nil, "recover-installer requires: " .. recovery.action ..
        " [ROOT <full-uuid>|EXTERNAL <full-uuid>]"
    end
    return withInstallerAuthority("recover installer metadata", function()
      return recovery.run(arguments[1], arguments[2], arguments[3],
        arguments[4], arguments[5])
    end, true)
  end
  if command == "recover-control" then
    if #arguments ~= 3 or arguments[1] ~= "OFFLINE" or arguments[2] ~= "NO_BACKUP"
        or arguments[3] ~= "CONFIRM" then
      return nil, "recover-control requires: " .. DAEMON_CONTROL_RECOVERY_ACTION
    end
    return withInstallerAuthority("recover daemon control", function()
      return recoverDaemonControl(table.unpack(arguments))
    end)
  end
  if command == "rollback" then
    if arguments[1] ~= "OFFLINE" or arguments[2] ~= "NO_BACKUP" or arguments[3] ~= "CONFIRM" then return nil, "rollback requires: rollback OFFLINE NO_BACKUP CONFIRM" end
    return withInstallerAuthority("rollback", function() return rollbackRelease(table.unpack(arguments)) end)
  end
  if command == "discard" then
    if arguments[1] ~= "NO_BACKUP" or arguments[2] ~= "CONFIRM" then return nil, "discard requires: discard NO_BACKUP CONFIRM" end
    return withInstallerAuthority("discard", function() return discardRelease(table.unpack(arguments)) end)
  end
  if command == "finalize" then
    if arguments[1] ~= "NO_BACKUP" or arguments[2] ~= "VERIFIED" or arguments[3] ~= "CONFIRM" then return nil, "finalize requires: finalize NO_BACKUP VERIFIED CONFIRM" end
    return withInstallerAuthority("finalize", function() return finalizeRelease(table.unpack(arguments)) end)
  end
  if command == "unlock" then
    if arguments[1] ~= "NO_BACKUP" or arguments[2] ~= "CONFIRM" then return nil, "unlock requires: unlock NO_BACKUP CONFIRM" end
    return withInstallerAuthority("legacy unlock", function()
      if not filesystem.exists(LEGACY_LOCK_PATH) then return nil, "no legacy installer lock exists" end
      checked(not filesystem.isDirectory or filesystem.isDirectory(LEGACY_LOCK_PATH),
        "legacy installer lock path is not a directory")
      if filesystem.exists(LEGACY_LOCK_OWNER_PATH) then removeFile(LEGACY_LOCK_OWNER_PATH) end
      if filesystem.exists(LEGACY_LOCK_OWNER_PATH .. ".next") then removeFile(LEGACY_LOCK_OWNER_PATH .. ".next") end
      local removed, reason = filesystem.remove(LEGACY_LOCK_PATH)
      checked(removed, "cannot remove legacy installer lock directory: " .. tostring(reason))
      return true, "legacy installer lock removed; run status before continuing"
    end, true)
  end
  return nil, "usage: plan | status | next ... | cancel ... | stage <https-url> NO_BACKUP | apply OFFLINE NO_BACKUP CONFIRM | recover-installer OFFLINE NO_BACKUP CONFIRM [ROOT <full-uuid>|EXTERNAL <full-uuid>] | recover-control OFFLINE NO_BACKUP CONFIRM | rollback OFFLINE NO_BACKUP CONFIRM | discard NO_BACKUP CONFIRM | finalize NO_BACKUP VERIFIED CONFIRM | unlock NO_BACKUP CONFIRM"
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
