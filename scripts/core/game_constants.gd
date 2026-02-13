class_name GameConstants
extends RefCounted

# ============================================
# MANA SYSTEM
# ============================================
const STARTING_MANA: int = 3
const MANA_CAP: int = 10
const MANA_PER_TURN: int = 1

# ============================================
# DECK & HAND
# ============================================
const HAND_SIZE: int = 10
const CARDS_PER_TURN: int = 3
const ATTACK_CARDS_PER_HERO: int = 2

# ============================================
# ENERGY SYSTEM
# ============================================
const ENERGY_ON_ATTACK: int = 10
const ENERGY_ON_HIT: int = 5
const ENERGY_ON_TURN_END: int = 10
const MAX_ENERGY: int = 100

# ============================================
# DAMAGE MULTIPLIERS
# ============================================
const EMPOWER_DAMAGE_MULT: float = 1.5
const EMPOWER_HEAL_MULT: float = 1.5
const EMPOWER_SHIELD_MULT: float = 1.5
const WEAK_DAMAGE_MULT: float = 0.5
const BREAK_DAMAGE_MULT: float = 1.5

# ============================================
# BUFF/DEBUFF VALUES
# ============================================
const REGEN_HEAL_MULT: float = 0.5
const THUNDER_DAMAGE_MULT: float = 0.6  # 60% ATK per stack

# ============================================
# AI PRIORITIES
# ============================================
const AI_HEAL_HP_THRESHOLD: float = 0.5  # Heal when below 50% HP
const AI_ATTACK_PRIORITY: int = 5
const AI_HEAL_PRIORITY: int = 5
const AI_BUFF_PRIORITY: int = 3

# ============================================
# ANIMATION TIMINGS (seconds)
# ============================================
const CARD_DEAL_DELAY: float = 0.08
const CARD_FADE_DURATION: float = 0.2
const ATTACK_ANIM_DURATION: float = 0.15
const HIT_ANIM_DURATION: float = 0.3
const TURN_TRANSITION_DELAY: float = 0.5

# ============================================
# UI SCALE VALUES
# ============================================
const CARD_HOVER_SCALE: float = 1.5
const MANA_PULSE_SCALE: float = 1.2
const HERO_PULSE_SCALE: float = 1.15

# ============================================
# DEFAULT STATS
# ============================================
const DEFAULT_BASE_ATTACK: int = 10
const DEFAULT_MAX_HP: int = 100
