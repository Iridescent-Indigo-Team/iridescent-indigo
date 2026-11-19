#!/usr/bin/env ruby
#===============================================================================
# halve_script_coords.rb [--dry-run] [--odd] [--only=NAMES] FILE_OR_DIR...
#-------------------------------------------------------------------------------
# Migration aid: halves hard-coded pixel values in Essentials-style Ruby
# scripts, so code written for the 512x384 Essentials screen fits the
# 256x192 Pokessentials screen. Use it on plugins or scripts imported from
# stock Essentials, then REVIEW THE DIFF: the tool only knows common patterns.
#
# Integer literals are halved (rounding halves away from zero) when they are:
#   * arguments of Viewport.new, Rect.new, Bitmap.new, BitmapSprite.new,
#     blt, fill_rect, clear_rect, gradient_fill_rect, draw_text,
#     src_rect.set, resize, move, newWithSize, Window/SpriteWindow
#     constructors, drawTextEx, drawFormattedTextEx, pbDrawShadowText,
#     pbDrawPlainText, pbDrawOutlineText, getFormattedText,
#     pbBottomLeftLines, IconSprite/ItemIconSprite/ChangelingSprite.new
#   * assigned to .x .y .ox .oy .width .height (also += and -=)
#   * assigned to constants or variables with coordinate-like names
#     (X, Y, WIDTH, HEIGHT, OFFSET, xpos, ypos, ...)
#   * the x/y entries of text position arrays ([text, x, y, align, ...]) and
#     the x/y/source rect entries of image position arrays
#     ([file, x, y, src_x, src_y, w, h]) passed to pbDrawTextPositions /
#     pbDrawImagePositions or stored in textpos/imagepos variables.
# Inside those expressions only + and - operands, the left side of / and %,
# and factors of 4 or more in * are halved, so "Graphics.width / 2" stays.
#
# --dry-run prints what would change; --odd lists odd values (which can't be
# halved exactly) so they can be checked by hand. --only=name1,name2 applies
# just the call rules for those method names (useful to re-run one rule on
# already converted code without halving anything twice).
# Needs Ruby 3.3+ (prism).
#===============================================================================
require "prism"

