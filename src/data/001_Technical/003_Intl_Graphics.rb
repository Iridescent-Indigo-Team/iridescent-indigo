#===============================================================================
# Localized graphics.
#
# Graphics with text drawn into them can be redrawn for each language in
# src/assets/locales/LANG/graphics/, which mirrors src/assets/graphics/. The
# build puts them in Graphics/Locales/LANG/ and writes Data/graphics_LANG.dat,
# a Hash from each replaced path (lower case, no extension, e.g.
# "graphics/ui/battle/cursor_command") to its localized path. Whenever the
# game loads a bitmap by filename, the localized version is used if the
# current language has one.
#===============================================================================
module LocalizedGraphics
  @@index = {}

  module_function

  # Loads the index of the language with this code ("en" clears it).
  def load(code)
    @@index = {}
    filename = "Data/graphics_#{code}.dat"
    return if nil_or_empty?(code) || !FileTest.exist?(filename)
    begin
      data = load_data(filename)
      @@index = data if data.is_a?(Hash)
    rescue StandardError
      @@index = {}
    end
  end

  def any?
    return !@@index.empty?
  end

  # The path to load instead of path, or path itself.
  def resolve(path)
    return path if @@index.empty? || !path.is_a?(String)
    key = path.tr("\\", "/").sub(/\A\.\//, "").sub(/\.(png|gif|jpg|jpeg|bmp)\z/i, "").downcase
    return @@index[key] || path
  end
end

def pbLocalizedGraphic(path)
  return LocalizedGraphics.resolve(path)
end

# Bitmaps loaded by filename use the localized graphic if there is one.
module LocalizedBitmapLoading
  def initialize(*args)
    if args.length == 1 && args[0].is_a?(String) && LocalizedGraphics.any?
      args = [LocalizedGraphics.resolve(args[0])]
    end
    super(*args)
  end
end

Bitmap.prepend(LocalizedBitmapLoading) if !Bitmap.ancestors.include?(LocalizedBitmapLoading)
