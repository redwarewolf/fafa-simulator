# FAFA Simulator — AI Context Document

## Overview
FAFA Simulator is a 2D football (soccer) club management game built with Godot 4.5 (GDScript). The tone is goofy and arcadey, not a realistic simulation. It is heavily inspired by Argentine football culture. The player takes the role of a football club director, responsible for both on-pitch decisions (squad, formation, tactics) and off-pitch management (finances, staff, transfers).

## Core Game Loop
The player manages a club from Division E (lowest) up to Division A (highest). Each division has a tournament. Winning a tournament promotes the club to the next division. The game ends (in victory) by winning the Division A championship.

Divisions, from lowest to highest: E, D, C, B, A.

The game uses a day-by-day calendar. Each day may trigger events such as: match days, transfer window openings, sponsor offers, injuries, player morale changes, or random scripted events. Between tournament matches, the player can schedule friendly matches.

## Match System
Matches are played in real-time using a custom 2D physics-based football engine. The world scene (`scenes/world.tscn`) is a 2350x1225 unit pitch with goals on both sides.

Players have four roles: Goalie, Defense, Midfield, Offense. Each role uses a dedicated AI behavior class: `GoalieBehavior`, `DefenderBehavior`, `MidfielderBehavior`, `ForwardBehavior`.

Player state machine states: IDLE, MOVING, RECOVERING, TACKLING, PREPPING_SHOT, SHOOTING, PASSING, HEADER, BICYCLE_KICK, VOLLEY_KICK, CHEST_CONTROL, HURT.

Ball state machine states: CARRIED, FREEFORM, SHOT. The ball supports passing, shooting, tumbling, and height simulation.

Before each match, the player sets formation and tactics.

## Player Quality
Each player has a quality tier that determines their base stat range at creation and their training ceiling. Quality is visible on the player card and in the transfer market.

| Quality    | Base Stat Range | Training Ceiling |
|------------|-----------------|-----------------|
| Common     | 1–20            | +10 (max 30)    |
| Uncommon   | 21–40           | +10 (max 50)    |
| Rare       | 41–60           | +10 (max 70)    |
| Epic       | 61–80           | +10 (max 90)    |
| Legendary  | 81–90           | +10 (max 100)   |

Quality also affects transfer market value and wage expectations. A Legendary player in Division E is a game-changer but will cost accordingly. Stats within the range are randomized per player at creation, so two Rare players of the same role will still differ.

## Player Stats
The 6 base stats are the player's core attributes — visible on the player card, shown in the transfer market, and used directly by the match engine. Think of them like RPG base stats (STR, DEX, INT). Each is a value within the range defined by the player's quality tier.

- PAC (Pace): affects movement speed and acceleration on the pitch.
- SHO (Shooting): affects shot power, accuracy, and finishing. Maps directly to PREPPING_SHOT, SHOOTING, VOLLEY_KICK, BICYCLE_KICK states.
- PAS (Passing): affects pass accuracy and range. Maps to PASSING state.
- DRI (Dribbling): affects ball control, agility, and reaction speed while carrying the ball. Maps to CARRIED ball state.
- DEF (Defending): affects tackle success rate and defensive positioning. Maps to TACKLING state and DefenderBehavior / GoalieBehavior.
- PHY (Physicality): affects strength in duels and header ability. Maps to HEADER state and HURT recovery time.

Each role has a weighted formula to compute an `overall` rating (1–100):
- Goalie: DEF 40%, PHY 25%, PAC 15%, PAS 10%, DRI 5%, SHO 5%
- Defense: DEF 35%, PHY 25%, PAC 20%, PAS 10%, DRI 5%, SHO 5%
- Midfield: PAS 30%, DRI 20%, DEF 15%, PAC 15%, PHY 10%, SHO 10%
- Offense: SHO 30%, PAC 25%, DRI 25%, PAS 10%, PHY 7%, DEF 3%

Note: exact weights are subject to balancing. The stat system is intentionally simple to keep the arcadey feel.

## Player Hidden Attributes
Separate from base stats and quality, each player has hidden runtime attributes. These are not shown on the transfer market or player card. They act as multipliers on top of base stats during match simulation and are affected by calendar events and club decisions.

- `stamina` (0–100): depletes during matches. Recovers on rest days. A player with low stamina performs below their base stats in matches.
- `morale` (0–100): affected by wins/losses, wages being paid on time, playing time, and random calendar events. Low morale reduces effective stats. High morale can briefly boost them.

## Club Management

### Squad
- Players are bought and sold via a transfer market.
- Scouts can be hired to discover new players.
- Players can be trained to improve individual stats up to their quality ceiling.
- Each player has: name, role, age, quality, PAC, SHO, PAS, DRI, DEF, PHY, overall (computed), skin_color.
- Player data is stored as `PlayerResource` (GDScript resource).

### Staff
- Scouts: hired to find players in the transfer market.
- Coaches: affect training quality.

### Finances
Revenue: match prizes, merchandising sales, sponsor deals, match fixing, underground bets (high risk/reward shady mechanics are explicitly part of the design).
Expenses: player wages, staff salaries, stadium maintenance, transfer fees.

## Data
Squad data is defined in `assets/json/squads.json`. Pre-built national squads available: FRANCE, ARGENTINA, BRAZIL, ENGLAND, GERMANY, ITALY, SPAIN, USA. The `DataLoader` autoload singleton loads this data at startup and makes it globally accessible.

## Project Structure
- `scenes/world.tscn` — main match scene
- `scenes/actors_container.gd` — spawns and manages players in a match
- `scenes/ball/` — ball node, state machine, and individual ball states
- `scenes/characters/` — player node, state machine, individual states, and AI behavior classes
- `scenes/ui/` — HUD, minimap (`minimap.gd`), menus
- `assets/json/squads.json` — all squad and player data
- `assets/art/` — sprites, palettes, UI assets
- `assets/music/` — gameplay and menu music
- `assets/sfx/` — sound effects
- `resources/player_resource.gd` — PlayerResource definition
- `utils/data_loader.gd` — DataLoader autoload

## Status
Core match engine is functional. Club management layer (calendar, finances, transfers, scouts) is in progress.