#===============================================================================
#
#===============================================================================
class MoveSelectionSprite < Sprite
  attr_reader :preselected
  attr_reader :index

  def initialize(viewport = nil, fifthmove = false)
    super(viewport)
    @movesel = AnimatedBitmap.new("Graphics/UI/Summary/cursor_move")
    @frame = 0
    @index = 0
    @fifthmove = fifthmove
    @preselected = false
    @updating = false
    refresh
  end

  def dispose
    @movesel.dispose
    super
  end

  def index=(value)
    @index = value
    refresh
  end

  def preselected=(value)
    @preselected = value
    refresh
  end

  def refresh
    w = @movesel.width
    h = @movesel.height / 2
    self.x = 120
    self.y = 46 + (self.index * 32)
    self.y -= 38 if @fifthmove
    self.y += 10 if @fifthmove && self.index == Pokemon::MAX_MOVES   # Add a gap
    self.bitmap = @movesel.bitmap
    if self.preselected
      self.src_rect.set(0, h, w, h)
    else
      self.src_rect.set(0, 0, w, h)
    end
  end

  def update
    @updating = true
    super
    @movesel.update
    @updating = false
    refresh
  end
end

#===============================================================================
# The cursor on the Summary screen's ribbons page. It is drawn in code to fit
# the ribbon slots (see PokemonSummary_Scene::RIBBON_SLOT_SIZE).
#===============================================================================
class RibbonSelectionSprite < MoveSelectionSprite
  # The cursor's colour (and when it is marking a ribbon being moved).
  CURSOR_COLOR      = Color.new(248, 56, 32)
  PRESELECTED_COLOR = Color.new(56, 144, 248)
  # The thickness of the cursor's outline.
  CURSOR_THICKNESS  = 2

  def initialize(viewport = nil)
    @cursor_bitmaps = [false, true].map { |pre| RibbonSelectionSprite.make_cursor_bitmap(pre) }
    super(viewport)
    @frame = 0
    @index = 0
    @preselected = false
    @updating = false
    @spriteVisible = true
    refresh
  end

  # @param preselected [Boolean] whether to draw the "being moved" cursor
  # @return [Bitmap] an outlined square the size of a ribbon slot
  def self.make_cursor_bitmap(preselected)
    size = PokemonSummary_Scene::RIBBON_SLOT_SIZE
    t = CURSOR_THICKNESS
    color = (preselected) ? PRESELECTED_COLOR : CURSOR_COLOR
    bmp = Bitmap.new(size, size)
    bmp.fill_rect(0, 0, size, t, color)
    bmp.fill_rect(0, size - t, size, t, color)
    bmp.fill_rect(0, 0, t, size, color)
    bmp.fill_rect(size - t, 0, t, size, color)
    return bmp
  end

  def dispose
    @cursor_bitmaps&.each { |b| b.dispose }
    super
  end

  def visible=(value)
    super
    @spriteVisible = value if !@updating
  end

  def refresh
    return if !@cursor_bitmaps
    pos = PokemonSummary_Scene.ribbon_slot_position(self.index)
    self.x = pos[0]
    self.y = pos[1]
    self.bitmap = @cursor_bitmaps[(self.preselected) ? 1 : 0]
    self.src_rect.set(0, 0, self.bitmap.width, self.bitmap.height)
  end

  def update
    @updating = true
    super
    self.visible = @spriteVisible && @index >= 0 && @index < PokemonSummary_Scene::RIBBONS_PER_PAGE
    @updating = false
    refresh
  end
end

