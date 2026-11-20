#===============================================================================
# Following Pokémon: settings.
#
# The first Pokémon in the party that isn't an egg and hasn't fainted walks
# behind the player. See docs/FOLLOWING_POKEMON.md for how it works and how to
# control it from events and maps.
#===============================================================================
module FollowingPokemon
  #-----------------------------------------------------------------------------
  # Graphics
  #-----------------------------------------------------------------------------

  # Folder (in Graphics/Characters) of the overworld Pokémon sprites. Shiny
  # sprites are in the folder of the same name plus " shiny". Sprites are named
  # like Pokémon sprites: SPECIES, SPECIES_form, SPECIES_female, and so on.
  SPRITE_FOLDER = "Followers"

  # Sprites whose frames are this wide or narrower (in pixels, in the game's
  # graphics) are small Pokémon; wider than MEDIUM_FRAME_WIDTH are large.
  SMALL_FRAME_WIDTH  = 32
  MEDIUM_FRAME_WIDTH = 48

  # How far (in pixels) a Pokémon of each size is drawn back from the
  # character it follows, so big sprites don't cover the player. The
  # Pokémon still stands on its own tile.
  SIZE_OFFSETS = {
    :small  => 0,
    :medium => 4,
    :large  => 8
  }

  # Size categories for particular species (or "SPECIES_form"), overriding the
  # size worked out from their sprite.
  SIZE_OVERRIDES = {
    # :ONIX    => :large,
    # :DIGLETT => :small
  }

  # How high (in pixels) an airborne Pokémon (Flying type, Levitate, or a
  # floating battle sprite) bobs up and down while idling, and how long (in
  # seconds) one bob takes.
  FLOAT_HEIGHT   = 2
  FLOAT_DURATION = 1.2

  # Species flags (the "flags" field of a species in PBS) that also make a
  # Pokémon airborne, for ones that float without being Flying type, having
  # Levitate or having a floating battle sprite. Airborne Pokémon bob in the
  # air, aren't hidden by tall grass and don't rustle it.
  AIRBORNE_FLAGS = ["Airborne", "Floating", "Levitating"]

  # Whether the follower is tinted by its status problem.
  APPLY_STATUS_TONES = true
  # Tints for each status problem: [red, green, blue, grey] (Tone values).
  STATUS_TONES = {
    :BURN      => [64, -32, -48, 0],
    :POISON    => [24, -40, 40, 0],
    :PARALYSIS => [56, 40, -48, 0],
    :FROZEN    => [-40, 24, 72, 0],
    :SLEEP     => [-32, -32, -32, 64]
  }

  #-----------------------------------------------------------------------------
  # Animations (in Data/Animations.rxdata, added by
  # tools/scripts/add_follower_animations.rb). They are found by name, so their
  # IDs don't matter.
  #-----------------------------------------------------------------------------

  # The Pokémon coming out of / going back into its Poké Ball.
  ANIMATION_BALL_OUT = "Follower ball out"
  ANIMATION_BALL_IN  = "Follower ball in"
  # The emote bubbles. FollowingPokemon.emote(:heart) and so on.
  EMOTES = {
    :music    => "Follower emote: music",
    :happy    => "Follower emote: happy",
    :smile    => "Follower emote: smile",
    :question => "Follower emote: question",
    :heart    => "Follower emote: heart",
    :poison   => "Follower emote: poison",
    :angry    => "Follower emote: angry",
    :ellipsis => "Follower emote: ellipsis",
    :sad      => "Follower emote: sad",
    :mad      => "Follower emote: mad"
  }
  # How long (in seconds) after the ball out animation starts that the Pokémon
  # appears, and after the ball in animation starts that it disappears.
  BALL_OUT_APPEAR_TIME = 0.2
  BALL_IN_VANISH_TIME  = 0.1

  #-----------------------------------------------------------------------------
  # When the Pokémon follows
  #-----------------------------------------------------------------------------

  # Map metadata flags (the "flags" property of a map's metadata in Tiled).
  # NoFollowingPokemon: the Pokémon stays in its Poké Ball on this map.
  # ShowFollowingPokemon: big Pokémon may follow on this map even though it's
  # indoors (see MAX_INDOOR_HEIGHT).
  MAP_FLAG_HIDE = "NoFollowingPokemon"
  MAP_FLAG_SHOW = "ShowFollowingPokemon"

  # Pokémon taller than this (in metres) go back into their Poké Ball on
  # indoor maps without wild encounters (e.g. houses), unless the map has the
  # ShowFollowingPokemon flag. nil to let every Pokémon follow indoors.
  MAX_INDOOR_HEIGHT = 3.0

  # Whether the Pokémon goes back into its Poké Ball while the player rides a
  # bicycle. (It always does while surfing, diving and flying.)
  HIDE_WHEN_CYCLING = true

  # Whether the Pokémon goes back into its Poké Ball while the nurse heals the
  # party at a Pokémon Center (the Recover All event command on a Pokémon
  # Center map), and comes back out when the nurse is done.
  POKEMON_CENTER_ANIMATION = true

  #-----------------------------------------------------------------------------
  # Walking together
  #-----------------------------------------------------------------------------

  # Every this many steps, the following Pokémon gains friendship from walking
  # with the player.
  FRIENDSHIP_STEPS = 250

  # Every this many steps, there's a chance (in %) that the following Pokémon
  # finds an item. It shows an exclamation bubble; talking to it then gives
  # the player the item.
  ITEM_STEPS  = 500
  ITEM_CHANCE = 40

  # Items the following Pokémon can find: [item, weight]. A higher weight is
  # more likely.
  ITEMS = [
    [:POTION, 20], [:ANTIDOTE, 10], [:PARALYZEHEAL, 10], [:AWAKENING, 10],
    [:SUPERPOTION, 12], [:REPEL, 10], [:POKEBALL, 15], [:GREATBALL, 8],
    [:ETHER, 5], [:REVIVE, 4], [:ESCAPEROPE, 6], [:TINYMUSHROOM, 6],
    [:PEARL, 5], [:STARDUST, 5], [:HONEY, 5], [:ULTRABALL, 3],
    [:BIGMUSHROOM, 2], [:BIGPEARL, 2], [:NUGGET, 1], [:RARECANDY, 1]
  ]

  # Every this many steps, there's a chance (in %) that the following Pokémon
  # shows an emote bubble on its own, hinting that it has something to say.
  AMBIENT_EMOTE_STEPS  = 120
  AMBIENT_EMOTE_CHANCE = 25

  # The emote shown when the follower has found an item. :exclaim is the usual
  # exclamation bubble (Settings::EXCLAMATION_ANIMATION_ID).
  ITEM_FOUND_EMOTE = :exclaim
end
