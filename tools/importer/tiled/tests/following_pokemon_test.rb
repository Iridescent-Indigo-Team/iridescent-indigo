#===============================================================================
# following_pokemon_test.rb
#-------------------------------------------------------------------------------
# Tests followers walking their leader's step history (Game_Follower), the
# following Pokémon's event (Game_FollowingPokemon) and the FollowingPokemon
# rules for which Pokémon follows and when, without the engine: the engine
# pieces they use are stubbed below.
# Run by test_tiled.py (make test-tiled); prints "ok" when every check passes.
#===============================================================================
ROOT = File.expand_path("../../../..", __dir__)
SCRIPTS = File.join(ROOT, "src", "data")

# --- Engine stubs ---------------------------------------------------------------
module System
  @uptime = 0.0
  def self.uptime; @uptime; end
  def self.uptime=(value); @uptime = value; end
end

module EventHandlers
  def self.trigger(*_args); end
  def self.add(*_args); end
end

# @param _hash [Hash] type checks (ignored here)
def validate(_hash); end

class Game_Map
  TILE_WIDTH  = 16
  TILE_HEIGHT = 16
  X_SUBPIXELS = 4
  Y_SUBPIXELS = 4
  REAL_RES_X  = TILE_WIDTH * X_SUBPIXELS
  REAL_RES_Y  = TILE_HEIGHT * Y_SUBPIXELS
end

class Tone
  attr_reader :red, :green, :blue, :gray
  def initialize(r, g, b, gray = 0); @red, @green, @blue, @gray = r, g, b, gray; end
end

module Settings
  EXCLAMATION_ANIMATION_ID = 3
end

load File.join(SCRIPTS, "010_Data", "001_GameData.rb")
load File.join(SCRIPTS, "010_Data", "001_Hardcoded data", "011_TerrainTag.rb")
load File.join(SCRIPTS, "004_Game classes", "006_Game_Character.rb")

class Game_Character
  def check_event_trigger_touch(_dir); end
  def check_event_trigger_after_turning; end
end

# Just enough of Game_Event for Game_Follower.
class Game_Event < Game_Character
  attr_reader :event
  def initialize(map_id, event, map = nil)
    super(map)
    @map_id = map_id
    @event  = event
    @id     = event.id
    moveto(event.x, event.y) if map
    refresh
  end
  def name; @event.name; end
  def refresh; @through = false; end   # As a default event page
end

module RPG
  class Event
    attr_accessor :id, :name, :x, :y, :pages
    def initialize(x, y)
      @x, @y, @id, @name = x, y, 0, ""
      @pages = [Struct.new(:list).new([])]
    end
  end
end

class Game_Temp
  attr_accessor :ending_surf
end
class PokemonGlobalMetadata
  attr_accessor :ice_sliding, :bridge, :surfing, :diving, :bicycle
end

def pbTurnTowardEvent(event, other)
  dx = event.x - other.x
  dy = event.y - other.y
  return if dx == 0 && dy == 0
  if dx.abs > dy.abs
    (dx > 0) ? event.turn_left : event.turn_right
  else
    (dy > 0) ? event.turn_up : event.turn_down
  end
end

def pbMapInterpreterRunning?; false; end

load File.join(SCRIPTS, "004_Game classes", "010_Game_Follower.rb")
load File.join(SCRIPTS, "004_Game classes", "011_Game_FollowerFactory.rb")
following = File.join(SCRIPTS, "012_Overworld", "009_Following Pokemon")
load File.join(following, "001_FollowingPokemon_Config.rb")
load File.join(following, "002_FollowingPokemon_Data.rb")
load File.join(following, "003_Game_FollowingPokemon.rb")
load File.join(following, "004_FollowingPokemon.rb")

