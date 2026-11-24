# Following Pokémon

The first Pokémon in the party that isn't an egg and hasn't fainted walks
behind the player. If the lead Pokémon faints, is moved, or is swapped out, the
next Pokémon that can follow takes its place.

The scripts are in `src/data/012_Overworld/009_Following Pokemon/`. The
settings are in `001_FollowingPokemon_Config.rb`.

## How it follows

The following Pokémon is a follower (`Game_FollowingPokemon`, a subclass of
`Game_Follower`). It walks behind the player the same way as every other
follower, such as a partner trainer:

- **It walks the leader's step history.** Every character remembers its last
  few steps (`Game_Character#step_history`), including the tile each step
  started from and what kind of step it was: `:step`, `:diagonal`, `:jump` or
  `:slide`. A follower takes the step its leader just left, so it copies:
  - ledge jumps
  - diagonal steps on sideways stairs
  - ice slides
  - steps across connected map edges

  If a follower falls behind (for example after its own move route), it
  catches up along the trail instead of teleporting.
- **It matches the leader's speed.** It walks, runs, cycles and slides at the
  same speed as the leader.
- **It never blocks anyone.** Followers aren't map events, so the player and
  NPCs never bump into them.
  - If the player walks into the follower, the two swap places.
  - If an NPC, a pushed Strength boulder or a move route puts someone on the
    follower's tile, the follower steps aside to a free tile.
- **It keeps up through warps.** After a transfer, followers line up behind
  the player on free tiles. Through doors, they walk into the door and come
  out of it behind the player.
- **It follows forced moves.** Steps the player takes in a move route are
  recorded too, so followers trail them.

Only one Pokémon follows at a time. It goes back into its Poké Ball while
another follower, such as a partner trainer, is with the player.

## When it follows

`FollowingPokemon.hide_reasons` lists everything that keeps the Pokémon in its
Poké Ball. It comes out when the list is empty and the player is standing
still.

| Reason | When |
|---|---|
| `:no_pokemon` | Every party Pokémon is an egg or has fainted |
| `:option_off` | The player turned "Following Pokémon" off in the Options screen |
| `:toggled_off` | An event called `FollowingPokemon.toggle(false)` |
| any symbol | An event called `FollowingPokemon.hide(symbol)` |
| `:map_flag` | The map's metadata has the flag `NoFollowingPokemon` |
| `:human_follower` | Another follower (e.g. a partner trainer) is with the player |
| `:surfing`, `:diving` | The player is surfing or diving |
| `:flying` | The player is flying (Fly) |
| `:cycling` | The player is on a bicycle (if `HIDE_WHEN_CYCLING`) |
| `:too_big_indoors` | The Pokémon is taller than `MAX_INDOOR_HEIGHT` metres and the map is indoors with no wild encounters. The map flag `ShowFollowingPokemon` allows it |
| `:pokemon_center` | The nurse is healing the party (Recover All on a Pokémon Center map) |
| `:player_hidden` | The player is invisible outside of an event. Door events hide the player for a moment, so this doesn't count while an event is running, and the Pokémon walks through the door with the player |

**Poké Ball animations.** Whenever the Pokémon goes into or comes out of its
Poké Ball, its Poké Ball animation plays. This includes turning it on or off,
changing the lead Pokémon, surfing, flying, bicycles, Pokémon Centers and map
flags. Two cases don't play it:
- A map transfer never plays it. A Pokémon that was out simply appears on the
  new map.
- Hiding because the player is invisible doesn't play it.

**Party changes.** Every frame, the Pokémon that should follow is compared
with the one shown:
- A different Pokémon goes back into its ball and the new one comes out.
- The same Pokémon with a new form, shininess or status changes its sprite at
  once.

**Saving.** The follower's position, and whether it's out, are saved in
`$PokemonGlobal.pokemon_follower` and restored on loading.

## Map metadata flags

Add these to the `flags` field of a map's metadata in Tiled (comma-separated):