class CoordHalver < Prism::Visitor
  # Methods whose listed argument indices are pixel values (:all = every arg).
  CALL_ARGS = {
    "blt"                => [0, 1],
    "fill_rect"          => [0, 1, 2, 3],
    "clear_rect"         => [0, 1, 2, 3],
    "gradient_fill_rect" => [0, 1, 2, 3],
    "draw_text"          => [0, 1, 2, 3],
    "resize"             => [0, 1],
    "move"               => [0, 1, 2, 3],
    "newWithSize"        => :all,
    "drawTextEx"         => [1, 2, 3],
    "drawFormattedTextEx" => [1, 2, 3],
    "pbDrawShadowText"   => [1, 2, 3, 4],
    "pbDrawPlainText"    => [1, 2, 3, 4],
    "pbDrawOutlineText"  => [1, 2, 3, 4],
    "getFormattedText"   => [1, 2, 3, 4, 6],
    "getLineBrokenText"  => [2],
    "pbBottomLeftLines"  => [2],
    "pbAddSprite"        => [1, 2],
    "setXY"              => [1, 2],      # PictureEx: (delay, x, y)
    "setDelta"           => [1, 2],
    "moveXY"             => [2, 3],      # PictureEx: (delay, duration, x, y)
    "moveDelta"          => [2, 3],
    "moveCurve"          => [2, 3, 4, 5, 6, 7],
    "setSrc"             => [1, 2],
    "setSrcSize"         => [1, 2],
    "addLabelForScreen"  => [1, 2, 3],
    "addImageForScreen"  => [1, 2],
    "drawSpot"           => [2, 3]
  }.freeze
  # Constructors: class name => argument indices.
  NEW_ARGS = {
    "Viewport"         => :all,
    "Rect"             => :all,
    "Bitmap"           => [0, 1],
    "BitmapSprite"     => [0, 1],
    "IconSprite"       => [0, 1],
    "ItemIconSprite"   => [0, 1],
    "ChangelingSprite" => [0, 1]
  }.freeze
  ATTRS = %w[x y ox oy width height].freeze
  COORD_NAME = /\A@?(x|y|ox|oy|w|h|xpos|ypos|x_pos|y_pos|xpos\d|ypos\d|width|height|left|top|
                 [a-z_]*_(x|y|xpos|ypos|width|height|offset|spacing|gap)|
                 (offset|spacing|gap)(_[a-z]+)?|(start|end|base|text|icon|bar|box)(x|y))\z/ix
  CONST_NAME = /(\A|_)(X|Y|WIDTH|HEIGHT|OFFSET|SPACING|GAP|MARGIN|PADDING|LINE_HEIGHT)(_|\z)|POS\z/
  CONST_SKIP = /FONT|SUBPIXELS|COLOR|SPEED|TIME|FRAME|COUNT|MAX|ZOOM|NUM|TOTAL|DURATION|ORIGIN/
  TEXTPOS_VAR = /textpos|textpositions|txtpos|textstrings/i
  IMAGEPOS_VAR = /imagepos|imgpos|imagepositions/i

  attr_reader :edits, :odd

  # only: list of method names; when set, only those call rules are applied.
  def initialize(source, only = nil)
    super()
    @only = only
    @source = source
    @edits = {}   # start offset => [end offset, text]
    @odd = []
  end

  #-----------------------------------------------------------------------------
  # Halving helpers
  #-----------------------------------------------------------------------------
  def halve_int(node)
    return if @edits.key?(node.location.start_offset)
    value = node.value
    return if value == 0
    half = (value / 2.0).round
    @odd.push([node.location.start_line, value]) if value.odd?
    @edits[node.location.start_offset] = [node.location.end_offset, half.to_s]
  end

  # Halves the pixel literals in an expression.
  def scale(node)
    case node
    when Prism::IntegerNode
      halve_int(node)
    when Prism::ParenthesesNode
      body = node.body
      body = body.body.last if body.is_a?(Prism::StatementsNode)
      scale(body)
    when Prism::IfNode   # ternary
      scale(node.statements&.body&.last)
      sub = node.respond_to?(:subsequent) ? node.subsequent : node.consequent
      scale(sub.is_a?(Prism::ElseNode) ? sub.statements&.body&.last : sub)
    when Prism::CallNode
      scale_call(node)
    end
  end

  def scale_call(node)
    name = node.name.to_s
    args = node.arguments&.arguments || []
    case name
    when "+", "-"
      scale(node.receiver)
      args.each { |a| scale(a) }
    when "-@"
      scale(node.receiver)
    when "/", "%", "round", "floor", "ceil", "to_i", "abs", "clamp"
      scale(node.receiver)
    when "*"
      # Only one factor of a product is a pixel size; if the other one is
      # already a size (a constant or .width/.height), the literal is a count.
      left = node.receiver
      right = args[0]
      if right.is_a?(Prism::IntegerNode) && right.value.abs >= 4
        halve_int(right) unless pixel_size?(left)
      elsif left.is_a?(Prism::IntegerNode) && left.value.abs >= 4
        halve_int(left) unless pixel_size?(right)
      end
    when "max", "min"
      if node.receiver.is_a?(Prism::ArrayNode)
        node.receiver.elements.each { |e| scale(e) }
      end
    end
  end

  # True if node already holds a pixel size (constant or width/height).
  def pixel_size?(node)
    node = node.body.body.last while node.is_a?(Prism::ParenthesesNode) && node.body.is_a?(Prism::StatementsNode)
    return true if node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
    return true if node.is_a?(Prism::CallNode) && %i[width height].include?(node.name)
    # An expression built from a size (such as "Graphics.width / 32") is too.
    if node.is_a?(Prism::CallNode) && %i[/ * + -].include?(node.name)
      return pixel_size?(node.receiver) || (node.arguments&.arguments || []).any? { |a| pixel_size?(a) }
    end
    return false
  end

  def scale_args(args, indices)
    return unless args
    list = args.arguments
    list.each_with_index do |arg, i|
      next if arg.is_a?(Prism::KeywordHashNode) || arg.is_a?(Prism::BlockArgumentNode)
      next unless indices == :all || indices.include?(i)
      scale(arg)
    end
  end

  def string_like?(node)
    node.is_a?(Prism::StringNode) || node.is_a?(Prism::InterpolatedStringNode) ||
      (node.is_a?(Prism::CallNode) && %w[_INTL _ISPRINTF sprintf format].include?(node.name.to_s))
  end

  # [text, x, y, align, base, shadow, ...]
  def scale_textpos(array)
    return unless array.is_a?(Prism::ArrayNode)
    el = array.elements
    if el.all? { |e| e.is_a?(Prism::ArrayNode) }
      el.each { |e| scale_textpos(e) }
      return
    end
    return if el.length < 3
    scale(el[1])
    scale(el[2])
  end

  # [file, x, y, src_x, src_y, width, height]
  def scale_imagepos(array)
    return unless array.is_a?(Prism::ArrayNode)
    el = array.elements
    if el.all? { |e| e.is_a?(Prism::ArrayNode) }
      el.each { |e| scale_imagepos(e) }
      return
    end
    return if el.length < 3
    el[1..6].each { |e| scale(e) }
  end

  def var_name(node)
    case node
    when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode then node.name.to_s
    end
  end

  #-----------------------------------------------------------------------------
  # Visitors
  #-----------------------------------------------------------------------------
  def visit_call_node(node)
    name = node.name.to_s
    recv = node.receiver
    if @only
      scale_args(node.arguments, CALL_ARGS[name]) if @only.include?(name) && CALL_ARGS.key?(name)
      return super
    end
    if name == "new" && recv.is_a?(Prism::ConstantReadNode)
      cname = recv.name.to_s
      if NEW_ARGS.key?(cname)
        scale_args(node.arguments, NEW_ARGS[cname])
      elsif cname =~ /Window/
        scale_args(node.arguments, :all)
      end
    elsif name == "set" && recv.is_a?(Prism::CallNode) && recv.name == :src_rect
      scale_args(node.arguments, :all)
    elsif CALL_ARGS.key?(name)
      if %w[fill_rect clear_rect gradient_fill_rect].include?(name) || name == "draw_text"
        first = node.arguments&.arguments&.first
        scale_args(node.arguments, CALL_ARGS[name]) unless first.is_a?(Prism::CallNode) && first.name == :new
      else
        scale_args(node.arguments, CALL_ARGS[name])
      end
    elsif name == "pbDrawTextPositions"
      scale_textpos(node.arguments&.arguments&.[](1))
    elsif name == "pbDrawImagePositions"
      scale_imagepos(node.arguments&.arguments&.[](1))
    elsif ATTRS.map { |a| "#{a}=" }.include?(name) && node.arguments
      scale(node.arguments.arguments.last)
    elsif %w[push << concat unshift].include?(name) && (vn = var_name(recv))
      if vn =~ TEXTPOS_VAR
        node.arguments&.arguments&.each { |a| scale_textpos(a) }
      elsif vn =~ IMAGEPOS_VAR
        node.arguments&.arguments&.each { |a| scale_imagepos(a) }
      end
    end
    super
  end

  # recv.x += 4
  def visit_call_operator_write_node(node)
    return super if @only
    if ATTRS.include?(node.read_name.to_s.delete_suffix("=")) && additive?(node)
      scale(node.value)
    end
    super
  end

  def visit_local_variable_write_node(node)
    return super if @only
    var_write(node.name.to_s, node.value)
    super
  end

  def visit_instance_variable_write_node(node)
    return super if @only
    var_write(node.name.to_s, node.value)
    super
  end

  def visit_local_variable_operator_write_node(node)
    return super if @only
    if node.name.to_s =~ COORD_NAME && additive?(node)
      scale(node.value)
    end
    super
  end

  def visit_instance_variable_operator_write_node(node)
    visit_local_variable_operator_write_node(node)
  end

  # True for "+=" and "-=" (prism renamed operator to binary_operator).
  def additive?(node)
    op = node.respond_to?(:binary_operator) ? node.binary_operator : node.operator
    return %i[+ -].include?(op.to_s.delete_suffix("=").to_sym)
  end

  def var_write(name, value)
    if name =~ TEXTPOS_VAR
      scale_textpos(value)
    elsif name =~ IMAGEPOS_VAR
      scale_imagepos(value)
    elsif name =~ COORD_NAME
      scale(value)
    end
  end

  def visit_constant_write_node(node)
    return super if @only
    name = node.name.to_s
    if name =~ CONST_NAME && name !~ CONST_SKIP
      value = node.value
      if value.is_a?(Prism::ArrayNode)
        value.elements.each { |e| scale(e) }
      else
        scale(value)
      end
    end
    super
  end

  #-----------------------------------------------------------------------------
  def result
    out = @source.b
    @edits.sort_by { |start, _| -start }.each do |start, (stop, text)|
      out[start...stop] = text
    end
    return out.force_encoding(Encoding::UTF_8)
  end
end

if $PROGRAM_NAME == __FILE__
  dry = ARGV.delete("--dry-run")
  show_odd = ARGV.delete("--odd")
  only_arg = ARGV.find { |a| a.start_with?("--only=") }
  only = only_arg && ARGV.delete(only_arg).split("=", 2)[1].split(",")
  if ARGV.empty?
    warn("Usage: ruby #{File.basename(__FILE__)} [--dry-run] [--odd] FILE_OR_DIR...")
    exit 2
  end
  files = ARGV.flat_map { |a| File.directory?(a) ? Dir.glob(File.join(a, "**", "*.rb")).sort : [a] }
  total = 0
  files.each do |file|
    source = File.read(file, encoding: "UTF-8")
    parsed = Prism.parse(source)
    unless parsed.errors.empty?
      warn("#{file}: parse error, skipped")
      next
    end
    halver = CoordHalver.new(source, only)
    parsed.value.accept(halver)
    next if halver.edits.empty?
    total += halver.edits.size
    puts("#{file}: #{halver.edits.size} values")
    halver.odd.each { |line, v| puts("  line #{line}: odd value #{v}") } if show_odd
    File.write(file, halver.result) unless dry
  end
  puts("#{total} values #{dry ? 'would be ' : ''}halved")
end
