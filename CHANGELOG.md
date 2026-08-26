# Changelog

## 1.0.1

- **The REMEMBER popup has no heading.** The row you pressed to open it already
  said REMEMBER and the box comes up over that row, so a title on the frame
  repeated the word back at you — and the vanilla screen this popup stands in
  for, the forget list in `MoveLearnMenu`, has no heading either: it is a
  framed column of move names and nothing else.
- It costs no rows either way, because `Menu` writes a title into the top
  border it was going to draw anyway. The frame is the same size it was; there
  is just no word on it. The suite asserts both — no title, and `th` still
  exactly its rows plus its border.

## 1.0.0

- **A POKéMON can be taught a move it has forgotten.** Gen 1 has no move
  reminder: a move that scrolled off the top of the four slots on the way up is
  gone for the rest of the save, and the only thing the cartridge ever offers
  back is a TM you have to own.
- **A REMEMBER row in the party menu's per-POKéMON popup**, through the
  engine's own `ui.party.submenu` hook — which is built for this, so the row
  needs no engine change. Appended under STATS and SWITCH rather than inserted
  among them: the order at the *front* of that list is load bearing, because
  `DisplayFieldMoveMonMenu` indexes `wFieldMoves` with menu items `0..n-1`.
- **The same row in the box**, with Gen1BillsBox 1.2.0 or newer installed,
  through the extension point that release added to its popup. Registered at
  `game.ready` rather than at load, so no load order has to be true for it to
  work — priority ties break by id, optional dependencies order nothing, and a
  player can install the two in either order.
- **The popup** lists every level-up move the POKéMON should already have had
  at the level it has reached and does not know now, each row naming the move
  and the level it comes in at, ordered by that level.
- **The forms it evolved out of count.** The evolution chain is walked
  backwards, so a CHARIZARD can be given back the EMBER it learned as a
  CHARMANDER. `PRE-EVO MOVES` off reads the current form's learnset alone,
  which is the later-generation move reminder's own rule.
- **The four-move case is the engine's own `MoveLearnMenu`** — the "delete an
  older move?" prompt, the forget list, the HM refusal, the "1, 2 and... Poof!"
  pages. Every one of those is text a player already knows, and a mod that
  redrew them would get one of them subtly wrong. Reached through
  `Screens.push`, so a mod that has replaced that screen is the one that
  answers here too.
- **A free slot is filled directly instead**, with `LearnedMove1Text` and the
  jingle riding the box: the same three lines the bag's TM path uses, so one
  event sounds the same however it was started.
- **Nothing is written to the save and nothing is read from it.** The list is
  derived from the learnset, so a POKéMON caught before this mod was installed
  answers exactly the same as one caught after, and a save loses nothing by
  adding the mod or by removing it again.
- **TM and HM moves are not in the pool.** A machine move is not forgotten, it
  is bought — the player still has the TM, or knowingly spent it — and handing
  those back free would quietly rewrite what a TM costs.
- **Not offered in battle.** The submenu there is SWITCH / STATS / CANCEL and
  the hook carries `ctx.battle` to say so.
- `PARTY REMEMBER`, `BOX REMEMBER`, `PRE-EVO MOVES` and `HIDE WHEN EMPTY`, in
  the mod manager.
- `pool()`, `chain()`, `any()`, `open()`, `teach()` and `available()` on
  `mod.exports`, so another mod can ask what a POKéMON has forgotten without
  opening a screen.