# A map made of characters: "." floor, "#" wall, "v" ledge (jumped down),
# "\\" StairsLeft, "/" StairsRight.
class TestMap
  attr_reader :map_id, :width, :height, :events, :terrain_tags, :passages, :priorities

  TILES = { "." => 0, "#" => 1, "v" => 2, "\\" => 3, "/" => 4 }

  def initialize(rows)
    @map_id = 1
    @rows = rows
    @width = rows[0].length
    @height = rows.length
    @events = {}
    @terrain_tags = [0, 0, GameData::TerrainTag.get(:Ledge).id_number,
                     GameData::TerrainTag.get(:StairsLeft).id_number,
                     GameData::TerrainTag.get(:StairsRight).id_number]
    @passages = [0, 0x0f, 0, 0, 0]
    @priorities = [0, 0, 0, 0, 0]
  end

  def valid?(x, y); x >= 0 && y >= 0 && x < @width && y < @height; end
  def cell(x, y); valid?(x, y) ? @rows[y][x] : "#"; end
  def data; self; end
  def [](x, y, z); (z == 0) ? TILES[cell(x, y)] : 0; end
  def terrain_tag(x, y); GameData::TerrainTag.try_get(@terrain_tags[TILES[cell(x, y)]]); end
  def passable?(x, y, _d, _self_event = nil); cell(x, y) != "#"; end
  def deepBush?(_x, _y); false; end
  def bush?(_x, _y); false; end
  def metadata; nil; end
end

# Map factory for a single map.
class TestFactory
  def initialize(map); @map = map; end
  def areConnected?(a, b); a == b; end
  def getMap(_id, _add = true); @map; end
  def getMapNoAdd(_id); @map; end
  def getRelativePos(_m1, x1, y1, _m2, x2, y2); [x2 - x1, y2 - y1]; end
  def getTerrainTag(_id, x, y); @map.terrain_tag(x, y); end
  def getTerrainTagFromCoords(_id, x, y); @map.terrain_tag(x, y); end
  def getFacingTile(dir, ch); getFacingTileFromPos(1, ch.x, ch.y, dir); end

  def getFacingTileFromPos(id, x, y, dir)
    x += (dir == 6) ? 1 : (dir == 4) ? -1 : 0
    y += (dir == 2) ? 1 : (dir == 8) ? -1 : 0
    return [id, x, y]
  end
end

# An NPC standing on the map.
class TestNPC < Game_Character
  def initialize(map, x, y)
    super(map)
    @character_name = "NPC 01"
    @through = false
    moveto(x, y)
  end
end

$failures = 0

def check(label, actual, expected)
  return if actual == expected
  puts "FAIL #{label}: expected #{expected.inspect}, got #{actual.inspect}"
  $failures += 1
end

def pos(c); [c.x, c.y]; end

def new_world(rows)
  map = TestMap.new(rows)
  $map_factory = TestFactory.new(map)
  $game_map = map
  $PokemonGlobal = PokemonGlobalMetadata.new
  $PokemonGlobal.bridge = 0
  $game_temp = Game_Temp.new
  leader = Game_Character.new(map)
  leader.through = true   # The player's own moves aren't under test here
  $game_player = leader
  return map, leader
end

def new_follower(map, x, y)
  data = FollowerData.new(1, 1, "Follower", 1, x, y, 2, "NPC 02", 0)
  return Game_Follower.new(data)
end

# --- Step history ---------------------------------------------------------------
map, leader = new_world(Array.new(8) { "." * 12 })
leader.moveto(5, 5)
check("moveto clears the history", leader.step_history, [])
leader.move_left
leader.move_up
leader.jump(0, -2)
kinds = leader.step_history.map { |step| step[:kind] }
check("history records each kind of step", kinds, [:step, :step, :jump])
check("history records where steps started", leader.step_history.map { |s| [s[:x], s[:y]] },
      [[5, 5], [4, 5], [4, 4]])
12.times { leader.move_right }
check("history is capped", leader.step_history.length, Game_Character::STEP_HISTORY_SIZE)

# --- Following along the trail --------------------------------------------------
map, leader = new_world(Array.new(8) { "." * 12 })
leader.moveto(5, 5)
follower = new_follower(map, 6, 5)
[:move_left, :move_left, :move_up].each do |move|
  leader.send(move)
  follower.follow_leader(leader)
