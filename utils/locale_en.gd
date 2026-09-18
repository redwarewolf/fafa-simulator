class_name LocaleEN

## English text for every Spanish string the game shows — built as a runtime
## Translation resource (no .csv/.import step, so it works without ever
## opening the editor). Godot's Control nodes auto-translate their `text`
## using its current value as the lookup key, so most static labels/buttons
## need no code changes at all, only an entry here. Strings assembled at
## runtime (e.g. an interpolated "%s hinchas") do NOT auto-translate once
## interpolated, so their *template* is wrapped in tr() at the call site —
## see e.g. hub.gd's fans_label — and that template is the key used below.
## Tree column titles/cell text also need an explicit tr() at the call site
## (TreeItem isn't a Control, so it never auto-translates) — see TreeStyle.
##
## Deliberately NOT covered: Grandi Tapir/Pepito Perinola's dialogue lines
## (hub.gd's intro/season-end lines, TAB_TUTORIALS/SUB_TUTORIALS, the random
## event narration in random_event_pool.gd). Those use custom {placeholder}
## substitution, not %-templates, and translating them means writing natural
## English dialogue in the same voice, not just wiring — a content task, not
## a plumbing one. They stay in Spanish regardless of locale for now.
##
## Keys are the exact Spanish source text (case/punctuation-sensitive).
## GameState loads this once via TranslationServer.add_translation() and
## switches locale with TranslationServer.set_locale("en"/"es") — see
## GameState.set_locale().

static func build() -> Translation:
	var t := Translation.new()
	t.locale = "en"
	for key in MESSAGES:
		t.add_message(key, MESSAGES[key])
	return t

