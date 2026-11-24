#================================================================================================
# Pokémon Iridescent Indigo Battle/Moves - 002_Wildfire.rb
#================================================================================================

class Battle::Move::DamageBurnTargetAlly < Battle::Move
  def canMagicCoat?; return true; end

  def pbFailsAgainstTarget?(user, target, show_message)
    return false if damagingMove?
    return !target.pbCanBurn?(user, show_message, self)
  end

  def pbEffectAgainstTarget(user, target)
    return if damagingMove?
    target.pbBurn(user)
  end

  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    target.pbBurn(user) if target.pbCanBurn?(user, false, self)
  end

  def pbEffectWhenDealingDamage(user, target)
    hitAlly = []
    target.allAllies.each do |b|
      next if !b.near?(target.index)
      next if !b.takesIndirectDamage?
      hitAlly.push([b.index, b.hp])
      b.pbReduceHP(b.totalhp / 16, false)
    end
    if hitAlly.length == 2
      @battle.pbDisplay(_INTL("The bursting flame hit {1} and {2}!",
                              @battle.battlers[hitAlly[0][0]].pbThis(true),
                              @battle.battlers[hitAlly[1][0]].pbThis(true)))
    elsif hitAlly.length > 0
      hitAlly.each do |b|
        @battle.pbDisplay(_INTL("The bursting flame hit {1}!",
                                @battle.battlers[b[0]].pbThis(true)))
      end
    end
    hitAlly.each { |b| @battle.battlers[b[0]].pbItemHPHealCheck }
  end
end

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("DamageBurnTargetAlly",
  proc { |score, move, user, target, ai, battle|
    target.battler.allAllies.each do |b|
      next if !b.near?(target.battler) || !b.takesIndirectDamage?
      score += 10
      if ai.trainer.has_skill_flag?("HPAware")
        score += 10 if b.hp <= b.totalhp / 16
      end
    end
    next score
  }
)