end
check("follower walks into the leader's last tile", pos(follower), [3, 5])
leader.move_up
follower.follow_leader(leader)
check("follower turns the corner", pos(follower), [3, 4])

# --- Ledges ---------------------------------------------------------------------
rows = Array.new(8) { "." * 12 }
rows[4][5] = "v"
map, leader = new_world(rows)
leader.moveto(5, 3)
follower = new_follower(map, 5, 2)
leader.jump(0, 2)
follower.follow_leader(leader)
check("follower stays on top of the ledge", pos(follower), [5, 3])
leader.move_down
follower.follow_leader(leader)
check("follower jumps the ledge", pos(follower), [5, 5])
check("follower is jumping", follower.jumping?, true)

# --- Sideways stairs ------------------------------------------------------------
rows = Array.new(6) { "." * 12 }
[[5, 4], [4, 3], [3, 2]].each { |x, y| rows[y][x] = "\\" }
map, leader = new_world(rows)
leader.moveto(6, 4)
leader.direction = 4
follower = new_follower(map, 7, 4)
4.times do
  leader.move_left
  follower.follow_leader(leader)
end
check("leader climbed the stairs", pos(leader), [2, 2])
check("follower climbs diagonally behind", pos(follower), [3, 2])
check("follower faces along the flight", follower.direction, 4)

# --- Catching up after falling behind -------------------------------------------
map, leader = new_world(Array.new(8) { "." * 12 })
leader.moveto(2, 2)
follower = new_follower(map, 10, 7)
leader.move_right
leader.move_right
follower.follow_leader(leader)
check("lagging follower catches up along the trail", pos(follower), [3, 2])

# --- Never blocking anyone ------------------------------------------------------
map, leader = new_world(Array.new(8) { "." * 12 })
leader.moveto(5, 3)
follower = new_follower(map, 5, 4)
follower.direction = 8
npc = TestNPC.new(map, 5, 4)
map.events[1] = npc
check("follower steps aside from an NPC", follower.resolve_overlap, true)
check("...sideways", [[4, 4], [6, 4]].include?(pos(follower)), true)
check("follower doesn't move when nothing is in the way", follower.resolve_overlap, false)
map.events.clear
check("free spot behind the leader", follower.spot_beside(leader, 8), [5, 2])
map.events[1] = TestNPC.new(map, 5, 2)
check("occupied spot isn't free", follower.spot_beside(leader, 8), nil)

# --- Following Pokémon: which Pokémon, sizes, hide reasons ----------------------
Pkmn = Struct.new(:personalID, :species, :form, :shiny, :gender, :status, :egg, :hp,
                  :totalhp, :types, :ability) do
  def shiny?; shiny; end
  def egg?; egg; end
  def fainted?; hp <= 0; end
  def hasType?(type); types.include?(type); end
  def hasAbility?(check); ability == check; end
  def name; species.to_s; end
end

def pkmn(id, species, egg: false, hp: 20, types: [:NORMAL], ability: :RUNAWAY)
  return Pkmn.new(id, species, 0, false, 0, :NONE, egg, hp, 20, types, ability)
end

module GameData
  class Species
    def self.check_graphic_file(path, species, _form = 0, _gender = 0, shiny = false, _shadow = false, subfolder = "")
      return "#{path}#{subfolder}#{(shiny) ? ' shiny' : ''}/#{species}.png"
    end
  end

  class SpeciesMetrics
    def self.get_species_form(species, _form)
      return Struct.new(:front_sprite_altitude).new((species == :GASTLY) ? 8 : 0)
    end
  end
end

Player = Struct.new(:party)
$player = Player.new([pkmn(1, :EGG, egg: true), pkmn(2, :PIDGEY, hp: 0), pkmn(3, :RATTATA)])
check("eggs and fainted Pokémon are skipped", FollowingPokemon.pokemon&.species, :RATTATA)
$player.party[2].hp = 0
check("no Pokémon if none can follow", FollowingPokemon.pokemon, nil)

