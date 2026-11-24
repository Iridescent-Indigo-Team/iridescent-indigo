#================================================================================================
# Pokémon Iridescent Indigo Battle/Moves - 001_MoonShift.rb
#================================================================================================

class Battle::Move::ChangeUserClefableForm < Battle::Move
  def pbEndOfMoveUsageEffect(user, targets, numHits, switchedBattlers)
    return if numHits == 0
    return if user.fainted? || user.effects[PBEffects::Transform]
    return if !user.isSpecies?(:CLEFABLE)
    return if user.hasActiveAbility?(:SHEERFORCE) && @addlEffect > 0
    return if user.form == 2
    user.pbChangeForm(2, _INTL("{1} transformed!", user.pbThis))
  end
end

MultipleForms.register(:CLEFABLE, {
  "getFormOnLeavingBattle" => proc { |pkmn, battle, usedInBattle, endBattle|
    next 0
  }
})