const MESSAGES := {
	# ── Main menu / settings / team creation ──────────────────────────────
	"Nueva Partida": "New Game",
	"Cargar Partida": "Load Game",
	"Todavía no hay un club guardado": "No saved club yet",
	"Configuración": "Settings",
	"Salir": "Quit",
	"Idioma": "Language",
	"< Volver": "< Back",
	"No se pudo cargar el club guardado": "Could not load saved club",
	"CREÁ TU CLUB": "CREATE YOUR CLUB",
	"Nombre del Club": "Club Name",
	"Ingresá un nombre de club": "Enter a club name",
	"Ej: Deportivo Rayo": "e.g. Deportivo Rayo",
	"Plantilla de Escudo": "Crest Template",
	"Color Primario": "Primary Color",
	"Color Secundario": "Secondary Color",
	"Aleatorio": "Randomize",
	"Tu Club": "Your Club",
	"EMPEZAR CARRERA": "START CAREER",

	# ── Month names (GameState.MONTH_NAMES / format_date) ──────────────────
	"enero": "January",
	"febrero": "February",
	"marzo": "March",
	"abril": "April",
	"mayo": "May",
	"junio": "June",
	"julio": "July",
	"agosto": "August",
	"septiembre": "September",
	"octubre": "October",
	"noviembre": "November",
	"diciembre": "December",

	# ── Hub header / nav ───────────────────────────────────────────────────
	"Plantel": "Squad",
	"Mercado": "Market",
	"Calendario": "Calendar",
	"Torneo": "Tournament",
	"Juveniles": "Youth",
	"División E": "Division E",
	"Próxima Fecha": "Next Date",
	"Partido de Prueba": "Test Match",
	"Pretemporada": "Pre-season",
	"1ª Mitad": "1st Half",
	"Receso de Temporada": "Mid-season Break",
	"2ª Mitad": "2nd Half",
	"División %s": "Division %s",
	"%s hinchas": "%s fans",

	# ── Shared column headers ──────────────────────────────────────────────
	"Nombre": "Name",
	"Edad": "Age",
	"Calidad": "Quality",
	"Valor": "Value",
	"Sueldo": "Wage",
	"Fecha": "Date",

	# ── Squad ───────────────────────────────────────────────────────────────
	"PLANTEL": "SQUAD",
	"Táctica:": "Tactic:",
	"Renombrar": "Rename",
	"Bloquear": "Lock",
	"+ Nueva": "+ New",
	"Guardar": "Save",
	"Eliminar": "Delete",
	"Renombrar la táctica seleccionada": "Rename selected tactic",
	"Bloquear/desbloquear las posiciones": "Lock/unlock dot positions",
	"Agregar nueva táctica": "Add new tactic",
	"Guardar las posiciones actuales": "Save current tactic positions",
	"Eliminar la táctica seleccionada": "Delete selected tactic",
	"Renombrar Táctica": "Rename Tactic",
	"Nombre de la táctica": "Tactic name",

	# ── Market ──────────────────────────────────────────────────────────────
	"VENDER": "SELL",
	"Presupuesto: $0": "Budget: $0",
	"SELECCIONÁ UN JUGADOR": "SELECT A PLAYER",
	"COMPRAR": "BUY",
	"MERCADO DE PASES CERRADO": "TRANSFER WINDOW CLOSED",
	"PLANTEL MUY CHICO": "SQUAD TOO SMALL",
	"PRESUPUESTO INSUFICIENTE": "NOT ENOUGH BUDGET",
	"Presupuesto: $%s": "Budget: $%s",
	"VENDER — $%s": "SELL — $%s",
	"COMPRAR — $%s": "BUY — $%s",

	# ── Club tab bar ────────────────────────────────────────────────────────
	"Estadio": "Stadium",
	"Personal": "Staff",
	"Entrenamiento": "Training",
	"Gastos": "Costs",
	"Ingresos": "Earnings",
	"Contrataciones": "Hiring",

	# ── Costs ───────────────────────────────────────────────────────────────
	"SUELDOS DEL PLANTEL": "SQUAD WAGES",
	"DESGLOSE DE GASTOS": "COST BREAKDOWN",
	"Sueldos del plantel: $0": "Squad wages: $0",
	"TOTAL POR FECHA: $0": "TOTAL PER DATE: $0",
	"Se descuenta automáticamente cada vez que avanzás la fecha.": "Deducted automatically every time you press Next Date.",
	"Sueldos del plantel: $%s": "Squad wages: $%s",
	"TOTAL POR FECHA: $%s": "TOTAL PER DATE: $%s",
	"Sin personal contratado": "No staff hired",
	"%s (Nivel %d)": "%s (Lvl %d)",

	# ── Earnings ────────────────────────────────────────────────────────────
	"INGRESOS": "EARNINGS",
	"0 hinchas  ·  Capacidad del estadio 0": "0 fans  ·  Stadium capacity 0",
	"%s hinchas  ·  Capacidad del estadio %d": "%s fans  ·  Stadium capacity %d",
	"Venta de Entradas": "Ticket Sales",
	"Venta de Merchandising": "Merchandise Sales",
	"Venta de Comida": "Food Sales",
	"Precio de entrada: $%s (División %s)": "Ticket price: $%s (Division %s)",
	"Asistencia esperada: %d – %d": "Expected attendance: %d – %d",
	"Ingreso estimado: $%s – $%s": "Est. gate revenue: $%s – $%s",
	"Solo en tus partidos de local (liga o amistoso).": "Only on your home matches (league or friendly).",
	"Todavía no está construido.": "Not built yet.",
	"Nivel %d  ·  $%s / unidad": "Level %d  ·  $%s / item",
	"Compradores esperados: %d – %d": "Expected buyers: %d – %d",
	"Ingreso estimado por fecha: $%s – $%s": "Est. income per date: $%s – $%s",

	# ── Hiring ──────────────────────────────────────────────────────────────
	"Contratá un Ojeador para desbloquear las contrataciones.": "Hire a Talent Scout to unlock hiring.",
	"JUGADORES OJEADOS": "SCOUTED PLAYERS",
	"Nuevo informe de scouting el próximo mes.": "New scouting report next month.",
	"FICHAR — $%s": "HIRE — $%s",

	# ── Stadium ─────────────────────────────────────────────────────────────
	"SEDE DEL CLUB": "CLUBHOUSE",
	"TRIBUNA": "TRIBUNE",
	"MEJORAS": "UPGRADES",
	"Edificio": "Building",
	"Tribuna": "Tribune",
	"Capacidad: %d": "Capacity: %d",
	"Nivel %d / %d": "Level %d / %d",
	"MÁX": "MAX",
	"Necesita %s Nvl %d": "Needs %s Lvl %d",
	"Nvl %d  $%s": "Lvl %d  $%s",
	"→ Nvl %d  $%s": "→ Lvl %d  $%s",

	# ── Staff ───────────────────────────────────────────────────────────────
	"PERSONAL": "STAFF",
	"Sin contratar": "Not hired",
	"$%s / fecha": "$%s / date",
	"CONTRATAR": "HIRE",
	"MEJORAR — Nvl %d": "UPGRADE — Lvl %d",
	"Centro de Entrenamiento": "Training Facility",
	"Ojeador": "Talent Scout",
	"Academia Juvenil": "Youth Academy",

	# ── Training ────────────────────────────────────────────────────────────
	"Contratá un Centro de Entrenamiento para desbloquear el entrenamiento.": "Hire a Training Facility to unlock training.",
	"Entrenar PAC": "Train PAC",
	"Entrenar SHO": "Train SHO",
	"Entrenar PAS": "Train PAS",
	"Entrenar DRI": "Train DRI",
	"Entrenar DEF": "Train DEF",
	"Entrenar PHY": "Train PHY",
	"CENTRO DE ENTRENAMIENTO": "TRAINING FACILITY",
	"Sesiones usadas: 0 / 0": "Sessions used: 0 / 0",
	"Cada sesión sube un stat de forma permanente en +6%, hasta el límite de sesiones de tu Centro de Entrenamiento. Podés gastar varias sesiones en el mismo stat para acumularlas, o repartirlas entre distintos stats.":
		"Each session permanently boosts one stat by +6%, up to your Training Facility's session cap. Spend sessions on the same stat to stack them, or spread them across different stats.",
	"Sesiones usadas: %d / %d": "Sessions used: %d / %d",
	"%s — n/d": "%s — n/a",
	"%s — sin sesiones": "%s — no sessions left",
	"Entrenar %s (+%d%%) — $%s": "Train %s (+%d%%) — $%s",

	# ── Youth ───────────────────────────────────────────────────────────────
	"Contratá una Academia Juvenil para desbloquear el plantel juvenil.": "Hire a Youth Academy to unlock the youth roster.",
	"ACADEMIA JUVENIL": "YOUTH ACADEMY",
	"Nueva camada cada pretemporada. Se suman al primer equipo automáticamente a los 18 años.": "New intake every pre-season. Graduates to the senior squad automatically at 18.",
	"SUBIR AL PRIMER EQUIPO": "PROMOTE TO FIRST TEAM",
	"LIBERAR": "RELEASE",

	# ── Calendar ────────────────────────────────────────────────────────────
	"CALENDARIO": "CALENDAR",
	"PRÓXIMO PARTIDO": "NEXT MATCH",
	"Local": "Home",
	"Visitante": "Away",
	"LOCAL": "HOME",
	"VISITANTE": "AWAY",
	"JUGADORES CLAVE": "KEY PLAYERS",
	"HISTORIAL": "HEAD TO HEAD",
	"SIN PARTIDOS": "NO FIXTURES",
	"RESULTADO": "RESULT",
	"PARTIDO": "FIXTURE",
	"PRÓXIMO": "UPCOMING",
	"Sin enfrentamientos previos": "No previous meetings",
	"Amistosos de Pretemporada": "Pre-season Friendlies",
	"Fecha %d": "Matchday %d",
	"Posición": "Position",
	"Puntos": "Points",
	"Récord": "Record",
	"OVR Plantel": "Squad OVR",
	"Goles": "Goals",

	# ── Tournament ──────────────────────────────────────────────────────────
	"TABLA DE POSICIONES": "STANDINGS",
	"MEJORES DE LA LIGA": "LEAGUE TOP RATED",
	"Seleccioná un club": "Select a club",
	"Primario": "Primary",
	"Secundario": "Secondary",
	"PJ": "P",
	"G": "W",
	"E": "D",
	"P": "L",
	"DG": "GD",
	"División %s   ·   %d jugadores": "Division %s   ·   %d players",
	"Jugados": "Played",
	"Goles a Favor": "Goals For",
	"En Contra": "Against",
	"Dif. de Goles": "Goal Diff",

	# ── Match / world ───────────────────────────────────────────────────────
	"Volver al Hub": "Back to Hub",
	"¡FALTA!": "FOUL!",
	"¡GANÓ %s!\n%s": "%s WINS!\n%s",
	"EMPATE\n%s": "DRAW\n%s",
	"EMPATE  %d - %d": "DRAW  %d - %d",
	"%s GANA  %d - %d": "%s LEADS  %d - %d",
	"¡GOL DE %s!": "%s SCORED!",
	"Hinchas: %s%d  (ahora %s)": "Fans: %s%d  (now %s)",
	"Ingresos por Entradas: $%s  (%s asistentes)": "Ticket Revenue: $%s  (%s attended)",
	"Goleadores:": "Scorers:",

	# ── Player card / misc UI ───────────────────────────────────────────────
	"Personaje": "Speaker",
	"SECCIÓN": "SECTION",
	"Sección": "Section",
	"Próximamente": "Coming soon",
	"POSICIONES": "POSITIONS",
	"Común": "Common",
	"Poco Común": "Uncommon",
	"Raro": "Rare",
	"Épico": "Epic",
	"Legendario": "Legendary",
	"Desconocido": "Unknown",
	"%s  •  %d años": "%s  •  Age %d",
	"--  •  -- años": "--  •  Age --",
	"todos los stats": "all stats",
	" (queda %d partido)": " (%d match left)",
	" (quedan %d partidos)": " (%d matches left)",
	"Resaca": "Hangover",
}
