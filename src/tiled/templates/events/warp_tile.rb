# Template: warp tile (stairs, cave entrances, map edges without a
# connection). Transfers the player when they step on it.
# Parameters:
#   to    - name of the map to go to
#   spawn - name of a Spawn object on that map

page 0, [
  play_se(audio(name: "Door exit")),
  transfer(to: param(:to), spawn: param(:spawn)),
]
