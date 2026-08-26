-- Standalone: luajit mods/Gen1Remember/tests/gen1remember_test.lua
--
-- Loads the mod through the headless SDK harness against the ROM-free
-- fixture dataset and asserts its stated effect: the pool is what the README
-- says it is (level-up moves at or below the level, pre-evolutions included,
-- machines and known moves excluded), the party popup grows a REMEMBER row
-- everywhere it should and nowhere it should not, and both teach paths land
-- the move in the same shape every engine learn site writes.
--
-- The fixture dataset is exactly the right shape for the pre-evolution rule:
-- FIXMON_A evolves into FIXMON_B at 16, and FIXMON_A's learnset carries a
-- move (FIX_EMBERISH at 7) that FIXMON_B's does not.  So a FIXMON_B is a
-- POKéMON with a forgotten move that only the chain walk can find.
--
-- Run it from a Gen1Recomp checkout with this mod at mods/Gen1Remember, or
-- set GEN1REMEMBER_DIR to wherever it lives.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")

local DIR = os.getenv("GEN1REMEMBER_DIR") or "mods/Gen1Remember"
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod(DIR, { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.state, "loaded", "and it really ran")

local exports = run.loader.exports["Gen1Remember"]
T.check(exports ~= nil, "the mod publishes its builders")
T.eq(type(exports.pool), "function", "pool is published")
T.eq(type(exports.chain), "function", "chain is published")
T.eq(type(exports.teach), "function", "teach is published")

-- ------- a stub game
--
-- The popup reads data, stack and input, and nothing else.

local function newStack()
  local stack = { states = {} }
  function stack:push(state, ...)
    table.insert(self.states, state)
    if type(state) == "table" and type(state.enter) == "function" then
      state:enter(...)
    end
  end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function fakeGame()
  local pressed = {}
  local game = {
    data = Data,
    save = { party = {}, flags = {}, player = { name = "RED", id = 1 } },
    stack = newStack(),
    input = {
      wasPressed = function(_, key) return pressed[key] end,
      isDown = function(_, key) return pressed[key] end,
    },
  }
  game.press = function(key) pressed = {}; pressed[key] = true end
  game.release = function() pressed = {} end
  return game
end

local function monB(level, moves)
  local slots = {}
  for _, id in ipairs(moves or { "FIX_SCRATCH" }) do
    slots[#slots + 1] = { id = id, pp = Data.moves[id].pp }
  end
  return { species = "FIXMON_B", level = level or 20, moves = slots,
           nickname = nil, hp = 20, stats = { hp = 20 } }
end

-- ------- the pool

local pool = exports.pool(Data, monB(20))
T.eq(#pool, 2, "a FIXMON_B that knows only its own move has two to remember")
T.eq(pool[1].move, "FIX_TACKLE", "the lower-level move is offered first")
T.eq(pool[1].level, 1, "and it is levelled at the level it is learned")
T.eq(pool[2].move, "FIX_EMBERISH", "then the one from further up")
T.eq(pool[2].level, 7, "at its own level")
T.check(pool[1].inherited, "a move from the pre-evolution is marked inherited")
T.eq(pool[1].species, "FIXMON_A", "and names the form that grants it")

-- the level gate: FIX_EMBERISH comes in at 7, so a level 5 mon cannot have
-- forgotten it yet
local young = exports.pool(Data, monB(5))
T.eq(#young, 1, "a move above the mon's level is not forgotten yet")
T.eq(young[1].move, "FIX_TACKLE", "only the one it should already have had")

-- known moves are out
local knows = exports.pool(Data, monB(20, { "FIX_SCRATCH", "FIX_TACKLE" }))
T.eq(#knows, 1, "a move already in a slot is not offered back")
T.eq(knows[1].move, "FIX_EMBERISH", "the one still missing is")

-- machines are out: FIXMON_A and FIXMON_C both carry FIX_CUT in tmhm
for _, row in ipairs(exports.pool(Data, monB(50))) do
  T.neq(row.move, "FIX_CUT", "a TM move is bought, not forgotten")
end

-- current-species-only is the other rule, and it really is different
local ownOnly = exports.pool(Data, monB(20), { preEvolutions = false })
T.eq(#ownOnly, 0, "PRE-EVO MOVES off reads the current form's learnset alone")

-- a POKéMON with nothing to remember
T.eq(exports.any(Data, monB(20, { "FIX_SCRATCH", "FIX_TACKLE", "FIX_EMBERISH" })),
     false, "a POKéMON that knows them all has nothing to remember")

-- ------- the chain

T.same(exports.chain(Data, "FIXMON_B"), { "FIXMON_B", "FIXMON_A" },
       "the chain is the mon's form and what it evolved from, nearest first")
T.same(exports.chain(Data, "FIXMON_A"), { "FIXMON_A" },
       "an unevolved form is a chain of one")
T.same(exports.chain(Data, "NOT_A_SPECIES"), {},
       "a species the dataset does not carry is an empty chain")

-- A cyclic evolution table is a content mod's mistake, and it must not be
-- one that hangs the party menu.  Hand-built rather than registered, because
-- the point is the walk's own termination and not the loader's validation.
do
  local cyclic = { pokemon = {
    LOOP_A = { evolutions = { { species = "LOOP_B" } }, learnset = {},
               level1Moves = {} },
    LOOP_B = { evolutions = { { species = "LOOP_A" } }, learnset = {},
               level1Moves = {} },
  }, moves = {} }
  local walked = exports.chain(cyclic, "LOOP_A")
  T.eq(#walked, 2, "a cycle in the evolution table terminates")
  T.eq(#exports.pool(cyclic, { species = "LOOP_A", level = 50, moves = {} }), 0,
       "and building a pool over one does not hang either")
end

-- a mon whose learnset names a move the dataset does not carry
do
  local broken = { pokemon = {
    GHOST_MOVE = { evolutions = {}, level1Moves = { "NO_SUCH_MOVE" },
                   learnset = { { level = 1, move = "NO_SUCH_MOVE" } } },
  }, moves = {} }
  T.eq(#exports.pool(broken, { species = "GHOST_MOVE", level = 9, moves = {} }),
       0, "a learnset naming an unknown move offers nothing rather than a blank")
end

-- ------- the party popup row

-- the vanilla identity the engine passes as `vanilla`: an unhooked build
-- hands its own list back (src/ui/PartyMenu.lua)
local function sameItems(_, items) return items end

local function submenu(game, mon, ctx)
  return Runtime.call("ui.party.submenu", sameItems, game, {
    { label = "STATS", action = "stats" },
    { label = "SWITCH", action = "switch" },
  }, mon, ctx or {})
end

local function labels(items)
  local out = {}
  for i, item in ipairs(items) do out[i] = item.label end
  return out
end

local game = fakeGame()
local rows = submenu(game, monB(20))
T.eq(#rows, 3, "the party popup grows a row")
T.same(labels(rows), { "STATS", "SWITCH", "REMEMBER" },
       "appended after the vanilla rows, where a new row is free")

-- in battle the submenu is SWITCH / STATS / CANCEL and this stays out of it
local battle = submenu(game, monB(20), { battle = true })
T.eq(#battle, 2, "no REMEMBER row in the battle submenu")

-- HIDE WHEN EMPTY (default on): a POKéMON with nothing to remember has no row
local nothing = submenu(game, monB(20, { "FIX_SCRATCH", "FIX_TACKLE",
                                          "FIX_EMBERISH" }))
T.eq(#nothing, 2, "a POKéMON with nothing to remember carries no row")

-- ------- the popup itself

local Menu = require("src.ui.Menu")

do
  local g = fakeGame()
  local mon = monB(20)
  exports.open(g, mon)
  local menu = g.stack:top()
  T.check(getmetatable(menu) == Menu, "REMEMBER opens a bordered menu")
  T.eq(#menu.items, 2, "with one row per move it can remember")
  T.check(menu.items[1].label:find("FIX TACKLE", 1, true) ~= nil,
          "the row names the move")
  T.check(menu.items[1].label:find("L1", 1, true) ~= nil,
          "and the level it comes in at")
  T.check(menu.tx + menu.tw <= 20, "and the frame stays on screen")
  -- it draws without throwing, which is the whole of what a draw test can say
  -- about a screen with no framebuffer to read back
  T.check(pcall(function() menu:draw() end), "and it draws")
end

do
  -- nothing to remember, with the row forced on: it says so rather than
  -- silently doing nothing
  local g = fakeGame()
  exports.open(g, monB(20, { "FIX_SCRATCH", "FIX_TACKLE", "FIX_EMBERISH" }))
  local top = g.stack:top()
  T.check(top ~= nil, "an empty pool still pushes something")
  T.check(getmetatable(top) ~= Menu, "and it is a message, not a menu")
end

-- ------- the teach

do
  -- a free slot: inserted directly, in the { id, pp } shape every engine
  -- learn site writes
  local g = fakeGame()
  local mon = monB(20)
  local told
  exports.teach(g, mon, "FIX_TACKLE", function(learned) told = learned end)
  T.eq(#mon.moves, 2, "a move goes into a free slot")
  T.eq(mon.moves[2].id, "FIX_TACKLE", "the slot names the move")
  T.eq(mon.moves[2].pp, Data.moves.FIX_TACKLE.pp, "with the move's own PP")
  T.eq(mon.moves[2].ppUps, nil, "and no PP Ups, like every other learn site")
  T.check(g.stack:top() ~= nil, "and it says so")
end

do
  -- four moves: handed to the engine's own MoveLearnMenu rather than redrawn
  local MoveLearnMenu = require("src.ui.MoveLearnMenu")
  local g = fakeGame()
  local mon = monB(20, { "FIX_SCRATCH", "FIX_TACKLE", "FIX_EMBERISH",
                         "FIX_CUT" })
  -- FIXMON_C shares FIX_TACKLE, so give this one a move it does not know by
  -- taking one back out first
  mon.moves[2] = { id = "FIX_CUT", pp = 30 }
  mon.moves[4] = { id = "FIX_SCRATCH", pp = 35 }
  exports.teach(g, mon, "FIX_TACKLE")
  T.eq(#mon.moves, 4, "a full moveset is not grown past four")
  -- MoveLearnMenu:enter pushes the "trying to learn / delete an older move?"
  -- prompt straight away, so it is the TextBox that is on top and the menu
  -- itself is under it -- which is the flow working, not a miss
  local found = false
  for _, state in ipairs(g.stack.states) do
    if getmetatable(state) == MoveLearnMenu then found = true end
  end
  T.check(found, "the four-move case is the engine's own forget flow")
  T.check(#g.stack.states >= 2,
          "and it opens with its own prompt over the forget list")
end

do
  -- teaching a move the mon already knows is refused rather than duplicated:
  -- the battle engine indexes moves by slot and two slots naming one move is
  -- a state no vanilla path can produce
  local g = fakeGame()
  local mon = monB(20)
  local told = nil
  exports.teach(g, mon, "FIX_SCRATCH", function(learned) told = learned end)
  T.eq(#mon.moves, 1, "a move already known is not added a second time")
  T.eq(told, false, "and the caller is told it did not happen")
end

do
  -- a move the dataset does not carry
  local g = fakeGame()
  local mon = monB(20)
  local told = nil
  exports.teach(g, mon, "NO_SUCH_MOVE", function(learned) told = learned end)
  T.eq(#mon.moves, 1, "an unknown move teaches nothing")
  T.eq(told, false, "and says so")
end

-- ------- the row actually opens the popup

do
  local g = fakeGame()
  local mon = monB(20)
  local items = submenu(g, mon)
  local remember = items[#items]
  T.eq(remember.label, "REMEMBER", "the appended row is the one")
  -- PartyMenu dispatches a hook-injected row as onSelect(mon, game)
  remember.onSelect(mon, g)
  T.check(getmetatable(g.stack:top()) == Menu, "and pressing it opens REMEMBER")
end

run.release()
T.finish("Gen1Remember")