rattata = pkmn(3, :RATTATA)
check("small sprite", FollowingPokemon.size_category(rattata, 32), :small)
check("medium sprite", FollowingPokemon.size_category(rattata, 40), :medium)
check("large sprite", FollowingPokemon.size_category(rattata, 64), :large)
FollowingPokemon::SIZE_OVERRIDES[:RATTATA] = :large
check("size override", FollowingPokemon.size_category(rattata, 32), :large)
FollowingPokemon::SIZE_OVERRIDES.delete(:RATTATA)

check("flying type is airborne", FollowingPokemon.airborne?(pkmn(4, :PIDGEY, types: [:FLYING])), true)
check("Levitate is airborne", FollowingPokemon.airborne?(pkmn(5, :KOFFING, ability: :LEVITATE)), true)
check("floating battler is airborne", FollowingPokemon.airborne?(pkmn(6, :GASTLY)), true)
check("ground Pokémon isn't airborne", FollowingPokemon.airborne?(rattata), false)

before = FollowingPokemon.signature(rattata)
rattata.status = :POISON
check("status changes the signature", FollowingPokemon.signature(rattata) != before, true)

map, leader = new_world(Array.new(8) { "." * 12 })
$PokemonSystem = Struct.new(:following_pokemon).new(0)
check("nothing hides a Pokémon by default", FollowingPokemon.hide_reasons(rattata), [])
$PokemonGlobal.surfing = true
check("surfing hides it", FollowingPokemon.hide_reasons(rattata).include?(:surfing), true)
$PokemonGlobal.surfing = false
$PokemonGlobal.followers.push(FollowerData.new(1, 1, "May", 1, 0, 0, 2, "", 0))
check("a human follower hides it", FollowingPokemon.hide_reasons(rattata), [:human_follower])
$PokemonGlobal.followers.clear
$PokemonSystem.following_pokemon = 1
check("the Options setting hides it", FollowingPokemon.hide_reasons(rattata), [:option_off])
$PokemonSystem.following_pokemon = 0
FollowingPokemon.data.hide_reasons.push(:cutscene)
check("scripts can hide it", FollowingPokemon.hide_reasons(rattata), [:cutscene])
FollowingPokemon.data.hide_reasons.clear
check("no Pokémon to follow", FollowingPokemon.hide_reasons(nil), [:no_pokemon])

# --- The following Pokémon's event ----------------------------------------------
data = FollowingPokemon.data
event = Game_FollowingPokemon.new(data)
check("hidden while in its Poké Ball", event.transparent, true)
data.out = true
check("visible once out", event.transparent, false)
event.pokemon = pkmn(4, :PIDGEY, types: [:FLYING])
check("airborne Pokémon idle-animate", event.instance_variable_get(:@step_anime), true)
check("airborne Pokémon aren't hidden by grass", event.bush_depth, 0)
check("sprite comes from the Followers folder", event.character_name, "Followers/PIDGEY")
check("shiny sprite folder", FollowingPokemon.sprite_name(Pkmn.new(7, :EEVEE, 0, true, 0, :NONE, false,
                                                                    20, 20, [:NORMAL], nil)),
      "Followers shiny/EEVEE")
event.pokemon = rattata
check("status tint", event.status_tone&.red, FollowingPokemon::STATUS_TONES[:POISON][0])
Anim = Struct.new(:name)
$data_animations = [nil, Anim.new("Grass rustle"), Anim.new("Follower ball out"), Anim.new("Follower ball in")]
check("animations are found by name", FollowingPokemon.animation_id("Follower ball in"), 3)
check("missing animation", FollowingPokemon.animation_id("Nope"), nil)
System.uptime = 10.0
event.play_ball_in
check("ball animation plays", event.animation_id, 3)
check("still visible as the ball animation starts", event.transparent, false)
System.uptime = 10.2
check("gone into its Poké Ball", event.transparent, true)
check("ball animation still playing", event.busy?, true)
System.uptime = 11.0
check("ball animation finished", event.busy?, false)

if $failures == 0
  puts "ok"
else
  exit(1)
end
