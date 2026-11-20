# Template: trainer. Essentials turns these comments into the full trainer
# event when the game compiles its data (Compiler#convert_to_trainer_event).
# The event's name, Trainer(3), is how far the trainer sees.
# Parameters:
#   trainer_type - trainer type id (trainer_types.txt), e.g. YOUNGSTER
#   trainer_name - the trainer's name (with trainers.txt)
#   intro        - said before the battle
#   defeated     - said when the player wins
#   after        - said when spoken to after the battle

page 0, [
  comment("Battle: #{param(:intro)}"),
  comment("Type: #{param(:trainer_type)}"),
  comment("Name: #{param(:trainer_name)}"),
  comment("EndSpeech: #{param(:defeated)}"),
  comment("EndBattle: #{param(:after)}"),
]
