# Event 10 "Apricorn tree" on Route 1 (map 5)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  comment("Gives 1 random Apricorn each time."),
  *comment(
    "For demonstration purposes only - Apricorn trees ",
    "should provide a fixed Apricorn, have a 24 hour delay ",
    "(like Kurt does), and should look different to ",
    "Headbutt trees.",
  ),
  *script(
    <<~'CODE'
    apricorns = [
      :REDAPRICORN,
      :YELLOWAPRICORN,
      :BLUEAPRICORN,
      :GREENAPRICORN,
      :PINKAPRICORN,
      :WHITEAPRICORN,
      :BLACKAPRICORN
    ]
    CODE
  ),
  *script(
    <<~'CODE'
    random_item = apricorns.sample
    pbItemBall(random_item)
    CODE
  ),
]
