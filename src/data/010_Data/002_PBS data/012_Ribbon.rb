module GameData
  #=============================================================================
  # Ribbons and Marks (together called mementos). A mark is a ribbon with
  # IsMark = true. Either may confer a title that is shown after the Pokémon's
  # name (or before it, with PrefixTitle) when the Pokémon has it affixed.
  #=============================================================================
  class Ribbon
    attr_reader :id
    attr_reader :real_name
    attr_reader :icon_position   # Where this ribbon's graphic is within ribbons.png
    attr_reader :real_description
    attr_reader :real_title          # Title shown after the name ("the Peckish")
    attr_reader :real_prefix_title   # Title shown before the name ("/Owner/'s")
    attr_reader :previous_ranks      # Lower ranks this ribbon replaces/collapses
    attr_reader :mark                # Whether this is a mark rather than a ribbon
    attr_reader :flags
    attr_reader :pbs_file_suffix

    DATA = {}
    DATA_FILENAME = "ribbons.dat"
    PBS_BASE_FILENAME = "ribbons"

    SCHEMA = {
      "SectionName"   => [:id,                "m"],
      "Name"          => [:real_name,         "s"],
      "IconPosition"  => [:icon_position,     "u"],
      "Description"   => [:real_description,  "q"],
      "Title"         => [:real_title,        "s"],
      "PrefixTitle"   => [:real_prefix_title, "s"],
      "PreviousRanks" => [:previous_ranks,    "*m"],
      "IsMark"        => [:mark,              "b"],
      "Flags"         => [:flags,             "*s"]
    }

    # Tokens that can be used inside a title and what replaces them.
    # /Owner/ is the Pokémon's original trainer, /Player/ the player and
    # /Variable_N/ the value of game variable N.
    TITLE_TOKEN_REGEXP = /\/(Owner|Player|Variable_(\d+))\//

    extend ClassMethodsSymbols
    include InstanceMethods

    def initialize(hash)
      @id                = hash[:id]
      @real_name         = hash[:real_name]        || "Unnamed"
      @icon_position     = hash[:icon_position]    || 0
      @real_description  = hash[:real_description] || "???"
      @real_title        = hash[:real_title]
      @real_prefix_title = hash[:real_prefix_title]
      @previous_ranks    = hash[:previous_ranks]   || []
      @mark              = hash[:mark]             || false
      @flags             = hash[:flags]            || []
      @pbs_file_suffix   = hash[:pbs_file_suffix]  || ""
    end

    # @return [String] the translated name of this ribbon
    def name
      return pbGetMessageFromHash(MessageTypes::RIBBON_NAMES, @real_name)
    end

    # @return [String] the translated description of this ribbon
    def description
      return pbGetMessageFromHash(MessageTypes::RIBBON_DESCRIPTIONS, @real_description)
    end

    # @return [Boolean] whether this ribbon/mark confers a title
    def has_title?
      return !nil_or_empty?(@real_prefix_title) || !nil_or_empty?(@real_title)
    end

    # @return [Boolean] whether the title goes before the Pokémon's name
    def prefix_title?
      return !nil_or_empty?(@real_prefix_title)
    end

    # The untranslated title text, with tokens left in place.
    # @return [String, nil]
    def real_title_text
      return (prefix_title?) ? @real_prefix_title : @real_title
    end

    # The translated title conferred by this ribbon/mark, with its tokens
    # (/Owner/, /Player/, /Variable_N/) replaced.
    # @param pkmn [Pokemon, nil] the Pokémon the title belongs to (for /Owner/)
    # @return [String] the title, or "" if this ribbon has none
    def title(pkmn = nil)
      return "" if !has_title?
      ret = pbGetMessageFromHash(MessageTypes::RIBBON_TITLES, real_title_text)
      return ret.gsub(TITLE_TOKEN_REGEXP) do
        case $1
        when "Owner"  then (pkmn&.owner) ? pkmn.owner.name : ""
        when "Player" then ($player) ? $player.name : ""
        else               ($game_variables) ? $game_variables[$2.to_i].to_s : ""
        end
      end
    end

    # @param pkmn [Pokemon, nil]
    # @return [String] the title with its first letter capitalised
    def title_capitalized(pkmn = nil)
      ret = title(pkmn)
      return ret if ret.empty?
      return ret[0].upcase + ret[1..]
    end

    # @return [Integer] the highest rank of this ribbon (1 if it has no ranks)
    def max_rank
      return 1 + @previous_ranks.length
    end

    # @return [Boolean] whether this is a mark
    def mark?
      return @mark
    end

    # @return [Boolean] whether this is a ribbon (i.e. not a mark)
    def ribbon?
      return !@mark
    end

    def has_flag?(flag)
      return @flags.any? { |f| f.downcase == flag.downcase }
    end

    # Ribbon categories
    def contest_ribbon?;   return has_flag?("ContestRibbon");   end
    def league_ribbon?;    return has_flag?("LeagueRibbon");    end
    def frontier_ribbon?;  return has_flag?("FrontierRibbon");  end
    def memorial_ribbon?;  return has_flag?("MemorialRibbon");  end
    def gift_ribbon?;      return has_flag?("GiftRibbon");      end
    # Mark categories
    def time_mark?;        return has_flag?("TimeMark");        end
    def weather_mark?;     return has_flag?("WeatherMark");     end
    def encounter_mark?;   return has_flag?("EncounterMark");   end
    def rarity_mark?;      return has_flag?("RarityMark");      end
    def personality_mark?; return has_flag?("PersonalityMark"); end
    def size_mark?;        return has_flag?("SizeMark");        end
    def party_mark?;       return has_flag?("PartyMark");       end
    def boss_mark?;        return has_flag?("BossMark");        end
  end
end
