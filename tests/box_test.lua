-- Standalone: luajit mods/Gen1Remember/tests/box_test.lua
--
-- The box half, which only exists when Gen1BillsBox is installed: this mod
-- registers a row provider on the popup Gen1BillsBox publishes, and does it at
-- game.ready rather than at load so no load order has to be true for it to
-- work.  Both mods are loaded together here, which is the only way to assert
-- that -- the seam is somebody else's export and a stub of it would only prove
-- this mod can call a stub.
--
-- Skipped, not failed, when Gen1BillsBox is not beside this checkout: the box
-- row is an optional dependency and a suite that cannot find it has learned
-- nothing about whether this mod is broken.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")

local DIR = os.getenv("GEN1REMEMBER_DIR") or "mods/Gen1Remember"
local BOX_DIR = os.getenv("GEN1BILLSBOX_DIR") or "mods/Gen1BillsBox"

local function present(path)
  local handle = io.open(path .. "/manifest.json", "r")
  if handle then handle:close() return true end
  return false
end

if not present(BOX_DIR) then
  print("Gen1BillsBox is not at " .. BOX_DIR .. "; the box row is untested")
  T.finish("Gen1Remember box (skipped)")
  return
end

local Data = T.fixtures.fresh()
local run = T.sdk.loadMods({ BOX_DIR, DIR }, { data = Data })
T.eq(#run.errors, 0, "both mods load clean (" .. tostring(run.errors[1]) .. ")")

local box = run.loader.exports["Gen1BillsBox"]
local remember = run.loader.exports["Gen1Remember"]
T.check(box ~= nil, "Gen1BillsBox loaded")
T.check(remember ~= nil, "Gen1Remember loaded")
T.check(type(box.actions) == "table",
        "Gen1BillsBox publishes the popup extension point")

local function monB(moves)
  local slots = {}
  for _, id in ipairs(moves or { "FIX_SCRATCH" }) do
    slots[#slots + 1] = { id = id, pp = Data.moves[id].pp }
  end
  return { species = "FIXMON_B", level = 20, moves = slots }
end

local stubGame = { data = Data, stack = { push = function() end } }

-- Before game.ready nothing is registered: the registration is deliberately
-- not done at load, because load order is not something this mod should have
-- to be right about.
T.eq(#box.actions.rows(stubGame, monB(), "box"), 0,
     "no row is registered at load time")

Runtime.emit("game.ready", { game = stubGame })

local rows = box.actions.rows(stubGame, monB(), "box")
T.eq(#rows, 1, "after game.ready the box popup grows a row")
T.eq(rows[1].label, "REMEMBER", "and it is REMEMBER")
T.eq(type(rows[1].onSelect), "function", "with something behind it")

-- the party side of the box gets it too: the box screen draws the party down
-- its left and the party menu cannot be reached from in there
T.eq(#box.actions.rows(stubGame, monB(), "party"), 1,
     "the party side of the box screen gets the row as well")

-- a POKéMON with nothing to remember carries no row, the same rule the party
-- menu's row follows
T.eq(#box.actions.rows(stubGame,
       monB({ "FIX_SCRATCH", "FIX_TACKLE", "FIX_EMBERISH" }), "box"), 0,
     "a POKéMON with nothing to remember carries no row here either")

-- game.ready fires again on a hot reload, and the registration is owner-keyed
-- so the second one replaces the first rather than stacking a stale provider
Runtime.emit("game.ready", { game = stubGame })
Runtime.emit("game.ready", { game = stubGame })
T.eq(#box.actions.rows(stubGame, monB(), "box"), 1,
     "a hot reload replaces the provider rather than stacking another")

-- pressing it opens the REMEMBER popup, same screen the party menu opens
do
  local Menu = require("src.ui.Menu")
  local pushed = {}
  local game = {
    data = Data,
    stack = {
      push = function(self, state) pushed[#pushed + 1] = state end,
      pop = function() return table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
  local row = box.actions.rows(game, monB(), "box")[1]
  row.onSelect()
  T.eq(#pushed, 1, "the row opens something")
  T.check(getmetatable(pushed[1]) == Menu, "and it is the REMEMBER menu")
end

run.release()
T.finish("Gen1Remember box")
