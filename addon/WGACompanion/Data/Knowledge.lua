-- WGA Companion: what Whirl knows. Written for WGA Companion in our own words; general class
-- knowledge from the classic game. WoW Forever may retune talents and items, so Whirl says so.
-- plan: { level, advice } in order; Whirl gives the latest one at or below your level.
local _, CM = ...
CM.Data = CM.Data or {}

CM.Data.Knowledge = {
  classes = {
    WARRIOR = {
      solo = { spec = "Arms", weapon = "the biggest two-handed weapon you can find",
        stats = { "Strength", "Stamina", "Agility" },
        plan = {
          { 10, "Put points in Arms: Improved Heroic Strike, then Deflection and Improved Rend." },
          { 20, "Keep going in Arms toward Deep Wounds and Impale. Two-handed weapon all the way." },
          { 30, "Sweeping Strikes at 30 makes pulling two mobs easy. Keep Rend and Overpower up." },
          { 40, "Mortal Strike at 40 is your big hit. After that, Fury for Cruelty, or Protection if you tank a lot." },
          { 50, "Finish Arms, then Fury for crit. Swap to a shield and Protection if your group needs a tank." },
        },
        tips = { "Use Charge to open, then Rend and Battle Shout.", "Eat between pulls; warriors have no self-healing.",
          "Overpower right after a dodge hits hard and can't be blocked." } },
      group = { role = "tank", spec = "Protection", stats = { "Stamina", "Defense", "Strength" },
        tips = { "Carry a one-hander and a shield even while you level Arms.", "Sunder Armor and Revenge hold threat best.",
          "Learn Taunt (Defensive Stance quest at 10) before your first dungeon." } },
    },
    PALADIN = {
      solo = { spec = "Retribution", weapon = "a slow two-handed weapon",
        stats = { "Strength", "Stamina", "Intellect" },
        plan = {
          { 10, "Start in Retribution: Benediction and Improved Judgement, then Improved Seal of the Crusader." },
          { 20, "Seal of Command at 20 is the big one. Pair it with the slowest two-hander you have." },
          { 30, "Keep going in Retribution for Vengeance. Judge, re-seal, and let the procs do the work." },
          { 40, "Take Holy or Protection depth for survival once Retribution's best talents are done." },
        },
        tips = { "Keep Blessing of Might and Devotion Aura up.", "Lay on Hands and Divine Protection save you from bad pulls." } },
      group = { role = "healer", spec = "Holy", stats = { "Intellect", "Spell power", "Stamina" },
        tips = { "Groups love a paladin healer; Flash of Light is cheap and fast.", "Bring Blessing of Wisdom for your own mana." } },
    },
    HUNTER = {
      solo = { spec = "Beast Mastery", weapon = "the best bow, gun or crossbow you can get, plus a stat stick in melee",
        stats = { "Agility", "Stamina", "Intellect" },
        plan = {
          { 10, "Tame a pet at 10 (class quest). Start Beast Mastery: Improved Aspect of the Hawk, Endurance Training." },
          { 20, "Keep going in Beast Mastery: Unleashed Fury and Ferocity make your pet tank and hurt." },
          { 30, "Intimidation and Bestial Discipline are next. Feed your pet to keep it happy." },
          { 40, "Bestial Wrath at 40. Then Marksmanship for Aimed Shot or Trueshot Aura." },
        },
        tips = { "Let the pet pull aggro, then shoot.", "Buy arrows or bullets every time you're in town.",
          "Feign Death drops aggro if a pull goes wrong." } },
      group = { role = "damage", spec = "Marksmanship", stats = { "Agility", "Attack power", "Intellect" },
        tips = { "Turn off pet Growl in groups.", "Use Hunter's Mark on the kill target and trap adds." } },
    },
    ROGUE = {
      solo = { spec = "Combat", weapon = "a fast main-hand and slow off-hand sword or dagger",
        stats = { "Agility", "Strength", "Stamina" },
        plan = {
          { 10, "Start in Combat: Improved Sinister Strike and Lightning Reflexes." },
          { 20, "Precision and Dual Wield Specialization next. Swords or maces are best for levelling." },
          { 30, "Blade Flurry at 30 for two-mob pulls, then Weapon Expertise." },
          { 40, "Adrenaline Rush at 40. Then Assassination for Malice and Relentless Strikes." },
        },
        tips = { "Open with Cheap Shot or Garrote, Sinister Strike, then Slice and Dice.", "Learn poisons at 20 and keep them on." } },
      group = { role = "damage", spec = "Combat", stats = { "Agility", "Hit", "Strength" },
        tips = { "Attack from behind and let the tank build threat first.", "Kick the casters." } },
    },
    PRIEST = {
      solo = { spec = "Shadow", weapon = "a wand, upgraded as often as you can",
        stats = { "Intellect", "Spirit", "Stamina" },
        plan = {
          { 10, "Five points in Discipline for Wand Specialization, then go Shadow." },
          { 20, "Spirit Tap in Shadow gives your mana back between pulls. Mind Flay at 20." },
          { 30, "Keep going in Shadow: Shadow Weaving and Vampiric Embrace." },
          { 40, "Shadowform at 40. Shield, Shadow Word: Pain, Mind Blast, then wand." },
        },
        tips = { "Power Word: Shield first, then damage.", "Wand the last bit of every mob to save mana." } },
      group = { role = "healer", spec = "Holy or Discipline", stats = { "Intellect", "Spirit", "Spell power" },
        tips = { "Use Renew and Lesser Heal ranks to save mana.", "Fortitude on everyone before the pull." } },
    },
    SHAMAN = {
      solo = { spec = "Enhancement", weapon = "a slow two-handed axe or mace",
        stats = { "Strength", "Agility", "Intellect" },
        plan = {
          { 10, "Start in Enhancement: Ancestral Knowledge and Shield Specialization or Thundering Strikes." },
          { 20, "Two-Handed Axes and Maces and Flurry are the core. Windfury Weapon at 30 hits hard." },
          { 30, "Keep stacking Enhancement for Elemental Weapons and Parry." },
          { 40, "Stormstrike at 40. After that, Restoration for Ancestral Healing helps solo too." },
        },
        tips = { "Lightning Bolt to pull, then melee with Earth Shock interrupts.", "Ghost Wolf at 20 saves a lot of walking." } },
      group = { role = "healer", spec = "Restoration", stats = { "Intellect", "Spell power", "Spirit" },
        tips = { "Chain Heal at 40 is your group heal.", "Drop Mana Spring and Strength of Earth totems for the group." } },
    },
    MAGE = {
      solo = { spec = "Frost", weapon = "a staff or wand with Intellect",
        stats = { "Intellect", "Stamina", "Spirit" },
        plan = {
          { 10, "Start in Frost: Improved Frostbolt and Elemental Precision." },
          { 20, "Ice Shards and Permafrost. Frost Nova then Frostbolt keeps mobs off you." },
          { 30, "Ice Block and Improved Blizzard let you AoE groups of mobs from about level 22." },
          { 40, "Ice Barrier at 40. Fire's Improved Fireball is good after Frost." },
        },
        tips = { "Conjure your own food and water.", "Polymorph the second mob on a double pull." } },
      group = { role = "damage", spec = "Frost", stats = { "Intellect", "Spell power", "Hit" },
        tips = { "Sheep the extra mobs and let the tank pull first.", "Hand out water before the run." } },
    },
    WARLOCK = {
      solo = { spec = "Affliction", weapon = "a wand and a staff or dagger with Intellect and Stamina",
        stats = { "Stamina", "Intellect", "Spirit" },
        plan = {
          { 10, "Start in Affliction: Improved Corruption, then Improved Drain Life or Siphon Life." },
          { 20, "Voidwalker tanks for you. Keep Corruption and Curse of Agony on and wand." },
          { 30, "Siphon Life and Improved Drain Soul keep you topped up. Life Tap, then Drain Life." },
          { 40, "Finish the key Affliction talents, then Demonology for a tougher Voidwalker. Your mount quest starts at 40." },
        },
        tips = { "Dot two mobs and fear one.", "Keep a few Soul Shards; Drain Soul on the last mob of a fight." } },
      group = { role = "damage", spec = "Affliction or Destruction", stats = { "Intellect", "Spell power", "Stamina" },
        tips = { "Use the Imp in groups for Blood Pact.", "Summon the group to the dungeon and hand out Healthstones." } },
    },
    DRUID = {
      solo = { spec = "Feral", weapon = "a staff or two-handed mace with Strength or Agility",
        stats = { "Strength", "Agility", "Stamina" },
        plan = {
          { 10, "Bear form at 10 (class quest). Start Feral: Ferocity and Feral Instinct." },
          { 20, "Cat form at 20. Sharpened Claws and Blood Frenzy make cat great for questing." },
          { 30, "Feral Charge and Faerie Fire (Feral) next. Travel form at 30." },
          { 40, "Leader of the Pack at 40. Then Restoration for Furor and better self-healing." },
        },
        tips = { "Shift out to heal yourself, then back in.", "Prowl and Ravage open fights from behind." } },
      group = { role = "tank or healer", spec = "Feral (bear) or Restoration", stats = { "Stamina", "Armor", "Agility" },
        tips = { "Bear tanks hold threat with Maul and Swipe.", "Innervate your healer or yourself when mana runs low." } },
    },
  },
  -- for players who are new to the game, by level
  newPlayer = {
    { 1, "Visit your class trainer every two levels for new spells. The Smart Guide marks quests for you." },
    { 5, "Pick two professions. Skinning, Herbalism or Mining make money while you level." },
    { 10, "You have talent points now. Open your talents (N) and spend them; ask me with /wga companion build." },
    { 12, "Learn First Aid from any town's trainer. Bandages save a lot of downtime." },
    { 20, "Buy bigger bags when you can; inventory space saves time." },
    { 30, "Keep your gear repaired, and sell grey items to vendors each time you're in town." },
    { 40, "Mount time! Check your riding trainer (in classic it's level 40), and keep gold aside for it." },
  },
}
