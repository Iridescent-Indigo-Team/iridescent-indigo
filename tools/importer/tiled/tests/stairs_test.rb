#===============================================================================
# stairs_test.rb
#-------------------------------------------------------------------------------
# Tests the sideways stairs step resolver in Game_Character
# (src/data/004_Game classes/006_Game_Character.rb) and the StairsLeft and
# StairsRight terrain tags without the engine: the few engine pieces they use
# are stubbed below.
# Run by test_tiled.py (make test-tiled); prints "ok" when every check passes.
#===============================================================================
ROOT = File.expand_path("../../../..", __dir__)
SCRIPTS = File.join(ROOT, "src", "data")

# --- Engine stubs ---------------------------------------------------------------
module System
  def self.uptime; 0.0; end
end

module EventHandlers
  def self.trigger(*_args); end
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

load File.join(SCRIPTS, "010_Data", "001_GameData.rb")
load File.join(SCRIPTS, "010_Data", "001_Hardcoded data", "011_TerrainTag.rb")
load File.join(SCRIPTS, "004_Game classes", "006_Game_Character.rb")

# A map made of terrain tags, with walls ("#") that block every direction.
class TestMap
  attr_reader :map_id, :width, :height, :events

  # @param rows [Array<String>] "." flat, "/" StairsRight, "\\" StairsLeft, "#" wall
  def initialize(rows)
    @map_id = 1
    @rows = rows
    @width = rows[0].length
    @height = rows.length
    @events = {}
  end

  def valid?(x, y); x >= 0 && y >= 0 && x < @width && y < @height; end
  def cell(x, y); valid?(x, y) ? @rows[y][x] : "#"; end

  def terrain_tag(x, y)
    case cell(x, y)
    when "\\" then GameData::TerrainTag.get(:StairsLeft)
    when "/"  then GameData::TerrainTag.get(:StairsRight)
    else           GameData::TerrainTag.get(:None)
    end
  end

  def passable?(x, y, _d, _self_event = nil); cell(x, y) != "#"; end
  def deepBush?(_x, _y); false; end
  def bush?(_x, _y); false; end
end

class Game_Character
  attr_reader :touched
  def check_event_trigger_touch(dir); @touched = dir; end
  def check_event_trigger_after_turning; end
end

$game_player = Struct.new(:x, :y, :through).new(-9, -9, true)
$map_factory = nil
$failures = 0

def check(label, actual, expected)
  return if actual == expected
  puts "FAIL #{label}: expected #{expected.inspect}, got #{actual.inspect}"
  $failures += 1
end

# A StairsLeft flight from (5,4) up to (3,2), landings at (6,4) and (2,2), and
# a StairsRight flight from (8,4) up to (10,2), landings at (7,4) and (11,2).
rows = Array.new(6) { "." * 12 }
[[5, 4], [4, 3], [3, 2]].each { |x, y| rows[y][x] = "\\" }
[[8, 4], [9, 3], [10, 2]].each { |x, y| rows[y][x] = "/" }
MAP = TestMap.new(rows)

def walker(x, y, dir = 2)
  c = Game_Character.new(MAP)
  c.moveto(x, y)
  c.direction = dir
  return c
end

def pos(c); [c.x, c.y]; end

# --- Tags -----------------------------------------------------------------------
check("StairsLeft tag", GameData::TerrainTag.get(:StairsLeft).sideways_stairs, :left)
check("StairsRight tag", GameData::TerrainTag.get(18).stairs?, true)
check("other tags aren't stairs", GameData::TerrainTag.get(:Ice).stairs?, false)

# --- Climbing a StairsLeft flight -----------------------------------------------
c = walker(6, 4, 4)
c.move_left
check("enter flight horizontally", pos(c), [5, 4])
c.move_left
check("climb diagonally", pos(c), [4, 3])
check("trail records the step's start", c.last_step_from, [1, 5, 4])
c.move_left
check("climb to the top tile", pos(c), [3, 2])
c.move_left
check("step off onto the top landing", pos(c), [2, 2])
check("faces left", c.direction, 4)

# --- Descending it --------------------------------------------------------------
c.move_right
check("enter from the top", pos(c), [3, 2])
c.move_right
check("descend diagonally", pos(c), [4, 3])
c.move_right
c.move_right
check("step off onto the bottom landing", pos(c), [6, 4])

# --- StairsRight is the mirror image --------------------------------------------
c = walker(7, 4, 6)
4.times { c.move_right }
check("climb a StairsRight flight", pos(c), [11, 2])
4.times { c.move_left }
check("descend a StairsRight flight", pos(c), [7, 4])

# --- Up/down on stairs does nothing ---------------------------------------------
c = walker(4, 3, 4)
c.move_up
check("up on stairs doesn't move", pos(c), [4, 3])
c.move_down
check("down on stairs doesn't move", pos(c), [4, 3])
c.turn_up
c.turn_down
check("up/down on stairs doesn't turn", c.direction, 4)
check("resolver swallows up", c.resolve_step(8), nil)
check("facing tile is diagonally ahead", c.step_offset, [-1, -1])

# --- Flights are only entered from their ends -----------------------------------
c = walker(4, 4, 8)
c.move_up
check("can't walk up into a stair", pos(c), [4, 4])
check("blocked step touches events", c.touched, 8)
c = walker(4, 2, 2)
c.move_down
check("can't walk down into a stair", pos(c), [4, 2])

# --- Diagonal steps check the destination ---------------------------------------
walled = TestMap.new(["....", "..\\.", "...\\", "...."])
c = Game_Character.new(walled)
c.moveto(3, 2)
c.direction = 4
check("diagonal through to an open stair", c.resolve_step(4), [-1, -1])
walled.instance_variable_get(:@rows)[1] = "..#."
check("a blocked stair stops the flight", c.resolve_step(4), [-1, 0])

# --- stairs_off / stairs_on -----------------------------------------------------
c = walker(4, 3, 4)
c.stairs_off
c.move_left
check("stairs_off moves straight", pos(c), [3, 3])
c.moveto(4, 3)
c.direction = 4
c.stairs_on
c.move_left
check("stairs_on moves diagonally again", pos(c), [3, 2])

# --- Bigger characters ignore stairs --------------------------------------------
c = walker(4, 3, 4)
c.width = 2
check("2-tile-wide characters aren't stair-aware", c.stairs_aware?, false)

# --- Placing a character on stairs ----------------------------------------------
c = Game_Character.new(MAP)
c.moveto(4, 3)
check("moveto onto StairsLeft faces down the flight", c.direction, 6)
check("moveto clears the trail", c.last_step_from, nil)
c = Game_Character.new(MAP)
c.direction = 8
c.moveto(9, 3)
check("moveto onto StairsRight faces down the flight", c.direction, 4)

if $failures == 0
  puts "ok"
else
  exit 1
end