#===============================================================================
#
#===============================================================================
class PokemonSummary_Scene
  MARK_WIDTH  = 8
  MARK_HEIGHT = 8
  # Layout of the ribbons page. Ribbon/mark icons come from
  # Graphics/UI/Summary/ribbons, 8 per row; their size is worked out from that
  # graphic's width, and they are drawn centred in each slot.
  RIBBON_COLUMNS   = 3
  RIBBON_ROWS      = 3
  RIBBONS_PER_PAGE = RIBBON_COLUMNS * RIBBON_ROWS
  RIBBON_SLOT_SIZE = 42
  RIBBON_GRID_X    = 119
  RIBBON_GRID_Y    = 35
  # Whether the ribbon slots are drawn in code over the background. Set to
  # false once bg_5 has slots drawn in it that match the layout above.
  RIBBON_DRAW_SLOTS = true
  # Area of bg_5 that is repainted when drawing the slots, and the points of
  # bg_5 whose colours are used for the panel and the slots.
  RIBBON_PANEL_RECT        = [109, 33, 147, 131]
  RIBBON_PANEL_COLOR_POINT = [112, 40]
  RIBBON_SLOT_COLOR_POINT  = [130, 54]
  # Colors used for messages in this scene
  RED_TEXT_BASE     = Color.new(248, 56, 32)
  RED_TEXT_SHADOW   = Color.new(224, 152, 144)
  BLACK_TEXT_BASE   = Color.new(64, 64, 64)
  BLACK_TEXT_SHADOW = Color.new(176, 176, 176)

  def pbUpdate
    pbUpdateSpriteHash(@sprites)
  end

  def pbStartScene(party, partyindex, inbattle = false)
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @party      = party
    @partyindex = partyindex
    @pokemon    = @party[@partyindex]
    @inbattle   = inbattle
    @page = 1
    @typebitmap    = AnimatedBitmap.new(_INTL("Graphics/UI/types"))
    @markingbitmap = AnimatedBitmap.new("Graphics/UI/Summary/markings")
    @sprites = {}
    @sprites["background"] = IconSprite.new(0, 0, @viewport)
    @sprites["pokemon"] = PokemonSprite.new(@viewport)
    @sprites["pokemon"].setOffset(PictureOrigin::CENTER)
    @sprites["pokemon"].x = 52
    @sprites["pokemon"].y = 103
    @sprites["pokemon"].setPokemonBitmap(@pokemon)
    @sprites["pokeicon"] = PokemonIconSprite.new(@pokemon, @viewport)
    @sprites["pokeicon"].setOffset(PictureOrigin::CENTER)
    @sprites["pokeicon"].x       = 23
    @sprites["pokeicon"].y       = 46
    @sprites["pokeicon"].visible = false
    @sprites["itemicon"] = ItemIconSprite.new(15, 160, @pokemon.item_id, @viewport)
    @sprites["itemicon"].blankzero = true
    @sprites["overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    pbSetSystemFont(@sprites["overlay"].bitmap)
    @sprites["movepresel"] = MoveSelectionSprite.new(@viewport)
    @sprites["movepresel"].visible     = false
    @sprites["movepresel"].preselected = true
    @sprites["movesel"] = MoveSelectionSprite.new(@viewport)
    @sprites["movesel"].visible = false
    @sprites["ribbonpresel"] = RibbonSelectionSprite.new(@viewport)
    @sprites["ribbonpresel"].visible     = false
    @sprites["ribbonpresel"].preselected = true
    @sprites["ribbonsel"] = RibbonSelectionSprite.new(@viewport)
    @sprites["ribbonsel"].visible = false
    @sprites["uparrow"] = AnimatedSprite.new("Graphics/UI/up_arrow", 8, 14, 20, 2, @viewport)
    @sprites["uparrow"].x = RIBBON_GRID_X + (RIBBON_COLUMNS * RIBBON_SLOT_SIZE / 2) - 7
    @sprites["uparrow"].y = 24
    @sprites["uparrow"].play
    @sprites["uparrow"].visible = false
    @sprites["downarrow"] = AnimatedSprite.new("Graphics/UI/down_arrow", 8, 14, 20, 2, @viewport)
    @sprites["downarrow"].x = RIBBON_GRID_X + (RIBBON_COLUMNS * RIBBON_SLOT_SIZE / 2) - 7
    @sprites["downarrow"].y = 148
    @sprites["downarrow"].play
    @sprites["downarrow"].visible = false
    @sprites["markingbg"] = IconSprite.new(130, 44, @viewport)
    @sprites["markingbg"].setBitmap("Graphics/UI/Summary/overlay_marking")
    @sprites["markingbg"].visible = false
    @sprites["markingoverlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    @sprites["markingoverlay"].visible = false
    pbSetSystemFont(@sprites["markingoverlay"].bitmap)
    @sprites["markingsel"] = IconSprite.new(0, 0, @viewport)
    @sprites["markingsel"].setBitmap("Graphics/UI/Summary/cursor_marking")
    @sprites["markingsel"].src_rect.height = @sprites["markingsel"].bitmap.height / 2
    @sprites["markingsel"].visible = false
    @sprites["messagebox"] = Window_AdvancedTextPokemon.new("")
    @sprites["messagebox"].viewport       = @viewport
    @sprites["messagebox"].visible        = false
    @sprites["messagebox"].letterbyletter = true
    pbBottomLeftLines(@sprites["messagebox"], 2)
    @nationalDexList = [:NONE]
    GameData::Species.each_species { |s| @nationalDexList.push(s.species) }
    drawPage(@page)
    pbFadeInAndShow(@sprites) { pbUpdate }
  end

  def pbStartForgetScene(party, partyindex, move_to_learn)
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @party      = party
    @partyindex = partyindex
    @pokemon    = @party[@partyindex]
    @page = 4
    @typebitmap = AnimatedBitmap.new(_INTL("Graphics/UI/types"))
    @sprites = {}
    @sprites["background"] = IconSprite.new(0, 0, @viewport)
    @sprites["overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    pbSetSystemFont(@sprites["overlay"].bitmap)
    @sprites["pokeicon"] = PokemonIconSprite.new(@pokemon, @viewport)
    @sprites["pokeicon"].setOffset(PictureOrigin::CENTER)
    @sprites["pokeicon"].x       = 23
    @sprites["pokeicon"].y       = 46
    @sprites["movesel"] = MoveSelectionSprite.new(@viewport, !move_to_learn.nil?)
    @sprites["movesel"].visible = false
    @sprites["movesel"].visible = true
    @sprites["movesel"].index   = 0
    new_move = (move_to_learn) ? Pokemon::Move.new(move_to_learn) : nil
    drawSelectedMove(new_move, @pokemon.moves[0])
    pbFadeInAndShow(@sprites)
  end

  def pbEndScene
    pbFadeOutAndHide(@sprites) { pbUpdate }
    pbDisposeSpriteHash(@sprites)
    @typebitmap.dispose
    @markingbitmap&.dispose
    @viewport.dispose
  end

  def pbDisplay(text)
    @sprites["messagebox"].text = text
    @sprites["messagebox"].visible = true
    pbPlayDecisionSE
    loop do
      Graphics.update
      Input.update
      pbUpdate
      if @sprites["messagebox"].busy?
        if Input.trigger?(Input::USE)
          pbPlayDecisionSE if @sprites["messagebox"].pausing?
          @sprites["messagebox"].resume
        end
      elsif Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
        break
      end
    end
    @sprites["messagebox"].visible = false
  end

  def pbConfirm(text)
    ret = -1
    @sprites["messagebox"].text    = text
    @sprites["messagebox"].visible = true
    using(cmdwindow = Window_CommandPokemon.new([_INTL("Yes"), _INTL("No")])) do
      cmdwindow.z       = @viewport.z + 1
      cmdwindow.visible = false
      pbBottomRight(cmdwindow)
      cmdwindow.y -= @sprites["messagebox"].height
      loop do
        Graphics.update
        Input.update
        cmdwindow.visible = true if !@sprites["messagebox"].busy?
        cmdwindow.update
        pbUpdate
        if !@sprites["messagebox"].busy?
          if Input.trigger?(Input::BACK)
            ret = false
            break
          elsif Input.trigger?(Input::USE) && @sprites["messagebox"].resume
            ret = (cmdwindow.index == 0)
            break
          end
        end
      end
    end
    @sprites["messagebox"].visible = false
    return ret
  end

  def pbShowCommands(commands, index = 0)
    ret = -1
    using(cmdwindow = Window_CommandPokemon.new(commands)) do
      cmdwindow.z = @viewport.z + 1
      cmdwindow.index = index
      pbBottomRight(cmdwindow)
      loop do
        Graphics.update
        Input.update
        cmdwindow.update
        pbUpdate
        if Input.trigger?(Input::BACK)
          pbPlayCancelSE
          ret = -1
          break
        elsif Input.trigger?(Input::USE)
          pbPlayDecisionSE
          ret = cmdwindow.index
          break
        end
      end
    end
    return ret
  end

  def drawMarkings(bitmap, x, y)
    mark_variants = @markingbitmap.bitmap.height / MARK_HEIGHT
    markings = @pokemon.markings
    markrect = Rect.new(0, 0, MARK_WIDTH, MARK_HEIGHT)
    (@markingbitmap.bitmap.width / MARK_WIDTH).times do |i|
      markrect.x = i * MARK_WIDTH
      markrect.y = [(markings[i] || 0), mark_variants - 1].min * MARK_HEIGHT
      bitmap.blt(x + (i * MARK_WIDTH), y, @markingbitmap.bitmap, markrect)
    end
  end

  def drawPage(page)
    if @pokemon.egg?
      drawPageOneEgg
      return
    end
    @sprites["pokemon"].setPokemonBitmap(@pokemon)
    @sprites["pokeicon"].pokemon = @pokemon
    @sprites["itemicon"].item = @pokemon.item_id
    overlay = @sprites["overlay"].bitmap
    overlay.clear
    base   = Color.new(248, 248, 248)
    shadow = Color.new(104, 104, 104)
    # Set background image
    @sprites["background"].setBitmap("Graphics/UI/Summary/bg_#{page}")
    imagepos = []
    # Show the Poké Ball containing the Pokémon
    ballimage = sprintf("Graphics/UI/Summary/icon_ball_%s", @pokemon.poke_ball)
    imagepos.push([ballimage, 7, 30])
    # Show status/fainted/Pokérus infected icon
    status = -1
    if @pokemon.fainted?
      status = GameData::Status.count - 1
    elsif @pokemon.status != :NONE
      status = GameData::Status.get(@pokemon.status).icon_position
    elsif @pokemon.pokerusStage == 1
      status = GameData::Status.count
    end
    if status >= 0
      imagepos.push([_INTL("Graphics/UI/statuses"), 62, 50, 0, 8 * status, 22, 8])
    end
    # Show Pokérus cured icon
    if @pokemon.pokerusStage == 2
      imagepos.push(["Graphics/UI/Summary/icon_pokerus", 88, 50])
    end
    # Show shininess star
    imagepos.push(["Graphics/UI/shiny", 1, 67]) if @pokemon.shiny?
    # Draw all images
    pbDrawImagePositions(overlay, imagepos)
    # Write various bits of text
    pagename = [_INTL("INFO"),
                _INTL("TRAINER MEMO"),
                _INTL("SKILLS"),
                _INTL("MOVES"),
                _INTL("RIBBONS")][page - 1]
    textpos = [
      [pagename, 13, 11, :left, base, shadow],
      [@pokemon.name, 23, 34, :left, base, shadow],
      [@pokemon.level.to_s, 23, 49, :left, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [_INTL("Item"), 33, 162, :left, base, shadow]
    ]
    # Write the held item's name
    if @pokemon.hasItem?
      textpos.push([@pokemon.item.name, 8, 179, :left, Color.new(64, 64, 64), Color.new(176, 176, 176)])
    else
      textpos.push([_INTL("None"), 8, 179, :left, Color.new(192, 200, 208), Color.new(208, 216, 224)])
    end
    # Write the gender symbol
    if @pokemon.male?
      textpos.push([_INTL("♂"), 89, 34, :left, Color.new(24, 112, 216), Color.new(136, 168, 208)])
    elsif @pokemon.female?
      textpos.push([_INTL("♀"), 89, 34, :left, Color.new(248, 56, 32), Color.new(224, 152, 144)])
    end
    # Draw all text
    pbDrawTextPositions(overlay, textpos)
    # Draw the Pokémon's markings
    drawMarkings(overlay, 42, 146)
    # Draw page-specific information
    case page
    when 1 then drawPageOne
    when 2 then drawPageTwo
    when 3 then drawPageThree
    when 4 then drawPageFour
    when 5 then drawPageFive
    end
  end

  def drawPageOne
    overlay = @sprites["overlay"].bitmap
    base   = Color.new(248, 248, 248)
    shadow = Color.new(104, 104, 104)
    dexNumBase   = (@pokemon.shiny?) ? Color.new(248, 56, 32) : Color.new(64, 64, 64)
    dexNumShadow = (@pokemon.shiny?) ? Color.new(224, 152, 144) : Color.new(176, 176, 176)
    # If a Shadow Pokémon, draw the heart gauge area and bar
    if @pokemon.shadowPokemon?
      shadowfract = @pokemon.heart_gauge.to_f / @pokemon.max_gauge_size
      imagepos = [
        ["Graphics/UI/Summary/overlay_shadow", 112, 120],
        ["Graphics/UI/Summary/overlay_shadowbar", 121, 140, 0, 0, (shadowfract * 124).floor, -1]
      ]
      pbDrawImagePositions(overlay, imagepos)
    end
    # Write various bits of text
    textpos = [
      [_INTL("Dex No."), 119, 43, :left, base, shadow],
      [_INTL("Species"), 119, 59, :left, base, shadow],
      [@pokemon.speciesName, 218, 59, :center, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [_INTL("Type"), 119, 75, :left, base, shadow],
      [_INTL("OT"), 119, 91, :left, base, shadow],
      [_INTL("ID No."), 119, 107, :left, base, shadow]
    ]
    # Write the Regional/National Dex number
    dexnum = 0
    dexnumshift = false
    if $player.pokedex.unlocked?(-1)   # National Dex is unlocked
      dexnum = @nationalDexList.index(@pokemon.species_data.species) || 0
      dexnumshift = true if Settings::DEXES_WITH_OFFSETS.include?(-1)
    else
      ($player.pokedex.dexes_count - 1).times do |i|
        next if !$player.pokedex.unlocked?(i)
        num = pbGetRegionalNumber(i, @pokemon.species)
        break if num <= 0
        dexnum = num
        dexnumshift = true if Settings::DEXES_WITH_OFFSETS.include?(i)
        break
      end
    end
    if dexnum <= 0
      textpos.push(["???", 218, 43, :center, dexNumBase, dexNumShadow])
    else
      dexnum -= 1 if dexnumshift
      textpos.push([sprintf("%03d", dexnum), 218, 43, :center, dexNumBase, dexNumShadow])
    end
    # Write Original Trainer's name and ID number
    if @pokemon.owner.name.empty?
      textpos.push([_INTL("RENTAL"), 218, 91, :center, Color.new(64, 64, 64), Color.new(176, 176, 176)])
      textpos.push(["?????", 218, 107, :center, Color.new(64, 64, 64), Color.new(176, 176, 176)])
    else
      ownerbase   = Color.new(64, 64, 64)
      ownershadow = Color.new(176, 176, 176)
      case @pokemon.owner.gender
      when 0
        ownerbase = Color.new(24, 112, 216)
        ownershadow = Color.new(136, 168, 208)
      when 1
        ownerbase = Color.new(248, 56, 32)
        ownershadow = Color.new(224, 152, 144)
      end
      textpos.push([@pokemon.owner.name, 218, 91, :center, ownerbase, ownershadow])
      textpos.push([sprintf("%05d", @pokemon.owner.public_id), 218, 107, :center,
                    Color.new(64, 64, 64), Color.new(176, 176, 176)])
      # Show the language tag of Pokémon from a game in another language
      if @pokemon.language != $player.language && !@pokemon.language_tag.empty?
        textpos.push([@pokemon.language_tag, 254, 107, :right,
                      Color.new(64, 64, 64), Color.new(176, 176, 176)])
      end
    end
    # Write Exp text OR heart gauge message (if a Shadow Pokémon)
    if @pokemon.shadowPokemon?
      textpos.push([_INTL("Heart Gauge"), 119, 123, :left, base, shadow])
      black_text_tag = shadowc3tag(BLACK_TEXT_BASE, BLACK_TEXT_SHADOW)
      heartmessage = [_INTL("The door to its heart is open! Undo the final lock!"),
                      _INTL("The door to its heart is almost fully open."),
                      _INTL("The door to its heart is nearly open."),
                      _INTL("The door to its heart is opening wider."),
                      _INTL("The door to its heart is opening up."),
                      _INTL("The door to its heart is tightly shut.")][@pokemon.heartStage]
      memo = black_text_tag + heartmessage
      drawFormattedTextEx(overlay, 117, 154, 132, memo)
    else
      endexp = @pokemon.growth_rate.minimum_exp_for_level(@pokemon.level + 1)
      textpos.push([_INTL("Exp. Points"), 119, 123, :left, base, shadow])
      textpos.push([@pokemon.exp.to_s_formatted, 244, 139, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)])
      textpos.push([_INTL("To Next Lv."), 119, 155, :left, base, shadow])
      textpos.push([(endexp - @pokemon.exp).to_s_formatted, 244, 171, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)])
    end
    # Draw all text
    pbDrawTextPositions(overlay, textpos)
    # Draw Pokémon type(s)
    @pokemon.types.each_with_index do |type, i|
      type_number = GameData::Type.get(type).icon_position
      type_rect = Rect.new(0, type_number * 14, 32, 14)
      type_x = (@pokemon.types.length == 1) ? 201 : 185 + (33 * i)
      overlay.blt(type_x, 73, @typebitmap.bitmap, type_rect)
    end
    # Draw Exp bar
    if @pokemon.level < GameData::GrowthRate.max_level
      w = @pokemon.exp_fraction * 64
      w = w.round
      pbDrawImagePositions(overlay,
                           [["Graphics/UI/Summary/overlay_exp", 181, 186, 0, 0, w, 3]])
    end
  end

  def drawPageOneEgg
    @sprites["itemicon"].item = @pokemon.item_id
    overlay = @sprites["overlay"].bitmap
    overlay.clear
    base   = Color.new(248, 248, 248)
    shadow = Color.new(104, 104, 104)
    # Set background image
    @sprites["background"].setBitmap("Graphics/UI/Summary/bg_egg")
    imagepos = []
    # Show the Poké Ball containing the Pokémon
    ballimage = sprintf("Graphics/UI/Summary/icon_ball_%s", @pokemon.poke_ball)
    imagepos.push([ballimage, 7, 30])
    # Draw all images
    pbDrawImagePositions(overlay, imagepos)
    # Write various bits of text
    textpos = [
      [_INTL("TRAINER MEMO"), 13, 11, :left, base, shadow],
      [@pokemon.name, 23, 34, :left, base, shadow],
      [_INTL("Item"), 33, 162, :left, base, shadow]
    ]
    # Write the held item's name
    if @pokemon.hasItem?
      textpos.push([@pokemon.item.name, 8, 179, :left, Color.new(64, 64, 64), Color.new(176, 176, 176)])
    else
      textpos.push([_INTL("None"), 8, 179, :left, Color.new(192, 200, 208), Color.new(208, 216, 224)])
    end
    # Draw all text
    pbDrawTextPositions(overlay, textpos)
    red_text_tag = shadowc3tag(RED_TEXT_BASE, RED_TEXT_SHADOW)
    black_text_tag = shadowc3tag(BLACK_TEXT_BASE, BLACK_TEXT_SHADOW)
    memo = ""
    # Write date received
    if @pokemon.timeReceived
      date  = @pokemon.timeReceived.day
      month = pbGetMonthName(@pokemon.timeReceived.mon)
      year  = @pokemon.timeReceived.year
      memo += black_text_tag + _INTL("{1} {2}, {3}", date, month, year) + "\n"
    end
    # Write map name egg was received on
    mapname = pbGetMapNameFromId(@pokemon.obtain_map)
    mapname = @pokemon.obtain_text if @pokemon.obtain_text && !@pokemon.obtain_text.empty?
    if mapname && mapname != ""
      mapname = red_text_tag + mapname + black_text_tag
      memo += black_text_tag + _INTL("A mysterious Pokémon Egg received from {1}.", mapname) + "\n"
    else
      memo += black_text_tag + _INTL("A mysterious Pokémon Egg.") + "\n"
    end
    memo += "\n"   # Empty line
    # Write Egg Watch blurb
    memo += black_text_tag + _INTL("\"The Egg Watch\"") + "\n"
    eggstate = _INTL("It looks like this Egg will take a long time to hatch.")
    eggstate = _INTL("What will hatch from this? It doesn't seem close to hatching.") if @pokemon.steps_to_hatch < 10_200
    eggstate = _INTL("It appears to move occasionally. It may be close to hatching.") if @pokemon.steps_to_hatch < 2550
    eggstate = _INTL("Sounds can be heard coming from inside! It will hatch soon!") if @pokemon.steps_to_hatch < 1275
    memo += black_text_tag + eggstate
    # Draw all text
    drawFormattedTextEx(overlay, 116, 43, 134, memo)
    # Draw the Pokémon's markings
    drawMarkings(overlay, 42, 146)
  end

  def drawPageTwo
    overlay = @sprites["overlay"].bitmap
    red_text_tag = shadowc3tag(RED_TEXT_BASE, RED_TEXT_SHADOW)
    black_text_tag = shadowc3tag(BLACK_TEXT_BASE, BLACK_TEXT_SHADOW)
    memo = ""
    # Write nature
    showNature = !@pokemon.shadowPokemon? || @pokemon.heartStage <= 3
    if showNature
      nature_name = red_text_tag + @pokemon.nature.name + black_text_tag
      memo += _INTL("{1} nature.", nature_name) + "\n"
    end
    # Write date received
    if @pokemon.timeReceived
      date  = @pokemon.timeReceived.day
      month = pbGetMonthName(@pokemon.timeReceived.mon)
      year  = @pokemon.timeReceived.year
      memo += black_text_tag + _INTL("{1} {2}, {3}", date, month, year) + "\n"
    end
    # Write map name Pokémon was received on
    mapname = pbGetMapNameFromId(@pokemon.obtain_map)
    mapname = @pokemon.obtain_text if @pokemon.obtain_text && !@pokemon.obtain_text.empty?
    mapname = _INTL("Faraway place") if nil_or_empty?(mapname)
    memo += red_text_tag + mapname + "\n"
    # Write how Pokémon was obtained
    mettext = [
      _INTL("Met at Lv. {1}.", @pokemon.obtain_level),
      _INTL("Egg received."),
      _INTL("Traded at Lv. {1}.", @pokemon.obtain_level),
      "",
      _INTL("Had a fateful encounter at Lv. {1}.", @pokemon.obtain_level)
    ][@pokemon.obtain_method]
    memo += black_text_tag + mettext + "\n" if mettext && mettext != ""
    # If Pokémon was hatched, write when and where it hatched
    if @pokemon.obtain_method == 1
      if @pokemon.timeEggHatched
        date  = @pokemon.timeEggHatched.day
        month = pbGetMonthName(@pokemon.timeEggHatched.mon)
        year  = @pokemon.timeEggHatched.year
        memo += black_text_tag + _INTL("{1} {2}, {3}", date, month, year) + "\n"
      end
      mapname = pbGetMapNameFromId(@pokemon.hatched_map)
      mapname = _INTL("Faraway place") if nil_or_empty?(mapname)
      memo += red_text_tag + mapname + "\n"
      memo += black_text_tag + _INTL("Egg hatched.") + "\n"
    else
      memo += "\n"   # Empty line
    end
    # Write characteristic
    if showNature
      best_stat = nil
      best_iv = 0
      stats_order = [:HP, :ATTACK, :DEFENSE, :SPEED, :SPECIAL_ATTACK, :SPECIAL_DEFENSE]
      start_point = @pokemon.personalID % stats_order.length   # Tiebreaker
      stats_order.length.times do |i|
        stat = stats_order[(i + start_point) % stats_order.length]
        if !best_stat || @pokemon.iv[stat] > @pokemon.iv[best_stat]
          best_stat = stat
          best_iv = @pokemon.iv[best_stat]
        end
      end
      characteristics = {
        :HP              => [_INTL("Loves to eat."),
                             _INTL("Takes plenty of siestas."),
                             _INTL("Nods off a lot."),
                             _INTL("Scatters things often."),
                             _INTL("Likes to relax.")],
        :ATTACK          => [_INTL("Proud of its power."),
                             _INTL("Likes to thrash about."),
                             _INTL("A little quick tempered."),
                             _INTL("Likes to fight."),
                             _INTL("Quick tempered.")],
        :DEFENSE         => [_INTL("Sturdy body."),
                             _INTL("Capable of taking hits."),
                             _INTL("Highly persistent."),
                             _INTL("Good endurance."),
                             _INTL("Good perseverance.")],
        :SPECIAL_ATTACK  => [_INTL("Highly curious."),
                             _INTL("Mischievous."),
                             _INTL("Thoroughly cunning."),
                             _INTL("Often lost in thought."),
                             _INTL("Very finicky.")],
        :SPECIAL_DEFENSE => [_INTL("Strong willed."),
                             _INTL("Somewhat vain."),
                             _INTL("Strongly defiant."),
                             _INTL("Hates to lose."),
                             _INTL("Somewhat stubborn.")],
        :SPEED           => [_INTL("Likes to run."),
                             _INTL("Alert to sounds."),
                             _INTL("Impetuous and silly."),
                             _INTL("Somewhat of a clown."),
                             _INTL("Quick to flee.")]
      }
      memo += black_text_tag + characteristics[best_stat][best_iv % 5] + "\n"
    end
    # Write all text
    drawFormattedTextEx(overlay, 116, 43, 134, memo)
  end

  def drawPageThree
    overlay = @sprites["overlay"].bitmap
    base   = Color.new(248, 248, 248)
    shadow = Color.new(104, 104, 104)
    # Determine which stats are boosted and lowered by the Pokémon's nature
    statshadows = {}
    GameData::Stat.each_main { |s| statshadows[s.id] = shadow }
    if !@pokemon.shadowPokemon? || @pokemon.heartStage <= 3
      @pokemon.nature_for_stats.stat_changes.each do |change|
        statshadows[change[0]] = Color.new(136, 96, 72) if change[1] > 0
        statshadows[change[0]] = Color.new(64, 120, 152) if change[1] < 0
      end
    end
    # Write various bits of text
    textpos = [
      [_INTL("HP"), 146, 41, :center, base, statshadows[:HP]],
      [sprintf("%d/%d", @pokemon.hp, @pokemon.totalhp), 231, 41, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [_INTL("Attack"), 124, 63, :left, base, statshadows[:ATTACK]],
      [@pokemon.attack.to_s, 228, 63, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [_INTL("Defense"), 124, 79, :left, base, statshadows[:DEFENSE]],
      [@pokemon.defense.to_s, 228, 79, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [_INTL("Sp. Atk"), 124, 95, :left, base, statshadows[:SPECIAL_ATTACK]],
      [@pokemon.spatk.to_s, 228, 95, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [_INTL("Sp. Def"), 124, 111, :left, base, statshadows[:SPECIAL_DEFENSE]],
      [@pokemon.spdef.to_s, 228, 111, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [_INTL("Speed"), 124, 127, :left, base, statshadows[:SPEED]],
      [@pokemon.speed.to_s, 228, 127, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [_INTL("Ability"), 112, 145, :left, base, shadow]
    ]
    # Draw ability name and description
    ability = @pokemon.ability
    if ability
      textpos.push([ability.name, 181, 145, :left, Color.new(64, 64, 64), Color.new(176, 176, 176)])
      drawTextEx(overlay, 112, 161, 141, 2, ability.description, Color.new(64, 64, 64), Color.new(176, 176, 176))
    end
    # Draw all text
    pbDrawTextPositions(overlay, textpos)
    # Draw HP bar
    if @pokemon.hp > 0
      w = @pokemon.hp * 48 / @pokemon.totalhp.to_f
      w = 1 if w < 1
      w = w.round
      hpzone = 0
      hpzone = 1 if @pokemon.hp <= (@pokemon.totalhp / 2).floor
      hpzone = 2 if @pokemon.hp <= (@pokemon.totalhp / 4).floor
      imagepos = [
        ["Graphics/UI/Summary/overlay_hp", 180, 55, 0, hpzone * 3, w, 3]
      ]
      pbDrawImagePositions(overlay, imagepos)
    end
  end

  def drawPageFour
    overlay = @sprites["overlay"].bitmap
    moveBase   = Color.new(64, 64, 64)
    moveShadow = Color.new(176, 176, 176)
    ppBase   = [moveBase,                # More than 1/2 of total PP
                Color.new(248, 192, 0),    # 1/2 of total PP or less
                Color.new(248, 136, 32),   # 1/4 of total PP or less
                Color.new(248, 72, 72)]    # Zero PP
    ppShadow = [moveShadow,             # More than 1/2 of total PP
                Color.new(144, 104, 0),   # 1/2 of total PP or less
                Color.new(144, 72, 24),   # 1/4 of total PP or less
                Color.new(136, 48, 48)]   # Zero PP
    @sprites["pokemon"].visible  = true
    @sprites["pokeicon"].visible = false
    @sprites["itemicon"].visible = true
    textpos  = []
    imagepos = []
    # Write move names, types and PP amounts for each known move
    yPos = 52
    Pokemon::MAX_MOVES.times do |i|
      move = @pokemon.moves[i]
      if move
        type_number = GameData::Type.get(move.display_type(@pokemon)).icon_position
        imagepos.push([_INTL("Graphics/UI/types"), 124, yPos - 2, 0, type_number * 14, 32, 14])
        textpos.push([move.name, 158, yPos, :left, moveBase, moveShadow])
        if move.total_pp > 0
          textpos.push([_INTL("PP"), 171, yPos + 16, :left, moveBase, moveShadow])
          ppfraction = 0
          if move.pp == 0
            ppfraction = 3
          elsif move.pp * 4 <= move.total_pp
            ppfraction = 2
          elsif move.pp * 2 <= move.total_pp
            ppfraction = 1
          end
          textpos.push([sprintf("%d/%d", move.pp, move.total_pp), 230, yPos + 16, :right, ppBase[ppfraction], ppShadow[ppfraction]])
        end
      else
        textpos.push(["-", 158, yPos, :left, moveBase, moveShadow])
        textpos.push(["--", 221, yPos + 16, :right, moveBase, moveShadow])
      end
      yPos += 32
    end
    # Draw all text and images
    pbDrawTextPositions(overlay, textpos)
    pbDrawImagePositions(overlay, imagepos)
  end

  def drawPageFourSelecting(move_to_learn)
    overlay = @sprites["overlay"].bitmap
    overlay.clear
    base   = Color.new(248, 248, 248)
    shadow = Color.new(104, 104, 104)
    moveBase   = Color.new(64, 64, 64)
    moveShadow = Color.new(176, 176, 176)
    ppBase   = [moveBase,                # More than 1/2 of total PP
                Color.new(248, 192, 0),    # 1/2 of total PP or less
                Color.new(248, 136, 32),   # 1/4 of total PP or less
                Color.new(248, 72, 72)]    # Zero PP
    ppShadow = [moveShadow,             # More than 1/2 of total PP
                Color.new(144, 104, 0),   # 1/2 of total PP or less
                Color.new(144, 72, 24),   # 1/4 of total PP or less
                Color.new(136, 48, 48)]   # Zero PP
    # Set background image
    if move_to_learn
      @sprites["background"].setBitmap("Graphics/UI/Summary/bg_learnmove")
    else
      @sprites["background"].setBitmap("Graphics/UI/Summary/bg_movedetail")
    end
    # Write various bits of text
    textpos = [
      [_INTL("MOVES"), 13, 11, :left, base, shadow],
      [_INTL("CATEGORY"), 10, 64, :left, base, shadow],
      [_INTL("POWER"), 10, 80, :left, base, shadow],
      [_INTL("ACCURACY"), 10, 96, :left, base, shadow]
    ]
    imagepos = []
    # Write move names, types and PP amounts for each known move
    yPos = 52
    yPos -= 38 if move_to_learn
    limit = (move_to_learn) ? Pokemon::MAX_MOVES + 1 : Pokemon::MAX_MOVES
    limit.times do |i|
      move = @pokemon.moves[i]
      if i == Pokemon::MAX_MOVES
        move = move_to_learn
        yPos += 10
      end
      if move
        type_number = GameData::Type.get(move.display_type(@pokemon)).icon_position
        imagepos.push([_INTL("Graphics/UI/types"), 124, yPos - 2, 0, type_number * 14, 32, 14])
        textpos.push([move.name, 158, yPos, :left, moveBase, moveShadow])
        if move.total_pp > 0
          textpos.push([_INTL("PP"), 171, yPos + 16, :left, moveBase, moveShadow])
          ppfraction = 0
          if move.pp == 0
            ppfraction = 3
          elsif move.pp * 4 <= move.total_pp
            ppfraction = 2
          elsif move.pp * 2 <= move.total_pp
            ppfraction = 1
          end
          textpos.push([sprintf("%d/%d", move.pp, move.total_pp), 230, yPos + 16, :right,
                        ppBase[ppfraction], ppShadow[ppfraction]])
        end
      else
        textpos.push(["-", 158, yPos, :left, moveBase, moveShadow])
        textpos.push(["--", 221, yPos + 16, :right, moveBase, moveShadow])
      end
      yPos += 32
    end
    # Draw all text and images
    pbDrawTextPositions(overlay, textpos)
    pbDrawImagePositions(overlay, imagepos)
    # Draw Pokémon's type icon(s)
    @pokemon.types.each_with_index do |type, i|
      type_number = GameData::Type.get(type).icon_position
      type_rect = Rect.new(0, type_number * 14, 32, 14)
      type_x = (@pokemon.types.length == 1) ? 65 : 48 + (35 * i)
      overlay.blt(type_x, 39, @typebitmap.bitmap, type_rect)
    end
  end

  def drawSelectedMove(move_to_learn, selected_move)
    # Draw all of page four, except selected move's details
    drawPageFourSelecting(move_to_learn)
    # Set various values
    overlay = @sprites["overlay"].bitmap
    base = Color.new(64, 64, 64)
    shadow = Color.new(176, 176, 176)
    @sprites["pokemon"].visible = false if @sprites["pokemon"]
    @sprites["pokeicon"].pokemon = @pokemon
    @sprites["pokeicon"].visible = true
    @sprites["itemicon"].visible = false if @sprites["itemicon"]
    textpos = []
    # Write power and accuracy values for selected move
    case selected_move.display_damage(@pokemon)
    when 0 then textpos.push(["---", 108, 80, :right, base, shadow])   # Status move
    when 1 then textpos.push(["???", 108, 80, :right, base, shadow])   # Variable power move
    else        textpos.push([selected_move.display_damage(@pokemon).to_s, 108, 80, :right, base, shadow])
    end
    if selected_move.display_accuracy(@pokemon) == 0
      textpos.push(["---", 108, 96, :right, base, shadow])
    else
      textpos.push(["#{selected_move.display_accuracy(@pokemon)}%", 108 + overlay.text_size("%").width, 96, :right, base, shadow])
    end
    # Draw all text
    pbDrawTextPositions(overlay, textpos)
    # Draw selected move's damage category icon
    imagepos = [["Graphics/UI/category", 83, 62, 0, selected_move.display_category(@pokemon) * 14, 32, 14]]
    pbDrawImagePositions(overlay, imagepos)
    # Draw selected move's description
    drawTextEx(overlay, 2, 112, 115, 5, selected_move.description, base, shadow)
  end

  # @param index [Integer] the index of a slot on the ribbons page
  # @return [Array<Integer>] the x and y of the slot's top left corner
  def self.ribbon_slot_position(index)
    return [RIBBON_GRID_X + (RIBBON_SLOT_SIZE * (index % RIBBON_COLUMNS)),
            RIBBON_GRID_Y + (RIBBON_SLOT_SIZE * (index / RIBBON_COLUMNS))]
  end

  # @return [Integer] the size of one icon in Graphics/UI/Summary/ribbons
  def ribbon_icon_size
    if !@ribbon_icon_size
      bmp = RPG::Cache.load_bitmap("", "Graphics/UI/Summary/ribbons")
      @ribbon_icon_size = bmp.width / 8
    end
    return @ribbon_icon_size
  end

  # Repaints the ribbon panel of bg_5 and draws empty slots in it, using
  # colours taken from bg_5 (see RIBBON_DRAW_SLOTS).
  # @param overlay [Bitmap]
  def drawRibbonSlots(overlay)
    bg = @sprites["background"].bitmap
    return if !bg
    panel_color = bg.get_pixel(*RIBBON_PANEL_COLOR_POINT)
    slot_color  = bg.get_pixel(*RIBBON_SLOT_COLOR_POINT)
    overlay.fill_rect(*RIBBON_PANEL_RECT, panel_color)
    size = RIBBON_SLOT_SIZE - 2
    RIBBONS_PER_PAGE.times do |i|
      x, y = PokemonSummary_Scene.ribbon_slot_position(i)
      # A square with its corners cut off
      overlay.fill_rect(x + 3, y + 1, size - 4, size, slot_color)
      overlay.fill_rect(x + 1, y + 3, size, size - 4, slot_color)
      overlay.fill_rect(x + 2, y + 2, size - 2, size - 2, slot_color)
    end
  end

  def drawPageFive
    overlay = @sprites["overlay"].bitmap
    @sprites["uparrow"].visible   = false
    @sprites["downarrow"].visible = false
    drawRibbonSlots(overlay) if RIBBON_DRAW_SLOTS
    # Write various bits of text
    textpos = [
      [_INTL("Ribbons/Marks:"), 117, 169, :left, Color.new(64, 64, 64), Color.new(176, 176, 176)],
      [@pokemon.numRibbons.to_s, 247, 169, :right, Color.new(64, 64, 64), Color.new(176, 176, 176)]
    ]
    # Draw all text
    pbDrawTextPositions(overlay, textpos)
    # Show all ribbons on this page
    imagepos = []
    icon_size = ribbon_icon_size
    first = @ribbonOffset * RIBBON_COLUMNS
    RIBBONS_PER_PAGE.times do |coord|
      ribbon_id = @pokemon.ribbons[first + coord]
      break if !ribbon_id
      ribn = GameData::Ribbon.get(ribbon_id).icon_position
      x, y = PokemonSummary_Scene.ribbon_slot_position(coord)
      offset = (RIBBON_SLOT_SIZE - icon_size) / 2
      imagepos.push(["Graphics/UI/Summary/ribbons", x + offset, y + offset,
                     icon_size * (ribn % 8), icon_size * (ribn / 8), icon_size, icon_size])
    end
    pbDrawImagePositions(overlay, imagepos)
    # Mark the ribbon/mark whose title is affixed with a small flag
    RIBBONS_PER_PAGE.times do |coord|
      ribbon_id = @pokemon.ribbons[first + coord]
      break if !ribbon_id
      next if ribbon_id != @pokemon.affixed_ribbon
      x, y = PokemonSummary_Scene.ribbon_slot_position(coord)
      x += RIBBON_SLOT_SIZE - 10
      y += 2
      overlay.fill_rect(x, y, 8, 8, Color.new(64, 64, 64))
      overlay.fill_rect(x + 1, y + 1, 6, 6, RibbonSelectionSprite::CURSOR_COLOR)
    end
  end

  def drawSelectedRibbon(ribbonid)
    # Draw all of page five
    drawPage(5)
    # Set various values
    overlay = @sprites["overlay"].bitmap
    base   = Color.new(64, 64, 64)
    shadow = Color.new(176, 176, 176)
    nameBase   = Color.new(248, 248, 248)
    nameShadow = Color.new(104, 104, 104)
    # Get data for selected ribbon
    ribbon_data = (ribbonid) ? GameData::Ribbon.get(ribbonid) : nil
    name = (ribbon_data) ? ribbon_data.name : ""
    desc = (ribbon_data) ? ribbon_data.description : ""
    kind = ""
    if ribbon_data
      kind = (ribbon_data.mark?) ? _INTL("Mark") : _INTL("Ribbon")
      rank = @pokemon.ribbonRank(ribbonid)
      kind = _INTL("{1} Rank {2}", kind, rank) if ribbon_data.max_rank > 1
    end
    # Draw the description box
    imagepos = [
      ["Graphics/UI/Summary/overlay_ribbon", 4, 140]
    ]
    pbDrawImagePositions(overlay, imagepos)
    # Draw name and kind of selected ribbon
    textpos = [
      [name, 9, 146, :left, nameBase, nameShadow],
      [kind, 247, 146, :right, nameBase, nameShadow]
    ]
    pbDrawTextPositions(overlay, textpos)
    # Draw selected ribbon's description
    drawTextEx(overlay, 9, 162, 240, 2, desc, base, shadow)
  end

  def pbGoToPrevious
    newindex = @partyindex
    while newindex > 0
      newindex -= 1
      if @party[newindex] && (@page == 1 || !@party[newindex].egg?)
        @partyindex = newindex
        break
      end
    end
  end

  def pbGoToNext
    newindex = @partyindex
    while newindex < @party.length - 1
      newindex += 1
      if @party[newindex] && (@page == 1 || !@party[newindex].egg?)
        @partyindex = newindex
        break
      end
    end
  end

  def pbChangePokemon
    @pokemon = @party[@partyindex]
    @sprites["pokemon"].setPokemonBitmap(@pokemon)
    @sprites["itemicon"].item = @pokemon.item_id
    pbSEStop
    @pokemon.play_cry
  end

  def pbMoveSelection
    @sprites["movesel"].visible = true
    @sprites["movesel"].index   = 0
    selmove    = 0
    oldselmove = 0
    switching = false
    drawSelectedMove(nil, @pokemon.moves[selmove])
    loop do
      Graphics.update
      Input.update
      pbUpdate
      if @sprites["movepresel"].index == @sprites["movesel"].index
        @sprites["movepresel"].z = @sprites["movesel"].z + 1
      else
        @sprites["movepresel"].z = @sprites["movesel"].z
      end
      if Input.trigger?(Input::BACK)
        (switching) ? pbPlayCancelSE : pbPlayCloseMenuSE
        break if !switching
        @sprites["movepresel"].visible = false
        switching = false
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        if selmove == Pokemon::MAX_MOVES
          break if !switching
          @sprites["movepresel"].visible = false
          switching = false
        elsif !@pokemon.shadowPokemon?
          if switching
            tmpmove                    = @pokemon.moves[oldselmove]
            @pokemon.moves[oldselmove] = @pokemon.moves[selmove]
            @pokemon.moves[selmove]    = tmpmove
            @sprites["movepresel"].visible = false
            switching = false
            drawSelectedMove(nil, @pokemon.moves[selmove])
          else
            @sprites["movepresel"].index   = selmove
            @sprites["movepresel"].visible = true
            oldselmove = selmove
            switching = true
          end
        end
      elsif Input.trigger?(Input::UP)
        selmove -= 1
        if selmove < Pokemon::MAX_MOVES && selmove >= @pokemon.numMoves
          selmove = @pokemon.numMoves - 1
        end
        selmove = 0 if selmove >= Pokemon::MAX_MOVES
        selmove = @pokemon.numMoves - 1 if selmove < 0
        @sprites["movesel"].index = selmove
        pbPlayCursorSE
        drawSelectedMove(nil, @pokemon.moves[selmove])
      elsif Input.trigger?(Input::DOWN)
        selmove += 1
        selmove = 0 if selmove < Pokemon::MAX_MOVES && selmove >= @pokemon.numMoves
        selmove = 0 if selmove >= Pokemon::MAX_MOVES
        selmove = Pokemon::MAX_MOVES if selmove < 0
        @sprites["movesel"].index = selmove
        pbPlayCursorSE
        drawSelectedMove(nil, @pokemon.moves[selmove])
      end
    end
    @sprites["movesel"].visible = false
  end

  # Lets the player look through this Pokémon's ribbons and marks, affix one's
  # title, and move them around.
  def pbRibbonSelection
    cols = RIBBON_COLUMNS
    rows = RIBBON_ROWS
    @sprites["ribbonsel"].visible = true
    @sprites["ribbonsel"].index   = 0
    selribbon    = @ribbonOffset * cols
    oldselribbon = selribbon
    switching = false
    numRibbons = @pokemon.ribbons.length
    numRows    = [(numRibbons + cols - 1) / cols, rows].max
    drawSelectedRibbon(@pokemon.ribbons[selribbon])
    loop do
      @sprites["uparrow"].visible   = (@ribbonOffset > 0)
      @sprites["downarrow"].visible = (@ribbonOffset < numRows - rows)
      Graphics.update
      Input.update
      pbUpdate
      if @sprites["ribbonpresel"].index == @sprites["ribbonsel"].index
        @sprites["ribbonpresel"].z = @sprites["ribbonsel"].z + 1
      else
        @sprites["ribbonpresel"].z = @sprites["ribbonsel"].z
      end
      hasMovedCursor = false
      if Input.trigger?(Input::BACK)
        (switching) ? pbPlayCancelSE : pbPlayCloseMenuSE
        break if !switching
        @sprites["ribbonpresel"].visible = false
        switching = false
      elsif Input.trigger?(Input::USE)
        if switching
          pbPlayDecisionSE
          # Move the ribbon being moved to the selected place
          if oldselribbon != selribbon
            ribbons = @pokemon.ribbons
            moved = ribbons.delete_at(oldselribbon)
            ribbons.insert([selribbon, ribbons.length].min, moved)
            if selribbon >= numRibbons
              selribbon = numRibbons - 1
              hasMovedCursor = true
            end
          end
          @sprites["ribbonpresel"].visible = false
          switching = false
          drawSelectedRibbon(@pokemon.ribbons[selribbon])
        elsif @pokemon.ribbons[selribbon]
          pbPlayDecisionSE
          case pbRibbonOptions(@pokemon.ribbons[selribbon])
          when :move
            @sprites["ribbonpresel"].index = selribbon - (@ribbonOffset * cols)
            oldselribbon = selribbon
            @sprites["ribbonpresel"].visible = true
            switching = true
          end
          drawSelectedRibbon(@pokemon.ribbons[selribbon])
        end
      elsif Input.trigger?(Input::UP)
        selribbon -= cols
        selribbon += numRows * cols if selribbon < 0
        hasMovedCursor = true
        pbPlayCursorSE
      elsif Input.trigger?(Input::DOWN)
        selribbon += cols
        selribbon -= numRows * cols if selribbon >= numRows * cols
        hasMovedCursor = true
        pbPlayCursorSE
      elsif Input.trigger?(Input::LEFT)
        selribbon -= 1
        selribbon += cols if selribbon % cols == cols - 1
        hasMovedCursor = true
        pbPlayCursorSE
      elsif Input.trigger?(Input::RIGHT)
        selribbon += 1
        selribbon -= cols if selribbon % cols == 0
        hasMovedCursor = true
        pbPlayCursorSE
      end
      next if !hasMovedCursor
      @ribbonOffset = selribbon / cols if selribbon < @ribbonOffset * cols
      @ribbonOffset = (selribbon / cols) - (rows - 1) if selribbon >= (@ribbonOffset + rows) * cols
      @ribbonOffset = 0 if @ribbonOffset < 0
      @ribbonOffset = numRows - rows if @ribbonOffset > numRows - rows
      @sprites["ribbonsel"].index    = selribbon - (@ribbonOffset * cols)
      @sprites["ribbonpresel"].index = oldselribbon - (@ribbonOffset * cols)
      drawSelectedRibbon(@pokemon.ribbons[selribbon])
    end
    @sprites["ribbonsel"].visible = false
  end

  # Shows the options for a ribbon/mark (affixing its title, moving it).
  # @param ribbon_id [Symbol] the selected ribbon/mark
  # @return [Symbol, nil] :move if the player chose to move it, otherwise nil
  def pbRibbonOptions(ribbon_id)
    ribbon_data = GameData::Ribbon.get(ribbon_id)
    commands = []
    cmds = []
    if ribbon_data.has_title? && !@pokemon.shadowPokemon?
      if @pokemon.affixed_ribbon == ribbon_id
        commands.push(_INTL("Remove title"))
        cmds.push(:remove_title)
      else
        commands.push(_INTL("Set as title"))
        cmds.push(:set_title)
      end
    end
    commands.push(_INTL("Move"))
    cmds.push(:move)
    commands.push(_INTL("Cancel"))
    cmds.push(nil)
    loop do
      cmd = pbShowCommands(commands)
      return nil if cmd < 0
      case cmds[cmd]
      when :set_title
        old_ribbon = @pokemon.affixed_ribbon
        @pokemon.affixed_ribbon = ribbon_id
        new_name = @pokemon.name_with_title(false)
        if !pbConfirm(_INTL("Should {1} be known as {2}?", @pokemon.name, new_name))
          @pokemon.affixed_ribbon = old_ribbon
          next
        end
        pbDisplay(_INTL("{1} will now be known as {2}!", @pokemon.name, new_name))
        return nil
      when :remove_title
        next if !pbConfirm(_INTL("Remove {1}'s title?", @pokemon.name))
        @pokemon.affixed_ribbon = nil
        pbDisplay(_INTL("{1} no longer has a title.", @pokemon.name))
        return nil
      end
      return cmds[cmd]
    end
  end

  def pbMarking(pokemon)
    @sprites["markingbg"].visible      = true
    @sprites["markingoverlay"].visible = true
    @sprites["markingsel"].visible     = true
    base   = Color.new(248, 248, 248)
    shadow = Color.new(104, 104, 104)
    ret = pokemon.markings.clone
    markings = pokemon.markings.clone
    mark_variants = @markingbitmap.bitmap.height / MARK_HEIGHT
    index = 0
    redraw = true
    markrect = Rect.new(0, 0, MARK_WIDTH, MARK_HEIGHT)
    loop do
      # Redraw the markings and text
      if redraw
        @sprites["markingoverlay"].bitmap.clear
        (@markingbitmap.bitmap.width / MARK_WIDTH).times do |i|
          markrect.x = i * MARK_WIDTH
          markrect.y = [(markings[i] || 0), mark_variants - 1].min * MARK_HEIGHT
          @sprites["markingoverlay"].bitmap.blt(150 + (29 * (i % 3)), 77 + (25 * (i / 3)),
                                                @markingbitmap.bitmap, markrect)
        end
        textpos = [
          [_INTL("Mark {1}", pokemon.name), 183, 51, :center, base, shadow],
          [_INTL("OK"), 183, 127, :center, base, shadow],
          [_INTL("Cancel"), 183, 152, :center, base, shadow]
        ]
        pbDrawTextPositions(@sprites["markingoverlay"].bitmap, textpos)
        redraw = false
      end
      # Reposition the cursor
      @sprites["markingsel"].x = 142 + (29 * (index % 3))
      @sprites["markingsel"].y = 72 + (25 * (index / 3))
      case index
      when 6   # OK
        @sprites["markingsel"].x = 142
        @sprites["markingsel"].y = 122
        @sprites["markingsel"].src_rect.y = @sprites["markingsel"].bitmap.height / 2
      when 7   # Cancel
        @sprites["markingsel"].x = 142
        @sprites["markingsel"].y = 147
        @sprites["markingsel"].src_rect.y = @sprites["markingsel"].bitmap.height / 2
      else
        @sprites["markingsel"].src_rect.y = 0
      end
      Graphics.update
      Input.update
      pbUpdate
      if Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        break
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        case index
        when 6   # OK
          ret = markings
          break
        when 7   # Cancel
          break
        else
          markings[index] = ((markings[index] || 0) + 1) % mark_variants
          redraw = true
        end
      elsif Input.trigger?(Input::ACTION)
        if index < 6 && markings[index] > 0
          pbPlayDecisionSE
          markings[index] = 0
          redraw = true
        end
      elsif Input.trigger?(Input::UP)
        if index == 7
          index = 6
        elsif index == 6
          index = 4
        elsif index < 3
          index = 7
        else
          index -= 3
        end
        pbPlayCursorSE
      elsif Input.trigger?(Input::DOWN)
        if index == 7
          index = 1
        elsif index == 6
          index = 7
        elsif index >= 3
          index = 6
        else
          index += 3
        end
        pbPlayCursorSE
      elsif Input.trigger?(Input::LEFT)
        if index < 6
          index -= 1
          index += 3 if index % 3 == 2
          pbPlayCursorSE
        end
      elsif Input.trigger?(Input::RIGHT)
        if index < 6
          index += 1
          index -= 3 if index % 3 == 0
          pbPlayCursorSE
        end
      end
    end
    @sprites["markingbg"].visible      = false
    @sprites["markingoverlay"].visible = false
    @sprites["markingsel"].visible     = false
    if pokemon.markings != ret
      pokemon.markings = ret
      return true
    end
    return false
  end

  def pbOptions
    dorefresh = false
    commands = []
    cmdGiveItem = -1
    cmdTakeItem = -1
    cmdPokedex  = -1
    cmdMark     = -1
    if !@pokemon.egg?
      commands[cmdGiveItem = commands.length] = _INTL("Give item")
      commands[cmdTakeItem = commands.length] = _INTL("Take item") if @pokemon.hasItem?
      commands[cmdPokedex = commands.length]  = _INTL("View Pokédex") if $player.has_pokedex
    end
    commands[cmdMark = commands.length]       = _INTL("Mark")
    commands[commands.length]                 = _INTL("Cancel")
    command = pbShowCommands(commands)
    if cmdGiveItem >= 0 && command == cmdGiveItem
      item = nil
      pbFadeOutIn do
        scene = PokemonBag_Scene.new
        screen = PokemonBagScreen.new(scene, $bag)
        item = screen.pbChooseItemScreen(proc { |itm| GameData::Item.get(itm).can_hold? })
      end
      dorefresh = pbGiveItemToPokemon(item, @pokemon, self, @partyindex) if item
    elsif cmdTakeItem >= 0 && command == cmdTakeItem
      dorefresh = pbTakeItemFromPokemon(@pokemon, self)
    elsif cmdPokedex >= 0 && command == cmdPokedex
      $player.pokedex.register_last_seen(@pokemon)
      pbFadeOutIn do
        scene = PokemonPokedexInfo_Scene.new
        screen = PokemonPokedexInfoScreen.new(scene)
        screen.pbStartSceneSingle(@pokemon.species)
      end
      dorefresh = true
    elsif cmdMark >= 0 && command == cmdMark
      dorefresh = pbMarking(@pokemon)
    end
    return dorefresh
  end

  def pbChooseMoveToForget(move_to_learn)
    new_move = (move_to_learn) ? Pokemon::Move.new(move_to_learn) : nil
    selmove = 0
    maxmove = (new_move) ? Pokemon::MAX_MOVES : Pokemon::MAX_MOVES - 1
    loop do
      Graphics.update
      Input.update
      pbUpdate
      if Input.trigger?(Input::BACK)
        selmove = Pokemon::MAX_MOVES
        pbPlayCloseMenuSE if new_move
        break
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        break
      elsif Input.trigger?(Input::UP)
        selmove -= 1
        selmove = maxmove if selmove < 0
        if selmove < Pokemon::MAX_MOVES && selmove >= @pokemon.numMoves
          selmove = @pokemon.numMoves - 1
        end
        @sprites["movesel"].index = selmove
        selected_move = (selmove == Pokemon::MAX_MOVES) ? new_move : @pokemon.moves[selmove]
        drawSelectedMove(new_move, selected_move)
      elsif Input.trigger?(Input::DOWN)
        selmove += 1
        selmove = 0 if selmove > maxmove
        if selmove < Pokemon::MAX_MOVES && selmove >= @pokemon.numMoves
          selmove = (new_move) ? maxmove : 0
        end
        @sprites["movesel"].index = selmove
        selected_move = (selmove == Pokemon::MAX_MOVES) ? new_move : @pokemon.moves[selmove]
        drawSelectedMove(new_move, selected_move)
      end
    end
    return (selmove == Pokemon::MAX_MOVES) ? -1 : selmove
  end

  def pbScene
    @pokemon.play_cry
    loop do
      Graphics.update
      Input.update
      pbUpdate
      dorefresh = false
      if Input.trigger?(Input::ACTION)
        pbSEStop
        @pokemon.play_cry
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        break
      elsif Input.trigger?(Input::USE)
        if @page == 4
          pbPlayDecisionSE
          pbMoveSelection
          dorefresh = true
        elsif @page == 5
          pbPlayDecisionSE
          pbRibbonSelection
          dorefresh = true
        elsif !@inbattle
          pbPlayDecisionSE
          dorefresh = pbOptions
        end
      elsif Input.trigger?(Input::UP) && @partyindex > 0
        oldindex = @partyindex
        pbGoToPrevious
        if @partyindex != oldindex
          pbChangePokemon
          @ribbonOffset = 0
          dorefresh = true
        end
      elsif Input.trigger?(Input::DOWN) && @partyindex < @party.length - 1
        oldindex = @partyindex
        pbGoToNext
        if @partyindex != oldindex
          pbChangePokemon
          @ribbonOffset = 0
          dorefresh = true
        end
      elsif Input.trigger?(Input::LEFT) && !@pokemon.egg?
        oldpage = @page
        @page -= 1
        @page = 1 if @page < 1
        @page = 5 if @page > 5
        if @page != oldpage   # Move to next page
          pbSEPlay("GUI summary change page")
          @ribbonOffset = 0
          dorefresh = true
        end
      elsif Input.trigger?(Input::RIGHT) && !@pokemon.egg?
        oldpage = @page
        @page += 1
        @page = 1 if @page < 1
        @page = 5 if @page > 5
        if @page != oldpage   # Move to next page
          pbSEPlay("GUI summary change page")
          @ribbonOffset = 0
          dorefresh = true
        end
      end
      drawPage(@page) if dorefresh
    end
    return @partyindex
  end
end

#===============================================================================
#
#===============================================================================
class PokemonSummaryScreen
  def initialize(scene, inbattle = false)
    @scene = scene
    @inbattle = inbattle
  end

  def pbStartScreen(party, partyindex)
    @scene.pbStartScene(party, partyindex, @inbattle)
    ret = @scene.pbScene
    @scene.pbEndScene
    return ret
  end

  def pbStartForgetScreen(party, partyindex, move_to_learn)
    ret = -1
    @scene.pbStartForgetScene(party, partyindex, move_to_learn)
    loop do
      ret = @scene.pbChooseMoveToForget(move_to_learn)
      break if ret < 0 || !move_to_learn
      break if $DEBUG || !party[partyindex].moves[ret].hidden_move?
      pbMessage(_INTL("HM moves can't be forgotten now.")) { @scene.pbUpdate }
    end
    @scene.pbEndScene
    return ret
  end

  def pbStartChooseMoveScreen(party, partyindex, message)
    ret = -1
    @scene.pbStartForgetScene(party, partyindex, nil)
    pbMessage(message) { @scene.pbUpdate }
    loop do
      ret = @scene.pbChooseMoveToForget(nil)
      break if ret >= 0
      pbMessage(_INTL("You must choose a move!")) { @scene.pbUpdate }
    end
    @scene.pbEndScene
    return ret
  end
end

#===============================================================================
#
#===============================================================================
def pbChooseMove(pokemon, variableNumber, nameVarNumber)
  return if !pokemon
  ret = -1
  pbFadeOutIn do
    scene = PokemonSummary_Scene.new
    screen = PokemonSummaryScreen.new(scene)
    ret = screen.pbStartForgetScreen([pokemon], 0, nil)
  end
  $game_variables[variableNumber] = ret
  if ret >= 0
    $game_variables[nameVarNumber] = pokemon.moves[ret].name
  else
    $game_variables[nameVarNumber] = ""
  end
  $game_map.need_refresh = true if $game_map
end
