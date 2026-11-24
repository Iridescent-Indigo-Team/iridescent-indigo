#================================================================================================
# Pokémon Iridescent Indigo Battle/Moves - 001_MoonShift.rb
#================================================================================================

class Battle::Move::ChangeUserClefableForm < Battle::Move
  def pbEndOfMoveUsageEffect(user, targets, numHits, switchedBattlers)
    return if numHits == 0
    return if user.fainted? || user.effects[PBEffects::Transform]
    return if !user.isSpecies?(:CLEFABLE)
    return if user.hasActiveAbility?(:SHEERFORCE) && @addlEffect > 0
    newForm = (user.form + 2) % 3
    user.pbChangeForm(newForm, _INTL("{1} transformed!", user.pbThis))
  end
end