- `NoFollowingPokemon`: the Pokémon stays in its Poké Ball on this map.
- `ShowFollowingPokemon`: big Pokémon may follow on this indoor map.

## Script commands

| Command | Effect |
|---|---|
| `FollowingPokemon.toggle(false)` / `toggle(true)` | Turn the following Pokémon off/on. The player's Options setting must also be on |
| `FollowingPokemon.hide(:reason)` / `show(:reason)` | Keep it in its ball for a while, e.g. during a cutscene. Several reasons can be active at once |
| `FollowingPokemon.recall_and_wait(:reason)` | Put it away and wait for the Poké Ball animation. `release(:reason)` lets it come back out |
| `FollowingPokemon.refresh` | Re-check the hide reasons immediately |
| `FollowingPokemon.emote(:heart, true)` | Show an emote bubble over it; `true` waits for the bubble to pop up |
| `FollowingPokemon.move_route([PBMoveRoute::JUMP, 0, 0], true)` | Give it a move route; `true` waits for the route to finish |
| `FollowingPokemon.talk` | Talk to it, as if the player pressed the Action button facing it |
| `FollowingPokemon.active?` | Whether it's out and visible |
| `FollowingPokemon.pokemon` | The Pokémon that follows (or would follow) |

The emotes are `:music`, `:happy`, `:smile`, `:question`, `:heart`,
`:poison`, `:angry`, `:ellipsis`, `:sad` and `:mad`, plus `:exclaim` for the
usual exclamation bubble.

### Event commands and Tiled

In event commands, the following Pokémon is character `-2`. In Tiled event
scripts it's `pokemon_follower`:

```ruby
*move_route(
  pokemon_follower,
  turn_left,
  jump(0, 0),
),
show_animation(pokemon_follower, anim(3)),
```

`script("follower_move_route(:pokemon)")` and
`script("follower_animation(:pokemon)")` also redirect the next Set Move
Route / Show Animation command to it. They work like `follower_move_route` and
`follower_animation` do for other followers.

## Talking to it

Pressing the Action button while facing the Pokémon:
1. plays its cry
2. hands over any item it has found
3. otherwise, says something

The dialogue comes from handlers in `006_FollowingPokemon_Dialogue.rb`. They
are tried in order, and the first one that says something wins. Most of them
only speak some of the time, so the Pokémon says different things each time.

| Priority | Handler | Says something about |
|---|---|---|
| 10 | `:status` | Its status problem |
| 20 | `:low_hp` | Being tired (HP below 1/4) |
| 30 | `:pokemon_center` | Being in a Pokémon Center |
| 31 | `:map_flags` | Labs (`PokemonLab` flag), dark maps and the Safari Zone |
| 32 | `:location` | The map, or the region from the map's town map position |
| 40 | `:weather` | Rain, snow, sun, sandstorms and fog, depending on its type |
| 45 | `:time_of_day` | Morning, evening and night |
| 50 | `:species` | Particular species |
| 60 | `:type` | Its type |
| 90 | `:friendship` | How much it likes the player (always says something) |

Add or replace handlers with `FollowingPokemon::Dialogue.add`:

```ruby
FollowingPokemon::Dialogue.add(:my_town, 33) do |pkmn|
  next false if $game_map.map_id != 5
  FollowingPokemon.emote(:music, true)
  pbMessage(_INTL("{1} loves this town!", pkmn.name))
  next true
end
```

**Translations.** Write all text with `_INTL("...")` and a literal string, as
above. `make update-locales` then adds it to every language's `scripts.csv`
(see [LOCALIZATION.md](LOCALIZATION.md)).

## Walking together

While the Pokémon is out:
- **Friendship.** It gains friendship every `FRIENDSHIP_STEPS` steps.
- **Items.** Every `ITEM_STEPS` steps it has an `ITEM_CHANCE`% chance to find
  an item from `ITEMS`. It shows an exclamation bubble, and gives the item
  when talked to.
- **Emotes.** Every `AMBIENT_EMOTE_STEPS` steps it may show an emote on its
  own, depending on how it feels.

