#===============================================================================
# Grammar tokens in translated text.
#
# Translations (and English text) can use these tokens. The {n} ones refer to
# the arguments given to _INTL/_MAPINTL/_ISPRINTF, as {n} placeholders do.
#   {1|def}           The noun in argument 1 with its definite article, as set
#                     in tools/importer/locales/locales.json for the language
#                     ("der Trank", "l'Hyper Potion", "lo Spray"...).
#   {1|Def}           The same, capitalised (start of a sentence).
#   {1|indef.acc}     Any other article/case/preposition the language defines,
#                     e.g. "def.dat" (dem Trank), "de.def" (du/de la/des).
#   {1|plural:one|other}
#                     Chooses by the number in argument 1, with the language's
#                     plural rule. A # in a choice is replaced by the number.
#   {1|g:masc|fem|neut}
#                     Chooses by the gender of the noun in argument 1.
#   {pg:male|female}  Chooses by the player's gender.
# The gender, number and sound of each translated name come from the CSVs
# (gender/sound columns) and are compiled into the language's message file
# (MessageTypes::LOCALE_DATA). See docs/LOCALIZATION.md.
#===============================================================================
module LocaleGrammar
  # Used when no translation is loaded (English).
  ENGLISH = {
    "code"           => "en",
    "plural"         => "one_is_1",
    "thousands"      => ",",
    "default_gender" => "n",
    "articles"       => {
      "def"   => { "" => "the " },
      "indef" => { "" => "a ", "vowel" => "an ", "pl" => "" }
    },
    "sounds"         => { "vowel" => "^[aeiou]" },
    "nouns"          => {}
  }
  GENDER_INDEX = { "m" => 0, "f" => 1, "n" => 2 }
  TOKEN_REGEXP = /\{(\d+|pg)([|:])([^{}]*)\}/

  @@sound_regexps = {}

  module_function

  # The grammar data of the current language.
  def data
    ret = MessageTypes.locale_data rescue nil
    return (ret.is_a?(Hash)) ? ret : ENGLISH
  end

  # Replaces every grammar token in string. args are the _INTL arguments
  # (args[1] is {1}). {n} and {n:format} placeholders are left alone.
  def format(string, args)
    return string if !string.is_a?(String) || !string.include?("{")
    return string.gsub(TOKEN_REGEXP) do |match|
      head = $1
      separator = $2
      body = $3
      if head == "pg"
        next (separator == ":") ? choose_player_gender(body.split("|", -1)) : match
      end
      next match if separator == ":"   # {1:d}, for _ISPRINTF
      index = head.to_i
      next match if index >= args.length
      expand(args[index], body) || match
    end
  end

  def expand(arg, body)
    op, rest = body.split(":", 2)
    case op
    when "plural"
      options = (rest || "").split("|", -1)
      return nil if options.empty?
      number = number_value(arg)
      text = options[plural_one?(number) ? 0 : [1, options.length - 1].min]
      return text.gsub("#") { arg.is_a?(Numeric) ? arg.to_s_formatted : arg.to_s }
    when "g"
      options = (rest || "").split("|", -1)
      return nil if options.empty?
      gender = noun_info(arg.to_s)[0]
      return options[[GENDER_INDEX[gender] || 0, options.length - 1].min]
    else
      return article(op, arg.to_s)
    end
  end

  def choose_player_gender(options)
    female = false
    begin
      female = ($player && $player.female?) ? true : false
    rescue StandardError
      female = false
    end
    return options[(female) ? [1, options.length - 1].min : 0] || ""
  end

  # The numeric value of an argument ("1.234" or 1234 -> 1234).
  def number_value(arg)
    return arg.abs if arg.is_a?(Numeric)
    digits = arg.to_s.gsub(/[^\d]/, "")
    return (digits.empty?) ? 0 : digits.to_i
  end

  def plural_one?(number)
    case data["plural"]
    when "one_is_0_1" then return number == 0 || number == 1
    end
    return number == 1
  end

  # [gender, number, sound] of a (translated) noun.
  def noun_info(noun)
    d = data
    info = d["nouns"][noun] if d["nouns"]
    gender = (info && info[0] && !info[0].empty?) ? info[0] : d["default_gender"] || "m"
    number = (info && info[1]) ? info[1] : "sg"
    sound  = (info && info[2] && !info[2].empty?) ? info[2] : guess_sound(noun)
    return [gender, number, sound]
  end

  # "vowel", "special" or "" for a noun, from the language's sound rules.
  def guess_sound(noun)
    sounds = data["sounds"] || {}
    ["special", "vowel"].each do |sound|
      next if !sounds[sound]
      key = data["code"].to_s + ":" + sound
      @@sound_regexps[key] ||= Regexp.new(sounds[sound], Regexp::IGNORECASE)
      return sound if noun[@@sound_regexps[key]]
    end
    return ""
  end

  # The noun with the article "name" in front of it, or nil if the language
  # has no such article.
  def article(name, noun)
    articles = data["articles"] || {}
    table = articles[name] || articles[name.downcase]
    if !table
      found = articles.keys.find { |k| k.downcase == name.downcase }
      table = articles[found] if found
    end
    return nil if !table
    gender, number, sound = noun_info(noun)
    sound = "" if sound == "none"
    # Most specific first; the sound (vowel/special) beats the bare gender, so
    # e.g. a French masculine noun starting with a vowel gets "l'", not "le"
    candidates = []
    if number == "pl"
      candidates.push("#{gender}.pl.#{sound}", "pl.#{sound}") if !sound.empty?
      candidates.push("#{gender}.pl", "pl")
    end
    candidates.push("#{gender}.#{sound}", sound) if !sound.empty?
    candidates.push(gender, "")
    prefix = nil
    candidates.each do |c|
      next if !table.has_key?(c)
      prefix = table[c]
      break
    end
    ret = (prefix || "") + noun
    ret = ret[0].upcase + ret[1..] if name[0] && name[0] == name[0].upcase && name[0] != name[0].downcase && !ret.empty?
    return ret
  end
end

# Grammar tokens, then {1}, {2}... placeholders.
def pbIntlFormat(string, args)
  return string if !string.is_a?(String)
  string = LocaleGrammar.format(string, args)
  (1...args.length).each do |i|
    string.gsub!(/\{#{i}\}/) { args[i].to_s }
  end
  return string
end
