# Template: item ball / hidden item.
# Parameters (custom properties on the placed event):
#   item     - item id, such as POTION
#   quantity - how many (default 1)
# Page 1 (self switch A, no graphic) is shown once the item is taken.

page 0, [
  *condition(
    script: "pbItemBall(:#{param(:item)}, #{param(:quantity, 1)})",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
]