## Graphics

**Overworld sprites** are in `Graphics/Characters/Followers/` and
`Graphics/Characters/Followers shiny/`. They are 4×4 sheets named like other
Pokémon sprites: `SPECIES`, `SPECIES_form`, `SPECIES_female`. Missing sprites
fall back to `000`.

A Pokémon with a [pattern](POKEMON_PATTERNS.md) uses
`Graphics/Characters/Patterns/<PATTERN>/Followers[ shiny]/` instead, if its
sprite is there.

**Sizes.** A sprite's size category comes from the width of one frame:

| Frame width | Category | Drawn back from the player by |
|---|---|---|
| up to `SMALL_FRAME_WIDTH` | `:small` | 0 px |
| up to `MEDIUM_FRAME_WIDTH` | `:medium` | 4 px |
| wider | `:large` | 8 px |

Big Pokémon are drawn further back so they don't cover the player, but they
still stand on their own tile. Set a species' category in `SIZE_OVERRIDES` to
override it. The offsets are in `SIZE_OFFSETS`.

**Airborne Pokémon** are Flying types, Pokémon with Levitate, Pokémon
whose battle sprite floats, and species with one of the flags in
`AIRBORNE_FLAGS` (`Airborne`, `Floating` or `Levitating`). They:
- loop their animation while idle
- bob gently
- aren't hidden by tall grass (bush or deep bush tiles)
- don't rustle the grass they move over
- don't kick up dust when they land
- keep animating while sliding on ice

**Other visual effects.** The Pokémon has a reflection on water. It is tinted
by:
- the time of day
- the screen tone
- its status problem (`STATUS_TONES`)

**Sprite preloading.** The party's sprites are preloaded and kept in
`RPG::Cache` across map transfers. Sprites of Pokémon that leave the party are
released.

**Animations** (`Data/Animations.rxdata`): the Poké Ball and emote animations
are named "Follower ball out", "Follower ball in" and "Follower emote: ...".
The game finds them by name. `make follower-animations`
(`tools/scripts/add_follower_animations.rb`) adds them to
`lib/pokemon-essentials/Data/Animations.rxdata`, and to the installed
`src/assets/data/Animations.rxdata` if there is one:
- It appends them after the existing animations, never overwriting any.
- Running it again updates them in place.

Emote bubbles use the "Top" position. For the following Pokémon, the game
moves that position down to the top of the Pokémon itself (the first row of its
sprite's frames with anything drawn in it), so the bubble sits on its head
whatever the size of its frames. The bubble rests at `EMOTE_OFFSET` pixels
from there (`[3, -1]`: centred, with its tail just above the head), whatever
cell positions the emote animations have in `Animations.rxdata`.

The animations are defined at Essentials' 2× scale, the scale of
`lib/pokemon-essentials/Data/Animations.rxdata`. The game reads the installed
1× copy (`src/assets/data/Animations.rxdata`), into which
`make follower-animations` writes them with their cell positions halved. After
the follower animations change, run `make follower-animations` (or
`tools/scripts/install_assets.sh --force`) so that copy is up to date, then
rebuild.

The pictures are `Graphics/Animations/Follower_ComeInOut.png`,
`Follower_Emote1.png` and `Follower_Emote2.png`.

## Debug menu

**Field options → Following Pokémon...** has these tools:

| Tool | What it does |
|---|---|
| Show state | Which Pokémon follows, its size, position and hide reasons, the player's step trail, the step counters and the sprite cache |
| Toggle on/off | Turns the following Pokémon off or back on |
| Refresh | Re-checks the hide reasons and puts the Pokémon next to the player |
| Play emote | Shows an emote bubble over the Pokémon |
| Find an item now | Gives the Pokémon a found item to hand over |
| Walking friendship gain | Applies one walking friendship gain |
| Find missing sprites | Lists the species and forms with no overworld sprite in `following_pokemon_missing_sprites.txt` |
| Reload sprite cache | Releases the preloaded sprites and loads the party's again |
