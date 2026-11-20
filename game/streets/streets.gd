extends GameMode3D
## streets -- free driving in a real city. Nothing here is made up: the roads, buildings,
## parks, trees and traffic lights come from OpenStreetMap, baked once into cities/*.json
## by tools/osm_city.py (GAME.md has the steps for adding another city). Chase cam behind
## the car. Closer to a driving sim than an arcade game: real sizes and speeds, weight,
## grip that runs out (push a corner too fast and the car runs wide), a reverse gear, and
## buildings you cannot drive through. The one game hook: every street of the city you
## drive down for the first time scores a point.
##
## Layout of this file: city data -> meshes -> the car -> camera -> autodrive -> exploring
## -> HUD (speedometer, street name, minimap, touch pedals).

## The places you can drive: the game's start screen offers one per entry. `look` sets the
## regional details: "med" (palms among the trees, solar water heaters on the roofs) or
## "north" (conifers among the trees). `city` is the
## file in cities/ (bake it with the "bake a real city" workflow, see GAME.md); `start` is
## the corner to begin at, by street names as OSM spells them: [street, cross street] puts
## the car on the first just past the second. Without one it starts on a main road
## mid-town.
const LEVELS := [
	{"name": "Givatayim", "city": "givatayim", "start": ["המרי", "שיינקין"], "look": "med"},
	{"name": "Bedford, Nova Scotia", "city": "bedford", "look": "north"},
	{"name": "Ashdod", "city": "ashdod", "start": ["שדרות הרצל", "החלוצים"], "look": "med"},
	# made up by tools/fake_city.py: one small town with one of everything, ringed by mountains,
	# that loads in a moment -- for checking a change, not for exploring
	{"name": "Kiryat Dimyon (test town)", "city": "dimyon", "start": ["הנשיא", "השוק"], "look": "med"},
	# a walk filmed in Givatayim, replayed in first person on its own (cities/details/givatayim.json)
	{"name": "A walk in Givatayim: Katzenelson to Ha-Meri", "city": "givatayim", "look": "med", "walk": "katzenelson_hameri"},
]
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md

## ---- the car, in real units (metres, seconds, kilograms, newtons) ----
const MASS := 1300.0
const WHEELBASE := 2.65
const CAR_LEN := 4.4
const CAR_WIDTH := 1.9
const CAR_HEIGHT := 1.55
const ENGINE_F := 5200.0             ## pull off the line, ~4 m/s^2
const POWER := 70000.0               ## then power-limited: ~150 km/h flat out
const REVERSE_F := 3000.0
const REVERSE_MAX := 6.0             ## ~22 km/h backwards
const BRAKE_F := 10500.0             ## ~8 m/s^2, a firm stop
const DRAG := 0.8                    ## 1/2 rho Cd A
const ROLL := 180.0                  ## rolling resistance
const ENGINE_BRAKE := 520.0          ## off the throttle
const MAX_STEER := 0.6               ## front wheel lock, radians (~34 degrees)
const STEER_V := 15.0                ## keyboard steering halves by this speed (m/s)
const STEER_RATE := 2.4              ## keyboard: lock to centre in ~0.4 s
const GRIP := 8.8                    ## tyres give up past ~0.9 g sideways: understeer
const CAR_R := 0.95                  ## the car is two circles of this radius...
const CAR_OFF := 1.25                ## ...this far ahead of and behind its centre
const BOUNCE := 0.12                 ## how much of a knock bounces back (a real car crumples: ~0.1-0.15; 0.45 was a bumper car)
const WALL_GRIP := 0.45              ## speed lost scraping along a wall, per m/s of impact
## Driving assist (on by default; the "assist" button switches it): straightens the car
## along the street and into its lane while you are not steering much, brakes before a
## wall, tree or pole, and puts you back on the road when you are pinned against one.
const ASSIST_ALIGN := 1.1            ## wheel angle per radian the car points off the road
const ASSIST_LANE := 0.07            ## wheel angle per metre off the middle of the lane
const ASSIST_MAX := 0.22             ## the most it ever turns the wheel, radians
const ASSIST_FADE := 0.35            ## steering input at which it lets go completely
const RESCUE_AFTER := 1.2            ## seconds stuck against something, pedal down, before a rescue

## Drivable road kinds and the speed autodrive keeps on them (m/s): Israeli urban limits,
## 50 on through roads, 40 on residential streets. Kinds not listed are footpaths: drawn,
## not driven by autodrive, though nothing stops you mounting the pavement.
const DRIVE := {
	"motorway": 25.0, "trunk": 22.0, "primary": 13.9, "secondary": 13.9, "tertiary": 13.9,
	"unclassified": 13.9, "residential": 13.9, "living_street": 5.5, "service": 6.0,
	"road": 13.9, "motorway_link": 16.0, "trunk_link": 13.9, "primary_link": 11.1,
	"secondary_link": 11.1, "tertiary_link": 11.1, "busway": 11.1,
}
## roads with no pavement: no kerbs, no people walking along them
const HIGHWAYS := {"motorway": true, "trunk": true, "motorway_link": true, "trunk_link": true}
## suburban main roads in the north are 60-70, not the 50 of a town's streets
const NORTH_FASTER := {"primary": 1.4, "secondary": 1.2}   # 70 and 60 km/h
## streets that get a row of trees along each pavement (Givatayim's are lined with them,
## and OSM maps few of them one by one) -- an embellishment, see GAME.md
const TREE_ROADS := ["primary", "secondary", "tertiary", "residential", "living_street", "unclassified"]
const TREE_GAP := 11.0
const MAX_TREES := 16000
const MAX_FOREST := 14000            ## trees added in parks and woods, on top
## Places from the map, by OSM kind: [palette role, what to call one with no name].
## Food is yellow, shops pink, health green, services blue, learning/culture/worship purple.
const POI_LOOK := {
	"restaurant": ["warn", "restaurant"], "cafe": ["warn", "café"], "fast_food": ["warn", "fast food"],
	"bar": ["warn", "bar"], "pub": ["warn", "pub"], "ice_cream": ["warn", "ice cream"],
	"shop": ["accent", "shop"],
	"pharmacy": ["friend", "pharmacy"], "clinic": ["friend", "clinic"], "doctors": ["friend", "doctor"],
	"dentist": ["friend", "dentist"],
	"bank": ["player", "bank"], "post_office": ["player", "post office"], "fuel": ["player", "fuel"],
	"school": ["prize", "school"], "kindergarten": ["prize", "kindergarten"], "library": ["prize", "library"],
	"place_of_worship": ["prize", "place of worship"], "cinema": ["prize", "cinema"],
	"theatre": ["prize", "theatre"], "community_centre": ["prize", "community centre"],
	"hotel": ["player", "hotel"], "museum": ["prize", "museum"], "attraction": ["prize", "attraction"],
}
## what to call an unnamed shop, by its OSM type (others: the type, spaced)
const SHOP_WORDS := {
	"supermarket": "supermarket", "convenience": "mini market", "bakery": "bakery",
	"greengrocer": "fruit & veg", "butcher": "butcher", "kiosk": "kiosk", "clothes": "clothes",
	"shoes": "shoes", "hairdresser": "hairdresser", "beauty": "beauty", "optician": "optician",
	"mobile_phone": "phones", "florist": "flowers", "laundry": "laundry", "dry_cleaning": "dry cleaning",
	"hardware": "hardware", "books": "books", "toys": "toys", "jewelry": "jewellery",
	"alcohol": "wine & spirits", "confectionery": "sweets", "pet": "pet shop", "furniture": "furniture",
	"electronics": "electronics", "car_repair": "garage", "variety_store": "everything shop",
}
const WIDE_SHOPS := ["supermarket", "department_store", "furniture", "hardware", "doityourself"]
const AWNINGS := ["accent", "prize", "player", "warn", "friend"]
const SIGN_RANGE := 110.0            ## signs further than this are not drawn
## People on the pavements: walkers kept around the car (respawned near it when left far
## behind), and some standing about by the cafe tables
const PEOPLE := ["Casual_Male", "Casual_Female", "Casual2_Male", "Casual2_Female", "Casual3_Female"]
const WALKERS := 18
const CHATTERS := 8
const PEOPLE_RANGE := 150.0
const PEOPLE_SEEN := 90.0            ## people further than this are not drawn or animated
const SIGNAL_CYCLE := [              ## [seconds, phase of group 1 (the junction's main road), of group 2]
	[20.0, "g", "r"], [3.0, "y", "r"], [2.5, "r", "r"],
	[11.0, "r", "g"], [3.0, "r", "y"], [2.5, "r", "r"],   # (all red 2.5 s: a big junction takes that to clear)
]   # (the main road's green the longer, as the town's own lights run: with 14 s each way a
    # main road was stop and go behind every red; see DEV.md for what the exam made of it)

const SEG_CELL := 24.0               ## spatial hash cell for road segments (m)
const BLD_CELL := 24.0
const CHUNK := 400.0                 ## buildings and trees are merged per square this big, for culling
const VIEW_RANGE := 1100.0           ## building chunks further than this are not drawn
const DETAIL_RANGE := 260.0          ## kerbs, road markings, garden walls: drawn this far
const GROUND_CELL := 400.0           ## squares the ground details are cut into (big: each layer is a draw a square)
const TREE_RANGE := 550.0
const LAMP_RANGE := 320.0            ## lamp posts, traffic-light poles: thin, gone in the haze
## The ground's layers, centimetres apart: a phone's depth buffer is coarser than a
## desktop's, and at 2 cm the grass under a road showed through it in green patches
const Y_AREA := 0.012
const Y_PATH := 0.03
const Y_ROAD := 0.065
const Y_MARK := 0.085
const NEW_STREET_M := 30.0           ## drive this far along a street for it to count
const MAP_R := 210.0                 ## the minimap shows this far around the car (m)
const AP_LAT := 3.6                  ## autodrive keeps the sideways pull in turns under this (m/s^2)
## Ground steeper than this (rise per metre, about 32 degrees) cannot be driven or walked up:
## it is as solid as a wall. No real town so far has any (Givatayim's steepest is 52%); the
## made-up town's mountains do, and they are what keeps it a valley.
const STEEP := 0.62

## Facades: a wall colour, a window grid per storey, a darker ground floor. UV is (metres
## along this wall, metres above the ground); UV2 is (wall length, roof height). COLOR.r is
## the building's brightness and COLOR.g how far it leans to the second wall tone.
## Facades. UV is (metres along this wall, metres above the building's lowest ground);
## UV2 is (wall length, roof height). Vertex COLOR carries the building: r brightness,
## g lean to the second tone, a lean to the stone tone, b the facade style:
##   0 punched windows with roller shutters (trisim) and the odd AC unit
##   1 balcony rows: a shaded recess per bay behind a parapet
##   2 Bauhaus ribbon windows        3 glass tower
## Ground floors of blocks are open between pillars (pilotis), towers get a glass lobby,
## and houses (under ~10 m) have windows from the ground up.
## Within ~150 m (and above the lowest web quality) the windows are not paint but depth,
## all worked out per pixel from the view, no geometry: the glass sits in a recess whose
## sides you see as you pass, and behind it is a room -- a ray from the eye is followed into
## a box the size of the bay (back wall with a sofa, a door or a picture, side walls, floor,
## ceiling: "interior mapping"), dim by day, lamp-lit at night if the room is. The pane
## reflects the sky (the street below the horizon), more at a glancing look; frames, slatted
## shutters and sills are drawn at the pane, softened to an average where a pixel is wider
## than they are. Balconies and the open ground floor are traced the same way, as hollows.
## Every colour in a room is one of the palette's wall tones, so /look still reskins them.
const WALL_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 wall_a : source_color;
uniform vec4 wall_b : source_color;
uniform vec4 wall_c : source_color;
uniform vec4 wall_d : source_color;   // yellow plaster
uniform vec4 wall_e : source_color;   // peach plaster
uniform vec4 wall_f : source_color;   // grey render
uniform vec4 glass : source_color;
uniform vec4 glass_b : source_color;  // a tower's tinted glass: blue, green, silver
uniform vec4 glass_c : source_color;
uniform vec4 glass_d : source_color;
uniform vec4 shutter : source_color;
uniform vec4 dark : source_color;
uniform vec4 lit : source_color;      // a lit room, at night
uniform vec4 lit_cool : source_color; // an office
uniform float night = 0.0;
uniform float siding = 0.0;           // northern houses: clapboard, white-framed windows
uniform vec4 trim : source_color;
uniform float textured = 1.0;         // photo plaster and the windows' depth (off at the lowest quality)
uniform sampler2D plaster_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 plaster_mean = vec3(0.5);
uniform vec4 sky_top : source_color;  // what the glass reflects: the sky as it is now
uniform vec4 sky_hor : source_color;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// In the functions below a window's own frame is used: x metres along the wall from the bay's
// left edge, y metres up from its floor, z out of the wall. v is the direction to the eye in
// that frame (v.z > 0); a ray from the eye goes the other way, m = -v.xy sideways for every
// v.z it goes in.

// The ray into an opening [lo, hi] whose pane sits rd into the wall: where it meets the pane
// (0, at g) or, before that, the side of the opening it runs into (1 its left side, 2 its
// right, 3 the sill, 4 the lintel) at depth dd.
int recess(vec2 p, vec3 v, vec2 lo, vec2 hi, float rd, out vec2 g, out float dd) {
	vec2 m = -v.xy;
	g = p + m * (rd / v.z);
	dd = rd;
	if (g.x >= lo.x && g.x <= hi.x && g.y >= lo.y && g.y <= hi.y) {
		return 0;
	}
	float tx = m.x < 0.0 ? (lo.x - p.x) / min(m.x, -0.0001) : (hi.x - p.x) / max(m.x, 0.0001);
	float ty = m.y < 0.0 ? (lo.y - p.y) / min(m.y, -0.0001) : (hi.y - p.y) / max(m.y, 0.0001);
	if (tx < ty) {
		dd = tx * v.z;
		g = p + m * tx;
		return m.x < 0.0 ? 1 : 2;
	}
	dd = ty * v.z;
	g = p + m * ty;
	return m.y < 0.0 ? 3 : 4;
}

// The room behind a pane met at g: a box from the bay's left to right edge, floor to ceiling
// and `deep` metres back. What the ray lands on, lit by the window's daylight (falling off
// into the room) or, at night, by the room's lamp if it is on. `blur` (0..1) fades the
// furniture to the walls' colour where a pixel is wider than it.
vec3 room_at(vec2 g, vec3 v, float cw, float deep, float rs, vec3 wallc, vec3 floorc, vec3 ceilc,
		vec3 sofac, vec3 lamp, float lit_on, float blur) {
	vec2 m = -v.xy;
	float tz = deep / v.z;
	float tx = m.x < 0.0 ? (0.05 - g.x) / min(m.x, -0.0001) : (cw - 0.05 - g.x) / max(m.x, 0.0001);
	float ty = m.y < 0.0 ? (0.0 - g.y) / min(m.y, -0.0001) : (2.8 - g.y) / max(m.y, 0.0001);
	float t = min(tz, min(tx, ty));
	vec2 h = g + m * t;
	float depth = t * v.z;
	vec3 c = wallc;
	float lgt = 0.55;   // side walls
	if (t == tz) {   // the back wall: a sofa or a cabinet, a door through, a picture
		lgt = 0.8;
		vec3 thing = c;
		if (h.y < 0.75 && h.x > cw * 0.12 && h.x < cw * 0.58) {
			thing = sofac;
		} else if (rs > 0.5 && h.x > cw * 0.66 && h.x < cw * 0.9 && h.y < 2.05) {
			thing = wallc * 0.45;
		} else if (rs < 0.3 && h.y > 1.35 && h.y < 1.85 && h.x > cw * 0.22 && h.x < cw * 0.46) {
			thing = sofac.bgr * 1.2;
		}
		c = mix(thing, c, blur);
	} else if (t == ty) {
		if (m.y < 0.0) {
			c = floorc;
			lgt = 0.62;
		} else {
			c = ceilc;
			lgt = 0.42;
		}
	}
	float day = lgt * (1.0 - depth / (deep + 3.0)) * 0.46;
	vec3 lamp_c = lamp * (0.45 + 0.55 * lgt) * lit_on;
	return c * mix(vec3(day), lamp_c, night);
}

// A pane: the room through it and the sky in it, more sky the more glancing the look (and
// always some: double glazing). `elev` is how far up the reflected ray points; below the
// horizon it shows the street and the houses across it.
vec3 pane(vec3 room_c, vec3 v, float elev, vec3 tint, vec3 street, float floor_f) {
	float f = mix(floor_f, 1.0, pow(1.0 - clamp(v.z, 0.0, 1.0), 3.0));
	vec3 sk = elev > 0.0 ? mix(sky_hor.rgb, sky_top.rgb, smoothstep(0.0, 0.45, elev))
		: mix(sky_hor.rgb * 0.85, street, 1.0 - smoothstep(-0.12, 0.0, elev));
	return mix(room_c * tint, sk * mix(vec3(1.0), tint, 0.35), f);
}

// how much of a line `w` wide (half-width) at distance d covers a pixel `aa` metres wide
float line_cover(float d, float w, float aa) {
	return clamp((w - d) / aa + 0.5, 0.0, 1.0);
}

void fragment() {
	// the slopes the lookups, the bump frame and the line widths need, taken before any branch
	vec2 puv = UV * 0.5;   // the plaster photo is 2 m across
	vec2 pdx = dFdx(puv);
	vec2 pdy = dFdy(puv);
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	float aa = max(2.0 * max(length(pdx), length(pdy)), 0.002);   // metres one pixel covers
	// COLOR.g picks the plaster (0 plain, then a pastel, yellow, peach, grey), COLOR.a how
	// far toward beige stone; a tinted plaster takes less of the stone
	float tk = floor(COLOR.g * 4.0 + 0.5);
	vec3 plaster = tk < 0.5 ? wall_a.rgb : (tk < 1.5 ? wall_b.rgb : (tk < 2.5 ? wall_d.rgb : (tk < 3.5 ? wall_e.rgb : wall_f.rgb)));
	vec3 base = mix(plaster, wall_c.rgb, COLOR.a * (tk < 0.5 ? 1.0 : 0.3)) * COLOR.r;
	// the render's own texture: a photo over its average, so the palette keeps the colour.
	// Clapboard (siding) takes it faintly: painted wood is not rough render.
	vec3 pb = vec3(0.0, 0.0, 1.0);
	if (textured > 0.5) {
		vec3 t = textureGrad(plaster_tex, puv, pdx, pdy).rgb;
		float k = siding > 0.5 ? 0.3 : 0.75;
		base *= mix(1.0, clamp(dot(t, vec3(0.333)) / dot(plaster_mean, vec3(0.333)), 0.0, 2.0), k);
		vec2 xy = (textureGrad(plaster_nrm, puv, pdx, pdy).rg * 2.0 - 1.0) * (siding > 0.5 ? 0.4 : 1.0);
		pb = vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
	}
	float pl = 1.0;   // 0 where the pixel is glass, a shutter or a frame: no plaster bumps there
	// the wall's own frame in view space: along it (the way UV.x grows), up, out of it
	vec3 nn = NORMAL;
	vec3 q2 = cross(dp2, nn);
	vec3 q1 = cross(nn, dp1);
	vec3 tt = q2 * pdx.x + q1 * pdy.x;
	vec3 bb = q2 * pdx.y + q1 * pdy.y;
	vec3 bv = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec3 tv = normalize(cross(bv, nn));
	if (dot(tv, tt) < 0.0) {
		tv = -tv;
	}
	vec3 to_eye = -normalize(VERTEX);
	vec3 v = vec3(dot(to_eye, tv), dot(to_eye, bv), max(dot(to_eye, nn), 0.03));
	float elev = -(INV_VIEW_MATRIX * vec4(to_eye, 0.0)).y;
	float near3d = textured * (1.0 - smoothstep(110.0, 220.0, length(VERTEX)));

	vec3 tower = tk < 0.5 ? glass.rgb : (tk < 1.5 ? glass_b.rgb : (tk < 2.5 ? glass_c.rgb : (tk < 3.5 ? glass_d.rgb : glass.rgb * 0.8)));
	float style = floor(COLOR.b * 3.99);
	float along = UV.x;
	float up = UV.y;
	float len = UV2.x;
	float top = UV2.y;
	float n = max(1.0, floor(len / 3.3));
	float cell = along / (len / n);
	float ci = floor(cell);
	float fx = fract(cell);
	float lv = floor(up / 3.0);
	float fy = fract(up / 3.0);
	// whole numbers only: interpolated vertex colours wobble in the last bits, and the hash
	// turned that wobble into grain across every window
	float seed = floor(COLOR.r * 50.0 + 0.5) * 7.0 + floor(COLOR.a * 10.0 + 0.5) * 13.0 + floor(COLOR.b * 4.0 + 0.5) * 5.0;
	float r1 = hash(vec2(ci, lv) + seed);
	float r2 = hash(vec2(ci + 13.0, lv * 3.0) + seed);
	// Stone and tile, as Givatayim's walls are: COLOR.a high is Jerusalem stone, laid in
	// courses of blocks; most blocks have a stone plinth to knee height whatever the walls
	// above; one white block in five is clad in small square mosaic tiles. Drawn only while a
	// pixel is smaller than the joints are wide apart, an average further off.
	float stone_k = COLOR.a;
	bool plinth = up < 0.9 && siding < 0.5 && hash(vec2(seed, 3.7)) < 0.6;
	if (siding < 0.5 && (stone_k > 0.45 || plinth)) {
		float course = 0.33;
		float row = floor(up / course);
		float bl = 0.55 + 0.35 * hash(vec2(row, seed + 1.0));
		float xs = along / bl + hash(vec2(row, seed));
		vec2 f = vec2(fract(xs) * bl, fract(up / course) * course);
		float jd = min(min(f.x, bl - f.x), min(f.y, course - f.y));
		vec3 sc = (plinth && stone_k <= 0.45) ? wall_c.rgb * COLOR.r * 0.9 : base;
		sc *= 0.94 + 0.12 * hash(vec2(floor(xs), row) + seed);
		base = mix(sc, sc * 0.72, line_cover(jd, 0.005, aa) * (1.0 - smoothstep(0.02, 0.06, aa)));
	} else if (siding < 0.5 && tk < 0.5 && stone_k < 0.2 && hash(vec2(seed, 9.1)) < 0.2) {
		vec2 tg = vec2(along, up) / 0.024;
		vec2 tf = abs(fract(tg) - 0.5);
		float tj = smoothstep(0.38, 0.46, max(tf.x, tf.y));
		base *= mix(1.0, (0.97 + 0.05 * hash(floor(tg) + seed)) * mix(1.0, 0.86, tj), 1.0 - smoothstep(0.006, 0.02, aa));
	}
	vec3 col = base;
	float rough = 0.92;
	// at night some rooms have the light on: warm in homes, cooler in offices
	float r3 = hash(vec2(ci * 1.7 + 3.0, lv * 2.3) + seed);
	vec3 room = r3 < 0.36 ? mix(lit.rgb, lit.rgb * 0.7, r2) : vec3(0.0);
	vec3 emit = vec3(0.0);
	bool facade = len >= 2.5 && up < top - 0.9;
	bool upper = up >= 3.0 || top < 10.0;
	// A block's ground floor: flats behind barred windows (the floors above are style's), the
	// way in -- a glazed door -- in the middle bay. (A block that really stands on columns has
	// no wall there at all: its walls start a storey up.)
	bool ground = !upper && style < 2.5;
	float wstyle = ground ? 0.0 : style;
	bool door = ground && n >= 2.0 && ci == floor(n * 0.5);
	if (siding > 0.5 && style < 0.5 && facade && fract(up / 0.24) < 0.13) {
		col *= 0.88;
	}
	// ---- the flat facade: paint only (far away, and the whole look at the lowest quality)
	if (facade && door) {
		if (fx > 0.27 && fx < 0.73 && fy < 0.78) {
			col = (fx < 0.3 || fx > 0.7 || fy > 0.75) ? trim.rgb * 0.8 : glass.rgb * 0.7;
			pl = 0.0;
			rough = 0.25;
			emit = lit.rgb * 0.5;
		}
	} else if (facade && (upper || ground)) {
		if (wstyle < 0.5 && siding > 0.5) {
			if (fx > 0.25 && fx < 0.75 && fy > 0.28 && fy < 0.84) {
				bool frame = fx < 0.29 || fx > 0.71 || fy < 0.32 || fy > 0.8 || abs(fx - 0.5) < 0.012 || abs(fy - 0.56) < 0.012;
				col = frame ? trim.rgb : glass.rgb;
				pl = 0.0;
				rough = frame ? 0.6 : 0.2;
				emit = frame ? vec3(0.0) : room;
			}
		} else if (wstyle < 0.5) {
			if (fx > 0.22 && fx < 0.78 && fy > 0.3 && fy < 0.85) {
				float shut = r1 > 0.45 ? (r1 - 0.45) * 1.6 : 0.0;
				bool closed = fy > 0.85 - 0.55 * shut;
				col = closed ? shutter.rgb : glass.rgb;
				pl = 0.0;
				rough = closed ? 0.8 : 0.2;
				emit = closed ? room * 0.12 : room;
			}
			if (r2 < 0.22 && fx > 0.56 && fx < 0.76 && fy > 0.1 && fy < 0.26) {
				col = shutter.rgb * 0.97;
				pl = 0.0;
			} else if (fx > 0.24 && fx < 0.76 && fy < 0.3 && siding < 0.5) {
				// a faint streak of grime down from the sill above
				col *= 1.0 - (fy / 0.3) * (0.04 + 0.06 * r2) * (1.0 - abs(fx - 0.5) * 3.0);
			}
			if (fy < 0.06) {
				col *= 0.88;
			}
		} else if (style < 1.5) {
			if (fx > 0.06 && fx < 0.94 && fy < 0.88) {
				if (fy < 0.34) {
					col = base * 1.05;
				} else {
					col = dark.rgb;
					pl = 0.0;
					if (fx > 0.3 && fx < 0.7 && fy > 0.36 && fy < 0.84) {
						col = r1 > 0.6 ? shutter.rgb : glass.rgb * 0.8;
						rough = 0.25;
						emit = r1 > 0.6 ? room * 0.12 : room;
					}
				}
			}
			if (fy > 0.88 && fy < 0.95) {
				col = base * 1.12;
			}
		} else if (style < 2.5) {
			if (fy > 0.38 && fy < 0.78 && fx > 0.04 && fx < 0.96) {
				col = glass.rgb;
				pl = 0.0;
				rough = 0.2;
				emit = room;
			}
		} else {
			if (fx > 0.04 && fx < 0.96 && fy > 0.08 && fy < 0.96) {
				col = tower * (0.85 + 0.3 * r1);
				pl = 0.0;
				rough = 0.12;
				emit = r3 < 0.3 ? lit_cool.rgb * (0.7 + 0.3 * r2) : vec3(0.0);
			}
		}
	} else if (facade && up < 2.7 && style > 2.5) {
		if (fx > 0.04) {
			col = glass.rgb;
			pl = 0.0;
			rough = 0.15;
			emit = lit_cool.rgb * 0.8;
		}
	}
	emit *= night * 1.25;

	// ---- the deep facade: recesses, rooms, reflections (near, and not at the lowest quality)
	bool deep_hit = false;
	vec3 col2 = col;
	vec3 emit2 = emit;
	float rough2 = rough;
	vec3 nrm2 = nn;
	float spec2 = 0.35;
	if (near3d > 0.0 && facade) {
		float cw = len / n;
		vec2 p = vec2(fx * cw, fy * 3.0);
		float r4 = hash(vec2(ci * 2.3 + 5.0, lv * 1.7) + seed);
		float r5 = hash(vec2(ci * 0.7 + 9.0, lv * 4.1) + seed);
		vec3 wallc = mix(wall_a.rgb, mix(wall_d.rgb, wall_b.rgb, r5), r4 * 0.6);
		vec3 floorc = r5 < 0.5 ? wall_e.rgb * 0.6 : wall_f.rgb * 0.8;
		vec3 sofac = mix(glass_b.rgb, wall_e.rgb, r4) * 0.75;
		vec3 lamp = mix(lit.rgb, lit.rgb * 0.7, r2);
		float lit_on = r3 < 0.36 ? 1.0 : 0.0;
		vec3 street = base * 0.55;
		vec3 tint = mix(vec3(1.0), glass.rgb / max(max(glass.r, glass.g), max(glass.b, 0.05)), 0.45);
		float blur = smoothstep(0.05, 0.2, aa);
		float wob = (r1 - 0.5) * 0.06;   // no two panes sit quite flat: each reflects a little differently
		if ((upper || ground) && wstyle < 0.5) {
			// punched windows (houses: inside a white casing), a recess, a sliding window or a
			// roller shutter part-way down, and a stone sill under it; on a block's ground floor
			// bars over them, and the door in the middle bay
			bool house = siding > 0.5;
			vec2 lo = house ? vec2(0.29 * cw, 0.96) : vec2(0.22 * cw, 0.9);
			vec2 hi = house ? vec2(0.71 * cw, 2.4) : vec2(0.78 * cw, 2.55);
			float rd = house ? 0.07 : 0.16;
			if (door) {
				lo = vec2(0.28 * cw, 0.0);
				hi = vec2(0.72 * cw, 2.3);
				rd = 0.3;
			}
			if (p.x > lo.x && p.x < hi.x && p.y > lo.y && p.y < hi.y) {
				deep_hit = true;
				vec2 g;
				float dd;
				int k = recess(p, v, lo, hi, rd, g, dd);
				if (k > 0) {
					col2 = (house ? trim.rgb : base) * (0.95 - 0.3 * dd / rd);
					nrm2 = k == 1 ? tv : (k == 2 ? -tv : (k == 3 ? bv : -bv));
					emit2 = vec3(0.0);
					rough2 = 0.85;
				} else {
					float shut = (r1 > 0.45 && !house && !door) ? (r1 - 0.45) * 1.6 : 0.0;
					float sy = hi.y - (hi.y - lo.y) * shut;
					if (g.y > sy) {   // the shutter's slats, and the room's light between them
						float sl = fract(g.y / 0.045);
						float gap = sl < 0.18 ? 1.0 : 0.0;
						float sharp = clamp(1.0 - aa / 0.03, 0.0, 1.0);
						col2 = shutter.rgb * mix(0.93, gap > 0.5 ? 0.72 : 0.96 + 0.08 * sl, sharp);
						emit2 = room * night * mix(0.06, gap * 0.25, sharp);
						rough2 = 0.75;
					} else {
						vec3 rc = door ? room_at(g, v, cw, 6.0, 1.0, wall_a.rgb, wall_f.rgb * 0.7, wall_a.rgb, wall_a.rgb * 0.8, lit.rgb, 1.0, blur)
							: room_at(g, v, cw, 3.5 + 2.0 * r4, r5, wallc, floorc, wall_a.rgb, sofac, lamp, lit_on, blur);
						// a curtain drawn part way across from one side
						float cur = r2 > 0.55 ? (r2 - 0.55) * 1.4 : 0.0;
						if ((r4 > 0.5 ? g.x - lo.x : hi.x - g.x) < (hi.x - lo.x) * cur) {
							rc = wall_a.rgb * mix(vec3(0.33), lamp * lit_on * 0.8, night);
						}
						// the frame round the glass and, Israeli style, the middle of a sliding window
						float fw = house ? 0.025 : 0.045;
						float dfr = min(min(g.x - lo.x, hi.x - g.x), min(g.y - lo.y, sy - g.y));
						float cover = line_cover(dfr, fw, aa);
						cover = max(cover, line_cover(abs(g.x - (lo.x + hi.x) * 0.5), house ? 0.012 : 0.028, aa));
						if (house) {   // a cross of muntins
							cover = max(cover, line_cover(abs(g.y - (lo.y + hi.y) * 0.5), 0.012, aa));
						}
						if (ground && !door) {   // security bars, white, every 13 cm, and a rail across
							cover = max(cover, line_cover(abs(fract((g.x - lo.x) / 0.13) - 0.5) * 0.13, 0.008, aa));
							cover = max(cover, line_cover(abs(g.y - (lo.y + sy) * 0.5), 0.01, aa));
						}
						col2 = mix(vec3(0.02), trim.rgb * 0.85, cover);
						emit2 = pane(rc, v, elev + wob, tint, street, 0.11) * (1.0 - cover);
						rough2 = mix(0.06, 0.5, cover);
						spec2 = 0.5;
					}
				}
			} else if (!house && !door && p.x > lo.x - 0.06 && p.x < hi.x + 0.06 && p.y < lo.y && p.y > lo.y - 0.12) {
				// the sill: its lit top edge, the shadow under it
				deep_hit = true;
				col2 = p.y > lo.y - 0.05 ? base * 1.1 : base * 0.74;
			}
		} else if (upper && style > 0.5 && style < 1.5) {
			// a balcony: a hollow 1.4 m deep behind the parapet, a glass door at its back
			vec2 lo = vec2(0.06 * cw, 1.02);
			vec2 hi = vec2(0.94 * cw, 2.64);
			if (p.x > lo.x && p.x < hi.x && p.y > lo.y && p.y < hi.y) {
				deep_hit = true;
				vec2 m = -v.xy;
				float tz = 1.4 / v.z;
				float tx = m.x < 0.0 ? (lo.x - p.x) / min(m.x, -0.0001) : (hi.x - p.x) / max(m.x, 0.0001);
				float ty = m.y < 0.0 ? (0.06 - p.y) / min(m.y, -0.0001) : (hi.y - p.y) / max(m.y, 0.0001);
				float t = min(tz, min(tx, ty));
				vec2 h = p + m * t;
				float shade = 1.0 - 0.35 * t * v.z / 1.4;
				emit2 = vec3(0.0);
				rough2 = 0.85;
				if (t == tz) {
					vec2 dlo = vec2(0.3 * cw, 0.06);
					vec2 dhi = vec2(0.7 * cw, 2.3);
					if (h.x > dlo.x && h.x < dhi.x && h.y < dhi.y) {
						if (r1 > 0.6) {   // its shutter down
							float sl = fract(h.y / 0.045);
							col2 = shutter.rgb * shade * mix(0.93, sl < 0.18 ? 0.72 : 1.0, clamp(1.0 - aa / 0.03, 0.0, 1.0));
							emit2 = room * 0.12 * night;
						} else {
							vec3 rc = room_at(h, v, cw, 4.0, r5, wallc, floorc, wall_a.rgb, sofac, lamp, lit_on, blur);
							float dfr = min(min(h.x - dlo.x, dhi.x - h.x), dhi.y - h.y);
							float cover = max(line_cover(dfr, 0.045, aa), line_cover(abs(h.x - cw * 0.5), 0.028, aa));
							col2 = mix(vec3(0.02), trim.rgb * 0.8 * shade, cover);
							emit2 = pane(rc, v, elev + wob, tint, street, 0.11) * (1.0 - cover) * mix(0.75, 1.0, night);
							rough2 = mix(0.06, 0.5, cover);
							spec2 = 0.5;
						}
					} else {
						col2 = base * 0.9 * shade;
					}
				} else if (t == ty) {   // its tiled floor, or the slab over it seen from below
					col2 = m.y < 0.0 ? floorc * 1.2 * shade : base * 0.85 * shade;
					nrm2 = m.y < 0.0 ? bv : -bv;
				} else {
					col2 = base * 0.95 * shade;
					nrm2 = m.x < 0.0 ? tv : -tv;
				}
			}
		} else if (upper && style > 1.5 && style < 2.5) {
			// Bauhaus ribbon windows: one long recess, a mullion every third of a bay
			vec2 lo = vec2(0.04 * cw, 1.14);
			vec2 hi = vec2(0.96 * cw, 2.34);
			if (p.x > lo.x && p.x < hi.x && p.y > lo.y && p.y < hi.y) {
				deep_hit = true;
				vec2 g;
				float dd;
				int k = recess(p, v, lo, hi, 0.12, g, dd);
				if (k > 0) {
					col2 = base * (0.95 - 0.3 * dd / 0.12);
					nrm2 = k == 1 ? tv : (k == 2 ? -tv : (k == 3 ? bv : -bv));
					emit2 = vec3(0.0);
					rough2 = 0.85;
				} else {
					vec3 rc = room_at(g, v, cw, 4.0, r5, wallc, floorc, wall_a.rgb, sofac, lamp, lit_on, blur);
					float third = (hi.x - lo.x) / 3.0;
					float dm = abs(fract((g.x - lo.x) / third + 0.5) - 0.5) * third;
					float dfr = min(min(g.x - lo.x, hi.x - g.x), min(g.y - lo.y, hi.y - g.y));
					float cover = max(line_cover(dfr, 0.04, aa), line_cover(dm, 0.025, aa));
					col2 = mix(vec3(0.02), dark.rgb * 1.4, cover);
					emit2 = pane(rc, v, elev + wob, tint, street, 0.11) * (1.0 - cover);
					rough2 = mix(0.06, 0.5, cover);
					spec2 = 0.5;
				}
			}
		} else if (upper && style > 2.5) {
			// a tower's curtain wall: flush tinted glass, offices behind it
			vec2 lo = vec2(0.04 * cw, 0.24);
			vec2 hi = vec2(0.96 * cw, 2.88);
			if (p.x > lo.x && p.x < hi.x && p.y > lo.y && p.y < hi.y) {
				deep_hit = true;
				vec3 ttint = mix(vec3(1.0), tower / max(max(tower.r, tower.g), max(tower.b, 0.05)), 0.7);
				vec3 offc = mix(wall_a.rgb, wall_f.rgb, 0.5);
				vec3 rc = room_at(p, v, cw, 6.0, r5, offc, wall_f.rgb * 0.6, wall_a.rgb, wall_f.rgb * 0.5,
					lit_cool.rgb * (0.7 + 0.3 * r2), r3 < 0.3 ? 1.0 : 0.0, blur);
				float dfr = min(min(p.x - lo.x, hi.x - p.x), min(p.y - lo.y, hi.y - p.y));
				float cover = line_cover(dfr, 0.035, aa);
				col2 = mix(vec3(0.02), tower * 0.6, cover);
				emit2 = pane(rc, v, elev + wob * 0.5, ttint, street, 0.35) * (1.0 - cover);
				rough2 = mix(0.05, 0.4, cover);
				spec2 = 0.6;
			}
		} else if (!upper && up < 2.7) {
			if (style > 2.5) {   // a tower's glass lobby, lit at night
				vec2 lo = vec2(0.04 * cw, 0.0);
				vec2 hi = vec2(cw, 2.7);
				if (p.x > lo.x) {
					deep_hit = true;
					vec3 rc = room_at(p, v, cw, 8.0, r5, wall_a.rgb, wall_f.rgb * 0.7, wall_a.rgb, wall_f.rgb * 0.5,
						lit_cool.rgb * 0.8, 1.0, blur);
					float cover = line_cover(min(p.x - lo.x, hi.y - p.y), 0.04, aa);
					col2 = mix(vec3(0.02), tower * 0.6, cover);
					emit2 = pane(rc, v, elev, mix(vec3(1.0), tint, 0.5), street, 0.2) * (1.0 - cover);
					rough2 = mix(0.06, 0.5, cover);
					spec2 = 0.5;
				}
			}
		}
	}
	if (deep_hit) {
		pl = 0.0;
		col = mix(col, col2, near3d);
		emit = mix(emit, emit2, near3d);
		rough = mix(rough, rough2, near3d);
	}
	// the foot of a wall darker: splashed dirt, and less of the sky's light reaches it
	col *= mix(0.74, 1.0, smoothstep(0.0, 1.5, up));
	if (pl > 0.5 && pb.z < 0.99999) {
		// the bump's frame from how the wall's metres run across the screen (works whichever
		// way round an outline was drawn); the photo's "up" is the wall's down (UV.y grows up)
		float inv = inversesqrt(max(max(dot(tt, tt), dot(bb, bb)), 1e-24));
		NORMAL = normalize(tt * inv * pb.x - bb * inv * pb.y + nn * pb.z);
	} else if (deep_hit) {
		NORMAL = normalize(mix(nn, nrm2, near3d));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = deep_hit ? mix(0.35, spec2, near3d) : 0.35;
	EMISSION = emit;
}
"""

## Triangle soup for one merged mesh surface. Godot treats CLOCKWISE triangles as front
## faces, so tri() takes the normal the face should have and fixes the winding itself.
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color,
			ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO, u2 := Vector2.ZERO) -> void:
		if (b - a).cross(d - a).dot(nrm) > 0.0:
			var t := b
			b = d
			d = t
			var tu := ub
			ub = ud
			ud = tu
		v.append(a)
		v.append(b)
		v.append(d)
		for i in 3:
			n.append(nrm)
			c.append(col)
			uv2.append(u2)
		uv.append(ua)
		uv.append(ub)
		uv.append(ud)

	## a flat quad on the ground (y up), corners in order around it
	func flat(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, y: float, col := Color.WHITE) -> void:
		var a := Vector3(p0.x, y, p0.y)
		var b := Vector3(p1.x, y, p1.y)
		var d := Vector3(p2.x, y, p2.y)
		var e := Vector3(p3.x, y, p3.y)
		tri(a, b, d, Vector3.UP, col)
		tri(a, d, e, Vector3.UP, col)

	## a quad on the ground with its own heights (corners in order around it)
	func quad3(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col := Color.WHITE) -> void:
		var nrm := (d - a).cross(b - a)
		if nrm.y < 0.0:
			nrm = -nrm
		nrm = nrm.normalized() if nrm.length_squared() > 0.000001 else Vector3.UP
		tri(a, b, d, nrm, col)
		tri(a, d, e, nrm, col)

	func empty() -> bool:
		return v.is_empty()

	## for the city-wide kinds (roads, kerbs, lawns...): a Buf per square of the map instead,
	## see CBuf
	func parts() -> Dictionary:
		return {Vector2i.ZERO: self}

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		return a

## A Buf that sorts its triangles into squares of the map as they come, so each square
## becomes its own mesh. One mesh for the whole city is drawn whole every frame, even the
## half behind the camera, and drawn again into the shadow map; squares are skipped when
## off screen or past their range.
class CBuf extends Buf:
	## while one square of the city is built (_build_tile): whether, and which (400 m: TILE)
	static var tiled := false
	static var tile := Vector2i.ZERO
	var cell := 400.0
	## Laid along a road or a fence that every square it crosses works out in full: keep only
	## the triangles that start in the square being built. (Otherwise everything goes into
	## that square's mesh, wherever it reaches: a building over the line is still one.)
	var clip := false
	var _parts := {}
	var _last_key := Vector2i(-99999, -99999)   # triangles come in runs along a street
	var _last: Buf = null

	func _init(size := 400.0) -> void:
		cell = size

	func tri(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color,
			ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO, u2 := Vector2.ZERO) -> void:
		var key := Vector2i(floori(a.x / cell), floori(a.z / cell))
		if tiled:
			var tk := Vector2i(floori(a.x / 400.0), floori(a.z / 400.0))
			if tk != tile:
				if clip:
					return
				key = Vector2i(floori((tile.x + 0.5) * 400.0 / cell), floori((tile.y + 0.5) * 400.0 / cell))
		if key != _last_key:
			_last_key = key
			_last = _parts.get(key)
			if _last == null:
				_last = Buf.new()
				_parts[key] = _last
		_last.tri(a, b, d, nrm, col, ua, ub, ud, u2)

	func empty() -> bool:
		return _parts.is_empty()

	func parts() -> Dictionary:
		return _parts

## ---- city data ----
var _city_name := ""
var _city_id := ""
var _place: Dictionary = {}          ## the LEVELS entry being driven
var _bounds := Rect2()
var _nodes := PackedVector2Array()
var _node_roads: Array = []          ## per node: Array of Vector2i(road, index along it)
var _node_r := PackedFloat32Array()  ## per node: half-width of the widest road through it
var _roads: Array = []               ## {pts, ids, w, k, o, name, en, drive, speed}
var _seg_hash := {}                  ## Vector2i cell -> Array of road * 4096 + segment
var _blds: Array = []                ## PackedVector2Array outlines, counter-clockwise
var _bld_box: Array = []             ## Rect2 per building
var _bld_solid := PackedByteArray()  ## 0 for a building raised on stilts you can drive under
var _bld_kind := PackedByteArray()   ## 1 a block on columns, 2 a house with a pitched roof, 3 balconies
var _bld_hash := {}
var _posts := PackedVector2Array()   ## round things you can hit: trees, signal poles
var _post_r := PackedFloat32Array()
var _post_hash := {}
var _boundary: Array = []            ## PackedVector2Array rings of the city limits
var _streets := {}                   ## name -> true, the named streets inside the limits
var _visited := {}
var _pois: Array = []                ## [Vector2 where, role, sign] for the minimap
var _dressing := {}                  ## how many lamps, solar heaters, tables went in (the report)
var _walkers: Array = []             ## {actor, line (PackedVector2Array), cum, s, dir, speed, dodge}
var _chatters: Array = []            ## {actor, spot}
var _table_spots: Array = []         ## Vector2 of every cafe table
var _furn: RefCounted                ## the street furniture builder (furniture.gd)
var _details: RefCounted             ## what a filmed walk added to the city (details.gd), or null
var _wired := {}                     ## road index -> true: Bedford's lamps hang off its power poles
var _flag_spots: Array = []          ## a flag on a staff off a lamp post (local X out over the road)
var _balcony_flags: Array = []       ## a flag hanging off a balcony's parapet
var _stop_ads: Array = []            ## the lit ad panel at the end of a bus shelter
var _stop_spots := PackedVector2Array()   ## every bus stop on the pavement (buses pull in at them)
var _stop_hash := {}
var _crossing_nodes: Array = []
var _people_t := 0.0
var _people_rng := RandomNumberGenerator.new()
var _hgrid := PackedFloat32Array()   ## ground height (m above the lowest point) on a grid
var _steep := false                  ## some of the ground is too steep to drive up (see STEEP)
var _made_up := false                ## the city file is invented (tools/fake_city.py), not OSM's
var _hx0 := 0.0
var _hz0 := 0.0
var _hstep := 1.0
var _hnx := 0
var _hnz := 0
var _slope := 0.0                    ## the road's pitch under the car, radians (uphill +)
var _signals: Array = []             ## per traffic-light group: {role -> MultiMesh}
var _sig_mats: Array = []            ## [group][0 red, 1 yellow, 2 green] materials
var _sig_phase := 0
var _sig_t := 0.0
var _sig_set := {}                   ## graph node -> true, for each node with traffic lights
var _sig_hash := {}                  ## the same nodes in a spatial hash
var _light_odo := -1000.0            ## the odometer when the car last went through a light
const LIGHT_SKIP := 45.0             ## lights this soon after one are the far side of the same junction

## ---- stop and give-way signs, where OSM has them ----
var _signs := {}                     ## graph node -> [[kind, way in (Vector2), line before the node (m)], ...]
var _sign_hash := {}
var _stopped_odo := 0.0              ## the odometer when the car was last (nearly) stopped
var _sign_odo := -1000.0             ## ... at the last stop sign it went through
var _ap_sign_done := -1              ## autodrive: the stop sign it has stopped at already
var _ap_sign_wait := 0.0
const ROAD_RANK := {"motorway": 6, "trunk": 6, "primary": 5, "secondary": 4, "tertiary": 3,
	"unclassified": 2, "residential": 1, "living_street": 0, "service": 0}

## ---- traffic ----
const Traffic := preload("res://game/streets/traffic.gd")
const Furniture := preload("res://game/streets/furniture.gd")
const Details := preload("res://game/streets/details.gd")
const DriveLog := preload("res://game/streets/drivelog.gd")
var _log := DriveLog.new()            ## the last two minutes, for the map page and "save log"
var _ap_why := ""                     ## what held autodrive's speed down this tick (for the log)
var _ap_lead := -1.0                  ## metres to the car ahead on its lane, or -1
var _traffic: Traffic = null
var _ap_wait := 0.0                  ## autodrive held up by a car this long

## ---- look ----
var _tone := {}
var _smat := {}                      ## tone name -> StandardMaterial3D
var _wall_mat: ShaderMaterial
var _font: Font

## ---- the car ----
var _car: Node3D
var _body: Node3D
var _wheels: Array = []              ## [node, rest rotation.y] for the two front wheels
var _spinners: Array = []            ## the four wheels' rolling parts
var _pos := Vector2.ZERO
var _yaw := 0.0                      ## heading: forward is (cos, sin) on the x/z ground
var _v := 0.0                        ## forward speed, m/s (negative = backwards)
var _v_lat := 0.0
var _yaw_rate := 0.0
var _steer := 0.0                    ## front wheel angle, radians
var _steer_in := 0.0                 ## keyboard steering after the ramp, -1..1
var _gear := 1                       ## 1 drive, -1 reverse
var _rev_hold := 0.0
var _a_long := 0.0
var _throttle_in := 0.0              ## the pedal this tick, for the engine's sound
## off the ground: over a crest too fast, or knocked up by a hard hit. A little more game
## than a real car would give (lighter gravity, a little lift off the crest), on purpose.
var _y := 0.0                        ## the car's height (the ground's, unless it is flying)
var _vy := 0.0
var _air := false
var _ground_was := 0.0
var _prev_y := 0.0
var _view_y := 0.0
var _spin := 0.0                     ## a knock's spin, dying away (rad/s)
const AIR_G := 7.5                   ## gravity in the air: floatier than 9.8, for longer jumps
const LIFTOFF := 1.3                 ## the ground falling away this much faster than the car (m/s)
var _roll := 0.0
var _pitch := 0.0
var _crash_cool := 0.0
var _odo := 0.0
var _assist := true
var _touch_t := 0.0                  ## counts down after the car touched something
var _pinned_t := 0.0
var _pin_at := Vector2.ZERO          ## where the car was when it started pushing against something
var _last_hit := ""                  ## what the car last bumped: "building 12" / "post 40", for the report

## ---- camera ----
var _cam_yaw := 0.0
var _cam_dist := 6.5
var _cockpit := false                ## the view from the driver's seat
var _cockpit_node: Node3D            ## dashboard, wheel, pillars: only shown in that view
var _wheel_node: Node3D
var _sedan_node: Node3D              ## the player's car body: only its shadow from the seat
## ---- the driver's controls: indicators, horn, lights ----
var _blink := 0                      ## indicator: -1 left, 1 right, 0 off
var _blink_t := 0.0                  ## seconds it has been on
var _blink_yaw := 0.0                ## the heading when it went on: off again after the turn
var _blink_lit := false
var _blink_nodes := {}               ## side -> its lamps (front and back corner)
var _reverse_nodes: Array = []
var _lights_on := false
var _beam_node: MeshInstance3D
var _horn_t := 0.0                   ## a tap of the horn: seconds left of it
var _horn_held := false
var _snd_tick: AudioStreamPlayer
var _snd_horn: AudioStreamPlayer
var _dial_speed: Node3D
var _dial_rpm: Node3D
var _dash_arrows := {}               ## side -> the green arrow on the dashboard
## ---- on foot ----
var _walking := false
var _me: Actor3D                     ## the driver, out of the car
var _me_anim := ""
var _car_at := Vector2.ZERO          ## where the car was left, and how
var _car_yaw_at := 0.0
var _car_y_at := 0.0
const WALK := 2.1                    ## m/s: a brisk walk (1.45, a stroll, was too slow to get anywhere)
const RUN := 6.2
const TURN_ON_FOOT := 2.6            ## rad/s
var _look_turn := 0.0                ## the driver's glance into a turn
var _ap_ring_n := 0                  ## autodrive: pieces of roundabout driven since it came onto one

## ---- autodrive (the bots' way in, and the seed of AI traffic later) ----
var _auto := false
var _ap_pts := PackedVector2Array()  ## the lane ahead
var _ap_v := PackedFloat32Array()    ## speed allowed at each of those points (corners)
var _ap_lim := PackedFloat32Array()  ## the limit on the road leading to each point
var _ap_end := Vector3i(-1, 0, 0)    ## the last leg planned: road, last index, direction
var _ap_stuck := 0.0
var _ap_bonks := 0.0                 ## buildings run into lately (one each, fading)
var _ap_back := 0.0
var _ap_turn := 0.0                   ## turning round on the spot to face the planned lane (s left)
## the crossing ahead, while autodrive waits for you to pick a way on:
## {node, at (Vector2), ways: [{leg: Vector3i, legs (all of them, across a junction drawn as
## several points), turn (radians, + = right), name, en}] left to right, pick (index), chosen
## (you picked it)}; {} when there is none
var _cross := {}
const CROSS_SHOW_S := 5.0            ## the choices show this many seconds before the crossing
const CROSS_V := 9.0                 ## undecided, autodrive comes up to it no faster (m/s)

## ---- going somewhere: an address, a route on the road graph, a beacon over it ----
var _astar: AStar2D                  ## the drivable road graph (one-ways are one-way)
var _edge_of := {}                   ## Vector2i(from node, to node) -> Vector3i(road, index, dir)
var _addr := {}                      ## street (as the address spells it) -> Array of [number, Vector2]
var _dest_on := false
var _dest := Vector2.ZERO            ## the address itself
var _dest_stop := Vector2.ZERO       ## the kerb in front of it, where the drive ends
var _dest_name := ""
var _dest_t := 0.0
var _beacon: MeshInstance3D
var _picker: Control
var _pick_body: Control              ## where the page of buttons goes
var _pick_letters: Control
var _pick_page_lbl: Label
var _pick_prev: Button
var _pick_next: Button
var _pick_mode := "streets"          ## or "numbers"
var _pick_letter := ""               ## "" = every street
var _pick_page := 0
var _pick_street := ""
var _pick_jump := false              ## the picker jumps the car there instead of driving
var _pick_jump_btn: Button
var _pick_title: Label
var _streets_list: Array = []        ## {name, en, label, count}, sorted, built once per city
var _dest_lbl: Label

## ---- exploring ----
var _on_name := ""
var _on_m := 0.0
var _scan_t := 0.0
var _inside := true
var _inside_t := 0.0

## ---- HUD ----
var _hud: Node2D
var _map: Control
var _street_lbl: Label
var _street_en_lbl: Label
var _speed_lbl: Label
var _fps_lbl: Label
var _gear_lbl: Label
var _count_lbl: Label
var _banner: Label
var _banner_tw: Tween
var _osm_lbl: Label
var _loaded := false
var _touch_seen := false
var _woke := false
var _stick_id := -1                  ## the touch that owns the stick; -1 when no thumb is down
var _stick := Vector2.ZERO           ## its deflection, inside the unit circle
var _sfx_was := 0.8
const AUTO_BTN := Rect2(184, 334, 100, 20)
const GOTO_BTN := Rect2(290, 334, 80, 20)
const ASSIST_BTN := Rect2(376, 334, 70, 20)
const NIGHT_BTN := Rect2(452, 334, 52, 20)
const VIEW_BTN := Rect2(578, 98, 52, 20)    ## chase cam / driver's seat (key C too)
const LIGHTS_BTN := Rect2(578, 122, 52, 20)  ## headlights (key L)
## (the indicators and the horn are keys only, Q / E and H: on screen they were clutter)
const WALK_BTN := Rect2(578, 146, 52, 20)    ## out of the car and back in (key F)
const STICK_C := Vector2(556, 268)   ## the touch stick sits still, here, on the right
const STICK_R := 52.0                ## thumb travel (design px) for full lock / full gas
const STICK_GRAB := 84.0             ## a thumb this close to its centre takes hold of it
const STICK_DEAD := 0.12

func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(-1500, -1300, 3000, 2600)   ## replaced by the city's real bounds

func _ready() -> void:
	title = "streets"
	# Before super(): the shell's own per-frame hook puts camera shake on top of where
	# _frame() leaves the camera, so _frame() has to run first.
	get_tree().process_frame.connect(_frame)
	super()
	Bus.palette_changed.connect(_retint_city)

func start(_config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	set_lives(0)
	_touch_seen = DisplayServer.is_touchscreen_available()   # phones get the stick hint at once
	_keep_screen_on(true)
	_make_font()
	_tones()
	_place = LEVELS[clampi(int(_config.get("level", 1)), 1, LEVELS.size()) - 1]
	var dev := OS.get_environment("STREETS_CAM").split(",", false)
	if dev.size() >= 5:
		for i in 5:
			_dev_cam.append(dev[i].to_float())
	# a big city takes seconds to build: say so, and build in steps a frame apart, so the
	# screen shows progress instead of hanging (a phone takes two or three times as long)
	_loading = UIKit.label("", 16, "ink")
	_loading.add_theme_font_override("font", _font)
	_loading.position = Vector2(120, 160)
	_loading.size = Vector2(400, 40)
	_loading.z_index = 100
	add_child(_loading)
	if not await _step("loading " + String(_place["name"])):
		return
	var t0 := Time.get_ticks_msec()
	if not _load_city(String(_place["city"])):
		_loading.queue_free()
		_build_hud()
		_show_banner("no city file -- see GAME.md", 30.0)
		return
	var t1 := Time.get_ticks_msec()
	_stage_ms["city file (parse, roads fitted, buildings cut)"] = t1 - t0
	world_area = _bounds
	_find_start()   # (the squares round it are built first)
	if not await _build_world():
		return
	var tw := Time.get_ticks_msec()
	if not await _warm_up():
		return
	_stage_ms["warm up (shaders compiled, 4 frames)"] = Time.get_ticks_msec() - tw
	_loading.queue_free()
	var tm := Time.get_ticks_msec()
	_map_build_cells()
	_stage("minimap", tm)
	_build_car()
	_place_start()
	_build_hud()
	_retint_city()
	_spawn_people()
	_spawn_crossers()
	_traffic = Traffic.new()
	_traffic.setup(self)
	_build_engine()
	_build_signal_sounds()
	if _place.has("walk"):
		_film_begin(String(_place["walk"]))
	_dressing["traffic"] = _traffic.alive_count()
	_loaded = true
	track3d(_car, "@")
	Probe.event("city", {"name": _city_name, "roads": _roads.size(), "buildings": _blds.size(),
		"trees": _posts.size(), "streets": _streets.size(), "dressing": _dressing, "stage_ms": _stage_ms,
		"parse_ms": t1 - t0, "build_ms": Time.get_ticks_msec() - t1})
	_show_banner(_city_name, 3.0)
	var dev_cam := OS.get_environment("STREETS_CAM").split(",", false)
	if dev_cam.size() >= 6 and dev_cam[5] == "1":
		_set_night(true)
	_build_rest()   # the rest of the city, while you drive

var _loading: Label

## Draw the city once looking each way from above the start, while the loading text is
## still up. A browser compiles each shader the first time something uses it, and that
## stalls the frame: better here than as each kind of thing first comes into view.
func _warm_up() -> bool:
	_loading.text = "building %s…\ngetting ready" % _city_name
	var mid := _bounds.get_center()
	var spot := _pos if _pos != Vector2.ZERO else mid
	var gy := _h(spot)
	for k in range(4):
		var d := Vector2(cos(k * PI * 0.5), sin(k * PI * 0.5))
		look_from(Vector3(spot.x - d.x * 20.0, gy + 12.0, spot.y - d.y * 20.0), Vector3(spot.x + d.x * 40.0, gy, spot.y + d.y * 40.0))
		_sky_follow()
		await get_tree().process_frame
		if not is_inside_tree():
			return false
	return true

## show what is being built and let a frame be drawn; false if the game was left meanwhile
func _step(what: String) -> bool:
	if not is_inside_tree():
		return false
	_loading.text = "building %s…\n%s" % [_city_name if _city_name != "" else String(_place["name"]), what]
	await get_tree().process_frame
	await get_tree().process_frame
	return is_inside_tree()

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	if _shadow_web:   # put the project's own shadow settings back for the next game
		RenderingServer.directional_shadow_atlas_set_size(
			int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)), true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)))
	_keep_screen_on(false)

## Watching autodrive means nobody touches the phone, and phones dim and lock. Natively
## Godot can hold the screen on; in a browser that is the Screen Wake Lock API, which the
## page must ask for while visible, again after the tab comes back (the browser drops the
## lock when it is hidden), and on some browsers only after a tap.
const WAKE_JS := """
window.__streetsWake = window.__streetsWake || (function () {
  var lock = null, want = false;
  function grab() {
    if (!want || lock || document.visibilityState !== 'visible' || !('wakeLock' in navigator)) return;
    navigator.wakeLock.request('screen').then(function (l) {
      lock = l;
      l.addEventListener('release', function () { lock = null; });
    }).catch(function () {});
  }
  document.addEventListener('visibilitychange', grab);
  return {
    start: function () { want = true; grab(); },
    stop: function () { want = false; if (lock) { lock.release(); lock = null; } }
  };
})();
"""

func _keep_screen_on(on: bool) -> void:
	DisplayServer.screen_set_keep_on(on)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(WAKE_JS + ("window.__streetsWake.start();" if on else "window.__streetsWake.stop();"), true)

## Divided roads: OSM maps each carriageway as a road of its own, one-way, and with no width
## given the bake guesses the class's -- 10 m for a secondary -- for each half. Ben Gurion's
## halves are 7-10 m apart centre to centre, so they overlapped, and each one's kerb and
## pavement ran down the other's lanes. Each half is made as wide as its lanes (3.3 m a lane),
## never so wide it reaches the other, and remembers the gap left between them: its inner
## side gets a kerb and half the median, not a pavement.
func _fit_dual_carriageways() -> void:
	var fitted := 0
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		var o := int(r["o"])
		if not r["drive"] or o == 0 or r.get("ring", false) or r["k"] == "service":
			continue
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5
		var acr: Array = []
		for j in range(pts.size() - 1):
			var c := (pts[j] + pts[j + 1]) * 0.5
			var d := (pts[j + 1] - pts[j]).normalized()
			var pair := _partner(c, d, ri, hw, o)
			if not pair.is_empty():
				acr.append((pair[1] as Vector2).distance_to(c))
		if acr.is_empty() or acr.size() * 2 < pts.size() - 1:
			continue   # beside another carriageway along less than half of it
		acr.sort()
		var across: float = acr[acr.size() / 2]
		if across > 40.0:
			continue
		var lanes := int(r["l"]) if int(r["l"]) > 0 else maxi(1, roundi(float(r["w"]) / 3.5))
		var w := minf(float(r["w"]), lanes * 3.3 + 0.5)
		w = minf(w, maxf(3.0, across - 0.5))
		r["w"] = w
		r["median"] = maxf(0.0, across - w)
		fitted += 1
	if fitted == 0:
		return
	_recompute_node_r()
	_dressing["dual_halves"] = fitted

func _recompute_node_r() -> void:
	for i in range(_node_r.size()):
		_node_r[i] = 0.0
	for r: Dictionary in _roads:
		if r["drive"]:
			for id: int in r["ids"]:
				_node_r[id] = maxf(_node_r[id], float(r["w"]) * 0.5)

## Road widths are guesses too (8 m a residential street, 10 m a secondary), and in the old
## streets the buildings stand closer than that: drawn at the guess, the road ran under
## them ("buildings halfway into the street"). Each road is narrowed, to no less than two
## lanes (one for a one-way), where over most of its length a wall stands within its
## asphalt and a strip of pavement. Only where a wall is near is a narrower width looked for.
func _fit_widths_to_buildings() -> void:
	var narrowed := 0
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		if not r["drive"] or HIGHWAYS.has(r["k"]) or r["k"] == "service":
			continue
		var hw := float(r["w"]) * 0.5
		var min_hw := 2.7 if int(r["o"]) == 0 else 1.8
		if hw <= min_hw:
			continue
		var pts: PackedVector2Array = r["pts"]
		var allowed: Array = []
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			if L < 0.5:
				continue
			var d := (b - a) / L
			var nrm := Vector2(-d.y, d.x)
			var n := maxi(1, int(L / 12.0))
			for k in range(n):
				var q := a + d * (L * (k + 0.5) / n)
				var room := hw
				for sg: float in [-1.0, 1.0]:
					var side := nrm * sg
					if _push_out(q + side * (hw + 0.9), 0.5, false) == Vector2.ZERO:
						continue
					var x := hw
					while x > min_hw:
						x = maxf(min_hw, x - 0.5)
						if _push_out(q + side * (x + 0.9), 0.5, false) == Vector2.ZERO:
							break
					room = minf(room, x)
				allowed.append(room)
		if allowed.is_empty():
			continue
		allowed.sort()
		var fit: float = allowed[int(allowed.size() * 0.3)]   # most of its length, not one corner
		if fit < hw - 0.2:
			r["w"] = fit * 2.0
			narrowed += 1
	if narrowed > 0:
		_recompute_node_r()
	_dressing["narrowed"] = narrowed

## What the narrowing leaves (it fits most of a street's length, not every building on it):
## a building whose front still stands on the road, or so close no pavement is left, has
## that front cut back to the road's edge plus a kerb and a strip of pavement. OSM's
## footprints and centre lines are each a little off and the road's width is a guess, so a
## metre off a facade is the likelier truth than a house standing in the lane. Not a
## building the road runs under (more than half of it would go: a passage through it, or a
## guess far too wide), nor one up on columns over it.
const BLD_CLEAR := 1.5                ## kerb and pavement kept in front of a building (m)

func _clip_buildings(bdata: Array) -> void:
	var clipped := 0
	var kept := 0
	for bi in range(_blds.size()):
		if _bld_solid[bi] == 0:
			continue
		var ring: PackedVector2Array = _blds[bi]
		var box: Rect2 = _bld_box[bi]
		var n := ring.size()
		var cuts: Array = []
		for code: int in _near(_seg_hash, box.get_center(), box.size.length() * 0.5 + 14.0, SEG_CELL):
			var r: Dictionary = _roads[code / 4096]
			if not _kerbed(r):
				continue
			var pts: PackedVector2Array = r["pts"]
			var sj := code % 4096
			var a := pts[sj]
			var b := pts[sj + 1]
			var c := float(r["w"]) * 0.5 + BLD_CLEAR
			if not box.grow(c).intersects(Rect2(a, Vector2.ZERO).expand(b)):
				continue
			for k in range(n):
				var cp := Geometry2D.get_closest_points_between_segments(a, b, ring[k], ring[(k + 1) % n])
				if cp[0].distance_to(cp[1]) < c - 0.05:
					cuts.append([a, b, c])
					break
		if cuts.is_empty():
			continue
		var area0 := _area_signed(ring)
		var cur := ring
		for cut: Array in cuts:
			var a: Vector2 = cut[0]
			var b: Vector2 = cut[1]
			var c: float = cut[2]
			var d := (b - a).normalized()
			if d == Vector2.ZERO:
				continue
			# the road's strip round this piece, rounded at both ends (squared off, the
			# outside of every bend and every junction's middle were left uncut)
			var lane := PackedVector2Array()
			for k in range(7):
				lane.append(b + Vector2(-d.y, d.x).rotated(-PI * k / 6.0) * c)
			for k in range(7):
				lane.append(a + Vector2(d.y, -d.x).rotated(-PI * k / 6.0) * c)
			var best := PackedVector2Array()
			var best_a := 0.0
			for piece: PackedVector2Array in Geometry2D.clip_polygons(cur, lane):
				var pa := _area(piece)   # (the largest: never a hole, smaller than its outline)
				if pa > best_a:
					best_a = pa
					best = piece
			cur = best
			if cur.size() < 3:
				break
		if cur.size() < 3 or _area(cur) < absf(area0) * 0.5:
			kept += 1
			continue
		if signf(_area_signed(cur)) != signf(area0):
			cur.reverse()
		_blds[bi] = cur
		_bld_box[bi] = _bld_box_of(cur)
		(bdata[bi] as Dictionary)["_ring"] = cur
		clipped += 1
	_dressing["bld_clipped"] = clipped
	_dressing["bld_over_road"] = kept

## ---- loading the city ---------------------------------------------------------------

func _load_city(id: String) -> bool:
	var dir: String = get_script().resource_path.get_base_dir() + "/cities/"
	var path := dir + id + ".json"
	if not FileAccess.file_exists(path):
		# not baked yet: drive whichever city is there rather than nothing
		var any := ""
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				any = dir + f
				break
		if any == "":
			Probe.note("no city file at %s -- bake one with tools/osm_city.py (GAME.md)" % path)
			return false
		Probe.note("no %s yet, driving %s instead" % [path, any.get_file()])
		path = any
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		Probe.note("city file %s did not parse" % path)
		return false
	var k := 1.0 / float(data.get("scale", 10))
	_city_id = path.get_file().get_basename()
	var extra := Details.load_for(dir, _city_id)
	if not extra.is_empty():
		_details = Details.new(self, extra)
		_details.edit_city(data)
	_city_name = String(data.get("name", id))
	var b: Array = data["bounds"]
	_bounds = Rect2(b[0], b[1], float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))

	var nd: Array = data["nodes"]
	_nodes.resize(nd.size() / 2)
	for i in range(_nodes.size()):
		_nodes[i] = Vector2(nd[i * 2], nd[i * 2 + 1]) * k
	_node_roads.resize(_nodes.size())
	_node_r.resize(_nodes.size())
	for i in range(_nodes.size()):
		_node_roads[i] = []

	for rd: Dictionary in data["roads"]:
		var kind := String(rd.get("k", ""))
		if rd.has("tu"):
			continue   # tunnels are underground; there is no underground yet
		var ids := PackedInt32Array()
		var pts := PackedVector2Array()
		for n in rd["n"]:
			ids.append(int(n))
			pts.append(_nodes[int(n)])
		var r := {"pts": pts, "ids": ids, "w": float(rd.get("w", 6.0)), "k": kind,
			"o": int(rd.get("o", 0)), "l": int(rd.get("l", 0)), "name": String(rd.get("name", "")),
			"en": String(rd.get("name_en", "")), "drive": DRIVE.has(kind), "pv": rd.has("pv"), "sv": String(rd.get("sv", "")),
			"speed": float(DRIVE.get(kind, 5.0)) * (NORTH_FASTER.get(kind, 1.0) if String(_place.get("look", "")) == "north" else 1.0),
			# a roundabout's ring: marked by the bake, or a one-way way that closes on itself
			"ring": rd.has("rb") or (int(rd.get("o", 0)) != 0 and ids.size() > 3 and ids[0] == ids[ids.size() - 1])}
		if rd.has("kerb"):
			r["kerb"] = int(rd["kerb"])   # its kerb's paint, set by hand (details.gd)
		var ri := _roads.size()
		_roads.append(r)
		var hw: float = r["w"] * 0.5
		for j in range(ids.size()):
			(_node_roads[ids[j]] as Array).append(Vector2i(ri, j))
			if r["drive"]:
				_node_r[ids[j]] = maxf(_node_r[ids[j]], hw)
		for j in range(pts.size() - 1):
			_hash_add(_seg_hash, Rect2(pts[j], Vector2.ZERO).expand(pts[j + 1]).grow(hw), SEG_CELL, ri * 4096 + j)

	_fit_dual_carriageways()

	for ring: Array in data.get("boundary", []):
		var poly := PackedVector2Array()
		for i in range(0, ring.size(), 2):
			poly.append(Vector2(ring[i], ring[i + 1]) * k)
		_boundary.append(poly)
	for r: Dictionary in _roads:
		if r["drive"] and r["name"] != "" and r["k"] != "service":
			for p: Vector2 in r["pts"]:
				if _in_city(p):
					_streets[r["name"]] = true
					break

	for bd: Dictionary in data["buildings"]:
		var flat: Array = bd["p"]
		var ring := PackedVector2Array()
		for i in range(0, flat.size(), 2):
			ring.append(Vector2(flat[i], flat[i + 1]) * k)
		var h := float(bd["h"])
		if bd.has("g"):
			# a guess: vary it a storey either way so a street is not one flat wall
			h += float(posmod(_hash_i(ring[0]), 3) - 1) * 3.0
		var base := float(bd.get("b", 0.0))
		var box := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			box = box.expand(p)
		var bi := _blds.size()
		_blds.append(ring)
		_bld_box.append(box)
		_bld_solid.append(1 if base < 2.4 else 0)
		_hash_add(_bld_hash, box, BLD_CELL, bi)
		bd["_h"] = h
		bd["_ring"] = ring
		bd["_base"] = base
		if bd.has("addr"):
			_add_address(String(bd["addr"]), box.get_center())
	var hg: Dictionary = data.get("height", {})
	if not hg.is_empty():
		_hx0 = float(hg["x0"])
		_hz0 = float(hg["z0"])
		_hstep = float(hg["step"])
		_hnx = int(hg["nx"])
		_hnz = int(hg["nz"])
		var raw: Array = hg["h"]
		_hgrid.resize(raw.size())
		for i in range(raw.size()):
			_hgrid[i] = float(raw[i]) * k
		_steep = _any_steep()
	_made_up = data.has("made_up")
	for a: Array in data.get("addrs", []):   # address points that are not on a building
		_add_address("%s %s" % [a[2], a[3]], Vector2(a[0], a[1]) * k)
	_fit_widths_to_buildings()
	_clip_buildings(data["buildings"])
	_mark_medians()
	_build_graph()
	_city_data = data
	return true

## "Sheinkin 47" -> filed under "Sheinkin" as number "47"
func _add_address(full: String, at: Vector2) -> void:
	var cut := full.rfind(" ")
	if cut <= 0:
		return
	var street := full.substr(0, cut)
	var num := full.substr(cut + 1)
	if not _addr.has(street):
		_addr[street] = []
	for a: Array in _addr[street]:
		if a[0] == num:
			return   # a building and an address point for the same door
	(_addr[street] as Array).append([num, at])

## the drivable roads as a directed graph for routing (Godot's AStar2D, distance-weighted)
func _build_graph() -> void:
	_astar = AStar2D.new()
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		if not r["drive"] or r["pv"]:
			continue
		var ids: PackedInt32Array = r["ids"]
		for j in range(ids.size() - 1):
			var a := ids[j]
			var b := ids[j + 1]
			if a == b:
				continue
			for id: int in [a, b]:
				if not _astar.has_point(id):
					_astar.add_point(id, _nodes[id])
			if r["o"] != -1:
				_astar.connect_points(a, b, false)
				_edge_of[Vector2i(a, b)] = Vector3i(ri, j, 1)
			if r["o"] != 1:
				_astar.connect_points(b, a, false)
				_edge_of[Vector2i(b, a)] = Vector3i(ri, j + 1, -1)

var _city_data: Dictionary = {}      ## the parsed file, kept only until the meshes exist

## ---- building the world ---------------------------------------------------------------

var _stage_ms := {}

func _stage(name: String, t0: int) -> int:
	var t := Time.get_ticks_msec()
	if not _bg_build:   # (in the background the clock runs on through the frames between)
		_stage_ms[name] = int(_stage_ms.get(name, 0)) + t - t0
	return t

func _build_world() -> bool:
	var t0 := Time.get_ticks_msec()
	# one shadow map over the near streets, not the default four cascades: those drew every
	# shadow-casting thing in view four more times a frame, more than the view itself
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_set_quality(QUALITY_WEB if OS.has_feature("web") else QUALITY.size() - 1)
	sun.rotation_degrees = Vector3(-50, -28, 0)
	_build_sky_dome()
	cam.near = 0.3
	cam.far = 2200.0
	# the ground, well past the edges so the horizon is not a cliff
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = _bounds.size + Vector2(4000, 4000)
	pm.material = _ground_mat()
	ground.mesh = pm
	ground.position = Vector3(_bounds.get_center().x, -0.4 if _hnx > 0 else 0.0, _bounds.get_center().y)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground)
	if _hnx > 0:
		_build_terrain()
	_build_edge()
	_build_setup(_stage("world", t0))
	# the squares round the start before the car is shown; the rest while it drives
	# (STREETS_BUILD_ALL=1: all of it first -- the scene tests look all over the city)
	var all_first := OS.get_environment("STREETS_BUILD_ALL") == "1"
	var near: Array = _tiles_todo.filter(func(t): return all_first or _tile_dist(t, _pos) < NEAR_FIRST)
	near.sort_custom(func(a, b): return _tile_dist(a, _pos) < _tile_dist(b, _pos))
	for i in range(near.size()):
		if not await _step("the streets round the start (%d of %d)" % [i + 1, near.size()]):
			return false
		await _build_tile(near[i])
	_tiles_todo = _tiles_todo.filter(func(t): return not _tiles_done.has(t))
	if _details != null:   # what a filmed walk added: built whole, once (details.gd)
		await _details.build()
	return true

## ---- building near-first ------------------------------------------------------------------
## The city is built a 400 m square at a time -- the squares its meshes are merged in anyway,
## so building it in pieces costs no extra draws. The squares round the start go in behind
## the loading text; the rest while you drive, the square nearest where the car is heading
## first, a few milliseconds a frame (_pause) so the driving never stutters.
## Anything laid along a road or a fence (asphalt, paint, kerbs, gardens, wires, fences) is
## worked out in full by every square the line crosses, and each square keeps only the
## triangles that start in it (CBuf.clip). Everything else -- a building, a tree, a sign, a
## shop, a parked car -- belongs to the one square its spot is in (_mine), which builds all
## of it, and records whatever goes with it (posts, parked cars, lights, tables) just once.
const TILE := 400.0                  ## = CHUNK = GROUND_CELL = BATCH_CELL
const NEAR_FIRST := 320.0            ## squares this close to the start are built before you drive
const BUILD_US := 6000               ## background building: microseconds a frame (half that when frames run slow)
var _tile := Vector2i.ZERO           ## the square being built
var _tiled := false                  ## a square is being built (its builders are at work)
var _tiles_done := {}
var _tiles_todo: Array = []          ## Vector2i: the squares still to build
var _tile_roads := {}                ## square -> roads whose line (15 m either side) reaches it
var _tile_nodes := {}                ## square -> the road nodes in it
var _tile_blds := {}                 ## square -> buildings (by the middle of the outline)
var _tile_areas := {}                ## square -> the city file's areas that reach it
var _tile_rings := {}                ## kind -> square -> indices into _area_rings[kind] that reach it
var _tile_trees := {}                ## square -> mapped trees
var _tile_pois := {}                 ## square -> places (shops, schools...)
var _tile_stops := {}                ## square -> bus stops
var _tile_signs := {}                ## square -> stop and give-way signs
var _tile_lit := {}                  ## square -> junctions with traffic lights
var _tile_bars := {}                 ## square -> mapped fences and hedges that reach it
var _crossing_set := {}
var _bg_build := false               ## building in the background: stop for the frame when over budget
var _bg_wait := false
var _yield_at := 0
var _build_us := BUILD_US
var _build_lbl: Label
var _build_total := 0                ## squares to build, all told (for the HUD)
var _schools: Array = []             ## schools and kindergartens: SLOW on the road near them
var _poi_taken := {}                 ## a shopfront spot already used -> how many there
var _mesh_cache := {}
var _shingles: StandardMaterial3D

## a mesh made once and shared by every square
func _cached(key: String, make: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = make.call()
	return _mesh_cache[key]
signal _build_tick

func _tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))

func _tile_rect(t: Vector2i) -> Rect2:
	return Rect2(Vector2(t) * TILE, Vector2(TILE, TILE))

## how far p is from square t (0 inside it)
func _tile_dist(t: Vector2i, p: Vector2) -> float:
	var r := _tile_rect(t)
	return p.clamp(r.position, r.end).distance_to(p)

## the squares a box reaches
func _tiles_over(box: Rect2) -> Array:
	var out: Array = []
	for tx in range(floori(box.position.x / TILE), floori(box.end.x / TILE) + 1):
		for tz in range(floori(box.position.y / TILE), floori(box.end.y / TILE) + 1):
			out.append(Vector2i(tx, tz))
	return out

func _bucket(table: Dictionary, t: Vector2i, item) -> void:
	if not table.has(t):
		table[t] = []
	(table[t] as Array).append(item)

## p is in the square being built: what stands there is built (and recorded) by it
func _mine(p: Vector2) -> bool:
	return not _tiled or _tile_of(p) == _tile

## p is within m metres of the square being built
func _near_tile(p: Vector2, m: float) -> bool:
	return not _tiled or _tile_rect(_tile).grow(m).has_point(p)

## the nodes within m metres of the square being built
func _nodes_near(m: float) -> Array:
	var out: Array = []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for ni: int in _tile_nodes.get(_tile + Vector2i(dx, dz), []):
				if _near_tile(_nodes[ni], m):
					out.append(ni)
	return out

## the outlines of one kind of area (park, wood, parking...) that reach the square
func _rings_near(kind: String) -> Array:
	var all: Array = _area_rings.get(kind, [])
	var out: Array = []
	for ri: int in (_tile_rings.get(kind, {}) as Dictionary).get(_tile, []):
		out.append(all[ri])
	return out

## an area's outline belongs to the square its box's middle is in
func _ring_mine(ring: PackedVector2Array) -> bool:
	return _mine(_bld_box_of(ring).get_center())

## a CBuf for something every square along it works out (see CBuf.clip)
func _clip_buf(cell: float) -> CBuf:
	var b := CBuf.new(cell)
	b.clip = true
	return b

func _tally(k: String, n: int) -> void:
	_dressing[k] = int(_dressing.get(k, 0)) + n

## the frame's building time is used up
func _over() -> bool:
	return _bg_build and Time.get_ticks_usec() > _yield_at

## Building in the background: hand the frame back and go on in the next one. Meanwhile
## the game is not building a square, so whatever it makes in between (night's light pools)
## is its own, not that square's.
func _pause() -> void:
	var was := _tiled
	var batching := _batching
	_set_tiling(false)
	_batching = false
	_bg_wait = true
	await _build_tick
	_batching = batching
	_set_tiling(was)
	_yield_at = Time.get_ticks_usec() + _build_us

## empty a big table or list a few hundred entries at a time, within the frame's budget
func _release(table) -> void:
	if table is Dictionary:
		var d: Dictionary = table
		var keys: Array = d.keys()
		for i in range(keys.size()):
			d.erase(keys[i])
			if i % 256 == 255 and _over():
				await _pause()
	elif table is Array:
		var a: Array = table
		while not a.is_empty():
			a.resize(maxi(0, a.size() - 256))
			if _over():
				await _pause()

func _set_tiling(on: bool) -> void:
	_tiled = on
	CBuf.tiled = on
	CBuf.tile = _tile

## What every square needs from the whole city, worked out once: which roads, junctions,
## buildings, areas and places reach each square; the outlines of the parks, woods and car
## parks; what traffic needs everywhere at once (which junctions have lights).
func _build_setup(t0: int) -> void:
	var k := 1.0 / float(_city_data.get("scale", 10))
	_furn = Furniture.new(self)
	_build_asph_hash()
	_bld_kind.resize((_city_data["buildings"] as Array).size())
	_bld_kind.fill(0)
	for ni in _city_data.get("crossings", []):
		_crossing_nodes.append(int(ni))
		_crossing_set[int(ni)] = true
	var areas: Array = _city_data.get("areas", [])
	for ai in range(areas.size()):
		var a: Dictionary = areas[ai]
		var kind := String(a["k"])
		var flat: Array = a["p"]
		var ring := PackedVector2Array()
		for i in range(0, flat.size(), 2):
			ring.append(Vector2(flat[i], flat[i + 1]) * k)
		a["_ring"] = ring
		if ring.size() < 3:
			continue
		var over := _tiles_over(_bld_box_of(ring))
		for t: Vector2i in over:
			_bucket(_tile_areas, t, ai)
		if kind in ["park", "grass", "wood", "pitch", "water", "parking", "plaza", "school"]:
			if not _area_rings.has(kind):
				_area_rings[kind] = []
				_tile_rings[kind] = {}
			for t: Vector2i in over:
				_bucket(_tile_rings[kind], t, (_area_rings[kind] as Array).size())
			(_area_rings[kind] as Array).append(ring)
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var reach := float(r["w"]) * 0.5 + 15.0
		var seen := {}
		for j in range(pts.size() - 1):
			for t: Vector2i in _tiles_over(Rect2(pts[j], Vector2.ZERO).expand(pts[j + 1]).grow(reach)):
				if not seen.has(t):
					seen[t] = true
					_bucket(_tile_roads, t, ri)
	for ni in range(_nodes.size()):
		_bucket(_tile_nodes, _tile_of(_nodes[ni]), ni)
	for bi in range(_bld_box.size()):
		_bucket(_tile_blds, _tile_of((_bld_box[bi] as Rect2).get_center()), bi)
	var tr: Array = _city_data.get("trees", [])
	for i in range(0, tr.size() - 1, 2):
		_bucket(_tile_trees, _tile_of(Vector2(tr[i], tr[i + 1]) * k), i)
	var pois: Array = _city_data.get("pois", [])
	for i in range(pois.size()):
		_bucket(_tile_pois, _tile_of(Vector2(pois[i][0], pois[i][1]) * k), i)
		if String(pois[i][2]) in ["school", "kindergarten"]:
			_schools.append(Vector2(pois[i][0], pois[i][1]) * k)
	var stops: Array = _city_data.get("stops", [])
	for i in range(stops.size()):
		_bucket(_tile_stops, _tile_of(Vector2(stops[i][0], stops[i][1]) * k), i)
	var signs: Array = _city_data.get("signs", [])
	for i in range(signs.size()):
		var node := int(signs[i][0])
		if node >= 0 and node < _nodes.size():
			_bucket(_tile_signs, _tile_of(_nodes[node]), i)
	var bars: Array = _city_data.get("barriers", [])
	for i in range(bars.size()):
		var flat: Array = bars[i][0]
		var seen := {}
		for j in range(0, flat.size() - 2, 2):
			var box := Rect2(Vector2(flat[j], flat[j + 1]) * k, Vector2.ZERO).expand(Vector2(flat[j + 2], flat[j + 3]) * k)
			for t: Vector2i in _tiles_over(box.grow(1.0)):
				if not seen.has(t):
					seen[t] = true
					_bucket(_tile_bars, t, i)
	_lights_setup()
	_parks_setup()
	_trees_setup()
	# every square with anything in it, and every square of the map (open land grows trees)
	var todo := {}
	for table: Dictionary in [_tile_roads, _tile_nodes, _tile_blds, _tile_areas, _tile_trees, _tile_pois]:
		for t: Vector2i in table:
			todo[t] = true
	for t: Vector2i in _tiles_over(_bounds):
		todo[t] = true
	_tiles_todo = todo.keys()
	_build_total = _tiles_todo.size()
	_stage("setup", t0)

## One square of the city, everything in it, each kind keeping clear of what went before
## (trees of buildings, lamps of trees...); the kerbs after the trees, whose leaves lie on
## their pavements.
## In the background each builder stops when the frame's few milliseconds are used up and
## goes on in the next frame.
func _build_tile(t: Vector2i) -> void:
	if _over():
		await _pause()
	_tiles_done[t] = true
	_tile = t
	_set_tiling(true)
	_batching = true
	for a: Array in [_stop_lines, _pole_plates, _chimneys, _mall_glass, _lobby_doors, _balcony_flags, _flag_spots, _stop_ads]:
		a.clear()   # made by one builder for the next, square by square
	var tk := Time.get_ticks_msec()
	await _build_ground()
	tk = _stage("roads", tk)
	await _build_buildings()
	tk = _stage("buildings", tk)
	await _build_roof_kit()
	await _build_facade_kit()
	tk = _stage("facades", tk)
	await _build_trees()
	tk = _stage("trees", tk)
	await _build_kerbs()   # (after the trees: the leaves on the pavement are under them)
	tk = _stage("kerbs", tk)
	await _furn.wires()
	tk = _stage("wires", tk)
	await _build_lamps()
	await _build_parks()
	tk = _stage("lamps", tk)
	await _build_parked()
	await _build_lots()
	tk = _stage("parked", tk)
	await _build_signals()
	await _build_signs()
	await _build_road_paint()
	await _build_speed_signs()
	await _build_street_signs()
	tk = _stage("signs", tk)
	await _build_pois()
	await _build_stops()
	tk = _stage("places", tk)
	await _furn.build()
	tk = _stage("furniture", tk)
	if _over():
		await _pause()
	await _flush_batches()
	if _pools_made:
		_make_pools()   # it is night: this square's light pools too
	_stage("batches", tk)
	_set_tiling(false)
	_batching = false

## the square to build next: the one nearest where the car will be in a few seconds
func _next_tile():
	if _tiles_todo.is_empty():
		return null
	var ahead := _pos + _fwd() * clampf(_v * 4.0, 0.0, 250.0)
	var best := 0
	var bd := INF
	for i in range(_tiles_todo.size()):
		var d := _tile_dist(_tiles_todo[i], ahead)
		if d < bd:
			bd = d
			best = i
	var t: Vector2i = _tiles_todo[best]
	_tiles_todo.remove_at(best)
	return t

## the rest of the city, a square at a time while the game runs
func _build_rest() -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	_bg_build = true
	_yield_at = Time.get_ticks_usec() + _build_us
	while is_inside_tree():
		var t = _next_tile()
		if t == null:
			break
		await _build_tile(t)
		n += 1
		if _build_lbl != null:
			_build_lbl.text = "building the city %d%%" % int(100.0 * _tiles_done.size() / maxf(_build_total, 1.0))
	if _build_lbl != null:
		_build_lbl.text = ""
	# what was only for building -- the file, the outlines, the squares' lists -- let go of a
	# little a frame (all at once, it took a frame and a half)
	for key: String in _city_data.keys():
		await _release(_city_data[key])
	_city_data = {}
	for table: Dictionary in [_area_rings, _asph_hash, _tile_roads, _tile_nodes, _tile_blds, _tile_areas, _tile_rings,
			_tile_trees, _tile_pois, _tile_stops, _tile_signs, _tile_lit, _tile_bars]:
		await _release(table)
	_bg_build = false
	Probe.event("city_built", {"squares": n, "ms": Time.get_ticks_msec() - t0, "posts": _posts.size(), "trees": _trees_made, "dressing": _dressing})

## ground height at p: the same two triangles per grid cell as the terrain mesh, so
## anything placed with it sits exactly on the drawn ground. 0 for a flat city.
## how far the road's surface is above the ground: wheels go on it, not in it
func road_top() -> float:
	return Y_ROAD + (0.07 if _hnx > 0 else 0.0)

func _h(p: Vector2) -> float:
	if _hnx == 0:
		return 0.0
	var fx := clampf((p.x - _hx0) / _hstep, 0.0, float(_hnx) - 1.001)
	var fz := clampf((p.y - _hz0) / _hstep, 0.0, float(_hnz) - 1.001)
	var i := int(fx)
	var j := int(fz)
	var ax := fx - i
	var az := fz - j
	var r := j * _hnx + i
	if ax + az <= 1.0:
		return _hgrid[r] + (_hgrid[r + 1] - _hgrid[r]) * ax + (_hgrid[r + _hnx] - _hgrid[r]) * az
	var h11 := _hgrid[r + _hnx + 1]
	return h11 + (_hgrid[r + _hnx] - h11) * (1.0 - ax) + (_hgrid[r + 1] - h11) * (1.0 - az)

## _g3's height (lift 0) for every point of a line, each worked out once
func _ground_line(pts: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(pts.size())
	var extra := 0.07 if _hnx > 0 else 0.0
	for i in range(pts.size()):
		out[i] = _h(pts[i]) + extra
	return out

## This square's ground: the parks, lawns, water and car parks, the roads' asphalt and the
## paths, their paint and zebras, the cast iron in them. All of it laid along lines and
## outlines that every square they reach works out in full (each keeping its own triangles).
func _build_ground() -> void:
	var areas := {}
	var all: Array = _city_data.get("areas", [])
	var sq := _tile_rect(_tile)
	var sq_poly := PackedVector2Array([sq.position, Vector2(sq.end.x, sq.position.y), sq.end, Vector2(sq.position.x, sq.end.y)])
	for ai: int in _tile_areas.get(_tile, []):
		if _over():
			await _pause()
		var a: Dictionary = all[ai]
		var kind := String(a["k"])
		# a school's grounds: paved, under whatever pitches and lawns OSM puts in them
		var tone := "grass" if kind in ["park", "grass"] else ("ground" if kind == "land" else ("plaza" if kind == "school" else kind))
		if not areas.has(tone):
			areas[tone] = CBuf.new(CHUNK)   # (each square fills only its own piece: no clipping)
		# islands sit on the sea, parks and car parks on whatever is under them
		var y := Y_AREA + (0.002 if tone in ["parking", "plaza"] else (0.001 if kind == "land" else 0.0))
		if kind == "school":
			y = Y_AREA - 0.001
		var ring: PackedVector2Array = a["_ring"]
		var flat := INF
		if tone == "water":   # water lies flat at the lowest point of its whole shore
			for p in ring:
				flat = minf(flat, _h(p))
		for piece: PackedVector2Array in _pieces_in(ring, sq, sq_poly):
			await _fill(areas[tone], piece, y, tone == "water", flat)
	for tone: String in areas:
		if _over():
			await _pause()
		_add_mesh(areas[tone], _surface(tone), false, VIEW_RANGE)
	# roads: asphalt ribbons, with a round patch where roads meet so corners are filled
	var asphalt := _clip_buf(CHUNK)
	var paths := _clip_buf(CHUNK)
	var walks := _clip_buf(CHUNK)   # footpaths in town: paved like the pavements
	var marks := _clip_buf(GROUND_CELL)
	var yellow := _clip_buf(GROUND_CELL)
	var metal := _clip_buf(GROUND_CELL)
	var metal_rim := _clip_buf(GROUND_CELL)
	for ri: int in _tile_roads.get(_tile, []):
		if _over():
			await _pause()
		var r: Dictionary = _roads[ri]
		var part := _near_part(r["pts"], r["w"] * 0.5 + 2.0)
		if part.size() >= 2:
			var under: Buf = asphalt if r["drive"] else (walks if _paved_walk(r) else paths)
			_ribbon(under, part, r["w"] * 0.5, Y_ROAD if r["drive"] else Y_PATH)
		_markings(marks, r, yellow)
		_street_metal(metal, metal_rim, ri)
	for ni: int in _tile_nodes.get(_tile, []):
		if _node_r[ni] > 0.0 and (_node_roads[ni] as Array).size() >= 2:
			_disc(asphalt, _nodes[ni], _node_r[ni] * 1.05, Y_ROAD)
	for ni: int in _nodes_near(30.0):
		if _crossing_set.has(ni):
			_zebra(marks, ni)
	for job: Array in [[metal_rim, "metalrim", DETAIL_RANGE], [metal, "metal", DETAIL_RANGE], [paths, "path", VIEW_RANGE * 0.6], [walks, "pavement", VIEW_RANGE * 0.6],
			[asphalt, "asphalt", VIEW_RANGE], [marks, "mark", DETAIL_RANGE], [yellow, "markyellow", DETAIL_RANGE]]:
		if _over():
			await _pause()
		_add_mesh(job[0], _surface(job[1]), false, job[2])

## the parts of an outline inside square `sq` (the whole outline when it lies inside)
func _pieces_in(ring: PackedVector2Array, sq: Rect2, sq_poly: PackedVector2Array) -> Array:
	if sq.encloses(_bld_box_of(ring)):
		return [ring]
	var cut := Geometry2D.intersect_polygons(ring, sq_poly)
	if cut.size() <= 1:
		return cut
	# an outline that crosses itself can come back with holes: keep the outer pieces (those
	# turning the same way as the biggest)
	var big := 0
	for i in range(cut.size()):
		if absf(_area_signed(cut[i])) > absf(_area_signed(cut[big])):
			big = i
	var way := signf(_area_signed(cut[big]))
	return cut.filter(func(c): return signf(_area_signed(c)) == way)

## how far along a line (cumulative lengths `cum`) its stretch near the square being built
## runs: Vector2(from, to); the whole line when no square is being built, (INF, -INF) when
## none of it is near
func _near_span(pts: PackedVector2Array, cum: PackedFloat32Array, reach: float) -> Vector2:
	if not _tiled:
		return Vector2(0.0, cum[cum.size() - 1])
	var box := _tile_rect(_tile).grow(reach)
	var span := Vector2(INF, -INF)
	for j in range(pts.size() - 1):
		if box.intersects(Rect2(pts[j], Vector2.ZERO).expand(pts[j + 1]).grow(0.01)):
			span.x = minf(span.x, cum[j])
			span.y = maxf(span.y, cum[j + 1])
	return span

## the stretch of a line near the square being built, with two more points each side so its
## bends come out just as the whole line's do (empty: none of it is near)
func _near_part(pts: PackedVector2Array, reach: float) -> PackedVector2Array:
	var box := _tile_rect(_tile).grow(reach)
	var i0 := -1
	var i1 := -1
	for j in range(pts.size() - 1):
		if box.intersects(Rect2(pts[j], Vector2.ZERO).expand(pts[j + 1]).grow(0.01)):
			if i0 < 0:
				i0 = j
			i1 = j
	if i0 < 0:
		return PackedVector2Array()
	return pts.slice(maxi(i0 - 2, 0), mini(i1 + 4, pts.size()))

## a map point on the ground, `lift` above it (a little more on hills: a straight piece
## of road between two points can dip under a bend in the ground)
## Where a person's feet go at p: on top of the pavement beside a kerbed road, on the
## asphalt, or on the ground's own layer -- each a little over the bare ground height, which
## is where people stood, a pavement's height (and on the hills the lift) into the slabs.
func _walk_y(p: Vector2) -> float:
	var hit := _nearest_seg(p, 5.0, true, true)
	var on := Y_AREA
	if not hit.is_empty():
		var edge: float = hit["edge"]
		if edge < 0.0:
			on = Y_ROAD
		elif edge < KERB_W + PAVE_W + 0.1 and _kerbed(_roads[hit["road"]]):
			on = KERB_H
	return _h(p) + on + (0.07 if _hnx > 0 else 0.0)

## a pavement's top over the bare ground
func _pave_top() -> float:
	return KERB_H + (0.07 if _hnx > 0 else 0.0)

func _g3(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, _h(p) + lift + (0.07 if _hnx > 0 else 0.0), p.y)

## the ground itself: one mesh over the city's height grid, smooth-shaded
func _build_terrain() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in range(_hnz):
		for i in range(_hnx):
			var h := _hgrid[j * _hnx + i]
			verts.append(Vector3(_hx0 + i * _hstep, h, _hz0 + j * _hstep))
			var hl := _hgrid[j * _hnx + maxi(i - 1, 0)]
			var hr := _hgrid[j * _hnx + mini(i + 1, _hnx - 1)]
			var hu := _hgrid[maxi(j - 1, 0) * _hnx + i]
			var hd := _hgrid[mini(j + 1, _hnz - 1) * _hnx + i]
			norms.append(Vector3(hl - hr, 2.0 * _hstep, hu - hd).normalized())
	# in blocks about CHUNK across, each its own mesh, so the ground behind the camera and
	# far off is not drawn (the flat plane under it takes over in the haze)
	var blk := maxi(2, int(CHUNK / _hstep))
	for bj in range(0, _hnz - 1, blk):
		for bi in range(0, _hnx - 1, blk):
			var j1 := mini(bj + blk, _hnz - 1)
			var i1 := mini(bi + blk, _hnx - 1)
			var w := i1 - bi + 1
			var bv := PackedVector3Array()
			var bn := PackedVector3Array()
			for j in range(bj, j1 + 1):
				for i in range(bi, i1 + 1):
					bv.append(verts[j * _hnx + i])
					bn.append(norms[j * _hnx + i])
			idx = PackedInt32Array()
			for j in range(j1 - bj):
				for i in range(i1 - bi):
					var a := j * w + i
					idx.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = bv
			arr[Mesh.ARRAY_NORMAL] = bn
			arr[Mesh.ARRAY_INDEX] = idx
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(0, _ground_mat())
			var mi := MeshInstance3D.new()
			mi.mesh = am
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = VIEW_RANGE + blk * _hstep * 0.71 + 300.0
			world.add_child(mi)

## A footpath in town -- a passage between blocks, steps, a pedestrian street -- is paved
## like the pavements; in a park, a wood or on grass it stays a path. (A walk filmed in
## Givatayim: its passages are pavers between garden walls, not trails through a lawn.)
const PAVED_WALKS := {"footway": true, "pedestrian": true, "steps": true}

func _paved_walk(r: Dictionary) -> bool:
	if r.has("_paved"):
		return r["_paved"]
	var paved := PAVED_WALKS.has(r["k"])
	if paved:
		var pts: PackedVector2Array = r["pts"]
		var mid := pts[pts.size() / 2].lerp(pts[(pts.size() - 1) / 2], 0.5)
		for kind: String in ["park", "grass", "wood"]:
			for ring: PackedVector2Array in _area_rings.get(kind, []):
				if _bld_box_of(ring).has_point(mid) and Geometry2D.is_point_in_polygon(mid, ring):
					paved = false
					break
	r["_paved"] = paved   # each square asks again: worked out once a road
	return paved

func _surface(tone: String) -> StandardMaterial3D:
	if _smat.has(tone):
		return _smat[tone]
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	m.metallic_specular = 0.25
	m.albedo_color = _tone.get(tone, Palette.col("warn"))
	_smat[tone] = m
	return m

## a Buf as mesh(es): one per square for a CBuf, each drawn while the camera is within
## `seen` metres of it (0: always)
func _add_mesh(buf: Buf, m: Material, shadows: bool, seen := 0.0) -> Array:
	if _batching and not buf.empty():
		var how := _merge_as(m)
		if not how.is_empty():
			_batch_buf(buf, m, how, shadows, seen)
			return []
	var made: Array = []
	var parts := buf.parts()
	var half := (buf as CBuf).cell * 0.71 if buf is CBuf else 0.0
	for key: Vector2i in parts:
		var part: Buf = parts[key]
		if part.empty():
			continue
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.arrays())
		am.surface_set_material(0, m)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if seen > 0.0:   # the range counts to the middle of the square, so add half of it
			mi.visibility_range_end = seen + half
			mi.visibility_range_end_margin = 40.0
		world.add_child(mi)
		made.append(mi)
	return made

## a polygon on the ground
func _fill(buf: Buf, ring: PackedVector2Array, y: float, level := false, flat := INF) -> void:
	var idx := Geometry2D.triangulate_polygon(ring)
	var flat_y := flat
	if level and flat_y == INF:   # water lies flat, at its shore's lowest point
		for p in ring:
			flat_y = minf(flat_y, _h(p))
	var stack: Array = []
	for i in range(0, idx.size(), 3):
		stack.append([ring[idx[i]], ring[idx[i + 1]], ring[idx[i + 2]]])
	# on hills, split triangles until they are small enough to follow the ground
	var most := _hstep * 0.8 if _hnx > 0 and not level else INF
	var n := 0
	while not stack.is_empty():
		n += 1
		if n % 256 == 0 and _over():   # (a lawn on a hillside is thousands of little triangles)
			await _pause()
		var t: Array = stack.pop_back()
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var d: Vector2 = t[2]
		var ab := a.distance_squared_to(b)
		var bd := b.distance_squared_to(d)
		var da := d.distance_squared_to(a)
		var longest := maxf(ab, maxf(bd, da))
		if longest > most * most and stack.size() < 200000:
			if longest == ab:
				var m := (a + b) * 0.5
				stack.append([a, m, d])
				stack.append([m, b, d])
			elif longest == bd:
				var m := (b + d) * 0.5
				stack.append([a, b, m])
				stack.append([a, m, d])
			else:
				var m := (d + a) * 0.5
				stack.append([a, b, m])
				stack.append([m, b, d])
			continue
		if level:
			var lift := y + (0.07 if _hnx > 0 else 0.0)
			buf.tri(Vector3(a.x, flat_y + lift, a.y), Vector3(b.x, flat_y + lift, b.y),
				Vector3(d.x, flat_y + lift, d.y), Vector3.UP, Color.WHITE)
		else:
			var pa := _g3(a, y)
			var pb := _g3(b, y)
			var pd := _g3(d, y)
			var nrm := (pb - pa).cross(pd - pa)
			if nrm.y < 0.0:
				nrm = -nrm
			buf.tri(pa, pb, pd, nrm.normalized() if nrm.length_squared() > 0.0 else Vector3.UP, Color.WHITE)

## Kerbs, pavements and front gardens along the streets. Kerbs are painted the Israeli
## way on some streets (red-white: no stopping, blue-white: paid parking, yellow-black:
## buses) by a shader, so a painted kerb costs no more than a plain one. Front gardens --
## a low stone wall behind the pavement, then a strip of garden with bushes -- go along
## residential streets. Everything stops short of junctions so the corners stay open.
const KERB_SHADER := """
shader_type spatial;
uniform vec4 plain : source_color;
uniform vec4 white : source_color;
uniform vec4 red : source_color;
uniform vec4 blue : source_color;
uniform vec4 yellow : source_color;
uniform vec4 black : source_color;
uniform float textured = 1.0;
uniform sampler2D conc : filter_linear_mipmap_anisotropic, repeat_enable;   // concrete grain
uniform vec3 conc_mean = vec3(0.5);
uniform vec4 pave : source_color;      // the pavement's tone: its pavers are mixed from it
uniform float med = 1.0;               // Israeli streets (else Bedford's poured slabs)
varying vec3 wpos;
varying float wup;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wup = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}
float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
// One paver under point g (metres: x along the street, y out from the kerb): (distance to
// its nearest joint in metres, the paver's own cell for its colour).
vec3 paver(vec2 g, float pattern) {
	if (pattern < 0.5) {
		// herringbone, 20 x 10 cm, at 45 degrees to the kerb: in brick widths, cell (cx, cy) is
		// the left or right half of a lying brick or the lower or upper half of a standing one,
		// by (cx - cy) and (cx + cy): the staircases of the pattern run along the diagonal
		vec2 r = vec2(g.x + g.y, g.y - g.x) * 0.70710678 / 0.1;
		vec2 c = floor(r);
		vec2 f = r - c;
		float s = mod(c.x + c.y, 4.0);
		vec4 e;   // joints on this cell's (left, right, bottom, top)
		vec2 id = c;
		if (mod(c.x - c.y, 2.0) < 0.5) {
			e = s < 1.0 ? vec4(1.0, 0.0, 1.0, 1.0) : vec4(1.0, 1.0, 1.0, 0.0);
		} else if (s < 2.0) {
			e = vec4(0.0, 1.0, 1.0, 1.0);
			id = c - vec2(1.0, 0.0);
		} else {
			e = vec4(1.0, 1.0, 0.0, 1.0);
			id = c - vec2(0.0, 1.0);
		}
		float jd = min(min(mix(9.0, f.x, e.x), mix(9.0, 1.0 - f.x, e.y)), min(mix(9.0, f.y, e.z), mix(9.0, 1.0 - f.y, e.w)));
		return vec3(jd * 0.1, id);
	}
	vec2 size = pattern < 1.5 ? vec2(0.2, 0.1) : (pattern < 2.5 ? vec2(0.4, 0.4) : vec2(1.5, 1.2));
	vec2 r = g / size;
	if (pattern < 1.5) {
		r.x += mod(floor(r.y), 2.0) * 0.5;   // stretcher bond: every other row half a brick on
	}
	vec2 c = floor(r);
	vec2 f = r - c;
	vec2 d = min(f, 1.0 - f) * size;
	return vec3(min(d.x, d.y), c);
}
void fragment() {
	if (COLOR.b > 0.5) {
		// The pavement: pavers in the street's own pattern and colours (COLOR.r: pattern x 4 +
		// colours), laid square to the kerb (UV: metres along, out from the kerb), a row of
		// them on end along the kerb; fallen leaves under the trees (COLOR.g: how many trees)
		float code = floor(COLOR.r * 16.0);
		float pattern = floor(code / 4.0);
		float mixk = code - pattern * 4.0;
		vec2 g = UV;
		bool border = pattern < 1.5 && g.y < 0.2;
		vec3 pv = border ? paver(vec2(g.x, g.y) * vec2(2.0, 0.5), 1.0) * vec3(0.5, 1.0, 1.0) : paver(g, pattern);
		float h = h21(pv.yz + (border ? 71.3 : 0.0));
		float h2 = h21(pv.yz + 13.7);
		vec3 base = pave.rgb;
		vec3 col;
		if (mixk < 0.5) {          // reds and browns, mixed
			vec3 a = base * vec3(1.32, 0.9, 0.78);
			vec3 b = base * vec3(1.12, 0.86, 0.76);
			vec3 cc = base * vec3(0.98, 0.84, 0.82);
			col = h < 0.4 ? a : (h < 0.75 ? b : cc);
		} else if (mixk < 1.5) {   // greys, a darker one here and there
			col = base * (h < 0.15 ? 0.84 : (h < 0.55 ? 0.95 : 1.03));
		} else if (mixk < 2.5) {   // pale sand
			col = base * vec3(1.16, 1.1, 0.96) * (0.94 + 0.08 * h);
		} else {                   // a mix of all of them
			col = h < 0.3 ? base * vec3(1.3, 0.92, 0.8) : (h < 0.5 ? base * vec3(1.1, 0.95, 0.75) : (h < 0.8 ? base * 0.95 : base * vec3(1.05, 0.9, 0.95)));
		}
		if (border) {
			col = base * 0.86;
		}
		col *= 0.92 + 0.12 * h2;
		// further off than a few pixels a paver, the pattern is its average colour
		float fw = length(fwidth(g));
		float far = smoothstep(0.012, 0.05, fw);
		vec3 avg = mixk < 0.5 ? base * vec3(1.16, 0.88, 0.79) : (mixk < 1.5 ? base * 0.93 : (mixk < 2.5 ? base * vec3(1.16, 1.1, 0.96) : base * vec3(1.12, 0.92, 0.84)));
		col = mix(col, avg, far);
		// the joints, sand-filled and dark, and each paver's bevelled edge
		float jw = 0.004;
		float joint = 1.0 - smoothstep(jw, jw + max(fw, 0.0015), pv.x);
		float bevel = smoothstep(jw, jw + 0.012, pv.x);
		col *= mix(1.0, mix(1.0, 0.66, joint) * mix(0.93, 1.0, bevel), 1.0 - far);
		// the grime of a street: wide soft stains, darker where feet and wheels go
		float st = h21(floor(wpos.xz / 2.3)) * 0.5 + h21(floor(wpos.xz / 0.9) + 4.1) * 0.5;
		col *= 0.9 + 0.1 * smoothstep(0.2, 0.8, st);
		if (textured > 0.5) {
			vec3 t = texture(conc, wpos.xz * 0.9).rgb;
			col *= mix(1.0, clamp(dot(t, vec3(0.333)) / dot(conc_mean, vec3(0.333)), 0.0, 2.0), 0.6);
		}
		// leaves: one in some 18 cm squares, more under the trees, yellow to brown, and in
		// Givatayim the odd bougainvillea petal
		float leafy = COLOR.g;
		vec2 lc = floor(wpos.xz / 0.18);
		float lh = h21(lc);
		if (leafy > 0.01 && lh < leafy * 0.3 && far < 0.99) {
			vec2 lp = fract(wpos.xz / 0.18) - 0.5 + (vec2(h21(lc + 3.1), h21(lc + 5.7)) - 0.5) * 0.4;
			float an = h21(lc + 9.2) * 6.2832;
			lp = vec2(lp.x * cos(an) - lp.y * sin(an), lp.x * sin(an) + lp.y * cos(an));
			float m = 1.0 - smoothstep(0.13, 0.17, length(lp * vec2(1.0, 2.3)));
			float k = h21(lc + 1.7);
			vec3 leaf = mix(vec3(0.62, 0.52, 0.18), vec3(0.42, 0.3, 0.16), k);
			if (med > 0.5 && k > 0.88) {
				leaf = vec3(0.72, 0.16, 0.42);
			}
			col = mix(col, leaf, m * (1.0 - far));
		}
		ALBEDO = col;
		ROUGHNESS = 0.9;
	} else {   // the kerb
	float pat = floor(COLOR.r * 3.99 + 0.01);
	float stripe = step(0.5, fract(UV.x * 0.5));
	vec3 c = plain.rgb;
	if (pat > 0.5 && pat < 1.5) { c = mix(red.rgb, white.rgb, stripe); }
	else if (pat > 1.5 && pat < 2.5) { c = mix(blue.rgb, white.rgb, stripe); }
	else if (pat > 2.5) { c = mix(yellow.rgb, black.rgb, stripe); }
	if (textured > 0.5) {
		// concrete grain through the paint (laid from above on the top, along on the face),
		// and the face's foot darker: road dirt thrown up against it
		vec2 uv = wup > 0.5 ? wpos.xz : vec2(UV.x, wpos.y);
		vec3 t = texture(conc, uv * 0.8).rgb;
		c *= mix(1.0, clamp(dot(t, vec3(0.333)) / dot(conc_mean, vec3(0.333)), 0.0, 2.0), 0.7);
		if (wup < 0.5) {
			c *= mix(0.7, 1.0, UV.y);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
	}
}
"""

## Flat roofs: tar and gravel -- the asphalt's grit, finer -- with dried-puddle stains
const ROOF_SHADER := """
shader_type spatial;
uniform vec4 tone : source_color;
uniform float textured = 1.0;
uniform sampler2D grit : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grit_mean = vec3(0.5);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = tone.rgb * COLOR.rgb;
	if (textured > 0.5) {
		vec3 t = texture(grit, wpos.xz / 1.4).rgb;
		c *= mix(1.0, clamp(dot(t, vec3(0.333)) / dot(grit_mean, vec3(0.333)), 0.0, 2.0), 0.55);
		c *= 1.0 - 0.18 * smoothstep(0.55, 0.85, noise(wpos.xz / 2.3));
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
"""
var _roof_mat: ShaderMaterial
const PAVE_W := 2.4                  ## pavement width (m)
const KERB_CUT := 4.5                ## kerbs stop this far past a junction's road edge: the corner's radius
const KERB_H := 0.14
const KERB_W := 0.2
var _kerb_mat: ShaderMaterial

func _build_kerbs() -> void:
	var kerb := _clip_buf(GROUND_CELL)
	var pave := kerb   # (the pavement is drawn by the kerb's shader, in the kerb's mesh: no extra draw)
	var wall := _clip_buf(GROUND_CELL)
	var garden := _clip_buf(GROUND_CELL)
	var fronts := {"hedge": _clip_buf(GROUND_CELL), "bars": _clip_buf(GROUND_CELL), "bar_posts": _clip_buf(GROUND_CELL),
		"chain": _clip_buf(GROUND_CELL), "chain_posts": _clip_buf(GROUND_CELL), "flowers": []}
	var bushes: Array = []
	var med := String(_place.get("look", "")) == "med"
	for ri: int in _tile_roads.get(_tile, []):
		var r: Dictionary = _roads[ri]
		if not _kerbed(r):
			continue   # motorways and their slip roads have no pavement
		if _over():
			await _pause()
		var hw: float = float(r["w"]) * 0.5
		var hsh := _hash_i((r["pts"] as PackedVector2Array)[0])
		_set_pave_code(hsh)
		var pat := 0
		if med:
			pat = [0, 0, 0, 0, 0, 1, 1, 1, 2, 3][posmod(hsh, 10)]
		if r.has("kerb"):
			pat = int(r["kerb"])   # (as filmed: 0 plain, 1 red-white, 2 blue-white, 3 yellow-black)
		var yard: bool = r["k"] in ["residential", "living_street"]
		var dual := r.has("median")
		var inner_sgn := -float(r["o"])   # a divided road's other half is on the left of its traffic
		for run: PackedVector2Array in _street_runs(r, KERB_CUT, true):
			if not _tile_rect(_tile).grow(hw + PAVE_W + 6.0).intersects(_bld_box_of(run)):
				continue   # a stretch nowhere near this square
			if _over():
				await _pause()
			for sgn: float in [-1.0, 1.0]:
				var inner_side := dual and sgn == inner_sgn
				var pw := PAVE_W
				if inner_side:
					var m: float = r["median"]
					if m < 0.25:
						continue   # the halves touch: a painted line, no kerb
					pw = clampf(m * 0.5 - KERB_W, 0.0, PAVE_W)   # each half paves its half of the median
				var inner := _offset_line(run, hw * sgn)
				var col := Color(float(pat) / 4.0 + 0.05, 0, 0) if not inner_side else Color(0.05, 0, 0)   # a median's kerb: plain
				var along := 0.0
				for i in range(run.size() - 1):
					var seg := run[i].distance_to(run[i + 1])
					var na := (inner[i] - run[i]).normalized()
					var nb := (inner[i + 1] - run[i + 1]).normalized()
					_kerb_run_piece(kerb, pave, ri, inner[i], inner[i + 1], na, nb, pw, col, along, seg)
					along += seg
				if inner_side:
					continue
				if not yard:
					continue
				# a low stone wall at the back of the pavement, a garden strip behind it
				var w_in := _offset_line(run, (hw + PAVE_W + 0.05) * sgn)
				var w_out := _offset_line(run, (hw + PAVE_W + 0.3) * sgn)
				var g_out := _offset_line(run, (hw + PAVE_W + 3.4) * sgn)
				var walled := PackedByteArray()   # which pieces of the run have the wall (for the fronts on it)
				walled.resize(run.size())
				for i in range(run.size() - 1):
					# (not where it would lie on another road: a garden strip of one street ran
					# over the asphalt of the next where they met at an angle)
					if _asphalt_other((w_out[i] + w_out[i + 1] + g_out[i] + g_out[i + 1]) * 0.25, ri) \
							or _asphalt_other(w_in[i], -1) or _asphalt_other(w_in[i + 1], -1) \
							or _asphalt_other((w_in[i] + w_in[i + 1]) * 0.5, -1):
						continue   # (nor where the wall itself would, on any road, its own too at
						           # a sharp bend: by the garden's middle alone, a wall stood
						           # across the next street, and autodrive hit it)
					walled[i] = 1
					garden.quad3(_g3(w_out[i], 0.03), _g3(w_out[i + 1], 0.03), _g3(g_out[i + 1], 0.03), _g3(g_out[i], 0.03))
					if not med:
						continue   # northern lawns run open to the pavement
					var wy := 0.62
					wall.quad3(_g3(w_in[i], wy), _g3(w_in[i + 1], wy), _g3(w_out[i + 1], wy), _g3(w_out[i], wy))
					if _mine(w_in[i]):   # (every square along the street works it out: one records it)
						add_wall((w_in[i] + w_out[i]) * 0.5, (w_in[i + 1] + w_out[i + 1]) * 0.5, 0.13)
					var fn := Vector3(-(w_in[i + 1] - w_in[i]).y, 0, (w_in[i + 1] - w_in[i]).x).normalized() * -sgn
					wall.tri(_g3(w_in[i], 0.0), _g3(w_in[i + 1], 0.0), _g3(w_in[i + 1], wy), fn, Color.WHITE)
					wall.tri(_g3(w_in[i], 0.0), _g3(w_in[i + 1], wy), _g3(w_in[i], wy), fn, Color.WHITE)
				if med:
					await _garden_fronts(run, hw, sgn, _hash_i(run[0]) + int(sgn) * 104729, fronts, walled)
				var step := 7.0
				var s := 3.0
				for i in range(run.size() - 1):
					var L := run[i].distance_to(run[i + 1])
					while s < L:
						var q := (w_out[i].lerp(w_out[i + 1], s / L)).lerp(g_out[i].lerp(g_out[i + 1], s / L), 0.45)
						if _mine(q) and posmod(_hash_i(q), 3 if med else 6) == 1 and not _asphalt_other(q, ri) and _push_out(q, 0.8, false) == Vector2.ZERO:
							var sc := 0.7 + 0.5 * float(posmod(_hash_i(q), 5)) / 4.0
							bushes.append(Transform3D(Basis.from_scale(Vector3(1.3, 0.9, 1.3) * sc), _g3(q, 0.45 * sc)))
						s += step
					s -= L
	if med:
		await _build_medians(kerb, pave)
	var corners := _clip_buf(GROUND_CELL)
	await _kerb_corners(kerb, pave, corners, Color((0.25 if med else 0.0) + 0.05, 0, 0))
	if _over():
		await _pause()
	_add_mesh(corners, _surface("asphalt"), false, VIEW_RANGE)
	if _kerb_mat == null:
		_kerb_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = KERB_SHADER
		_kerb_mat.shader = sh
		_kerb_mat.set_shader_parameter("conc", _tex("concrete_pavement_diff"))
		_kerb_mat.set_shader_parameter("conc_mean", TEX_MEAN["concrete_pavement"])
		_kerb_mat.set_shader_parameter("textured", 1.0 if _quality > 0 else 0.0)
		_retint_kerbs()
	_add_mesh(kerb, _kerb_mat, false, DETAIL_RANGE * 1.6)
	_add_mesh(wall, _surface("stonewall"), false, DETAIL_RANGE)
	_add_mesh(garden, _surface("grass"), false, DETAIL_RANGE * 1.6)
	if _over():
		await _pause()
	_add_mesh(fronts["hedge"], _surface("bush"), true, DETAIL_RANGE * 1.2)
	_add_mesh(fronts["bars"], _furn._fence_material("railing", 0.15), false, DETAIL_RANGE * 0.8)
	_add_mesh(fronts["bar_posts"], _surface("railing"), false, DETAIL_RANGE * 0.8)
	_add_mesh(fronts["chain"], _furn._fence_material("fencegreen", 0.12), false, DETAIL_RANGE * 0.8)
	_add_mesh(fronts["chain_posts"], _surface("fencegreen"), false, DETAIL_RANGE * 0.8)
	if not (fronts["flowers"] as Array).is_empty():
		# bougainvillea: a leafy green shrub (the trees' leaf cards, small) with a smaller
		# crown of magenta on top of it -- the instance colour turns the leaves into flowers
		var leaves: Array = []
		var blooms: Array = []
		for t: Transform3D in fronts["flowers"]:
			leaves.append(t * Transform3D(Basis.from_scale(Vector3(0.55, 0.5, 0.5)), Vector3.ZERO))
			blooms.append(t * Transform3D(Basis.from_scale(Vector3(0.45, 0.35, 0.42)), Vector3(0.0, 0.18, 0.05)))
		var green: Array = []
		var pink: Array = []
		for i in range(leaves.size()):
			green.append(Color(0.82, 0.95, 0.78, 0.125))   # broad leaves (atlas cell 0)
			pink.append(Color(2.9, 0.55, 1.9, 0.375))      # small ones (cell 1), magenta
		_chunked(_tree_meshes["crown"], leaves, DETAIL_RANGE, green, null, false)
		_chunked(_tree_meshes["crown"], blooms, DETAIL_RANGE, pink, null, false)
		_tally("bougainvillea", leaves.size())
	if not bushes.is_empty():
		# leafy shrubs: the trees' leaf-card crowns, small (a smooth ball read as a toy)
		var shrubs: Array = []
		var cols: Array = []
		for t: Transform3D in bushes:
			shrubs.append(t * Transform3D(Basis.from_scale(Vector3(0.5, 0.55, 0.5)), Vector3.ZERO))
			cols.append(Color(0.8, 0.92, 0.78, 0.125))
		_chunked(_tree_meshes["crown"], shrubs, DETAIL_RANGE, cols, null, false)
	_tally("bushes", bushes.size())

## Israeli main streets are not open down the middle: a raised island divides the two ways.
## A wide two-way main road (OSM maps many as one road) gets one, MEDIAN_W wide, kerbed both
## sides and paved on top, solid to the car; it stops short of every junction (turning across
## is still possible there) and leaves a gap at each zebra. r["mid"] is its half width.
const MEDIAN_W := 1.2

func _median_road(r: Dictionary) -> bool:
	if not r["drive"] or int(r["o"]) != 0 or r.get("ring", false) or not _kerbed(r):
		return false
	var w := float(r["w"])
	# (secondary streets come out 10 m wide, tertiary 9: the main roads, not the side streets)
	return (r["k"] in ["trunk", "primary", "secondary"] and w >= 9.5) or (r["k"] == "tertiary" and (w >= 12.0 or int(r["l"]) >= 4))

## which roads get one, for the whole city at once (autodrive's turn lane keeps off them
## wherever they are; the islands go up square by square)
func _mark_medians() -> void:
	if String(_place.get("look", "")) != "med":
		return
	for r: Dictionary in _roads:
		if _median_road(r):
			r["mid"] = MEDIAN_W * 0.5

func _build_medians(kerb: Buf, pave: Buf) -> void:
	var zebra := {}
	for ni: int in _crossing_nodes:
		zebra[ni] = true
	var made := 0.0
	var mw := MEDIAN_W * 0.5
	for ri: int in (_tile_roads.get(_tile, []) if _tiled else range(_roads.size())):
		var r: Dictionary = _roads[ri]
		if not r.has("mid"):
			continue
		if _over():
			await _pause()
		# the zebras on it, to leave a gap at
		var gaps: Array = []
		var ids: PackedInt32Array = r["ids"]
		for k in range(ids.size()):
			if zebra.has(ids[k]):
				gaps.append(_nodes[ids[k]])
		for run: PackedVector2Array in _street_runs(r, KERB_CUT, true):
			if _tiled and not _tile_rect(_tile).grow(10.0).intersects(_bld_box_of(run)):
				continue   # a stretch nowhere near this square
			var cum := 0.0
			for i in range(run.size() - 1):
				var a := run[i]
				var b := run[i + 1]
				var seg := a.distance_to(b)
				var gap := false
				for gp: Vector2 in gaps:
					if Geometry2D.get_closest_point_to_segment(gp, a, b).distance_to(gp) < 3.5:
						gap = true
				if not gap:
					var d := (b - a) / maxf(seg, 0.001)
					var rt := Vector2(-d.y, d.x)
					for sgn: float in [1.0, -1.0]:
						# a kerb at mw each side, its face out to the lanes, paved behind to the middle
						var na := -rt * sgn
						_kerb_run_piece(kerb, pave, ri, a + rt * mw * sgn, b + rt * mw * sgn, na, na,
								maxf(mw - KERB_W, 0.0), Color(0.05, 0, 0), cum, seg)
					if _mine(a):   # (recorded once, by the square it starts in)
						add_wall(a, b, mw)
						made += seg
				cum += seg
	_tally("median_m", int(made))

func _kerbed(r: Dictionary) -> bool:
	return r["drive"] and not r["pv"] and r["k"] != "service" and not HIGHWAYS.has(r["k"])

## ways out of node n along roads that have kerbs
func _kerb_arms(n: int) -> int:
	var count := 0
	for e: Vector2i in _node_roads[n]:
		var r: Dictionary = _roads[e.x]
		if not _kerbed(r):
			continue
		if e.y > 0:
			count += 1
		if e.y < (r["pts"] as PackedVector2Array).size() - 1:
			count += 1
	return count

## p lies on the asphalt of some drivable road other than ri. Asked tens of thousands of
## times while the kerbs go in, so against its own fine grid of road surfaces (8 m squares,
## a handful of segments each) rather than the 24 m one everything else uses.
var _asph_hash := {}
const ASPH_CELL := 8.0

func _build_asph_hash() -> void:
	_asph_hash = {}
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5
		for j in range(pts.size() - 1):
			_hash_add(_asph_hash, Rect2(pts[j], Vector2.ZERO).expand(pts[j + 1]).grow(hw), ASPH_CELL, ri * 4096 + j)

func _asphalt_other(p: Vector2, ri: int) -> bool:
	for code: int in (_asph_hash.get(_cell(p, ASPH_CELL), []) as Array):
		var rj := code / 4096
		if rj == ri:
			continue
		var r2: Dictionary = _roads[rj]
		if not r2["drive"]:
			continue
		var p2: PackedVector2Array = r2["pts"]
		var sj := code % 4096
		var cp := Geometry2D.get_closest_point_to_segment(p, p2[sj], p2[sj + 1])
		if p.distance_squared_to(cp) < pow(maxf(float(r2["w"]) * 0.5 - 0.25, 0.0), 2.0):
			return true
	return false

## One stretch of kerb (inner edge a-b, outward normals na/nb) and the pavement behind it,
## left out wherever it would lie on another road's asphalt: where two roads overlap (a
## divided road's halves, a slip road) the pavement no longer runs down the lanes, and a
## driveway gets its gap. A clear stretch goes in whole; one that is not, in short pieces.
func _kerb_run_piece(kerb: Buf, pave: Buf, ri: int, a: Vector2, b: Vector2, na: Vector2, nb: Vector2, pw: float,
		col: Color, along: float, seg: float) -> void:
	var ts: Array = [0.5] if seg <= 8.0 else [0.15, 0.5, 0.85]
	var clear := true
	for t: float in ts:
		if _kerb_probe(a, b, na, nb, t, pw, ri) != Vector2.ZERO:
			clear = false
			break
	if clear:
		_kerb_piece(kerb, pave, a, b, na, nb, pw, col, along)
		return
	var n := maxi(2, ceili(seg / 1.5))
	for k in range(n):
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var hit: Vector2 = _kerb_probe(a, b, na, nb, (t0 + t1) * 0.5, pw, ri)
		if hit.x > 0.0:
			continue
		_kerb_piece(kerb, pave, a.lerp(b, t0), a.lerp(b, t1), na.lerp(nb, t0).normalized(), na.lerp(nb, t1).normalized(),
			0.0 if hit.y > 0.0 else pw, col, along + seg * t0)

## (kerb on another road's asphalt, pavement on it) at fraction t of a kerb stretch
func _kerb_probe(a: Vector2, b: Vector2, na: Vector2, nb: Vector2, t: float, pw: float, ri: int) -> Vector2:
	var q := a.lerp(b, t)
	var nq := na.lerp(nb, t).normalized()
	return Vector2(1.0 if _asphalt_other(q + nq * KERB_W * 0.5, ri) else 0.0,
		1.0 if pw > 0.05 and _asphalt_other(q + nq * (KERB_W + pw * 0.5), ri) else 0.0)

## a kerb from a to b (its face toward the road, its top KERB_W wide) and pw of pavement behind
func _kerb_piece(kerb: Buf, pave: Buf, a: Vector2, b: Vector2, na: Vector2, nb: Vector2, pw: float, col: Color, along: float) -> void:
	var seg := a.distance_to(b)
	var a0 := _g3(a, 0.0)
	var a1 := _g3(b, 0.0)
	var t0 := a0 + Vector3(0, KERB_H, 0)
	var t1 := a1 + Vector3(0, KERB_H, 0)
	var oa := a + na * KERB_W
	var ob := b + nb * KERB_W
	var o0 := _g3(oa, KERB_H)
	var o1 := _g3(ob, KERB_H)
	var nm := (na + nb).normalized()
	var face := Vector3(-nm.x, 0, -nm.y)
	kerb.tri(a0, a1, t1, face, col, Vector2(along, 0), Vector2(along + seg, 0), Vector2(along + seg, 1))
	kerb.tri(a0, t1, t0, face, col, Vector2(along, 0), Vector2(along + seg, 1), Vector2(along, 1))
	kerb.tri(t0, t1, o1, Vector3.UP, col, Vector2(along, 0), Vector2(along + seg, 0), Vector2(along + seg, 1))
	kerb.tri(t0, o1, o0, Vector3.UP, col, Vector2(along, 0), Vector2(along + seg, 1), Vector2(along, 1))
	if pw > 0.05:
		var c2 := _g3(ob + nb * pw, KERB_H)
		var c3 := _g3(oa + na * pw, KERB_H)
		var nrm := (c2 - o0).cross(o1 - o0)
		if nrm.y < 0.0:
			nrm = -nrm
		nrm = nrm.normalized() if nrm.length_squared() > 0.000001 else Vector3.UP
		var pc := Color(_pave_code, _leafy((oa + ob) * 0.5 + (na + nb) * pw * 0.25), 1.0)
		pave.tri(o0, o1, c2, nrm, pc, Vector2(along, 0), Vector2(along + seg, 0), Vector2(along + seg, pw))
		pave.tri(o0, c2, c3, nrm, pc, Vector2(along, 0), Vector2(along + seg, pw), Vector2(along, pw))

## The paving a street (or a corner) gets: its pattern -- herringbone, rows of bricks, square
## slabs; Bedford's poured concrete -- and its colours -- reds and browns, greys, sand, all of
## them mixed -- as the red of the pavement's vertex colour (see KERB_SHADER)
var _pave_code := 0.0

func _set_pave_code(hsh: int) -> void:
	var pattern := 3
	var colours := 1
	if String(_place.get("look", "")) != "north":
		var p := posmod(hsh, 100)
		pattern = 0 if p < 45 else (1 if p < 75 else 2)
		var c := posmod(hsh >> 7, 100)
		colours = 0 if c < 30 else (1 if c < 70 else (2 if c < 85 else 3))
		if pattern == 2 and colours == 0:
			colours = 1   # (slabs come grey or sand)
	_pave_code = (float(pattern * 4 + colours) + 0.5) / 16.0

## A garden's front, plot by plot along one side of a street's run (each 14-22 m, a gap
## between them where the gates are), as a walk down Givatayim's streets has them: a clipped
## hedge behind the low wall, white bars or green chain-link on top of it, or the bare wall;
## bougainvillea spilling over one in six. Keyed to the run, so every square along the
## street works out the same plots (the fronts are laid like the kerbs: CBuf.clip).
func _garden_fronts(run: PackedVector2Array, hw: float, sgn: float, key: int, fronts: Dictionary,
		walled: PackedByteArray) -> void:
	var on_wall := _offset_line(run, (hw + PAVE_W + 0.175) * sgn)
	var behind := _offset_line(run, (hw + PAVE_W + 0.85) * sgn)
	var cum := PackedFloat32Array([0.0])
	for i in range(1, run.size()):
		cum.append(cum[i - 1] + run[i - 1].distance_to(run[i]))
	var total := cum[cum.size() - 1]
	var near := _tile_rect(_tile).grow(6.0)
	var s := 0.0
	var plot := 0
	while s < total - 2.0:
		var h := posmod(key + plot * 7919, 1000003)
		var e := minf(s + 14.0 + float(posmod(h, 9)), total)
		var style := posmod(h >> 4, 100)
		var line := behind if style < 42 else on_wall
		var pts: Array = [_along(line, cum, s + 0.7)]
		var seg: Array = [_seg_at(cum, s + 0.7)]   # the piece of the run each stretch starts on
		var box := Rect2(pts[0], Vector2.ZERO)
		for i in range(1, line.size() - 1):
			if cum[i] > s + 0.7 and cum[i] < e - 0.7:
				pts.append(line[i])
				seg.append(i)
				box = box.expand(line[i])
		pts.append(_along(line, cum, e - 0.7))
		box = box.expand(pts[pts.size() - 1])
		if _tiled and not near.intersects(box.grow(1.0)):
			s = e   # a plot nowhere near this square: its own square lays it (same plots, same key)
			plot += 1
			continue
		if _over():
			await _pause()
		if style < 42:
			# a hedge behind the wall, on the garden strip: off the roads where the strip is
			# (looked at already), but it can still run into a house, so it looks for those
			for k in range(pts.size() - 1):
				if walled[int(seg[k])] and (pts[k] as Vector2).distance_to(pts[k + 1]) >= 0.3 \
						and _off_road(pts[k], 0.45) and _off_road(pts[k + 1], 0.45):
					# (its ends clear of the asphalt by its half width: where the strip met
					# another street at a bend, one stood 0.4 m into the road)
					_furn._hedge_line(fronts["hedge"], pts[k], pts[k + 1], false)
		elif style < 76:
			# bars or chain-link on the wall: only where the wall is, which was looked at
			# already and is solid already, so no looking again and no walls of its own --
			# and in one panel per piece of the wall, its foot along the wall's top
			var bars := style < 62
			var run_u := 0.0
			for k in range(pts.size() - 1):
				var a: Vector2 = pts[k]
				var b: Vector2 = pts[k + 1]
				if not walled[int(seg[k])] or a.distance_to(b) < 0.3:
					continue
				var A := _g3(a, 0.6)
				var B := _g3(b, 0.6)
				if bars:
					run_u = _furn.wall_fence(fronts["bars"], fronts["bar_posts"], A, B, 0.95, _tone["railing"], 2.4, true, run_u)
				else:
					run_u = _furn.wall_fence(fronts["chain"], fronts["chain_posts"], A, B, 1.3, _tone["fencegreen"], 2.6, false, run_u)
		if posmod(h >> 9, 100) < 16:   # bougainvillea over the wall, a few clumps
			for t: float in [0.25, 0.5, 0.75]:
				var q := _along(on_wall, cum, lerpf(s, e, t)) - (on_wall[0] - run[0]).normalized() * 0.15
				if _mine(q) and _push_out(q, 0.4, false) == Vector2.ZERO:
					var sc := 0.8 + 0.5 * float(posmod(_hash_i(q), 7)) / 6.0
					(fronts["flowers"] as Array).append(Transform3D(Basis.from_scale(Vector3(1.4, 1.0, 1.1) * sc), _g3(q, 0.62 + 0.3 * sc)))
		s = e
		plot += 1

## how many trees overhang a spot on the pavement, 0..1 (for the leaves on it)
func _leafy(p: Vector2) -> float:
	var sum := 0.0
	for i: int in _near(_post_hash, p, 7.0, BLD_CELL):
		if absf(_post_r[i] - 0.3) < 0.001:   # (a tree's post)
			sum += 1.0 - clampf(_posts[i].distance_to(p) / 7.0, 0.0, 1.0)
	return clampf(sum * 0.7, 0.0, 1.0)

## which piece of a line `s` metres along it is on (cum: the distance to each point)
func _seg_at(cum: PackedFloat32Array, s: float) -> int:
	for i in range(1, cum.size()):
		if cum[i] >= s:
			return i - 1
	return cum.size() - 2

## the point `dist` metres along a road's points from index k going `step`, and the way on
func _walk_pts(pts: PackedVector2Array, k: int, step: int, dist: float) -> Array:
	var left := dist
	while k + step >= 0 and k + step < pts.size():
		var seg := pts[k].distance_to(pts[k + step])
		var d := (pts[k + step] - pts[k]) / maxf(seg, 0.001)
		if seg >= left:
			return [pts[k] + d * left, d, true]
		left -= seg
		k += step
	return [pts[k], Vector2.ZERO, false]

## The corners of every junction: between each road coming in and the next one round, a
## kerb that curves from one street's edge to the other's (red and white in Israel: no
## stopping at a corner), its pavement behind it, and the asphalt filled out to it. Across
## the mouth of a T, a straight kerb; between the two halves of a divided road, a flat nose.
var _corner_cut_at: Array = []        ## corners laid piece by piece: [middle, middle clear] (for tests)

func _kerb_corners(kerb: Buf, pave: Buf, fill: Buf, col: Color) -> void:
	for ni: int in _nodes_near(60.0):   # (every square a corner reaches works it out)
		if _over():
			await _pause()
		if _kerb_arms(ni) < 3:
			continue
		var c := _nodes[ni]
		var cut := _node_r[ni] + KERB_CUT
		var arms: Array = []   # [angle, point at the cut, way out there, half width, road]
		var through: Array = []   # the ways out of pieces too short for a corner of their own
		for e: Vector2i in _node_roads[ni]:
			var r: Dictionary = _roads[e.x]
			if not _kerbed(r):
				continue
			var pts: PackedVector2Array = r["pts"]
			for step: int in [-1, 1]:
				if e.y + step < 0 or e.y + step >= pts.size():
					continue
				var at: Array = _walk_pts(pts, e.y, step, cut)
				if not at[2]:
					var q := pts[e.y + step]
					through.append(atan2(q.y - c.y, q.x - c.x))
					continue   # too short to reach the corner (a piece across a median)
				var p: Vector2 = at[0]
				arms.append([atan2(p.y - c.y, p.x - c.x), p, at[1], float(r["w"]) * 0.5, e.x])
		if arms.size() < 2:
			continue
		arms.sort_custom(func(x, y): return x[0] < y[0])
		for i in range(arms.size()):
			var A: Array = arms[i]
			var B: Array = arms[(i + 1) % arms.size()]
			var gap: float = fposmod(float(B[0]) - float(A[0]), TAU)
			if gap > 3.6 or gap < 0.02:
				continue
			# no corner across a road that goes out between the two: on a divided road's median
			# side, the piece of the cross street through the median. (Laid anyway, it ran
			# straight across the opening; cut up where it lay on the asphalt, what was left
			# stood out of the island's end as an arrowhead and spikes.)
			var crossed := false
			for ang: float in through:
				var into := fposmod(ang - float(A[0]), TAU)
				if into > 0.05 and into < gap - 0.05:
					crossed = true
					break
			if crossed:
				if _mine(c):
					_tally("corners_across_roads", 1)
				continue
			var ua: Vector2 = A[2]
			var ub: Vector2 = B[2]
			_set_pave_code(_hash_i((_roads[int(A[4])]["pts"] as PackedVector2Array)[0]))   # (the paving of one of its streets)
			var P: Vector2 = (A[1] as Vector2) + Vector2(-ua.y, ua.x) * float(A[3])   # A's right edge
			var Q: Vector2 = (B[1] as Vector2) + Vector2(ub.y, -ub.x) * float(B[3])   # B's left edge
			if P.distance_to(Q) > 45.0:
				continue
			var curve := PackedVector2Array()
			var X = Geometry2D.line_intersects_line(P, ua, Q, ub)
			var round := X != null and gap > 0.35 and gap < 2.9 and (X as Vector2).distance_to(c) < cut * 2.5 \
				and ((X as Vector2) - P).dot(ua) < 0.0 and ((X as Vector2) - Q).dot(ub) < 0.0
			if round:
				for k in range(7):
					var t := k / 6.0
					curve.append(P * (1.0 - t) * (1.0 - t) + (X as Vector2) * 2.0 * (1.0 - t) * t + Q * t * t)
				# the asphalt out to the curve (the two streets' edges met in a sharp corner)
				var xg := _g3(X, Y_ROAD)
				for k in range(6):
					fill.tri(xg, _g3(curve[k], Y_ROAD), _g3(curve[k + 1], Y_ROAD), Vector3.UP, Color.WHITE)
			else:
				var n := maxi(1, ceili(P.distance_to(Q) / 3.0))
				for k in range(n + 1):
					curve.append(P.lerp(Q, float(k) / n))
			# a look along the corner: clear (nearly always), it goes in whole; else piece by
			# piece, leaving out what lies on another road. (One look at its middle let a kerb
			# straight across a road's mouth in whole wherever its middle happened to miss
			# the asphalt -- a strip of pavement across the junction.)
			var whole := true
			for k in range(curve.size()):
				var kt := (curve[mini(k + 1, curve.size() - 1)] - curve[maxi(k - 1, 0)]).normalized()
				var kn := Vector2(-kt.y, kt.x)
				if kn.dot(curve[k] - c) < 0.0:
					kn = -kn
				if _asphalt_other(curve[k] + kn * KERB_W * 0.5, -1) \
						or (k == curve.size() / 2 and _asphalt_other(curve[k] + kn * (KERB_W + PAVE_W * 0.5), -1)):
					whole = false
					break
			if not whole and _mine(c):
				# (and whether the one look at its middle would have let it in whole)
				var m := curve.size() / 2
				var mt := (curve[m] - curve[m - 1]).normalized()
				var mn := Vector2(-mt.y, mt.x) * (1.0 if Vector2(-mt.y, mt.x).dot(curve[m] - c) >= 0.0 else -1.0)
				_corner_cut_at.append([curve[m], not _asphalt_other(curve[m] + mn * KERB_W * 0.5, -1) \
					and not _asphalt_other(curve[m] + mn * (KERB_W + PAVE_W * 0.5), -1)])
			var along := 0.0
			for k in range(curve.size() - 1):
				var a := curve[k]
				var b := curve[k + 1]
				var tg := b - a
				if tg.length_squared() < 0.0001:
					continue
				var nrm := Vector2(-tg.y, tg.x).normalized()
				if nrm.dot((a + b) * 0.5 - c) < 0.0:
					nrm = -nrm
				if whole:
					_kerb_piece(kerb, pave, a, b, nrm, nrm, PAVE_W, col, along)
				else:
					_kerb_run_piece(kerb, pave, -1, a, b, nrm, nrm, PAVE_W, col, along, a.distance_to(b))
				along += a.distance_to(b)

func _retint_kerbs() -> void:
	if _roof_mat != null:
		_roof_mat.set_shader_parameter("tone", _tone["roof"])
	if _kerb_mat == null:
		return
	_kerb_mat.set_shader_parameter("plain", _tone["kerb"])
	_kerb_mat.set_shader_parameter("white", Palette.col("ink"))
	# the kerb paint is vivid, as it is on the street, but red rather than the palette's pink
	_kerb_mat.set_shader_parameter("red", _natural(Palette.col("hazard").lerp(Palette.col("warn"), 0.22), 0.85))
	_kerb_mat.set_shader_parameter("blue", _natural(Palette.col("player").lerp(Palette.col("bg"), 0.35), 0.85))
	_kerb_mat.set_shader_parameter("yellow", Palette.col("warn"))
	_kerb_mat.set_shader_parameter("black", Palette.col("bg"))
	_kerb_mat.set_shader_parameter("pave", _tone["pavement"])
	_kerb_mat.set_shader_parameter("med", 0.0 if String(_place.get("look", "")) == "north" else 1.0)

## a street's stretches between junctions, each cut short where it meets one (so kerbs
## and walls leave the corner open), points every few metres
## A road's stretches between the places it meets others, trimmed back from them. For kerbs
## (`kerbs`): only real junctions (three or more kerbed ways) cut them, trimmed `extra` metres
## past the junction's middle road edge, so the corner can be rounded; where two OSM pieces
## of the same street join, or a driveway comes in, the kerb runs on.
func _street_runs(r: Dictionary, extra := 2.0, kerbs := false) -> Array:
	var pts: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	var out: Array = []
	var start := 0
	var cuts := func(n: int) -> bool:
		return _kerb_arms(n) >= 3 if kerbs else (_node_roads[n] as Array).size() >= 2
	for i in range(1, pts.size()):
		var junction: bool = cuts.call(ids[i])
		if junction or i == pts.size() - 1:
			var run := PackedVector2Array()
			for k in range(start, i + 1):
				run.append(pts[k])
			var cut_a := _node_r[ids[start]] + extra if cuts.call(ids[start]) else 0.0
			var cut_b := _node_r[ids[i]] + extra if junction else 0.0
			var trimmed := _trim(run, cut_a, cut_b)
			if trimmed.size() >= 2:
				out.append(trimmed)
			start = i
	return out

## the polyline from `a` metres in to `b` metres short of its end
func _trim(run: PackedVector2Array, a: float, b: float) -> PackedVector2Array:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, run.size()):
		cum.append(cum[i - 1] + run[i - 1].distance_to(run[i]))
	var total := cum[cum.size() - 1]
	var out := PackedVector2Array()
	if total - a - b < 2.0:
		return out
	# the street's own corners, plus points often enough to follow the ground's detail
	var step := maxf(6.0, _hstep * 0.7) if _hnx > 0 else INF
	out.append(_along(run, cum, a))
	var s := a
	for i in range(1, run.size() - 1):
		while s + step < cum[i] and s + step < total - b:
			s += step
			out.append(_along(run, cum, s))
		if cum[i] > a and cum[i] < total - b:
			out.append(run[i])
			s = cum[i]
	while s + step < total - b:
		s += step
		out.append(_along(run, cum, s))
	out.append(_along(run, cum, total - b))
	return out

## a polyline moved sideways by d (right of travel for d > 0), mitred at the bends
func _offset_line(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in range(n):
		var d_in := (pts[i] - pts[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var d_out := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else Vector2.ZERO
		var t := d_in + d_out
		if t.length_squared() < 0.0001:
			t = d_out if d_out != Vector2.ZERO else d_in
		t = t.normalized()
		var side := Vector2(-t.y, t.x)
		var m := 1.0
		if i > 0 and i < n - 1:
			m = 1.0 / maxf(side.dot(Vector2(-d_out.y, d_out.x)), 0.5)
		out.append(pts[i] + side * d * m)
	return out

## a strip of half-width hw along a polyline, mitred at the bends
func _ribbon(buf: Buf, pts: PackedVector2Array, hw: float, y: float) -> void:
	if _hnx > 0:   # on hills: a point every 5 m so the road follows the ground
		var dense := PackedVector2Array([pts[0]])
		for i in range(1, pts.size()):
			var L := pts[i - 1].distance_to(pts[i])
			var parts := maxi(1, ceili(L / 5.0))
			for k in range(1, parts + 1):
				dense.append(pts[i - 1].lerp(pts[i], float(k) / parts))
		pts = dense
	var n := pts.size()
	if n < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(n):
		var d_in := (pts[i] - pts[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var d_out := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else Vector2.ZERO
		var d := d_in + d_out
		if d.length_squared() < 0.0001:
			d = d_out if d_out != Vector2.ZERO else d_in
		d = d.normalized()
		var side := Vector2(-d.y, d.x)
		var m := 1.0
		if i > 0 and i < n - 1:
			m = 1.0 / maxf(side.dot(Vector2(-d_out.y, d_out.x)), 0.5)
		left.append(pts[i] - side * hw * m)
		right.append(pts[i] + side * hw * m)
	var hl := _ground_line(left)
	var hr := _ground_line(right)
	for i in range(n - 1):
		buf.quad3(Vector3(left[i].x, hl[i] + y, left[i].y), Vector3(left[i + 1].x, hl[i + 1] + y, left[i + 1].y),
			Vector3(right[i + 1].x, hr[i + 1] + y, right[i + 1].y), Vector3(right[i].x, hr[i] + y, right[i].y))

func _disc(buf: Buf, c: Vector2, r: float, y: float, seg := 14) -> void:
	var mid := _g3(c, y)
	var rim: Array = []
	for i in range(seg):
		rim.append(_g3(c + Vector2(cos(TAU * i / seg), sin(TAU * i / seg)) * r, y))
	for i in range(seg):
		var p0: Vector3 = rim[i]
		var p1: Vector3 = rim[(i + 1) % seg]
		var nrm := (p0 - mid).cross(p1 - mid)
		if nrm.y < 0.0:
			nrm = -nrm
		buf.tri(mid, p0, p1, nrm.normalized() if nrm.length_squared() > 0.0 else Vector3.UP, Color.WHITE)

## Cast iron in the road: a manhole cover every 55-95 m down a street, somewhere in its
## width, and a drain grate at the kerb every 40-65 m, on alternate sides -- flat on the
## asphalt, clear of the junctions, merged into the ground like the paint. Kept to a few
## triangles each: a big city has thousands.
func _street_metal(metal: Buf, rim: Buf, ri: int) -> void:
	var r: Dictionary = _roads[ri]
	if not r["drive"] or HIGHWAYS.has(r["k"]) or r["k"] == "service":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_city_name) + 77 + ri * 7919   # the road's own: every square works it out alike
	var y := Y_MARK + 0.004
	var pts: PackedVector2Array = r["pts"]
	var w: float = r["w"]
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var total := cum[cum.size() - 1]
	var clear: Array = []   # the junctions along it: (distance along, how far to keep off)
	var ids: PackedInt32Array = r["ids"]
	for i in range(ids.size()):
		if (_node_roads[ids[i]] as Array).size() >= 2:
			clear.append(Vector2(cum[i], _node_r[ids[i]] + 1.5))
	var span := _near_span(pts, cum, 20.0)
	var s := rng.randf_range(10.0, 40.0)
	while s < total - 4.0:
		if _clear_of(clear, s):
			var off := rng.randf_range(-0.25, 0.25)
			if s < span.x - 2.0 or s > span.y + 2.0:
				s += rng.randf_range(55.0, 95.0)
				continue
			var a := _along(pts, cum, s)
			var d := (_along(pts, cum, minf(s + 1.0, total)) - a).normalized()
			var at := a + Vector2(-d.y, d.x) * w * off
			_disc(rim, at, 0.36, y, 8)
			_disc(metal, at, 0.31, y + 0.002, 8)
			if _mine(at):
				_tally("manholes", 1)
		s += rng.randf_range(55.0, 95.0)
	if not _kerbed(r):
		return
	var sg := 1.0 if rng.randf() < 0.5 else -1.0
	s = rng.randf_range(6.0, 25.0)
	while s < total - 3.0:
		if _clear_of(clear, s) and s > span.x - 2.0 and s < span.y + 2.0:
			var a := _along(pts, cum, s)
			var d := (_along(pts, cum, minf(s + 1.0, total)) - a).normalized()
			var side := Vector2(-d.y, d.x) * sg
			var c := a + side * (w * 0.5 - 0.32)
			_flat_rect(rim, c, d, side, 0.9, 0.46, y)
			_flat_rect(metal, c, d, side, 0.78, 0.34, y + 0.002)
			if _mine(c):
				_tally("drains", 1)
		s += rng.randf_range(40.0, 65.0)
		sg = -sg

func _clear_of(clear: Array, s: float) -> bool:
	for c: Vector2 in clear:
		if absf(s - c.x) < c.y:
			return false
	return true

## a flat rectangle on the ground at c, `along` x `across` metres, along d
func _flat_rect(buf: Buf, c: Vector2, d: Vector2, side: Vector2, along: float, across: float, y: float) -> void:
	var a := d * along * 0.5
	var b := side * across * 0.5
	buf.quad3(_g3(c - a - b, y), _g3(c + a - b, y), _g3(c + a + b, y), _g3(c - a + b, y))

## dashed white lines: down the middle of a two-way street, between lanes of a one-way
## Paint along a road. Two-way: a centre line (white dashes in Givatayim; in Nova Scotia
## yellow -- a solid double line on main roads, dashed on side streets). One-way with
## lanes: white dashes between them. Main roads in the north also get solid white edge
## lines; so do motorways everywhere. No paint across junctions.
const MAIN_ROADS := {"motorway": true, "trunk": true, "primary": true, "secondary": true, "tertiary": true}

func _markings(buf: Buf, r: Dictionary, yellow: Buf) -> void:
	if not r["drive"] or r["k"] == "service":
		return
	var w: float = r["w"]
	var pts: PackedVector2Array = r["pts"]
	var north := String(_place.get("look", "")) == "north"
	var main: bool = MAIN_ROADS.has(r["k"])
	var lines: Array = []   # [offset, solid, yellow]
	if r["o"] == 0:
		if w >= 6.5 or north:
			if north and main:
				lines = [[-0.12, true, true], [0.12, true, true]]
			else:
				lines = [[0.0, false, north]]
	else:
		var lanes: int = r["l"]
		for i in range(1, lanes):
			lines.append([-w * 0.5 + w * i / lanes, false, false])
	if (north and main) or r["k"] in ["motorway", "trunk"]:
		for sg: float in [-1.0, 1.0]:
			lines.append([sg * (w * 0.5 - 0.35), true, false])
	if lines.is_empty():
		return
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var clear: Array = []
	var ids: PackedInt32Array = r["ids"]
	for i in range(ids.size()):
		if (_node_roads[ids[i]] as Array).size() >= 2:
			clear.append(Vector2(cum[i], _node_r[ids[i]] + 2.5))
	var total := cum[cum.size() - 1]
	var span := _near_span(pts, cum, 20.0)
	if span.x > span.y:
		return
	for ln: Array in lines:
		var off: float = ln[0]
		var solid: bool = ln[1]
		var target: Buf = yellow if ln[2] else buf
		var dash := 3.0
		var step := 3.0 if solid else 8.0
		var s := 1.5 + maxf(0.0, floorf((span.x - 1.5 - dash) / step)) * step
		while s + dash < minf(total, span.y + step + dash):
			var ok := true
			for c: Vector2 in clear:
				if absf(s + dash * 0.5 - c.x) < c.y + dash * 0.5:
					ok = false
					break
			if ok:
				var a := _along(pts, cum, s)
				var b := _along(pts, cum, s + dash + (0.05 if solid else 0.0))
				var d := (b - a).normalized()
				var side := Vector2(-d.y, d.x)
				var oa := a + side * off
				var ob := b + side * off
				var hw := 0.07 if not solid else 0.06
				target.quad3(_g3(oa - side * hw, Y_MARK), _g3(ob - side * hw, Y_MARK),
					_g3(ob + side * hw, Y_MARK), _g3(oa + side * hw, Y_MARK))
			s += step

func _along(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for i in range(1, pts.size()):
		if cum[i] >= s:
			var seg := cum[i] - cum[i - 1]
			return pts[i - 1].lerp(pts[i], (s - cum[i - 1]) / maxf(seg, 0.001))
	return pts[pts.size() - 1]

## a zebra crossing over every road through a crossing node
func _zebra(buf: Buf, ni: int) -> void:
	if ni < 0 or ni >= _nodes.size():
		return
	var c := _nodes[ni]
	for e: Vector2i in _node_roads[ni]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var a := pts[maxi(e.y - 1, 0)]
		var b := pts[mini(e.y + 1, pts.size() - 1)]
		var d := (b - a).normalized()
		var side := Vector2(-d.y, d.x)
		var hw: float = r["w"] * 0.5 - 0.4
		var o := -hw
		while o < hw:
			var p := c + side * (o + 0.25)
			var yz := Y_MARK + 0.002
			buf.quad3(_g3(p - d * 1.5 - side * 0.25, yz), _g3(p + d * 1.5 - side * 0.25, yz),
				_g3(p + d * 1.5 + side * 0.25, yz), _g3(p - d * 1.5 + side * 0.25, yz))
			o += 1.0
		return   # one road is enough; the others through this node are its continuation

## every building: walls with a window grid (one shader), flat roofs, merged per chunk
func _build_buildings() -> void:
	if _wall_mat == null:
		_wall_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = WALL_SHADER
		_wall_mat.shader = sh
		_wall_mat.set_shader_parameter("plaster_tex", _tex("painted_plaster_wall_diff"))
		_wall_mat.set_shader_parameter("plaster_nrm", _tex("painted_plaster_wall_nor"))
		_wall_mat.set_shader_parameter("plaster_mean", TEX_MEAN["painted_plaster_wall"])
		_wall_mat.set_shader_parameter("textured", 1.0 if _quality > 0 else 0.0)
		_roof_mat = ShaderMaterial.new()
		var rsh := Shader.new()
		rsh.code = ROOF_SHADER
		_roof_mat.shader = rsh
		_roof_mat.set_shader_parameter("grit", _tex("asphalt_02_diff"))
		_roof_mat.set_shader_parameter("grit_mean", TEX_MEAN["asphalt_02"])
		_roof_mat.set_shader_parameter("tone", _tone["roof"])
		_roof_mat.set_shader_parameter("textured", 1.0 if _quality > 0 else 0.0)
	var roof := _roof_mat
	var chunks := {}
	var north := String(_place.get("look", "")) == "north"
	var med := String(_place.get("look", "")) == "med"
	var gables := {"roof": CBuf.new(CHUNK), "end": CBuf.new(CHUNK)}
	var cores := CBuf.new(CHUNK)   # the walled-in middle of a block lifted on columns
	var all: Array = _city_data["buildings"]
	for bi: int in _tile_blds.get(_tile, []):
		if _over():
			await _pause()
		var bd: Dictionary = all[bi]
		var ring: PackedVector2Array = bd["_ring"]
		# on a slope: walls start below the lowest corner, the roof sits its height above
		# the average ground, and the window rows count from the lowest corner
		var g_lo := INF
		var g_sum := 0.0
		for p in ring:
			var gh := _h(p)
			g_lo = minf(g_lo, gh)
			g_sum += gh
		var g_avg := g_sum / ring.size()
		var raised: float = bd["_base"]
		var h: float = g_avg + float(bd["_h"])
		var base: float = g_lo + raised - (0.6 if raised == 0.0 and _hnx > 0 else 0.0)
		var key := _cell(_bld_box_of(ring).get_center(), CHUNK)
		if not chunks.has(key):
			chunks[key] = [Buf.new(), Buf.new()]
		var walls: Buf = chunks[key][0]
		var roofs: Buf = chunks[key][1]
		var hsh := _hash_i(ring[0])
		var bright := 0.84 + 0.18 * float(posmod(hsh, 7)) / 6.0
		# the plaster: mostly white, cream and stone; some pastel, yellow, peach or grey
		# (Bedford's clapboard comes in more colours)
		var pick := posmod(hsh >> 3, 100)
		var tk := 0
		if north:
			tk = 0 if pick < 34 else (1 if pick < 48 else (2 if pick < 62 else (3 if pick < 76 else 4)))
		else:
			tk = 0 if pick < 54 else (1 if pick < 62 else (2 if pick < 74 else (3 if pick < 84 else 4)))
		var tint := float(tk) / 4.0
		var stone := float(posmod(hsh >> 5, 5)) * 0.18   # 0 white .. 0.72 beige stone
		var rel := float(bd["_h"])
		var style: int = 3 if rel > 32.0 else (0 if rel < 10.0 else [0, 0, 0, 0, 1, 1, 1, 2, 0, 1][posmod(hsh >> 7, 10)])
		var col := Color(bright, tint, float(style) / 4.0 + 0.05, stone)
		var n := ring.size()
		var area := 0.0
		for i in range(n):
			area += ring[i].x * ring[(i + 1) % n].y - ring[(i + 1) % n].x * ring[i].y
		var sgn := 1.0 if area > 0.0 else -1.0
		# a pitched roof only on a house that stands on the ground: a raised "building" is a
		# canopy or a carport (OSM: a roof on stilts), and a house roof on it flew
		var gabled := north and rel < 10.0 and absf(area) * 0.5 < 450.0 and raised == 0.0
		# "komat amudim": many Givatayim blocks stand on columns, the ground floor open for
		# parking round a walled-in stairwell and lobby
		var pilotis := med and style <= 1 and rel >= 7.0 and rel <= 22.0 and raised == 0.0 \
			and absf(area) * 0.5 > 140.0 and posmod(hsh >> 11, 100) < 35 and not bd.has("shops")
		var wall_base := g_lo + 3.0 if pilotis else base
		# flat roofs have a low parapet round them; the facade's window grid still stops
		# at the roof itself (u2.y)
		var lip := 0.7 if not gabled and rel >= 5.0 and raised == 0.0 else 0.0
		var look := {"style": style, "rgb": _wall_rgb(bright, tint, stone), "g_lo": g_lo, "top": h,
			"sgn": sgn, "gabled": gabled, "pilotis": pilotis, "lip": lip}
		bd["_look"] = look
		_bld_kind[bi] = 1 if pilotis else (2 if gabled else 0)
		if pilotis:
			_lift_on_columns(ring, sgn, base, g_lo + 3.0, roofs, cores, look)
		elif raised >= 2.0:
			_stilts(ring, sgn, g_lo, base, roofs, look)
		for i in range(n):
			var a := ring[i]
			var b := ring[(i + 1) % n]
			var e := b - a
			var len := e.length()
			if len < 0.05:
				continue
			var out := Vector2(e.y, -e.x).normalized() * sgn
			var nrm := Vector3(out.x, 0.0, out.y)
			var a0 := Vector3(a.x, wall_base, a.y)
			var b0 := Vector3(b.x, wall_base, b.y)
			var a1 := Vector3(a.x, h + lip, a.y)
			var b1 := Vector3(b.x, h + lip, b.y)
			var u2 := Vector2(len, h - g_lo)
			var y0 := wall_base - g_lo
			var y1 := h + lip - g_lo
			walls.tri(a0, b0, b1, nrm, col, Vector2(0, y0), Vector2(len, y0), Vector2(len, y1), u2)
			walls.tri(a0, b1, a1, nrm, col, Vector2(0, y0), Vector2(len, y1), Vector2(0, y1), u2)
			if lip > 0.0:   # the parapet's inside, seen from the roof
				var ar := Vector3(a.x, h, a.y)
				var br := Vector3(b.x, h, b.y)
				walls.tri(ar, a1, b1, -nrm, col, Vector2(0, h - g_lo), Vector2(0, y1), Vector2(len, y1), u2)
				walls.tri(ar, b1, br, -nrm, col, Vector2(0, h - g_lo), Vector2(len, y1), Vector2(len, h - g_lo), u2)
		if gabled:
			_gable(gables, ring, h, hsh)
		var idx := Geometry2D.triangulate_polygon(ring)
		var rc := Color(bright * 0.95, bright * 0.95, bright * 0.95)
		for i in range(0, idx.size(), 3):
			var p0 := ring[idx[i]]
			var p1 := ring[idx[i + 1]]
			var p2 := ring[idx[i + 2]]
			roofs.tri(Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p2.x, h, p2.y), Vector3.UP, rc)
	for key: Vector2i in chunks:
		if _over():
			await _pause()
		var walls: Buf = chunks[key][0]
		var roofs: Buf = chunks[key][1]
		var am := ArrayMesh.new()
		if not walls.empty():
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, walls.arrays())
			am.surface_set_material(am.get_surface_count() - 1, _wall_mat)
		if not roofs.empty():
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, roofs.arrays())
			am.surface_set_material(am.get_surface_count() - 1, roof)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.visibility_range_end = VIEW_RANGE   # past this the haze has it anyway
		mi.visibility_range_end_margin = 80.0
		world.add_child(mi)
	_add_mesh(cores, _surface("lobby"), true, VIEW_RANGE * 0.5)
	if not (gables["roof"] as Buf).empty():
		if _shingles == null:
			_shingles = StandardMaterial3D.new()
			_shingles.vertex_color_use_as_albedo = true
			_shingles.roughness = 0.9
		_add_mesh(gables["roof"], _shingles, true, VIEW_RANGE)
		_add_mesh(gables["end"], _surface("gable"), true, VIEW_RANGE)

func _area(poly: PackedVector2Array) -> float:
	return absf(_area_signed(poly))

func _area_signed(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		a += poly[i].x * poly[(i + 1) % poly.size()].y - poly[(i + 1) % poly.size()].x * poly[i].y
	return a * 0.5

var _chimneys: Array = []
var _area_rings := {}                ## "park" / "grass" / "wood" / "pitch" -> outlines, while building
var _landmarks: Array = []           ## [where, "playground" | "pitch"]

## ---- what makes a block look lived in ---------------------------------------------------------
## Givatayim: stacks of balconies on the street side, an AC unit or two on the walls, a
## canopy over the entrance with the blue house-number plate beside it, the columns of the
## blocks that stand on them. Bedford: a porch on the street side of a house, a chimney.
## All of it instanced, in the building's own wall colour.
func _build_facade_kit() -> void:
	var med := String(_place.get("look", "")) == "med"
	var north := String(_place.get("look", "")) == "north"
	var kit := {"balcony": [], "column": [], "canopy": [], "porch": [], "post": []}
	var kit_col := {"balcony": [], "column": [], "canopy": [], "porch": [], "post": []}
	var encl: Array = [[], []]   # balconies closed in, shutters a little or a lot down
	var acs: Array = []
	var plates: Array = []
	var all: Array = _city_data["buildings"]
	for bi: int in _tile_blds.get(_tile, []):
		if _over():
			await _pause()
		var bd: Dictionary = all[bi]
		if not bd.has("_look"):
			continue
		var look: Dictionary = bd["_look"]
		var wc: Color = look["rgb"]
		for t: Transform3D in look.get("cols", []):
			kit["column"].append(t)
			kit_col["column"].append(wc)
		var rel: float = bd["_h"]
		if rel < 3.0 or float(bd["_base"]) > 0.0:
			continue
		var ring: PackedVector2Array = bd["_ring"]
		var hsh := _hash_i(ring[0])
		var g_lo: float = look["g_lo"]
		var street := _street_edge(ring, float(look["sgn"]))
		var bname := String(bd.get("name", ""))
		if bname != "" and (_area(ring) >= 300.0 or rel >= 20.0):
			var face_edge := street if not street.is_empty() else _longest_edge(ring, float(look["sgn"]))
			var mall := _is_mall(bname)
			_name_on(bname, face_edge, float(look["top"]), g_lo, mall)
			if mall and not street.is_empty():
				_mall_front(face_edge, g_lo, wc, kit, kit_col)
				continue
		var style: int = look["style"]
		if med and rel <= 32.0:
			var floors := int((rel + 0.3) / 3.0)
			# balconies: one or two stacks up the street side
			if not street.is_empty() and style != 1 and floors >= 2:
				var a: Vector2 = street[0]
				var b: Vector2 = street[1]
				var out: Vector2 = street[2]
				var L := a.distance_to(b)
				var n := maxi(1, int(L / 3.3))
				var cw := L / n
				if L >= 7.0:
					var stacks := 1 if n < 4 else 2
					var face := Basis(Vector3.UP, atan2(out.x, out.y))
					for sk in range(stacks):
						var ci := posmod(hsh >> (3 + sk * 4), n)
						if n >= 3:
							ci = 1 + posmod(hsh >> (3 + sk * 4), n - 2)
						if sk == 1 and ci == posmod(hsh >> 3, n):
							ci = (ci + 2) % n
						var at := a + (b - a) / L * ((ci + 0.5) * cw)
						for lv in range(1, floors):
							var p := at + out * 0.62
							kit["balcony"].append(Transform3D(face, Vector3(p.x, g_lo + lv * 3.0, p.y)))
							kit_col["balcony"].append(wc)
							# a third of them closed in, the Israeli way: glass above the parapet
							# and a roller shutter part-way down
							if med and posmod(hsh >> (sk * 7 + lv * 3 + 2), 100) < 34:
								(encl[posmod(hsh >> (lv + 1), 2)] as Array).append(Transform3D(face, Vector3(p.x, g_lo + lv * 3.0, p.y)))
							# now and then a flag hung over the parapet
							if posmod(hsh >> (sk * 5 + lv), 29) == 0 and String(_place.get("look", "")) == "med":
								_balcony_flags.append(Transform3D(face, Vector3(p.x, g_lo + lv * 3.0 + 1.02, p.y) + face * Vector3(0, 0, 0.67)))
					if _bld_kind[bi] == 0:
						_bld_kind[bi] = 3
			# AC units: a couple on the walls, beside a window, any side
			var placed := 0
			for i in range(ring.size()):
				if placed >= 3 or floors < 1:
					break
				var a := ring[i]
				var b := ring[(i + 1) % ring.size()]
				var L := a.distance_to(b)
				if L < 4.0 or posmod((hsh >> (i % 8)) + i, 3) != 0:
					continue
				var e := (b - a) / L
				var out := Vector2(e.y, -e.x) * float(look["sgn"])
				var n := maxi(1, int(L / 3.3))
				var ci := posmod(hsh + i * 7, n)
				var lv := posmod(hsh + i * 3, maxi(floors, 1))
				var p := a + e * ((ci + 0.86) * L / n) + out * 0.2
				acs.append(Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), Vector3(p.x, g_lo + lv * 3.0 + 0.75, p.y)))
				placed += 1
			# the entrance: a canopy over the door, the lit blue number plate beside it
			if not street.is_empty() and not look["pilotis"]:
				var a: Vector2 = street[0]
				var b: Vector2 = street[1]
				var out: Vector2 = street[2]
				var mid := (a + b) * 0.5
				var e := (b - a).normalized()
				var face := Basis(Vector3.UP, atan2(out.x, out.y))
				var cp := mid + out * 0.55
				kit["canopy"].append(Transform3D(face, Vector3(cp.x, g_lo + 2.75, cp.y)))
				kit_col["canopy"].append(wc * 0.92)
				var pp := mid + e * 1.7 + out * 0.03
				plates.append(Transform3D(face, Vector3(pp.x, g_lo + 2.2, pp.y)))
		elif north and look["gabled"] and not street.is_empty():
			# a porch: a little roof on two posts in front of the door
			var a: Vector2 = street[0]
			var b: Vector2 = street[1]
			var out: Vector2 = street[2]
			if a.distance_to(b) >= 6.0 and posmod(hsh >> 6, 10) < 7:
				var mid := (a + b) * 0.5 + (b - a).normalized() * float(posmod(hsh, 3) - 1) * 1.5
				var e := (b - a).normalized()
				var face := Basis(Vector3.UP, atan2(out.x, out.y))
				var rp := mid + out * 0.95
				kit["porch"].append(Transform3D(face, Vector3(rp.x, g_lo + 2.6, rp.y)))
				kit_col["porch"].append(wc)
				for sd: float in [-1.4, 1.4]:
					var q := mid + e * sd + out * 1.7
					kit["post"].append(Transform3D(Basis(), Vector3(q.x, g_lo + 1.3, q.y)))
					kit_col["post"].append(wc)
	var tinted := _vc_mat()
	var meshes := {"balcony": _cached("balcony", _balcony_mesh), "column": _boxm(Vector3.ONE), "canopy": _boxm(Vector3(2.4, 0.14, 1.1)),
		"porch": _boxm(Vector3(3.4, 0.14, 1.9)), "post": _boxm(Vector3(0.14, 2.6, 0.14))}
	var ranges := {"balcony": 230.0, "column": 260.0, "canopy": 150.0, "porch": 220.0, "post": 160.0}
	for k: String in kit:
		if not (kit[k] as Array).is_empty():
			await _chunked_paced(meshes[k], kit[k], ranges[k], kit_col[k], tinted, k != "post")
	for v in range(2):
		if not (encl[v] as Array).is_empty():
			_chunked(_cached("enclosure%d" % v, _enclosure_mesh.bind(v)), encl[v], 230.0, [], tinted)
	_tally("closed_balconies", (encl[0] as Array).size() + (encl[1] as Array).size())
	if not _mall_glass.is_empty():
		_chunked(_boxm(Vector3.ONE), _mall_glass, 400.0, [], _shop_glass())
	if not _lobby_doors.is_empty():
		_chunked(_boxm(Vector3(1.9, 2.4, 0.05)), _lobby_doors, 160.0, [], _shop_glass())
	if not acs.is_empty():
		var ac := _boxm(Vector3(0.82, 0.55, 0.32))
		ac.material = _surface("tank")
		_chunked(ac, acs, 140.0)
	if not plates.is_empty():
		var pl := _boxm(Vector3(0.36, 0.24, 0.04))
		pl.material = mat("player", 0.6)
		_chunked(pl, plates, 110.0)
	if not _chimneys.is_empty():
		var ch := _boxm(Vector3(0.7, 2.2, 0.7))
		ch.material = _surface("brick")
		_chunked(ch, _chimneys, 450.0, [], null, true)
	_tally("balconies", (kit["balcony"] as Array).size())
	_tally("columns", (kit["column"] as Array).size())
	_tally("porches", (kit["porch"] as Array).size())
	_tally("chimneys", _chimneys.size())

## the building's name in big letters along the top of its street side: malls, towers,
## the cinema, schools -- the places people give directions by
var _names: Array = []

func _name_on(text: String, edge: Array, top: float, g_lo: float, mall: bool) -> void:
	if edge.is_empty():
		return
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var out: Vector2 = edge[2]
	var L := a.distance_to(b)
	var lb := Label3D.new()
	lb.text = text
	lb.font = _font
	lb.font_size = 96
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x
	lb.pixel_size = clampf(L * 0.75 / maxf(w, 1.0), 0.008, 0.035)
	lb.outline_size = 12
	var role := "accent" if mall else "ink"
	lb.modulate = Palette.col(role)
	lb.outline_modulate = Palette.col("bg")
	lb.set_meta("role", role)
	var mid := (a + b) * 0.5 + out * 0.25
	var y := (g_lo + 5.9) if mall else maxf(top - 1.6, g_lo + 3.0)
	lb.position = Vector3(mid.x, y, mid.y)
	lb.rotation.y = atan2(out.x, out.y)
	lb.double_sided = false
	lb.visibility_range_end = 520.0
	world.add_child(lb)
	_names.append(lb)

func _is_mall(name: String) -> bool:
	var n := name.to_lower()
	return n.contains("mall") or n.contains("קניון") or n.contains(" מול") or n.begins_with("מול ") \
		or n.contains("plaza") or n.contains("centre") and n.contains("shopping")

## a mall's street side: glass shopfronts all along the ground floor, and a big canopy on
## columns over the way in
func _mall_front(edge: Array, g_lo: float, wc: Color, kit: Dictionary, kit_col: Dictionary) -> void:
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var out: Vector2 = edge[2]
	var L := a.distance_to(b)
	var e := (b - a) / L
	var face := Basis(Vector3.UP, atan2(out.x, out.y))
	var mid := (a + b) * 0.5
	var glass := mid + out * 0.08
	_mall_glass.append(Transform3D(face * Basis.from_scale(Vector3(maxf(L - 1.0, 2.0), 3.4, 0.1)),
		Vector3(glass.x, g_lo + 1.8, glass.y)))
	var cp := mid + out * 1.8
	kit["canopy"].append(Transform3D(face * Basis.from_scale(Vector3(minf(12.0, L * 0.5) / 2.4, 2.4, 3.3)), Vector3(cp.x, g_lo + 4.0, cp.y)))
	kit_col["canopy"].append(wc * 0.9)
	for sd: float in [-1.0, 1.0]:
		var q := mid + e * sd * minf(5.0, L * 0.2) + out * 3.2
		kit["column"].append(Transform3D(Basis.from_scale(Vector3(0.45, 4.0, 0.45)), Vector3(q.x, g_lo + 2.0, q.y)))
		kit_col["column"].append(wc)
		_add_post(q, 0.25)

var _mall_glass: Array = []
var _lobby_doors: Array = []         ## the glass doors of the lobbies under blocks on columns (this square's)

func _longest_edge(ring: PackedVector2Array, sgn: float) -> Array:
	var best := 0.0
	var pick: Array = []
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if a.distance_to(b) > best:
			best = a.distance_to(b)
			pick = [a, b, Vector2(b.y - a.y, a.x - b.x).normalized() * sgn]
	return pick

## a balcony closed in, over the parapet of _balcony_mesh: a band of glass in white frames
## up to the slab above, and a roller shutter down over it -- `v` 0 a little, 1 most of the
## way. Its colours are its own (vertex colours), not the wall's.
func _enclosure_mesh(v: int) -> ArrayMesh:
	var b := Buf.new()
	var glass: Color = _tone["glass"].darkened(0.15)
	var shutter: Color = _tone["shutter"]
	var frame: Color = _tone["mark"]
	var lo := 1.0
	var hi := 2.82
	var drop := 0.28 if v == 0 else 0.72
	var cut := hi - (hi - lo) * drop   # where the shutter's bottom edge is
	var panel := func(a: Vector3, e: Vector3, y0: float, y1: float, n: Vector3, col: Color) -> void:
		b.tri(Vector3(a.x, y0, a.z), Vector3(e.x, y0, e.z), Vector3(e.x, y1, e.z), n, col)
		b.tri(Vector3(a.x, y0, a.z), Vector3(e.x, y1, e.z), Vector3(a.x, y1, a.z), n, col)
	# the front and the two sides
	var faces := [[Vector3(-1.35, 0, 0.62), Vector3(1.35, 0, 0.62), Vector3.BACK],
		[Vector3(-1.35, 0, -0.62), Vector3(-1.35, 0, 0.62), Vector3.LEFT],
		[Vector3(1.35, 0, 0.62), Vector3(1.35, 0, -0.62), Vector3.RIGHT]]
	for f: Array in faces:
		panel.call(f[0], f[1], lo, cut, f[2], glass)
		panel.call(f[0], f[1], cut, hi, f[2], shutter)
		panel.call(f[0] + (f[2] as Vector3) * 0.01, f[1] + (f[2] as Vector3) * 0.01, cut - 0.05, cut, f[2], frame)
		panel.call(f[0] + (f[2] as Vector3) * 0.01, f[1] + (f[2] as Vector3) * 0.01, lo, lo + 0.05, f[2], frame)
	# the window mullions on the front
	for x: float in [-0.45, 0.45]:
		b.tri(Vector3(x - 0.03, lo, 0.635), Vector3(x + 0.03, lo, 0.635), Vector3(x + 0.03, cut, 0.635), Vector3.BACK, frame)
		b.tri(Vector3(x - 0.03, lo, 0.635), Vector3(x + 0.03, cut, 0.635), Vector3(x - 0.03, cut, 0.635), Vector3.BACK, frame)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	return am

## a balcony, local +Z out of the wall: a slab and a solid parapet round its three sides
func _balcony_mesh() -> ArrayMesh:
	var b := Buf.new()
	_box(b, Vector3(0, -0.09, 0), Vector3(2.7, 0.18, 1.24))
	_box(b, Vector3(0, 0.5, 0.58), Vector3(2.7, 1.0, 0.08))
	for sx: float in [-1.0, 1.0]:
		_box(b, Vector3(sx * 1.31, 0.5, 0), Vector3(0.08, 1.0, 1.24))
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	return am

## the side of a building facing its street: the longest edge whose outside looks toward
## the nearest road, as [a, b, out], or [] when no road is near
func _street_edge(ring: PackedVector2Array, sgn: float) -> Array:
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	var hit := _nearest_seg(c, 22.0, true, true)
	if hit.is_empty():
		return []
	var to: Vector2 = ((hit["q"] as Vector2) - c).normalized()
	var best := -INF
	var pick: Array = []
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var e := b - a
		var L := e.length()
		if L < 3.0:
			continue
		var out := Vector2(e.y, -e.x).normalized() * sgn
		var facing := out.dot(to)
		if facing > 0.5 and facing * minf(L, 14.0) > best:
			best = facing * minf(L, 14.0)
			pick = [a, b, out]
	return pick

## the colour the facade shader gives a building's walls, for things stuck on them
func _wall_rgb(bright: float, tint: float, stone: float) -> Color:
	var tk := int(round(tint * 4.0))
	var plaster: Color = _tone[["wall", "wall2", "wall4", "wall5", "wall6"][clampi(tk, 0, 4)]]
	var c := plaster.lerp(_tone["wall3"], stone * (1.0 if tk == 0 else 0.3))
	return Color(c.r * bright, c.g * bright, c.b * bright)

## a block on columns: the floors above start at `lift`; under them, a walled-in core set
## back from the edge (stairs, lobby, storage), the ceiling of the open floor, and a column
## at every corner and every few metres along the edges
func _lift_on_columns(ring: PackedVector2Array, sgn: float, base: float, lift: float, roofs: Buf,
		cores: Buf, look: Dictionary) -> void:
	var cols: Array = []
	var ceil_c := Color(0.86, 0.86, 0.84)   # (light plaster: dark, it read as a hole)
	var idx := Geometry2D.triangulate_polygon(ring)
	for i in range(0, idx.size(), 3):
		var p0 := ring[idx[i]]
		var p1 := ring[idx[i + 1]]
		var p2 := ring[idx[i + 2]]
		roofs.tri(Vector3(p0.x, lift, p0.y), Vector3(p1.x, lift, p1.y), Vector3(p2.x, lift, p2.y), Vector3.DOWN, ceil_c)
	# set back 2.2 m: whichever way round the outline runs, the smaller of the two offsets
	var inner: Array = Geometry2D.offset_polygon(ring, -2.2)
	var other: Array = Geometry2D.offset_polygon(ring, 2.2)
	if not inner.is_empty() and not other.is_empty() and _area(other[0]) < _area(inner[0]):
		inner = other
	if not inner.is_empty() and _area(inner[0]) < _area(ring) * 0.95:
		var core: PackedVector2Array = inner[0]
		var ca := 0.0
		for i in range(core.size()):
			ca += core[i].x * core[(i + 1) % core.size()].y - core[(i + 1) % core.size()].x * core[i].y
		var cs := 1.0 if ca > 0.0 else -1.0
		# the lobby's glass door, lit, on the side of the core that faces the street
		var street := _street_edge(ring, sgn)
		var to: Vector2 = street[2] if not street.is_empty() else Vector2.ZERO
		var door: Array = []
		var best := 0.3
		for i in range(core.size()):
			var a := core[i]
			var b := core[(i + 1) % core.size()]
			var e := b - a
			if e.length() < 0.05:
				continue
			var out := Vector2(e.y, -e.x).normalized() * cs
			var nrm := Vector3(out.x, 0.0, out.y)
			cores.tri(Vector3(a.x, base, a.y), Vector3(b.x, base, b.y), Vector3(b.x, lift, b.y), nrm, Color.WHITE)
			cores.tri(Vector3(a.x, base, a.y), Vector3(b.x, lift, b.y), Vector3(a.x, lift, a.y), nrm, Color.WHITE)
			if e.length() >= 2.4 and out.dot(to) > best:
				best = out.dot(to)
				door = [(a + b) * 0.5 + out * 0.04, out]
		if not door.is_empty():
			var dp: Vector2 = door[0]
			var dout: Vector2 = door[1]
			_lobby_doors.append(Transform3D(Basis(Vector3.UP, atan2(dout.x, dout.y)), Vector3(dp.x, base + 1.2, dp.y)))
	var hgt := lift - base
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var e := b - a
		var L := e.length()
		if L < 0.5:
			continue
		var d := e / L
		var inward := -Vector2(e.y, -e.x).normalized() * sgn
		var steps := maxi(1, int(L / 4.5))
		for k in range(steps):
			var q := a + d * (L * float(k) / steps) + inward * 0.28 + (d * 0.28 if k == 0 else Vector2.ZERO)
			cols.append(Transform3D(Basis.from_scale(Vector3(0.4, hgt, 0.4)), Vector3(q.x, base + hgt * 0.5, q.y)))
	look["cols"] = cols

## a raised roof (a canopy, a carport, a covered walkway): what holds it up -- a column at
## each corner and every 6 m along the edges, solid to the car -- and its underside
func _stilts(ring: PackedVector2Array, sgn: float, ground: float, under: float, roofs: Buf, look: Dictionary) -> void:
	var cols: Array = []
	var hgt := under - ground
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var L := a.distance_to(b)
		if L < 0.5:
			continue
		var d := (b - a) / L
		var inward := -Vector2(b.y - a.y, a.x - b.x).normalized() * sgn
		var steps := maxi(1, int(L / 6.0))
		for k in range(steps):
			var q := a + d * (L * float(k) / steps) + inward * 0.3 + (d * 0.3 if k == 0 else Vector2.ZERO)
			cols.append(Transform3D(Basis.from_scale(Vector3(0.35, hgt, 0.35)), Vector3(q.x, ground + hgt * 0.5, q.y)))
			_add_post(q, 0.25)
	var idx := Geometry2D.triangulate_polygon(ring)
	var c := Color(0.6, 0.6, 0.6)
	for i in range(0, idx.size(), 3):
		var p0 := ring[idx[i]]
		var p1 := ring[idx[i + 1]]
		var p2 := ring[idx[i + 2]]
		roofs.tri(Vector3(p0.x, under, p0.y), Vector3(p1.x, under, p1.y), Vector3(p2.x, under, p2.y), Vector3.DOWN, c)
	look["cols"] = cols

## a pitched roof over a house: the footprint's tightest rectangle, the ridge along its
## long side, eaves a little past the walls, shingles grey or red-brown
func _gable(g: Dictionary, ring: PackedVector2Array, top: float, hsh: int) -> void:
	var best := INF
	var u := Vector2.RIGHT
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for i in range(ring.size()):
		var e := (ring[(i + 1) % ring.size()] - ring[i]).normalized()
		if e == Vector2.ZERO:
			continue
		var v := Vector2(-e.y, e.x)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in ring:
			var q := Vector2(p.dot(e), p.dot(v))
			mn = mn.min(q)
			mx = mx.max(q)
		var area := (mx.x - mn.x) * (mx.y - mn.y)
		if area < best:
			best = area
			u = e
			lo = mn
			hi = mx
	var v := Vector2(-u.y, u.x)
	if hi.y - lo.y > hi.x - lo.x:   # the ridge runs along the long side
		var t := u
		u = v
		v = -t
		var l2 := Vector2(-hi.y, lo.x)
		var h2 := Vector2(-lo.y, hi.x)
		lo = l2
		hi = h2
	lo -= Vector2(0.35, 0.35)
	hi += Vector2(0.35, 0.35)
	var rise := (hi.y - lo.y) * 0.32
	var cy := (lo.y + hi.y) * 0.5
	var P := func(a: float, b: float, y: float) -> Vector3:
		var q := u * a + v * b
		return Vector3(q.x, y, q.y)
	var shades := [Palette.col("bg").lerp(Palette.col("bg_alt"), 0.6), Palette.col("hazard").lerp(Palette.col("bg"), 0.55),
		Palette.col("warn").lerp(Palette.col("bg"), 0.62), Palette.col("bg_alt").lerp(Palette.col("ink"), 0.25)]
	var col: Color = shades[posmod(hsh >> 9, shades.size())]
	var r0: Vector3 = P.call(lo.x, cy, top + rise)
	var r1: Vector3 = P.call(hi.x, cy, top + rise)
	for side: Array in [[lo.y, 1.0], [hi.y, -1.0]]:
		var e0: Vector3 = P.call(lo.x, side[0], top - 0.15)
		var e1: Vector3 = P.call(hi.x, side[0], top - 0.15)
		var nrm := (e1 - e0).cross(r0 - e0).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		(g["roof"] as Buf).tri(e0, e1, r1, nrm, col)
		(g["roof"] as Buf).tri(e0, r1, r0, nrm, col)
	for end: Array in [[lo.x + 0.35, -1.0], [hi.x - 0.35, 1.0]]:
		var a: Vector3 = P.call(end[0], lo.y + 0.35, top)
		var b: Vector3 = P.call(end[0], hi.y - 0.35, top)
		var c: Vector3 = P.call(end[0], cy, top + rise - 0.1)
		var out := Vector3(u.x, 0, u.y) * float(end[1])
		(g["end"] as Buf).tri(a, b, c, out, Color.WHITE)
	if posmod(hsh >> 13, 10) < 6:   # a chimney up one end, through the slope
		var at: Vector3 = P.call(lo.x + 1.3, cy + (hi.y - lo.y) * 0.18, top + rise * 0.72)
		_chimneys.append(Transform3D(Basis(Vector3.UP, atan2(u.x, u.y)), at))

func _bld_box_of(ring: PackedVector2Array) -> Rect2:
	var box := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		box = box.expand(p)
	return box

## trees: the ones OSM knows, plus a row along each pavement of a residential street
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	var spots: Array = []   ## [x, z, scale]
	var forest := {}        # index into spots -> true
	var grates: Array = []  # an iron grate round each street tree's trunk, flat on the pavement
	var k := 1.0 / float(_city_data.get("scale", 10))
	var tr: Array = _city_data.get("trees", [])
	for i: int in _tile_trees.get(_tile, []):
		var p := Vector2(tr[i], tr[i + 1]) * k
		if _tree_ok(p, 2.0):
			_add_post(p, 0.3)
			rng.seed = _hash_i(p)
			spots.append(Vector3(p.x, p.y, rng.randf_range(0.85, 1.3)))
	# a row along each pavement of a residential street (the road's own random numbers, so
	# every square it crosses plants it alike, each its own stretch)
	for ri: int in _tile_roads.get(_tile, []):
		var r: Dictionary = _roads[ri]
		if not TREE_ROADS.has(r["k"]) or _trees_made + spots.size() >= MAX_TREES:
			continue
		if _over():
			await _pause()
		rng.seed = hash(_city_name) + ri * 7919
		var pts: PackedVector2Array = r["pts"]
		var ids: PackedInt32Array = r["ids"]
		var off: float = r["w"] * 0.5 + 1.3
		var s := rng.randf() * TREE_GAP
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			var d := (b - a) / maxf(L, 0.001)
			var side := Vector2(-d.y, d.x)
			# real streets keep the corners clear (sight lines); so do we
			var keep_a := _node_r[ids[j]] + 9.0 if (_node_roads[ids[j]] as Array).size() >= 2 else 0.0
			var keep_b := _node_r[ids[j + 1]] + 9.0 if (_node_roads[ids[j + 1]] as Array).size() >= 2 else 0.0
			while s < L:
				if s < keep_a or s > L - keep_b:
					s += TREE_GAP
					continue
				for sgn: float in [-1.0, 1.0]:
					if rng.randf() < 0.22:
						continue
					var p := a + d * s + side * off * sgn
					var sc := rng.randf_range(0.8, 1.25)
					if _mine(p) and _tree_ok(p, 5.0):
						_add_post(p, 0.3)
						spots.append(Vector3(p.x, p.y, sc))
						grates.append(Transform3D(Basis(Vector3.UP, sc * 9.0), Vector3(p.x, _h(p) + KERB_H + 0.006, p.y)))
				s += TREE_GAP + rng.randf_range(-2.5, 2.5)
			s -= L
	# parks get trees where OSM has few; woods are filled (conifers in the north): each
	# square plants its share of an outline, in its own part of it
	var sq := _tile_rect(_tile)
	for kind: String in ["park", "grass", "wood"]:
		for ring: PackedVector2Array in _rings_near(kind):
			var area := _area(ring)
			if area < 500.0 or _trees_made + spots.size() >= MAX_TREES + MAX_FOREST:
				continue
			var box := _bld_box_of(ring)
			var part := box.intersection(sq)
			if part.get_area() <= 0.0:
				continue
			var per := 70.0 if kind == "wood" else 160.0
			var want := roundi(mini(int(area / per), 2500) * part.get_area() / maxf(box.get_area(), 1.0))
			rng.seed = _hash_i(ring[0]) + _tile.x * 92821 + _tile.y * 68917
			for _i in range(want * 2):
				if want <= 0 or _trees_made + spots.size() >= MAX_TREES + MAX_FOREST:
					break
				if _over():
					await _pause()
				var p := Vector2(rng.randf_range(part.position.x, part.end.x), rng.randf_range(part.position.y, part.end.y))
				var sc := rng.randf_range(0.8, 1.35)
				if not _mine(p) or not Geometry2D.is_point_in_polygon(p, ring) or not _tree_ok(p, 4.5 if kind == "wood" else 7.0):
					continue
				_add_post(p, 0.3)
				if kind == "wood":
					forest[spots.size()] = true
				spots.append(Vector3(p.x, p.y, sc))
				want -= 1
	# open land: copses and lone trees where the ground is green, and shrubs, clumped by the
	# same kind of noise as the ground's colour. Kept off water, car parks and plazas, and
	# well off the roads; thinned evenly to the city's cap (_trees_setup)
	var north := String(_place.get("look", "")) == "north"
	var wild_cap := 15000 if north else 1800
	var step := 22.0 if north else 16.0
	var thresh := 0.56 if north else 0.7
	var nx := int(_bounds.size.x / step)
	var nz := int(_bounds.size.y / step)
	var gx0 := maxi(0, ceili((sq.position.x - _bounds.position.x) / step - 0.5))
	var gx1 := mini(nx - 1, floori((sq.end.x - _bounds.position.x) / step - 0.5))
	var gz0 := maxi(0, ceili((sq.position.y - _bounds.position.y) / step - 0.5))
	var gz1 := mini(nz - 1, floori((sq.end.y - _bounds.position.y) / step - 0.5))
	var wild := 0
	for gz in range(gz0, gz1 + 1):
		if _over():
			await _pause()
		for gx in range(gx0, gx1 + 1):
			var c := _bounds.position + Vector2(gx + 0.5, gz + 0.5) * step
			if not _mine(c) or _wild_made >= wild_cap:
				continue
			if _vnoise(c / 70.0) * 0.65 + _vnoise(c / 15.0) * 0.35 < thresh:
				continue
			rng.seed = gx * 73856093 + gz * 19349663
			if rng.randf() > _wild_keep:
				continue
			var p := c + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * step
			var blocked := false
			for ri: int in _near(_no_grow, p, 1.0, 60.0):
				if Geometry2D.is_point_in_polygon(p, _no_rings[ri]):
					blocked = true
					break
			if blocked or not _off_road(p, 5.0) or not _tree_ok(p, 6.0):
				continue
			_add_post(p, 0.3)
			forest[spots.size()] = true
			spots.append(Vector3(p.x, p.y, rng.randf_range(0.7, 1.25)))
			wild += 1
			_wild_made += 1
	_tally("wild_trees", wild)
	_trees_made += spots.size()
	if not grates.is_empty():
		_chunked(_furn.grate_kit(), grates, 120.0)
		_tally("tree_grates", grates.size())
	if spots.is_empty():
		return
	var look := String(_place.get("look", ""))
	var parts := {"trunk": [], "crown": [], "ptrunk": [], "fronds": [], "ftrunk": [], "cone": []}
	var colours := {"trunk": [], "crown": [], "ptrunk": [], "fronds": [], "ftrunk": [], "cone": []}
	var put := func(part: String, xf: Transform3D, col: Color) -> void:
		(parts[part] as Array).append(xf)
		(colours[part] as Array).append(col)
	for si in range(spots.size()):
		var sp: Vector3 = spots[si]
		var sc := sp.z
		var base := Vector3(sp.x, _h(Vector2(sp.x, sp.y)), sp.y)
		rng.seed = _hash_i(Vector2(sp.x, sp.y)) + 101   # the tree's own look, wherever it was planted from
		var spin := Basis(Vector3.UP, rng.randf() * TAU)
		var g := rng.randf_range(0.85, 1.1)
		var kind := _tree_kind(look, forest.has(si), rng.randf())
		var spec: Array = TREE_KINDS[kind]
		# [trunk part, trunk scale (w, h), crown part, crown scale (w, h, w), crown height,
		#  leaf tint, lean (radians)]
		var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf() * float(spec[6]))
		var b := lean * spin
		var tw: Vector2 = spec[1]
		var cw: Vector3 = spec[3]
		var tint: Color = spec[5]
		var jitter := Vector3(rng.randf_range(0.85, 1.15), rng.randf_range(0.85, 1.15), rng.randf_range(0.85, 1.15))
		var tpart: String = spec[0]
		var trunk_h := 2.6 if tpart != "ptrunk" else 7.0
		var bark := Color(1.9, 1.9, 1.8) if kind == "birch" else (Color(1.6, 1.55, 1.45) if kind == "eucalyptus" else Color(1, 1, 1))
		# the leaves (the atlas cell rides in the colour's alpha); some of the round street
		# trees are feathery, like the melias and jacarandas that line Israeli streets
		var cell: int = LEAF_CELL.get(kind, 0)
		if kind == "round" and rng.randf() < 0.3:
			cell = 2
		put.call(tpart, Transform3D(b * Basis.from_scale(Vector3(tw.x, tw.y, tw.x) * sc), base + b * Vector3(0, trunk_h * 0.5 * tw.y * sc, 0)), bark)
		put.call(spec[2], Transform3D(b * Basis.from_scale(cw * jitter * sc), base + b * Vector3(0, float(spec[4]) * sc, 0)),
			Color(tint.r * g, tint.g * g, tint.b * g, (float(cell) + 0.5) / 4.0))
	for part: String in parts:
		await _chunked_paced(_tree_meshes[part], parts[part], TREE_RANGE, colours[part], null, true)

var _tree_meshes := {}
var _trees_made := 0
var _wild_made := 0
var _wild_keep := 1.0                ## the share of open land's green spots that get a tree
var _no_grow := {}
var _no_rings: Array = []

## What every square's trees share: the meshes, where nothing grows, and how thinly open
## land is planted -- counted over the whole map first (on every third row and column: an
## estimate is enough), then each green spot kept with the same chance, so the city's cap
## thins them evenly (stopping at the cap left the far side of the map bare).
func _trees_setup() -> void:
	var north := String(_place.get("look", "")) == "north"
	for kind: String in ["water", "parking", "plaza", "pitch"]:
		for ring: PackedVector2Array in _area_rings.get(kind, []):
			_hash_add(_no_grow, _bld_box_of(ring), 60.0, _no_rings.size())
			_no_rings.append(ring)
	var step := 22.0 if north else 16.0
	var thresh := 0.56 if north else 0.7
	var wild_cap := 15000 if north else 1800
	var nx := int(_bounds.size.x / step)
	var nz := int(_bounds.size.y / step)
	var green := 0
	for gz in range(0, nz, 3):
		for gx in range(0, nx, 3):
			var c := _bounds.position + Vector2(gx + 0.5, gz + 0.5) * step
			if _vnoise(c / 70.0) * 0.65 + _vnoise(c / 15.0) * 0.35 >= thresh:
				green += 9
	_wild_keep = minf(1.0, float(wild_cap) * 1.4 / maxf(green, 1.0))
	var leaf := _surface("leaf")   # (the hedges and bushes still use it plain)
	leaf.vertex_color_use_as_albedo = true
	_surface("trunk").vertex_color_use_as_albedo = true
	var mats := _make_tree_mats()
	var palm_trunk := CylinderMesh.new()
	palm_trunk.top_radius = 0.15
	palm_trunk.bottom_radius = 0.24
	palm_trunk.height = 7.0
	palm_trunk.radial_segments = 8
	palm_trunk.rings = 1
	palm_trunk.material = mats[3]
	_tree_meshes = {"trunk": _trunk_mesh(3, mats[2]), "crown": _card_crown(CROWN_LUMPS, 28, mats[0]), "ptrunk": palm_trunk,
		"fronds": _frond_mesh(mats[4]), "ftrunk": _trunk_mesh(0, mats[2]), "cone": _card_cone(70, mats[1])}

## Trees by kind, after what the streets really have. Givatayim: big dark ficus, light
## feathery acacias and jacarandas, round street trees, olives, a few cypresses and Aleppo
## pines, date palms and tall thin fan palms, and tall pale eucalyptus (the roadsides' and
## parks' tree). Bedford: maples, oaks, birches, spruce.
## [trunk part, trunk (width, height) scale, crown part, crown (w, h, w) scale, crown
## height, leaf tint, most lean]. All from four meshes, so variety costs no draw calls.
const TREE_KINDS := {
	"ficus":   ["trunk", Vector2(1.7, 0.95), "crown", Vector3(3.3, 2.3, 3.3), 3.9, Color(0.62, 0.8, 0.64), 0.04],
	"acacia":  ["trunk", Vector2(0.9, 1.25), "crown", Vector3(2.9, 1.65, 2.9), 4.4, Color(1.12, 1.2, 0.82), 0.1],
	"round":   ["trunk", Vector2(1.0, 1.0), "crown", Vector3(2.2, 2.0, 2.2), 3.9, Color(0.9, 1.02, 0.88), 0.05],
	"olive":   ["trunk", Vector2(1.2, 0.7), "crown", Vector3(1.6, 1.25, 1.6), 2.6, Color(0.92, 0.98, 0.9), 0.12],
	"cypress": ["ftrunk", Vector2(0.8, 0.4), "cone", Vector3(0.32, 1.55, 0.32), 5.1, Color(0.55, 0.72, 0.6), 0.02],
	"pine":    ["trunk", Vector2(0.95, 2.7), "crown", Vector3(2.5, 1.55, 2.5), 7.7, Color(0.6, 0.76, 0.72), 0.12],
	"eucalyptus": ["trunk", Vector2(0.95, 2.4), "crown", Vector3(2.3, 2.4, 2.3), 8.3, Color(0.8, 0.94, 0.86), 0.12],
	"date":    ["ptrunk", Vector2(1.0, 1.0), "fronds", Vector3(1, 1, 1), 7.0, Color(0.95, 1.0, 0.9), 0.14],
	"fan":     ["ptrunk", Vector2(0.62, 1.75), "fronds", Vector3(0.62, 0.7, 0.62), 12.2, Color(0.95, 1.05, 0.8), 0.05],
	"maple":   ["trunk", Vector2(1.2, 1.1), "crown", Vector3(2.8, 2.5, 2.8), 4.4, Color(0.9, 1.0, 0.8), 0.04],
	"oak":     ["trunk", Vector2(1.6, 1.0), "crown", Vector3(3.4, 2.4, 3.4), 4.3, Color(0.7, 0.86, 0.68), 0.05],
	"birch":   ["trunk", Vector2(0.65, 1.5), "crown", Vector3(1.6, 2.2, 1.6), 4.6, Color(1.1, 1.18, 0.85), 0.08],
	"spruce":  ["ftrunk", Vector2(1.0, 0.6), "cone", Vector3(1.0, 1.25, 1.0), 4.6, Color(0.68, 0.8, 0.72), 0.02],
}

func _tree_kind(look: String, wood: bool, r: float) -> String:
	if look == "north":
		if wood:
			return "spruce" if r < 0.68 else ("birch" if r < 0.82 else ("maple" if r < 0.93 else "oak"))
		return "maple" if r < 0.42 else ("spruce" if r < 0.62 else ("birch" if r < 0.78 else "oak"))
	if wood:
		return "pine" if r < 0.38 else ("eucalyptus" if r < 0.58 else ("cypress" if r < 0.68 else ("olive" if r < 0.84 else "round")))
	var table := [["ficus", 0.22], ["acacia", 0.39], ["round", 0.56], ["olive", 0.63], ["cypress", 0.68],
		["pine", 0.73], ["eucalyptus", 0.79], ["date", 0.9], ["fan", 1.0]]
	for t: Array in table:
		if r < float(t[1]):
			return t[0]
	return "round"

## ---- trees: leaf cards, bark, palm fronds ------------------------------------------------
## A crown is a cloud of cards, each a cluster of leaves from textures/leaves_atlas.png
## (2x2: broad leaves, small narrow ones, feathery fronds, needle sprays; made by
## textures/leaf_atlas.py from Poly Haven's CC0 leaf photos). The vertex shader turns every
## card to face the camera (or the sun, in the shadow pass: dappled shadows), lights it as
## if the crown were a soft ball, and gives every tree its own outline -- cards pushed out
## here and in there, a few left out -- and a little sway in the wind. The leaf kind and the
## colour come in each copy's instance colour (alpha: the atlas cell), so all of this costs
## no more draw calls than the plain balls did. The photos are divided by each cell's average
## colour, so the palette's leaf tone still decides the colour.
const CROWN_SHADER := """
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;
uniform sampler2D leaves : filter_linear_mipmap, repeat_disable;
uniform vec3 leaf_col : source_color;
uniform vec3 cell_mean[4];
uniform float card_size = 0.5;     // half a card, in the crown's own size
uniform float keep = 1.0;          // the share of cards drawn (fewer at the lowest quality)
varying vec3 tint;
varying vec2 cuv;
varying float shade;
varying float lighter;
varying flat int cell;
varying flat float core;   // 1 on a conifer's solid middle (UV2.y -1): plain geometry, no card
float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
void vertex() {
	core = UV2.y < -0.5 ? 1.0 : 0.0;
	tint = COLOR.rgb;
	cell = int(clamp(floor(COLOR.a * 4.0), 0.0, 3.0));
	if (core > 0.5) {
		VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		cuv = vec2(0.5);
		shade = 0.4;
		lighter = 0.0;
	} else {
	vec3 o = MODEL_MATRIX[3].xyz;
	float seed = h1(o.x * 0.37 + o.z * 1.13);
	float r = UV2.x;        // the card's own random number
	float out_ = UV2.y;     // 0 deep in the crown .. 1 at its surface
	vec3 n = NORMAL;        // out from the crown's middle
	vec3 p = VERTEX + n * (sin(dot(n, vec3(2.1, 1.3, 1.7)) * 2.0 + seed * 6.28) * 0.16
		+ sin(dot(n, vec3(-1.4, 2.3, 0.9)) * 3.0 + seed * 11.0) * 0.1);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float sz = length(MODEL_MATRIX[2].xyz);
	float sc = mix((sx + sz) * 0.5, sy, 0.25);
	bool alive = fract(r * 13.7 + seed * 7.31) < keep * 0.9;
	float s = alive ? card_size * (0.75 + 0.5 * fract(r * 5.3)) * sc * inversesqrt(keep) : 0.0;
	vec3 c = (MODELVIEW_MATRIX * vec4(p, 1.0)).xyz;
	float t = TIME * 1.1 + seed * 6.28;
	c.x += (sin(t) * 0.035 + sin(t * 2.7 + r * 6.0) * 0.03 * out_) * sc;
	vec2 k = UV * 2.0 - 1.0;
	float a = r * 6.2832 + seed * 3.0;
	VERTEX = c + vec3(k.x * cos(a) - k.y * sin(a), k.x * sin(a) + k.y * cos(a), 0.0) * s;
	vec3 nv = normalize((MODELVIEW_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = normalize(mix(nv, vec3(0.0, 0.0, 1.0), 0.2));
	cuv = UV;
	// deep in the crown and underneath it darker; some clumps lighter, some darker
	shade = mix(0.58, 1.0, out_) * mix(0.78, 1.05, clamp(p.y * 0.5 + 0.5, 0.0, 1.0)) * (0.88 + 0.24 * h1(r * 3.1 + seed));
	lighter = step(0.82, h1(r * 7.7 + seed * 2.0));
	}
}
void fragment() {
	vec2 uv = (cuv * 0.94 + 0.03 + vec2(float(cell % 2), float(cell / 2))) * 0.5;
	vec4 t = texture(leaves, uv);
	// smaller mipmaps average the leaves' edges away: thicken the alpha with distance, or
	// far trees thin out to nothing
	vec2 ts = uv * 1024.0;
	vec2 dx = dFdx(ts);
	vec2 dy = dFdy(ts);
	float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	vec3 c = leaf_col * tint * clamp(t.rgb / cell_mean[cell], vec3(0.0), vec3(2.5)) * shade;
	c *= mix(vec3(1.0), vec3(1.16, 1.1, 0.78), lighter * 0.8);
	ALBEDO = core > 0.5 ? leaf_col * tint * shade : c;
	ALPHA = core > 0.5 ? 1.0 : clamp(t.a * (1.0 + lod * 0.35), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""

## Bark: a photo (textures/) over its average, times the palette's trunk tone and the copy's
## colour (birches and eucalyptus pale), with its bumps
const BARK_SHADER := """
shader_type spatial;
uniform sampler2D bark_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 bark_mean = vec3(0.5);
uniform vec3 bark_col : source_color;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float textured = 1.0;
void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 c = bark_col * COLOR.rgb;
	if (textured > 0.5) {
		c *= clamp(texture(bark_tex, uv).rgb / bark_mean, vec3(0.0), vec3(2.5));
		NORMAL_MAP = vec3(texture(bark_nrm, uv).rg, 1.0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
"""

## A palm frond: a strip along the frond (UV.y 0 at the trunk .. 1 at the tip, UV.x -1..1
## across), cut by the shader into a rib and leaflets slanting out toward the tip, narrow
## at both ends, the tips drying yellow
const FROND_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 leaf_col : source_color;
void fragment() {
	float u = abs(UV.x);
	float v = UV.y;
	float edge = 0.1 + 0.9 * pow(sin(clamp(v, 0.0, 1.0) * 3.14159), 0.6);
	float f = v * 34.0 - u * 1.8;
	float k = fract(f);
	float aa = fwidth(f) + 0.001;
	float leaflet = 1.0 - smoothstep(0.58 - aa, 0.58 + aa, k);
	float inside = 1.0 - smoothstep(edge - 0.04, edge, u);
	float rib = 1.0 - smoothstep(0.03, 0.05, u);
	ALPHA = max(rib, leaflet * inside);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 c = leaf_col * COLOR.rgb * (0.78 + 0.35 * u) * mix(1.06, 0.82, k);
	c = mix(c, c * vec3(1.3, 1.18, 0.66), smoothstep(0.72, 1.0, v) * 0.6 * (1.0 - rib));
	ALBEDO = mix(c, leaf_col * COLOR.rgb * vec3(1.1, 1.05, 0.7), rib * 0.6);
	ROUGHNESS = 0.7;
	SPECULAR = 0.3;
}
"""

## a broad-leaved crown's lumps (middle, radius), in the crown's own size: close enough to
## read as one crown, not a bunch of balls
const CROWN_LUMPS := [[Vector3(0, 0, 0), 1.0], [Vector3(0.45, 0.1, 0.25), 0.78], [Vector3(-0.4, 0.15, -0.3), 0.75],
	[Vector3(0.05, 0.45, -0.02), 0.72]]
## the atlas cell each kind's leaves come from: 0 broad, 1 small and narrow, 2 feathery, 3 needles
const LEAF_CELL := {"ficus": 0, "round": 0, "maple": 0, "oak": 0, "acacia": 2, "olive": 1, "birch": 1,
	"eucalyptus": 1, "pine": 3, "cypress": 3, "spruce": 3, "date": 0, "fan": 0}
## each cell's average colour as stored (leaf_atlas.py prints them), for the shader to divide by
const LEAF_MEAN := [Vector3(0.332, 0.355, 0.113), Vector3(0.333, 0.357, 0.116),
	Vector3(0.405, 0.433, 0.230), Vector3(0.200, 0.294, 0.138)]
var _tree_mats: Array = []           ## [crown, cone, bark, palm bark, fronds] materials, for the palette

func _tree_shader_mat(code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	m.shader = sh
	return m

## the materials, once per city: cards for crowns and cones (each its own card size), two
## barks, the fronds
func _make_tree_mats() -> Array:
	var atlas := load(TEX_DIR + "leaves_atlas.png") as Texture2D
	var means := PackedVector3Array(LEAF_MEAN)
	var crown := _tree_shader_mat(CROWN_SHADER)
	crown.set_shader_parameter("leaves", atlas)
	crown.set_shader_parameter("cell_mean", means)
	crown.set_shader_parameter("card_size", 0.5)
	var cone := crown.duplicate() as ShaderMaterial
	cone.set_shader_parameter("card_size", 0.75)
	var bark := _tree_shader_mat(BARK_SHADER)
	bark.set_shader_parameter("bark_tex", _tex("bark_brown_02_diff"))
	bark.set_shader_parameter("bark_nrm", _tex("bark_brown_02_nor"))
	bark.set_shader_parameter("bark_mean", TEX_MEAN["bark_brown_02"])
	bark.set_shader_parameter("uv_scale", Vector2(1.0, 1.0))
	var pbark := bark.duplicate() as ShaderMaterial
	pbark.set_shader_parameter("bark_tex", _tex("palm_tree_bark_diff"))
	pbark.set_shader_parameter("bark_nrm", _tex("palm_tree_bark_nor"))
	pbark.set_shader_parameter("bark_mean", TEX_MEAN["palm_tree_bark"])
	pbark.set_shader_parameter("uv_scale", Vector2(1.0, 3.5))
	var fronds := _tree_shader_mat(FROND_SHADER)
	_tree_mats = [crown, cone, bark, pbark, fronds]
	_retint_trees()
	_tree_quality()
	return _tree_mats

func _retint_trees() -> void:
	if _tree_mats.is_empty():
		return
	for i in [0, 1, 4]:
		(_tree_mats[i] as ShaderMaterial).set_shader_parameter("leaf_col", _tone["leaf"])
	for i in [2, 3]:
		(_tree_mats[i] as ShaderMaterial).set_shader_parameter("bark_col", _tone["trunk"])

## the lowest web quality: two cards in three (each bigger), and plain bark
func _tree_quality() -> void:
	if _tree_mats.is_empty():
		return
	for i in [0, 1]:
		(_tree_mats[i] as ShaderMaterial).set_shader_parameter("keep", 1.0 if _quality > 0 else 0.67)
	for i in [2, 3]:
		(_tree_mats[i] as ShaderMaterial).set_shader_parameter("textured", 1.0 if _quality > 0 else 0.0)

## One card per corner set: VERTEX the card's middle (the shader spreads its corners across
## the screen), UV the corner, UV2 (the card's random number, how far out of the crown it
## is), NORMAL out from the crown's middle.
func _cards_mesh(cards: Array, m: Material, core: Array = []) -> ArrayMesh:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for cd: Array in cards:
		var at: Vector3 = cd[0]
		var n: Vector3 = cd[1]
		var r: float = cd[2]
		var o: float = cd[3]
		var b := v.size()
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			v.append(at)
			nr.append(n)
			uv.append(corner)
			uv2.append(Vector2(r, o))
			col.append(Color.WHITE)
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	# solid core triangles: [position, normal] per corner, UV2.y -1 so the shader leaves them be
	for i in range(core.size()):
		idx.append(v.size())
		v.append(core[i][0])
		nr.append(core[i][1])
		uv.append(Vector2(0.5, 0.5))
		uv2.append(Vector2(0.0, -1.0))
		col.append(Color.WHITE)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = nr
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_TEX_UV2] = uv2
	a[Mesh.ARRAY_COLOR] = col
	a[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	am.surface_set_material(0, m)
	# the cards reach past their middles: a box round the whole crown, or a copy whose
	# middle is just off screen is culled with its leaves still in view
	am.custom_aabb = AABB(Vector3(-2.6, -2.2, -2.6), Vector3(5.2, 4.6, 5.2))
	return am

## a broad-leaved crown: cards through the same few lumps the plain crown had, most of them
## near the outside so the outline is full
func _card_crown(blobs: Array, n: int, m: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var vol := 0.0
	for bl: Array in blobs:
		vol += pow(float(bl[1]), 3.0)
	var cards: Array = []
	for _i in range(n):
		var pick := rng.randf() * vol
		var bl: Array = blobs[0]
		for b2: Array in blobs:
			pick -= pow(float(b2[1]), 3.0)
			bl = b2
			if pick <= 0.0:
				break
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var o := 0.35 + 0.65 * sqrt(rng.randf())
		var at: Vector3 = (bl[0] as Vector3) + dir * float(bl[1]) * o
		cards.append([at, (at + Vector3(0, 0.15, 0)).normalized(), rng.randf(), o])
	return _cards_mesh(cards, m)

## a conifer: cards up a cone (the old cone mesh's shape: 6 high, 1.8 round at the foot,
## centred), more toward the foot, and one on the tip, round a dark solid cone a little
## smaller: a real conifer is dense, and through a gap you see more needles, not sky
func _card_cone(n: int, m: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var cards: Array = [[Vector3(0, 2.75, 0), Vector3.UP, 0.5, 1.0]]
	for _i in range(n - 1):
		var y := -2.7 + 5.3 * pow(rng.randf(), 0.8)
		var rmax := 1.8 * (3.0 - y) / 6.0
		var o := 0.4 + 0.6 * sqrt(rng.randf())
		var a := rng.randf() * TAU
		var at := Vector3(cos(a) * rmax * o, y, sin(a) * rmax * o)
		cards.append([at, Vector3(cos(a), 0.35, sin(a)).normalized(), rng.randf(), o])
	var core: Array = []
	var sides := 8
	for j in range(sides):
		var a0 := TAU * j / sides
		var a1 := TAU * (j + 1) / sides
		var p0 := Vector3(cos(a0) * 1.15, -2.9, sin(a0) * 1.15)
		var p1 := Vector3(cos(a1) * 1.15, -2.9, sin(a1) * 1.15)
		var tip := Vector3(0, 2.3, 0)
		var n0 := Vector3(cos(a0), 0.25, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), 0.25, sin(a1)).normalized()
		core.append_array([[p0, n0], [p1, n1], [tip, Vector3.UP]])
	var am := _cards_mesh(cards, m, core)
	am.custom_aabb = AABB(Vector3(-2.6, -3.6, -2.6), Vector3(5.2, 7.4, 5.2))
	return am

## A trunk (2.6 high, centred, like the cylinder it replaces) with smooth sides, bark UVs in
## metres and, if asked, branches forking up into the crown from its top half, which show
## through the gaps between the leaves
class Tubes:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func tube(a: Vector3, b: Vector3, ra: float, rb: float, sides: int) -> void:
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.FORWARD if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var side2 := axis.cross(side)
		var L := a.distance_to(b)
		var base := v.size()
		for j in range(sides + 1):
			var ang := TAU * j / sides
			var out := side * cos(ang) + side2 * sin(ang)
			var along := -side * sin(ang) + side2 * cos(ang)
			for e in range(2):
				v.append(a.lerp(b, float(e)) + out * (ra if e == 0 else rb))
				nr.append(out)
				tg.append_array([along.x, along.y, along.z, 1.0])
				uv.append(Vector2(float(j) / sides * 0.9 * (ra + rb) / 0.27, L * float(e)))
				col.append(Color.WHITE)
		for j in range(sides):
			var i0 := base + j * 2
			idx.append_array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3])

	func mesh(m: Material) -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = nr
		a[Mesh.ARRAY_TANGENT] = tg
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = col
		a[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(0, m)
		return am

func _trunk_mesh(branches: int, m: Material) -> ArrayMesh:
	var t := Tubes.new()
	t.tube(Vector3(0, -1.3, 0), Vector3(0, 1.3, 0), 0.16, 0.11, 7)
	for i in range(branches):
		var ang := TAU * i / branches + 0.4
		var d := Vector3(cos(ang) * 0.75, 1.0, sin(ang) * 0.75).normalized()
		var s := Vector3(0, 0.45 + 0.3 * (i % 2), 0)
		t.tube(s, s + d * 1.6, 0.075, 0.03, 5)
	return t.mesh(m)

## Palm fronds as strips the frond shader cuts into leaflets: nine drooping, three young ones
## standing up in the middle. UV.x -1..1 across, UV.y 0 at the trunk .. 1 at the tip; the
## two halves fold up a little from the rib, as real fronds do.
func _frond_mesh(m: Material) -> ArrayMesh:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for i in range(12):
		var young := i >= 9
		var a := TAU * i / 9.0 + 0.3 * (i % 2) if not young else TAU * (i - 9) / 3.0 + 0.5
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var segs := 7
		var base := v.size()
		for s in range(segs + 1):
			var t := float(s) / segs
			var p := dir * 3.1 * t + Vector3(0, 2.1 * t - 2.8 * t * t, 0) if not young \
				else dir * 1.1 * t + Vector3(0, 2.0 * t - 0.4 * t * t, 0)
			var fwd := (dir * 3.1 + Vector3(0, 2.1 - 5.6 * t, 0)).normalized() if not young \
				else (dir * 1.1 + Vector3(0, 2.0 - 0.8 * t, 0)).normalized()
			var w := 0.48 if not young else 0.32
			var fold := Vector3(0, 0.14, 0)
			var up := side.cross(fwd).normalized()
			if up.y < 0.0:
				up = -up
			for k in [-1.0, 0.0, 1.0]:
				v.append(p + side * w * k + fold * absf(k))
				nr.append(up)
				uv.append(Vector2(k, t))
				col.append(Color.WHITE)
		for s in range(segs):
			var r0 := base + s * 3
			var r1 := r0 + 3
			idx.append_array([r0, r1, r0 + 1, r0 + 1, r1, r1 + 1, r0 + 1, r1 + 1, r0 + 2, r0 + 2, r1 + 1, r1 + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, m)
	return am

## Israeli roofs: solar water heaters ("dud shemesh"), a tilted panel facing south with
## its white tank behind, one to a handful per block depending on its size
func _build_roof_kit() -> void:
	if String(_place.get("look", "")) != "med":
		return
	var panels: Array = []
	var tanks: Array = []
	var rooms: Array = []            ## the stairwell room most blocks have on the roof
	var rng := RandomNumberGenerator.new()
	var all: Array = _city_data["buildings"]
	for bi: int in _tile_blds.get(_tile, []):
		if _over():
			await _pause()
		var bd: Dictionary = all[bi]
		var rel: float = bd["_h"]
		if rel < 6.0 or rel > 45.0:
			continue
		var ring: PackedVector2Array = bd["_ring"]
		var box := _bld_box_of(ring)
		var area := 0.0
		var g_sum := 0.0
		for i in range(ring.size()):
			area += ring[i].x * ring[(i + 1) % ring.size()].y - ring[(i + 1) % ring.size()].x * ring[i].y
			g_sum += _h(ring[i])
		var top := g_sum / ring.size() + rel
		var want := clampi(int(absf(area) * 0.5 / 200.0), 1, 4)
		rng.seed = _hash_i(ring[0])
		if rel > 9.0 and rng.randf() < 0.6:
			for _try in range(8):
				var q := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
				var room_fits := true
				for d: Vector2 in [Vector2.ZERO, Vector2(2.2, 0), Vector2(-2.2, 0), Vector2(0, 2.4), Vector2(0, -2.4)]:
					if not Geometry2D.is_point_in_polygon(q + d, ring):
						room_fits = false
						break
				if room_fits:
					rooms.append(Transform3D(Basis(Vector3.UP, rng.randf() * 0.2), Vector3(q.x, top + 1.3, q.y)))
					break
		var placed := 0
		for _try in range(want * 5):
			if placed >= want:
				break
			var p := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
			var fits := true
			for d: Vector2 in [Vector2.ZERO, Vector2(1.4, 0), Vector2(-1.4, 0), Vector2(0, 1.2), Vector2(0, -1.2)]:
				if not Geometry2D.is_point_in_polygon(p + d, ring):
					fits = false
					break
			if not fits:
				continue
			placed += 1
			# the panel faces south (+z), tilted ~35 degrees; the tank lies behind, east-west
			panels.append(Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(p.x, top + 0.55, p.y + 0.15)))
			tanks.append(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(p.x, top + 1.05, p.y - 0.55)))
	var panel := BoxMesh.new()
	panel.size = Vector3(2.0, 0.06, 1.15)
	panel.material = _surface("solar")
	var tank := CylinderMesh.new()
	tank.top_radius = 0.3
	tank.bottom_radius = 0.3
	tank.height = 1.8
	tank.radial_segments = 8
	tank.rings = 1
	tank.material = _surface("tank")
	_chunked(panel, panels, 420.0)
	_chunked(tank, tanks, 420.0)
	var room := BoxMesh.new()
	room.size = Vector3(3.0, 2.6, 3.4)
	room.material = _surface("roofroom")
	_chunked(room, rooms, VIEW_RANGE * 0.5)
	_tally("roof_rooms", rooms.size())
	_tally("solar", panels.size())

## street lamps along the pavements, every ~34 m, alternating sides
## Lamp posts down the streets, every 34 m, the sides taking turns. Most are tall and grey
## with one arm out over the road. Givatayim's main roads have the ornate dark-green ones,
## a curved arm and a lantern with a flag on a staff off each, and where a main road is
## split into two carriageways, a double one down the middle (the other carriageway's
## lamps are those same ones). In Bedford a street with power lines has its lamps on the
## power poles instead (furniture.gd's wires).
const FANCY_ROADS := {"primary": true, "secondary": true, "tertiary": true}
func _build_lamps() -> void:
	var med := String(_place.get("look", "")) == "med"
	var poles: Array = []
	var arms: Array = []
	var heads: Array = []
	var ornate: Array = []
	var doubles: Array = []
	var lanterns: Array = []
	for ri: int in _tile_roads.get(_tile, []):
		var r: Dictionary = _roads[ri]
		if not r["drive"] or r["pv"] or r["k"] == "service" or _wired.has(ri):
			continue
		if _over():
			await _pause()
		var flip := posmod(ri, 2) == 0   # (from the road's own start: every square alike)
		var fancy := med and FANCY_ROADS.has(r["k"])
		var o := int(r["o"])
		var dual: bool = o != 0 and (FANCY_ROADS.has(r["k"]) or r["k"] == "trunk") and not r.get("ring", false)
		var pts: PackedVector2Array = r["pts"]
		var ids: PackedInt32Array = r["ids"]
		var hw: float = float(r["w"]) * 0.5
		var s := 10.0
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			var d := (b - a) / maxf(L, 0.001)
			var side := Vector2(-d.y, d.x)
			var keep_a := _node_r[ids[j]] + 6.0 if (_node_roads[ids[j]] as Array).size() >= 2 else 0.0
			var keep_b := _node_r[ids[j + 1]] + 6.0 if (_node_roads[ids[j + 1]] as Array).size() >= 2 else 0.0
			while s < L:
				if s > keep_a and s < L - keep_b:
					flip = not flip
					var c := a + d * s
					var pair: Array = _partner(c, d, ri, hw, o) if dual else []
					if not pair.is_empty():
						# half of a dual carriageway: the lamps go down the middle, planted by the
						# half with the lower number so they go in once
						var gap: float = pair[2]
						var left: Vector2 = pair[3]
						var m := c + left * (hw + gap * 0.5)
						if ri < int(pair[0]) and gap >= 1.0 and _mine(m) and _off_road(m, 0.25) and _push_out(m, 0.3, false) == Vector2.ZERO \
								and _clear_of_posts(m, 3.0):
							var gy := _h(m)
							var bs := Basis(Vector3.UP, atan2(-left.y, left.x))   # local X across the road
							(doubles if med else poles).append(Transform3D(bs if med else Basis(), Vector3(m.x, gy + (0.0 if med else 3.5), m.y)))
							for sg: float in [-1.0, 1.0]:
								var arm_dir := left * sg
								var lp := m + arm_dir * (1.6 if med else 1.75)
								if med:
									lanterns.append(Transform3D(Basis(), Vector3(lp.x, gy + 6.85, lp.y)))
									var fb := Basis(Vector3.UP, atan2(-arm_dir.y, arm_dir.x))
									var fp := m + arm_dir * 0.08
									_flag_spots.append(Transform3D(fb, Vector3(fp.x, gy + 4.4, fp.y)))
								else:
									var face := Basis(Vector3.UP, atan2(-arm_dir.y, arm_dir.x))
									var am := m + arm_dir * 0.9
									arms.append(Transform3D(face, Vector3(am.x, gy + 6.95, am.y)))
									heads.append(Transform3D(face, Vector3(lp.x, gy + 6.85, lp.y)))
								_pool_at.append(Vector3(lp.x + arm_dir.x * 0.5, lp.y + arm_dir.y * 0.5, 7.5))
							_add_post(m, 0.18)
						s += 34.0
						continue
					# one-way: on the pavement side (right of the traffic); else the sides take turns
					var sgn := float(o) if o != 0 else (1.0 if flip else -1.0)
					var out := side * sgn
					var p := c + out * (hw + 0.9)
					var ok := _mine(p) and _push_out(p, 0.6, false) == Vector2.ZERO
					var on := _nearest_seg(p, 10.0, true)
					ok = ok and (on.is_empty() or float(on["edge"]) > 0.4) and _clear_of_posts(p, 2.5)
					if ok:
						var gy := _h(p)
						var toward := -out
						if fancy:
							var bs := Basis(Vector3.UP, atan2(-toward.y, toward.x))   # local X out over the road
							ornate.append(Transform3D(bs, Vector3(p.x, gy, p.y)))
							var lp := p + toward * 1.6
							lanterns.append(Transform3D(Basis(), Vector3(lp.x, gy + 6.85, lp.y)))
							var fp := p + toward * 0.08
							_flag_spots.append(Transform3D(bs, Vector3(fp.x, gy + 4.4, fp.y)))
							_pool_at.append(Vector3(lp.x + toward.x * 0.5, lp.y + toward.y * 0.5, 7.0))
						else:
							var face := Basis(Vector3.UP, atan2(-toward.y, toward.x))
							poles.append(Transform3D(Basis(), Vector3(p.x, gy + 3.5, p.y)))
							var arm := p + toward * 0.9
							arms.append(Transform3D(face, Vector3(arm.x, gy + 6.95, arm.y)))
							var head := p + toward * 1.75
							heads.append(Transform3D(face, Vector3(head.x, gy + 6.85, head.y)))
							_pool_at.append(Vector3(head.x + toward.x * 0.6, head.y + toward.y * 0.6, 7.5))
						_add_post(p, 0.15)
				s += 34.0
			s -= L
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.09
	pole.height = 7.0
	pole.radial_segments = 6
	pole.rings = 1
	pole.material = _surface("pole")
	var arm_m := BoxMesh.new()
	arm_m.size = Vector3(1.8, 0.07, 0.07)
	arm_m.material = _surface("pole")
	var head_m := BoxMesh.new()
	head_m.size = Vector3(0.6, 0.14, 0.28)
	head_m.material = _surface("lamp")
	_chunked(pole, poles, LAMP_RANGE)
	_chunked(arm_m, arms, LAMP_RANGE)
	_chunked(head_m, heads, LAMP_RANGE)
	if not lanterns.is_empty():
		_chunked(_furn.ornate_kit(false), ornate, LAMP_RANGE)
		_chunked(_furn.ornate_kit(true), doubles, LAMP_RANGE)
		var lantern := CylinderMesh.new()
		lantern.top_radius = 0.13
		lantern.bottom_radius = 0.24
		lantern.height = 0.42
		lantern.radial_segments = 6
		lantern.rings = 1
		lantern.material = _surface("lamp")
		_chunked(lantern, lanterns, LAMP_RANGE)
	_tally("lamps", poles.size() + ornate.size() + doubles.size())
	_tally("lamps_ornate", ornate.size())
	_tally("lamps_median", doubles.size())

## the other half of a dual carriageway beside point c of road ri (heading d along its
## points, one-way `o`): [road, nearest point, the gap between their asphalt, the way to
## it], or [] when there is none
func _partner(c: Vector2, d: Vector2, ri: int, hw: float, o: int) -> Array:
	var travel := d * float(o)
	var left := Vector2(travel.y, -travel.x)   # left of the traffic: where the median is
	var best: Array = []
	var best_across := INF
	for code: int in _near(_seg_hash, c, hw + 18.0, SEG_CELL):
		var rj := code / 4096
		if rj == ri:
			continue
		var r2: Dictionary = _roads[rj]
		if not r2["drive"] or int(r2["o"]) == 0:
			continue
		var p2: PackedVector2Array = r2["pts"]
		var sj := code % 4096
		var d2 := (p2[sj + 1] - p2[sj]).normalized() * float(r2["o"])
		if d2.dot(travel) > -0.85:
			continue   # not running the other way beside it
		var q := Geometry2D.get_closest_point_to_segment(c, p2[sj], p2[sj + 1])
		var across := (q - c).dot(left)
		if across <= 0.0 or (q - c).length() > across * 1.25 + 2.0:
			continue
		if across < best_across:
			best_across = across
			best = [rj, q, across - hw - float(r2["w"]) * 0.5, left]
	return best

## the pools of light under street and park lamps: built the first time it gets dark (a
## few thousand discs that follow the hills are not worth the wait if it never does)
var _pool_at: Array = []             ## Vector3(x, z, radius)
var _pools_made := false
var _pools_from := 0                 ## _pool_at before this have theirs

func _make_pools() -> void:
	_pools_made = true
	var pools := CBuf.new(GROUND_CELL)
	for i in range(_pools_from, _pool_at.size()):
		var q: Vector3 = _pool_at[i]
		_pool(pools, Vector2(q.x, q.y), q.z)
	_pools_from = _pool_at.size()
	for mi: MeshInstance3D in _add_mesh(pools, _glow_mat("lamplight", 0.4), false, LAMP_RANGE):
		mi.visible = _night
		_night_nodes.append(mi)

## ---- the bare ground: patches, not one flat colour ------------------------------------------
## Open land drawn in one colour read as empty, a grey plain. A shader breaks it into
## patches of grass, bare earth and darker scrub (two sizes of noise, by world position, so
## it does not swim): nothing more to draw, just a different colour per pixel. The north is
## mostly green; Givatayim's few open lots are mostly dry.
const GROUND_SHADER := """
shader_type spatial;
uniform vec4 base : source_color;
uniform vec4 green : source_color;
uniform vec4 dark : source_color;
uniform float greenness = 0.5;
uniform vec4 rock : source_color;
uniform float textured = 1.0;
uniform sampler2D grass_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_mean = vec3(0.5);
varying vec3 wpos;
varying float wup;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wup = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}
void fragment() {
	float n = noise(wpos.xz / 70.0) * 0.65 + noise(wpos.xz / 15.0) * 0.35;
	float g = smoothstep(0.62 - greenness * 0.45, 0.78 - greenness * 0.4, n);
	vec3 c = mix(base.rgb, green.rgb, g);
	c = mix(c, dark.rgb, smoothstep(0.62, 0.9, noise(wpos.xz / 31.0 + 17.0)) * 0.55);
	// a mountainside steeper than any town street is bare rock, in bands and blotches
	float bare = smoothstep(0.86, 0.74, wup + (noise(wpos.xz / 9.0) - 0.5) * 0.08);
	vec3 stone = rock.rgb * (0.72 + 0.28 * noise(vec2(wpos.y * 0.45, (wpos.x + wpos.z) * 0.03))) * (0.85 + 0.3 * noise(wpos.xz / 6.0));
	c = mix(c, stone, bare);
	c *= 0.94 + 0.06 * noise(wpos.xz / 2.5);
	if (textured > 0.5) {   // the lawn photo (see TONE_SHADER), over earth and grass alike
		// Its 2 m repeat lines up into a grid further off, so it fades out with distance (the
		// noise above, which never repeats, carries the far ground), and a second copy 7.3 m
		// across, turned, breaks up the repeat nearer in.
		float kd = 1.0 - smoothstep(25.0, 110.0, length(VERTEX));
		vec2 uv = wpos.xz * 0.5;
		vec3 t = texture(grass_tex, uv).rgb;
		vec3 t2 = texture(grass_tex, vec2(wpos.z, -wpos.x) * 0.137 + vec2(0.31, 0.77)).rgb;
		float lawn = 1.0 - bare * 0.6;   // less of the lawn photo on bare rock
		// the lawn's colours only where it is grass: bare earth (and rock) takes just its light
		// and dark -- its greens and yellows on grey earth came out as speckles of colour
		vec3 lw = vec3(0.2126, 0.7152, 0.0722);
		float gg = g * (1.0 - bare);
		vec3 d1 = mix(vec3(dot(t, lw) / dot(grass_mean, lw)), t / grass_mean, gg);
		vec3 d2 = mix(vec3(dot(t2, lw) / dot(grass_mean, lw)), t2 / grass_mean, gg);
		c *= mix(vec3(1.0), clamp(d1, vec3(0.0), vec3(2.6)), 0.85 * kd * lawn);
		c *= mix(vec3(1.0), clamp(d2, vec3(0.0), vec3(2.6)), 0.3 * lawn * (1.0 - smoothstep(60.0, 260.0, length(VERTEX))));
		vec2 xy = (texture(grass_nrm, uv).rg * 2.0 - 1.0) * 0.8 * kd;
		vec3 b = vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
		vec3 tx = (VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
		tx = normalize(tx - NORMAL * dot(NORMAL, tx));
		NORMAL = normalize(tx * b.x + cross(NORMAL, tx) * b.y + NORMAL * b.z);
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""
var _ground_shader_mat: ShaderMaterial

func _ground_mat() -> ShaderMaterial:
	if _ground_shader_mat == null:
		_ground_shader_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = GROUND_SHADER
		_ground_shader_mat.shader = sh
		_ground_shader_mat.set_shader_parameter("grass_tex", _tex("leafy_grass_diff"))
		_ground_shader_mat.set_shader_parameter("grass_nrm", _tex("leafy_grass_nor"))
		_ground_shader_mat.set_shader_parameter("grass_mean", TEX_MEAN["leafy_grass"])
		_ground_shader_mat.set_shader_parameter("textured", 1.0 if _quality > 0 else 0.0)
		_retint_ground()
	return _ground_shader_mat

func _retint_ground() -> void:
	if _ground_shader_mat == null:
		return
	var north := String(_place.get("look", "")) == "north"
	var base: Color = _tone["ground"]
	var green: Color = _tone["grass"]
	_ground_shader_mat.set_shader_parameter("base", base)
	_ground_shader_mat.set_shader_parameter("green", green.lerp(base, 0.25))
	_ground_shader_mat.set_shader_parameter("dark", green.lerp(Palette.col("bg"), 0.45))
	_ground_shader_mat.set_shader_parameter("greenness", 0.8 if north else 0.3)
	_ground_shader_mat.set_shader_parameter("rock", _tone["rock"])

## the same noise in script, for clumping what grows on open land where the green is
func _vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash01(i)
	var b := _hash01(i + Vector2(1, 0))
	var c := _hash01(i + Vector2(0, 1))
	var d := _hash01(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)

func _hash01(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(12.9898, 78.233))) * 43758.5453, 1.0)

## ---- parks and pitches ----------------------------------------------------------------------
## Along the paths through a park: benches facing the path, low park lamps (lit at night,
## with their pools). In a big enough park, a playground: a slide tower, swings and a
## sandpit on a soft floor. On a sports pitch: its lines, and goals or basketball hoops.

var _parks: Array = []               ## [outline, box] of the parks and lawns big enough for benches
var _park_hash := {}

func _parks_setup() -> void:
	for kind: String in ["park", "grass"]:
		for ring: PackedVector2Array in _area_rings.get(kind, []):
			if _area(ring) >= 400.0:
				_hash_add(_park_hash, _bld_box_of(ring), 60.0, _parks.size())
				_parks.append([ring, _bld_box_of(ring)])

func _build_parks() -> void:
	var parks := _parks
	var park_hash := _park_hash
	var benches: Array = []
	var posts: Array = []
	var globes: Array = []
	for ri: int in _tile_roads.get(_tile, []):
		var r: Dictionary = _roads[ri]
		if r["drive"]:
			continue
		if _over():
			await _pause()
		var flip := posmod(ri, 2) == 0
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5
		var s_bench := 6.0
		var s_lamp := 12.0
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			if L < 0.5:
				continue
			var d := (b - a) / L
			var side := Vector2(-d.y, d.x)
			var mid := (a + b) * 0.5
			var inside := false
			for pi: int in _near(park_hash, mid, 1.0, 60.0):
				var pk: Array = parks[pi]
				if (pk[1] as Rect2).grow(2.0).has_point(mid) and Geometry2D.is_point_in_polygon(mid, pk[0]):
					inside = true
					break
			if not inside:
				s_bench -= L
				s_lamp -= L
				continue
			while s_bench < L:
				flip = not flip
				var out := side * (1.0 if flip else -1.0)
				var q := a + d * s_bench + out * (hw + 0.75)
				if _mine(q) and _push_out(q, 0.9, true) == Vector2.ZERO and _off_road(q, 1.0):
					benches.append(Transform3D(Basis(Vector3.UP, atan2(-out.x, -out.y)), _g3(q, 0.0)))
					_add_post(q, 0.5)
				s_bench += 19.0
			s_bench -= L
			while s_lamp < L:
				var q := a + d * s_lamp - side * (hw + 0.6) * (1.0 if flip else -1.0)
				if _mine(q) and _push_out(q, 0.5, true) == Vector2.ZERO and _off_road(q, 1.0):
					var gy := _h(q)
					posts.append(Transform3D(Basis(), Vector3(q.x, gy + 1.8, q.y)))
					globes.append(Transform3D(Basis(), Vector3(q.x, gy + 3.75, q.y)))
					_pool_at.append(Vector3(q.x, q.y, 4.5))
					_add_post(q, 0.1)
				s_lamp += 27.0
			s_lamp -= L
	var bench := _cached("bench", func() -> Mesh:
		var bench_buf := Buf.new()
		_box(bench_buf, Vector3(0, 0.44, 0), Vector3(1.7, 0.07, 0.46))
		_box(bench_buf, Vector3(0, 0.74, -0.22), Vector3(1.7, 0.36, 0.06))
		for sx: float in [-0.72, 0.72]:
			_box(bench_buf, Vector3(sx, 0.22, 0), Vector3(0.07, 0.44, 0.42))
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bench_buf.arrays())
		am.surface_set_material(0, _surface("furniture"))
		return am)
	_chunked(bench, benches, 160.0, [], null, true)
	var post := CylinderMesh.new()
	post.top_radius = 0.045
	post.bottom_radius = 0.06
	post.height = 3.6
	post.radial_segments = 6
	post.rings = 1
	post.material = _surface("pole")
	var globe := SphereMesh.new()
	globe.radius = 0.22
	globe.height = 0.44
	globe.radial_segments = 8
	globe.rings = 4
	globe.material = _surface("lamp")
	_chunked(post, posts, LAMP_RANGE)
	_chunked(globe, globes, LAMP_RANGE)
	# playgrounds, in the bigger parks
	var play := {"friend": CBuf.new(CHUNK), "warn": CBuf.new(CHUNK), "accent": CBuf.new(CHUNK),
		"player": CBuf.new(CHUNK), "pole": CBuf.new(CHUNK), "soft": CBuf.new(CHUNK), "sand": CBuf.new(CHUNK)}
	var made := 0
	for ring: PackedVector2Array in _rings_near("park") + _rings_near("grass"):
		if _area(ring) < 1500.0 or not _ring_mine(ring):
			continue
		var spot := _clear_spot(ring, 7.0)
		if not spot.is_finite():
			continue
		_playground(play, spot, float(posmod(_hash_i(spot), 360)) * PI / 180.0)
		_landmarks.append([spot, "playground"])
		made += 1
	var mats := {"friend": mat("friend", 0.12), "warn": mat("warn", 0.12), "accent": mat("accent", 0.12),
		"player": mat("player", 0.12), "pole": _surface("pole"), "soft": _surface("rubber"), "sand": _surface("sand")}
	for k: String in play:
		_add_mesh(play[k], mats[k], k != "soft" and k != "sand", 260.0)
	# pitches: lines, and goals or hoops
	var lines := CBuf.new(GROUND_CELL)
	var frames := CBuf.new(CHUNK)
	var pitches := 0
	for ring: PackedVector2Array in _rings_near("pitch"):
		if _ring_mine(ring):
			_sports_pitch(ring, lines, frames)
			pitches += 1
	_add_mesh(lines, _surface("mark"), false, DETAIL_RANGE)
	_add_mesh(frames, _surface("mark"), true, 260.0)
	_tally("benches", benches.size())
	_tally("playgrounds", made)
	_tally("pitches", pitches)

## a point inside `ring` with nothing solid or a path within `r` of it, nearest its middle
func _clear_spot(ring: PackedVector2Array, r: float) -> Vector2:
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	var box := _bld_box_of(ring)
	var best := Vector2.INF
	var bd := INF
	for i in range(40):
		var q := c if i == 0 else Vector2(lerpf(box.position.x, box.end.x, fposmod(i * 0.618, 1.0)),
			lerpf(box.position.y, box.end.y, fposmod(i * 0.382 + 0.17, 1.0)))
		if not Geometry2D.is_point_in_polygon(q, ring):
			continue
		var ok := true
		for k in range(8):
			var e := q + Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * r
			if not Geometry2D.is_point_in_polygon(e, ring):
				ok = false
				break
		if not ok or _push_out(q, r, true) != Vector2.ZERO:
			continue
		var hit := _nearest_seg(q, r + 3.0, false)
		if not hit.is_empty() and float(hit["edge"]) < r:
			continue
		if q.distance_to(c) < bd:
			bd = q.distance_to(c)
			best = q
	return best

## a box turned by `yaw` about its own middle, into a Buf
func _obox(buf: Buf, c: Vector3, size: Vector3, yaw: float, tilt := 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	var h := size * 0.5
	for ax in range(3):
		for sg: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sg
			var u := Vector3.ZERO
			u[(ax + 1) % 3] = h[(ax + 1) % 3]
			var w := Vector3.ZERO
			w[(ax + 2) % 3] = h[(ax + 2) % 3]
			var f := n * h[ax]
			var pts: Array = []
			for q: Vector3 in [f - u - w, f + u - w, f + u + w, f - u + w]:
				pts.append(c + basis * q)
			_poly(buf, pts, basis * n)

## a slide tower with a roof, a swing frame and a sandpit, on a round soft floor
func _playground(b: Dictionary, at: Vector2, yaw: float) -> void:
	var gy := _h(at)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var P := func(q: Vector2, y: float) -> Vector3: return Vector3(q.x, gy + y, q.y)
	var floor_buf: Buf = b["soft"]
	var seg := 16
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		floor_buf.tri(P.call(at, 0.04), P.call(at + Vector2(cos(a0), sin(a0)) * 7.0, 0.04),
			P.call(at + Vector2(cos(a1), sin(a1)) * 7.0, 0.04), Vector3.UP, Color.WHITE)
	# the tower and its slide
	var t := at - side * 2.5
	for c: Vector2 in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(0.6, 0.6), Vector2(-0.6, 0.6)]:
		var q := t + side * c.x + fwd * c.y
		_obox(b["pole"], P.call(q, 1.45), Vector3(0.1, 2.9, 0.1), yaw)
	_obox(b["friend"], P.call(t, 1.5), Vector3(1.4, 0.1, 1.4), yaw)
	_obox(b["accent"], P.call(t, 2.95), Vector3(1.6, 0.1, 1.6), yaw)
	var run := t + fwd * 2.05
	_obox(b["warn"], P.call(run, 0.8), Vector3(0.62, 0.06, 2.9), yaw, 0.5)
	# swings
	var sw := at + side * 2.6
	for e: float in [-1.6, 1.6]:
		for l: float in [-0.5, 0.5]:
			_obox(b["player"], P.call(sw + side * e + fwd * l * 0.6, 1.2), Vector3(0.08, 2.5, 0.08), yaw, l * 0.45)
	_obox(b["player"], P.call(sw, 2.4), Vector3(0.1, 0.1, 3.4), yaw + PI * 0.5)
	for e: float in [-0.7, 0.7]:
		var q := sw + side * e
		_obox(b["pole"], P.call(q, 1.5), Vector3(0.03, 1.8, 0.03), yaw)
		_obox(b["warn"], P.call(q, 0.55), Vector3(0.5, 0.05, 0.22), yaw)
	# the sandpit
	var sp := at + fwd * -3.4
	for e: float in [-1.5, 1.5]:
		_obox(b["friend"], P.call(sp + fwd * e, 0.15), Vector3(3.2, 0.3, 0.15), yaw)
		_obox(b["friend"], P.call(sp + side * e, 0.15), Vector3(3.2, 0.3, 0.15), yaw + PI * 0.5)
	_obox(b["sand"], P.call(sp, 0.08), Vector3(2.9, 0.12, 2.9), yaw)

## a pitch: the tightest rectangle round it, its lines (inset a metre), and a goal at each
## end (a basketball hoop on a small court)
func _sports_pitch(ring: PackedVector2Array, lines: Buf, frames: Buf) -> void:
	var best := INF
	var u := Vector2.RIGHT
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for i in range(ring.size()):
		var e := (ring[(i + 1) % ring.size()] - ring[i]).normalized()
		if e == Vector2.ZERO:
			continue
		var v := Vector2(-e.y, e.x)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in ring:
			var q := Vector2(p.dot(e), p.dot(v))
			mn = mn.min(q)
			mx = mx.max(q)
		if (mx.x - mn.x) * (mx.y - mn.y) < best:
			best = (mx.x - mn.x) * (mx.y - mn.y)
			u = e
			lo = mn
			hi = mx
	var v := Vector2(-u.y, u.x)
	if hi.y - lo.y > hi.x - lo.x:   # u along the long side
		var t := u
		u = v
		v = -t
		var l2 := Vector2(-hi.y, lo.x)
		var h2 := Vector2(-lo.y, hi.x)
		lo = l2
		hi = h2
	var L := hi.x - lo.x
	var W := hi.y - lo.y
	if L < 12.0 or W < 7.0 or best > 12000.0:
		return
	_landmarks.append([u * (lo.x + hi.x) * 0.5 + v * (lo.y + hi.y) * 0.5, "pitch"])
	var at := func(a: float, b: float) -> Vector2: return u * a + v * b
	var strip := func(p0: Vector2, p1: Vector2) -> void:
		var d := (p1 - p0).normalized()
		var n := Vector2(-d.y, d.x) * 0.06
		lines.quad3(_g3(p0 - n, 0.05), _g3(p1 - n, 0.05), _g3(p1 + n, 0.05), _g3(p0 + n, 0.05))
	var x0 := lo.x + 1.0
	var x1 := hi.x - 1.0
	var y0 := lo.y + 1.0
	var y1 := hi.y - 1.0
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	for e: Array in [[x0, y0, x1, y0], [x1, y0, x1, y1], [x1, y1, x0, y1], [x0, y1, x0, y0], [cx, y0, cx, y1]]:
		strip.call(at.call(e[0], e[1]), at.call(e[2], e[3]))
	var cr := minf(3.0, (y1 - y0) * 0.16)
	for i in range(16):
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		strip.call(at.call(cx + cos(a0) * cr, cy + sin(a0) * cr), at.call(cx + cos(a1) * cr, cy + sin(a1) * cr))
	var yaw := atan2(u.x, u.y)
	for end: Array in [[x0, 1.0], [x1, -1.0]]:
		var g: Vector2 = at.call(end[0], cy)
		var gy := _h(g)
		if L >= 34.0:   # football: two posts and a bar
			var gw := minf(5.0, (y1 - y0) * 0.3)
			for sd: float in [-0.5, 0.5]:
				var q := g + v * gw * sd
				_obox(frames, Vector3(q.x, gy + 1.1, q.y), Vector3(0.1, 2.2, 0.1), yaw)
			_obox(frames, Vector3(g.x, gy + 2.2, g.y), Vector3(gw + 0.1, 0.1, 0.1), yaw)
		else:   # a hoop: a pole off the end line and a backboard over it
			var q := g - u * 0.6 * float(end[1])
			_obox(frames, Vector3(q.x, gy + 1.6, q.y), Vector3(0.12, 3.2, 0.12), yaw)
			var bb := g + u * 0.3 * float(end[1])
			_obox(frames, Vector3(bb.x, gy + 3.35, bb.y), Vector3(1.6, 1.0, 0.06), yaw)

## ---- night ---------------------------------------------------------------------------------
## The same city after dark: the sun down to a dim blue moon (and no shadows, which also
## makes the night cheaper to draw), a share of the windows lit, the street lamps on with a
## pool of light under each, shop windows bright, headlights and their beams on the road.
## Light that is drawn, not computed: real lights in this renderer redraw everything they
## touch, which a browser cannot afford by the hundred.

var _night := false
var _night_nodes: Array = []          ## shown only at night: light pools, headlight beams

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color;
uniform float strength = 0.5;
void fragment() {
	// UV: 0 at the light, 1 at the rim (pools); beams fade along their length and to the sides
	float k = UV2.x > 0.5 ? (1.0 - UV.y) * (1.0 - UV.y) * (1.0 - UV.x * UV.x) : clamp(1.0 - length(UV), 0.0, 1.0);
	ALBEDO = col.rgb * k * k * strength;
}
"""
var _glow_mats := {}

func _glow_mat(tone: String, strength: float) -> ShaderMaterial:
	var key := "%s|%.2f" % [tone, strength]
	if _glow_mats.has(key):
		return _glow_mats[key]
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GLOW_SHADER
	m.shader = sh
	m.set_shader_parameter("col", _tone[tone])
	m.set_shader_parameter("strength", strength)
	m.set_meta("tone", tone)
	_glow_mats[key] = m
	return m

## a disc of light on the ground round p, following the hills: a ring at half the radius
## and one at the rim, each point's height worked out once
func _pool(buf: Buf, p: Vector2, r: float) -> void:
	var seg := 12
	var mid := _g3(p, 0.09)
	var inner: Array = []
	var outer: Array = []
	var dirs: Array = []
	for i in range(seg):
		var e := Vector2(cos(TAU * i / seg), sin(TAU * i / seg))
		dirs.append(e)
		inner.append(_g3(p + e * r * 0.55, 0.09))
		outer.append(_g3(p + e * r, 0.09))
	for i in range(seg):
		var j := (i + 1) % seg
		var e0: Vector2 = dirs[i]
		var e1: Vector2 = dirs[j]
		buf.tri(mid, inner[i], inner[j], Vector3.UP, Color.WHITE, Vector2.ZERO, e0 * 0.55, e1 * 0.55)
		buf.tri(inner[i], outer[i], outer[j], Vector3.UP, Color.WHITE, e0 * 0.55, e0, e1)
		buf.tri(inner[i], outer[j], inner[j], Vector3.UP, Color.WHITE, e0 * 0.55, e1, e1 * 0.55)

## a headlight beam on the road, local to a car facing +Z: from the bumper, 26 m out and
## widening (UV.x across, UV.y along; UV2.x = 1 marks it as a beam for the shader)
func _beam_mesh() -> ArrayMesh:
	var b := Buf.new()
	var near := 2.3
	var far := 28.0
	var steps := 6
	for i in range(steps):
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var z0 := lerpf(near, far, t0)
		var z1 := lerpf(near, far, t1)
		var w0 := lerpf(0.9, 5.5, t0)
		var w1 := lerpf(0.9, 5.5, t1)
		var u2 := Vector2(1, 0)
		b.tri(Vector3(-w0, 0.07, z0), Vector3(w0, 0.07, z0), Vector3(w1, 0.07, z1), Vector3.UP, Color.WHITE,
			Vector2(-1, t0), Vector2(1, t0), Vector2(1, t1), u2)
		b.tri(Vector3(-w0, 0.07, z0), Vector3(w1, 0.07, z1), Vector3(-w1, 0.07, z1), Vector3.UP, Color.WHITE,
			Vector2(-1, t0), Vector2(1, t1), Vector2(-1, t1), u2)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	return am

func _set_night(on: bool) -> void:
	_night = on
	if on and not _pools_made:
		_make_pools()
	for n: Node3D in _night_nodes:
		n.visible = on
	_lights_on = on   # headlights on with the dark (the lights button still switches them)
	if _beam_node != null:
		_beam_node.visible = _lights_on
	_retint_city()
	if on:
		sun.shadow_enabled = false
	else:
		_set_quality(_quality)
	if _traffic != null:
		_traffic.set_night(on)
	if _furn != null:
		_furn.set_night(on)
	if _car_shader_mat != null:
		_car_material()
	_show_banner("night" if on else "day", 1.2)
	Probe.event("night", {"on": on})

## Parked cars down Givatayim's streets, half up on the pavement the way they really
## park there: one sedan mesh shared by all of them, each in its own colour.
const PARKED_FILL := 0.26            ## share of the kerb taken
func _build_parked() -> void:
	if String(_place.get("look", "")) != "med":
		return   # northern suburbs park in driveways
	var xf: Array = []
	var cols: Array = []
	var xf_by := {"sedan": [], "hatch": [], "suv": [], "van": []}
	var cols_by := {"sedan": [], "hatch": [], "suv": [], "van": []}
	var palette := _car_paints()
	var rng := RandomNumberGenerator.new()
	for ri: int in _tile_roads.get(_tile, []):
		var r: Dictionary = _roads[ri]
		if not r["drive"] or r["pv"] or not (r["k"] in ["residential", "tertiary", "unclassified", "living_street"]):
			continue
		if _over():
			await _pause()
		rng.seed = hash(_city_name) + 11 + ri * 7919   # the road's own: every square parks it alike
		var hw: float = float(r["w"]) * 0.5
		for run: PackedVector2Array in _street_runs(r):
			var cum := PackedFloat32Array([0.0])
			for i in range(1, run.size()):
				cum.append(cum[i - 1] + run[i - 1].distance_to(run[i]))
			var total := cum[cum.size() - 1]
			for sgn: float in [-1.0, 1.0]:
				var s := 4.0 + rng.randf() * 3.0
				while s < total - 4.0:
					if rng.randf() < PARKED_FILL:
						var kind: String = CAR_MIX[rng.randi() % CAR_MIX.size()]
						var paint: Color = palette[rng.randi() % palette.size()]
						var c := _along(run, cum, s)
						var d := (_along(run, cum, minf(s + 1.0, total)) - c).normalized()
						var side := Vector2(-d.y, d.x) * sgn
						var p := c + side * (hw + 0.6)   # mostly up on the pavement: a third of a car in the road
						var ok := _mine(p) and _push_out(p, 1.0, false) == Vector2.ZERO
						for i: int in _near(_post_hash, p, 1.4, BLD_CELL):
							if _posts[i].distance_to(p) < 1.4:
								ok = false
						var face := d * sgn   # nose with the traffic on its side
						# not poking into the asphalt: near a corner the next street can be
						# right there, and the car stood in its lane
						ok = ok and _off_road(p + face * 1.25, -0.1) and _off_road(p - face * 1.25, -0.1)
						if ok:
							var yaw := atan2(face.x, face.y)
							# with the ground: nose up a hill, leaning across a camber (level, on a
							# slope one end floated and the other sank into the road)
							var lx := Vector2(face.y, -face.x)
							var pitch := atan2(_h(p + face * 1.4) - _h(p - face * 1.4), 2.8)
							var roll := atan2(_h(p + lx * 0.8) - _h(p - lx * 0.8), 1.6)
							var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch) \
								* Basis(Vector3.BACK, roll) * Basis(Vector3.FORWARD, -0.05 * sgn)
							(xf_by[kind] as Array).append(Transform3D(lean, _g3(p, 0.1)))   # half up the kerb
							(cols_by[kind] as Array).append(paint)
							xf.append(0)
							_add_post(p + face * 1.25, 0.85)
							_add_post(p - face * 1.25, 0.85)
					s += 5.6
	_parked_xf = xf_by   # drawn with the car parks' cars, in one set of batches (_build_lots)
	_parked_cols = cols_by
	_tally("parked", xf.size())

## Car parks: OSM's parking areas -- a block's own lot behind its buildings, a supermarket's
## -- laid out in rows of bays along their long side (2.5 m wide, 5 m deep, two rows back to
## front across a 6 m aisle), the bays painted, and about three in four taken. Bays that
## would stick out of the lot, into a building, onto a road or onto a tree are left out.
var _lot_at: Array = []              ## a car in each car park (for tests and tours)
var _parked_xf := {}                 ## the street's parked cars by shape, to batch with the car parks'
var _parked_cols := {}
const LOT_CARS := 6000               ## car-park cars in a whole city, at most: they are a lot to draw
var _lot_cars := 0

func _build_lots() -> void:
	var rings: Array = _rings_near("parking").filter(_ring_mine)
	var palette := _car_paints()
	var rng := RandomNumberGenerator.new()
	var xf_by := {"sedan": [], "hatch": [], "suv": [], "van": []}
	var cols_by := {"sedan": [], "hatch": [], "suv": [], "van": []}
	for kind: String in _parked_xf:   # the street's parked cars go in the same batches
		(xf_by[kind] as Array).append_array(_parked_xf[kind])
		(cols_by[kind] as Array).append_array(_parked_cols[kind])
	_parked_xf = {}
	_parked_cols = {}
	var lines := CBuf.new(GROUND_CELL)
	var cars := 0
	var ly := Y_AREA + 0.012
	for ring: PackedVector2Array in rings:
		var area := _area(ring)
		if area < 120.0 or area > 8000.0:
			continue   # (a mall's or a stadium's acres of tarmac: left empty, it is a lot to draw)
		if _over():
			await _pause()
		rng.seed = _hash_i(ring[0]) + 31
		var n := ring.size()
		var u := Vector2.RIGHT
		var longest := 0.0
		for i in range(n):
			var e := ring[(i + 1) % n] - ring[i]
			if e.length() > longest:
				longest = e.length()
				u = e.normalized()
		var v := Vector2(-u.y, u.x)
		var umin := INF
		var umax := -INF
		var vmin := INF
		var vmax := -INF
		for q in ring:
			umin = minf(umin, q.dot(u))
			umax = maxf(umax, q.dot(u))
			vmin = minf(vmin, q.dot(v))
			vmax = maxf(vmax, q.dot(v))
		var inside := func(q: Vector2) -> bool: return Geometry2D.is_point_in_polygon(q, ring)
		# rows across the lot: [row facing back, aisle, row facing forward], again and again
		var vv := vmin + 0.5
		var row := 0
		var bays := 0
		var taken := 0
		while vv + 5.0 <= vmax - 0.3 and bays < 140:
			if _over():
				await _pause()
			var face := -v if row % 2 == 0 else v   # nose in, away from the aisle
			var uu := umin + 0.6
			var placed_any := false
			while uu + 2.5 <= umax - 0.6 and bays < 140:
				var p := u * (uu + 1.25) + v * (vv + 2.5)
				var ok: bool = inside.call(p + u * 1.15 + v * 2.3) and inside.call(p - u * 1.15 + v * 2.3) \
					and inside.call(p + u * 1.15 - v * 2.3) and inside.call(p - u * 1.15 - v * 2.3)
				ok = ok and _push_out(p, 1.4, false) == Vector2.ZERO and _off_road(p, 1.6) and _clear_of_posts(p, 1.8)
				if ok:
					placed_any = true
					bays += 1
					# the bay's two side lines
					for side: float in [-1.25, 1.25]:
						var a := p + u * side - v * 2.5
						var b := p + u * side + v * 2.5
						lines.quad3(_g3(a - u * 0.05, ly), _g3(b - u * 0.05, ly), _g3(b + u * 0.05, ly), _g3(a + u * 0.05, ly))
					if rng.randf() < 0.66 and taken < 70 and _lot_cars + cars < LOT_CARS:
						taken += 1
						var kind: String = CAR_MIX[rng.randi() % CAR_MIX.size()]
						var f := face.rotated(rng.randf_range(-0.05, 0.05))
						var at := p + u * rng.randf_range(-0.15, 0.15) - face * 0.2
						(xf_by[kind] as Array).append(Transform3D(Basis(Vector3.UP, atan2(f.x, f.y)), _g3(at, 0.02)))
						if taken == 1:
							_lot_at.append(at)
						(cols_by[kind] as Array).append(palette[rng.randi() % palette.size()])
						_add_post(at + f * 1.25, 0.85)
						_add_post(at - f * 1.25, 0.85)
						cars += 1
				uu += 2.5
			vv += 5.0 + (6.0 if row % 2 == 0 else 0.4)   # the aisle after the first row of a pair
			row += 1
	# a car park mapped only by its lanes (OSM: service=parking_aisle, as most blocks' own
	# lots are): a row of bays down each side of each lane
	for ri: int in _tile_roads.get(_tile, []):
		var r: Dictionary = _roads[ri]
		if r.get("sv", "") != "parking_aisle":
			continue
		if _over():
			await _pause()
		rng.seed = hash(_city_name) + 31 + ri * 7919
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5
		var taken := 0
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			if L < 4.0:
				continue
			var d := (b - a) / L
			var nrm := Vector2(-d.y, d.x)
			var s := 2.5
			while s + 1.25 < L - 1.0:
				for sg: float in [-1.0, 1.0]:
					var face := nrm * sg   # nose in, away from the lane
					var p := a + d * s + face * (hw + 2.6)
					if not _mine(p) or _push_out(p, 1.4, false) != Vector2.ZERO or not _off_road(p, 1.2) or not _clear_of_posts(p, 1.8):
						continue
					for side: float in [-1.25, 1.25]:
						var q0 := p + d * side - face * 2.5
						var q1 := p + d * side + face * 2.5
						lines.quad3(_g3(q0 - d * 0.05, ly), _g3(q1 - d * 0.05, ly), _g3(q1 + d * 0.05, ly), _g3(q0 + d * 0.05, ly))
					if rng.randf() < 0.6 and taken < 24 and _lot_cars + cars < LOT_CARS:
						taken += 1
						var kind: String = CAR_MIX[rng.randi() % CAR_MIX.size()]
						var f := face.rotated(rng.randf_range(-0.05, 0.05))
						(xf_by[kind] as Array).append(Transform3D(Basis(Vector3.UP, atan2(f.x, f.y)), _g3(p, 0.02)))
						(cols_by[kind] as Array).append(palette[rng.randi() % palette.size()])
						_add_post(p + f * 1.25, 0.85)
						_add_post(p - f * 1.25, 0.85)
						cars += 1
				s += 2.5
	for kind: String in xf_by:
		if not (xf_by[kind] as Array).is_empty():
			_chunked(_parked_mesh(kind), xf_by[kind], 140.0, cols_by[kind], null, true, true)
	_add_mesh(lines, _surface("mark"), false, DETAIL_RANGE)
	_lot_cars += cars
	_tally("lot_cars", cars)

## car colours as Israeli streets have them (and Canadian ones are not far off): mostly
## white, silver, grey and black, now and then a blue, a red or a beige
func _car_paints() -> Array:
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	var alt := Palette.col("bg_alt")
	var white := ink
	var silver := ink.lerp(alt, 0.32)
	var grey := alt.lerp(ink, 0.22)
	var black := bg.lerp(alt, 0.35)
	var out: Array = [white, white, white, white, silver, silver, silver, grey, grey, black, black,
		Palette.col("player").lerp(bg, 0.55), Palette.col("hazard").lerp(bg, 0.4), Palette.col("warn").lerp(ink, 0.5).lerp(alt, 0.2)]
	return out.map(func(c: Color) -> Color: return _natural(c, 0.6))

## parked cars and traffic: mostly sedans and hatchbacks, some SUVs, the odd van
const CAR_MIX := ["sedan", "sedan", "sedan", "hatch", "hatch", "hatch", "suv", "suv", "van"]

## the shared car mesh for parked cars and traffic: the sedan's body, wheels, lights and
## plates as ONE surface, one draw call a batch (as six surfaces, a patch of parked cars
## cost six). Each part's colour is in its vertex colour, and what it is in the alpha:
## the shader (CAR_SHADER) makes paint take the car's own colour (instance custom data, or
## paint_col on the player's car), and gives every part its own finish: paint a clear coat
## that reflects the sky (more at a glancing look) with dark wheel wells and door seams
## (from the wheels' place in UV2), glass that reflects more, five-spoke rims, number plates
## with their characters, headlights that light at night and tail lights that flare on the
## brake (custom alpha).
const CAR_SHADER := """
shader_type spatial;
uniform float night = 0.0;
uniform vec4 lamp : source_color;
uniform vec4 tail : source_color;
uniform vec4 sky_top : source_color;   // what the paint and glass reflect: the sky as it is now,
uniform vec4 sky_hor : source_color;
uniform vec4 street : source_color;    // and the road below the horizon
uniform vec4 well : source_color;      // a wheel well's dark
uniform float fixed_paint = 0.0;       // 1: paint_col (the player's car), not the copy's own colour
uniform vec4 paint_col : source_color;
uniform float occupied = 0.0;          // the player's car: 1 while the player sits in it
uniform vec4 skin : source_color;      // the people inside: skin, hair, and two shirts to pick from
uniform vec4 hair : source_color;
uniform vec4 shirt_a : source_color;
uniform vec4 shirt_b : source_color;
varying vec4 custom;
varying vec3 lpos;                     // the car's own frame: x across, y up from the road, z forward
varying vec3 lnrm;
varying vec3 lcam;                     // the eye, in that frame
varying float who;                     // a number of the car's own, for its people's looks
void vertex() {
	custom = INSTANCE_CUSTOM;
	lpos = VERTEX;
	lnrm = NORMAL;
	lcam = transpose(mat3(MODEL_MATRIX)) * (CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz);
	who = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}
// where a ray (from o along unit d) first meets an ellipsoid at c with radii r; -1 if not
float ray_blob(vec3 o, vec3 d, vec3 c, vec3 r) {
	vec3 oo = (o - c) / r;
	vec3 dd = d / r;
	float a = dot(dd, dd);
	float b = dot(oo, dd);
	float k = b * b - a * (dot(oo, oo) - 1.0);
	if (k < 0.0) {
		return -1.0;
	}
	return (-b - sqrt(k)) / a;
}
vec3 sky_at(float e) {
	return e > 0.0 ? mix(sky_hor.rgb, sky_top.rgb, smoothstep(0.0, 0.5, e))
		: mix(sky_hor.rgb * 0.8, street.rgb, 1.0 - smoothstep(-0.25, 0.0, e));
}
float line_cover(float d, float w, float aa) {
	return clamp((w - d) / aa + 0.5, 0.0, 1.0);
}
void fragment() {
	float part = COLOR.a;
	vec3 col = COLOR.rgb;
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	vec3 to_eye = normalize(-VERTEX);
	float ndv = clamp(dot(NORMAL, to_eye), 0.0, 1.0);
	vec3 rw = (INV_VIEW_MATRIX * vec4(reflect(-to_eye, NORMAL), 0.0)).xyz;
	vec3 refl = sky_at(rw.y) * (1.0 - 0.75 * night);
	float aa = fwidth(lpos.z) + 0.001;
	if (part > 0.9) {            // paint
		col = fixed_paint > 0.5 ? paint_col.rgb : custom.rgb;
		col *= mix(0.72, 1.0, smoothstep(0.12, 0.55, lpos.y));   // grime, and less light, low down
		float f = 0.05 + 0.55 * pow(1.0 - ndv, 4.0);
		float side = abs(lnrm.x);
		vec2 wd = vec2(abs(lpos.z) - UV2.x, lpos.y - UV2.y);
		if (UV2.y > 0.0 && side > 0.35 && length(wd) < UV2.y + 0.075) {
			col = well.rgb;   // the wheel well round the tyre
			f = 0.0;
			rough = 0.9;
		} else {
			if (UV2.y > 0.0 && side > 0.55 && lpos.y > 0.3) {
				// door seams: behind the front wheel, at the pillar, ahead of the back wheel
				float d = min(min(abs(lpos.z - (UV2.x - UV2.y - 0.14)), abs(lpos.z + 0.19 * UV2.x)),
					abs(lpos.z + UV2.x - UV2.y - 0.1));
				col *= 1.0 - 0.6 * line_cover(d, 0.006, aa);
			}
			rough = 0.3;
			metal = 0.1;
			spec = 0.6;
		}
		emit = refl * f;
	} else if (part > 0.7) {     // glass, and whoever sits behind it
		vec3 inside = vec3(0.0);
		// UV2 on a car's glass: (front seats' z, their cushion's height); traffic's custom
		// alpha 2+ has a driver, 4+ a passenger too (the rest of it is the brake light)
		float occ = fixed_paint > 0.5 ? occupied : floor(custom.a * 0.5);
		if (UV2.y > 0.0 && occ > 0.5) {
			vec3 rd = normalize(lpos - lcam);
			float best = 1e9;
			vec3 col_hit = vec3(0.0);
			vec3 n_hit = vec3(0.0, 1.0, 0.0);
			for (int s = 0; s < 2; s++) {
				if (s == 1 && occ < 1.5) {
					break;
				}
				float x = s == 0 ? 0.36 : -0.36;   // the driver on the car's left (+X)
				vec3 head = vec3(x, UV2.y + 0.6, UV2.x);
				vec3 body = vec3(x, UV2.y + 0.28, UV2.x - 0.05);
				float th = ray_blob(lcam, rd, head, vec3(0.1, 0.12, 0.11));
				if (th > 0.0 && th < best) {
					best = th;
					vec3 hp = lcam + rd * th;
					n_hit = normalize((hp - head) / vec3(0.1, 0.12, 0.11));
					// hair on top and at the back, a face in front
					col_hit = (n_hit.y > 0.35 || n_hit.z < -0.2) ? hair.rgb : skin.rgb;
				}
				float tb = ray_blob(lcam, rd, body, vec3(0.21, 0.24, 0.14));
				if (tb > 0.0 && tb < best) {
					best = tb;
					n_hit = normalize((lcam + rd * tb - body) / vec3(0.21, 0.24, 0.14));
					col_hit = mix(shirt_a.rgb, shirt_b.rgb, fract(who * (s == 0 ? 1.0 : 7.3)));
				}
			}
			// lit dimly from the windows above and the side, the cabin itself dark
			inside = best < 1e8 ? col_hit * (0.22 + 0.25 * max(n_hit.y, 0.0) + 0.1 * abs(n_hit.x)) : vec3(0.02);
			inside *= 1.0 - 0.7 * night;
		}
		float f = 0.12 + 0.88 * pow(1.0 - ndv, 3.0);
		emit = mix(inside, refl, f);
		rough = 0.05;
	} else if (part > 0.6) {     // number plate: a row of dark characters
		float cell = (UV.x - 0.1) / 0.8 * 7.0;
		float ch = step(0.1, UV.x) * step(UV.x, 0.9) * step(0.26, UV.y) * step(UV.y, 0.74)
			* step(0.18, fract(cell)) * step(fract(cell), 0.82);
		col = mix(col, col * 0.08, ch);
		rough = 0.4;
	} else if (part > 0.45) {    // trim
		rough = 0.55;
		emit = refl * 0.05;
	} else if (part > 0.35) {    // a rim: five spokes round the hub, dark between them
		float r = length(UV);
		float sp = cos(atan(UV.y, UV.x) * 5.0);
		bool solid = r < 0.3 || r > 0.84 || sp > 0.35;
		col = solid ? col : well.rgb;
		metal = solid ? 0.7 : 0.0;
		rough = 0.35;
		emit = solid ? refl * 0.25 : vec3(0.0);
	} else if (part > 0.2) {     // tyres
		rough = 0.9;
		spec = 0.2;
	} else if (part > 0.05) {    // headlights (and anything lit like them: a taxi's sign)
		emit = lamp.rgb * night * 2.5 + refl * 0.3;
		rough = 0.1;
	} else {                     // tail lights
		col = tail.rgb;
		emit = tail.rgb * (0.25 + 1.1 * night + 2.8 * (custom.a - floor(custom.a * 0.5) * 2.0));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
}
"""
var _car_shader_mat: ShaderMaterial
var _player_car_mat: ShaderMaterial  ## the same shader on the player's car, its paint its own

func _car_material() -> ShaderMaterial:
	if _car_shader_mat == null:
		_car_shader_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = CAR_SHADER
		_car_shader_mat.shader = sh
	for m: ShaderMaterial in [_car_shader_mat, _player_car_mat]:
		if m == null:
			continue
		m.set_shader_parameter("lamp", _tone["lamplight"])
		m.set_shader_parameter("tail", Palette.col("hazard"))
		m.set_shader_parameter("night", 1.0 if _night else 0.0)
		m.set_shader_parameter("street", _tone["asphalt"])
		m.set_shader_parameter("well", (_tone["tyre"] as Color).darkened(0.55))
		m.set_shader_parameter("skin", _tone["skin"])
		m.set_shader_parameter("hair", _tone["hair"])
		m.set_shader_parameter("shirt_a", _tone["shirt_a"])
		m.set_shader_parameter("shirt_b", _tone["shirt_b"])
		if env != null and env.sky != null:
			var rs := _sky_reflect()
			m.set_shader_parameter("sky_top", rs[0])
			m.set_shader_parameter("sky_hor", rs[1])
		if m == _player_car_mat:
			m.set_shader_parameter("fixed_paint", 1.0)
			m.set_shader_parameter("paint_col", _tone[String(m.get_meta("paint", "paint"))])
			m.set_shader_parameter("occupied", 0.0 if _walking else 1.0)
	return _car_shader_mat

var _car_meshes := {}

func _parked_mesh(kind := "sedan") -> ArrayMesh:
	if _car_meshes.has(kind):
		return _car_meshes[kind]
	if kind == "bus":
		return _bus_mesh()
	if kind == "moto":
		return _moto_mesh()
	if kind == "truck":
		return _truck_mesh()
	var taxi := kind == "taxi"
	var cm := _car_body("sedan" if taxi else kind, true)
	if taxi:
		# the roof sign: lit like a headlight, so it glows at night
		var sign := Buf.new()
		_box(sign, Vector3(0, 1.52, -0.3), Vector3(0.62, 0.17, 0.26))
		cm.add_buf(sign, Color(Palette.col("warn"), 0.1))
	var am := cm.mesh(_car_material())
	# a box round the whole car (lights and mirrors stand a little proud of the body)
	am.custom_aabb = am.get_aabb().grow(0.1)
	_car_meshes[kind] = am
	return am

## ---- car bodies ----------------------------------------------------------------------------
## A car is built from its side profile (CAR_SHAPES) as two lofts with smooth normals. The
## lower body is a rounded cross-section at each of a run of stations from the back to the
## front, between the outline's bottom (the sills, the bumpers' curve) and its top (boot,
## waist, bonnet), narrowing at the corners in plan; the cabin is a second loft from the
## waist to the roof line, the windscreen and rear window its sloped ends, the pillars and the
## roof rail in paint. So the light rolls over the shoulders, the bonnet and the roof instead
## of breaking at flat sides. One indexed surface per car shape: each part (paint, glass,
## trim, tyres, rims, lights, plates) is told apart by its vertex colour's alpha, for
## CAR_SHADER, and the lower body's UV2 carries the wheels' place and size so the shader can
## darken the wheel wells and draw the door seams.
const CAR_CORNER := 0.45             ## the plan's corner radius, front and back (m)

class CarMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, col: Color, t := Vector2.ZERO, t2 := Vector2.ZERO) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	## a triangle facing `out` (Godot's front faces are clockwise: the winding is fixed to match)
	func tri(a: int, b: int, d: int, out: Vector3) -> void:
		if (v[b] - v[a]).cross(v[d] - v[a]).dot(out) > 0.0:
			idx.append_array([a, d, b])
		else:
			idx.append_array([a, b, d])

	## a Buf's triangle soup as it is, in one colour (boxes: lights, trim)
	func add_buf(b: Buf, col: Color, t2 := Vector2.ZERO) -> void:
		for i in range(b.v.size()):
			idx.append(vert(b.v[i], b.n[i], col, b.uv[i] if i < b.uv.size() else Vector2.ZERO, t2))

	func mesh(m: Material) -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(0, m)
		return am

## the side outline cut straight down at z: (its bottom, its top)
func _span_at(outline: PackedVector2Array, z: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if a.x == b.x or (a.x - z) * (b.x - z) > 0.0:
			continue
		var y := lerpf(a.y, b.y, (z - a.x) / (b.x - a.x))
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(lo, hi) if lo <= hi else Vector2(0.5, 0.5)

## the side outline cut across at height y: its front (or back) end
func _end_at(outline: PackedVector2Array, y: float, front: bool) -> float:
	var best := -INF if front else INF
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if a.y == b.y or (a.y - y) * (b.y - y) > 0.0:
			continue
		var z := lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
		best = maxf(best, z) if front else minf(best, z)
	return best

## the body's half-width at z: full along the sides, rounding off at the four corners
func _plan_w(z: float, hw: float, hl: float) -> float:
	var d := absf(z) - (hl - CAR_CORNER)
	if d <= 0.0:
		return hw
	return hw - CAR_CORNER + sqrt(maxf(CAR_CORNER * CAR_CORNER - d * d, 0.0))

## how far the rounded corner pulls the front (or back) in at x off the middle
func _plan_in(x: float, hw: float) -> float:
	var d := absf(x) - (hw - CAR_CORNER)
	if d <= 0.0:
		return 0.0
	return CAR_CORNER - sqrt(maxf(CAR_CORNER * CAR_CORNER - d * d, 0.0))

## A loft through rings of points (one per station, the same count each), normals smoothed
## over the grid and turned away from each station's middle; `part.call(i, j)` colours the
## quad from station i, ring point j. A vertex is shared by the quads of one part only, so
## glass and paint keep their own edges.
func _loft(cm: CarMesh, rings: Array, mids: PackedVector3Array, closed: bool, part: Callable, t2: Vector2,
		glass_t2 := Vector2.ZERO) -> void:
	var count := rings.size()
	var m: int = (rings[0] as PackedVector3Array).size()
	var nrm: Array = []
	for i in range(count):
		var ring: PackedVector3Array = rings[i]
		var prev: PackedVector3Array = rings[maxi(i - 1, 0)]
		var next: PackedVector3Array = rings[mini(i + 1, count - 1)]
		var nr := PackedVector3Array()
		for j in range(m):
			var jp := (j + 1) % m if closed else mini(j + 1, m - 1)
			var jm := (j - 1 + m) % m if closed else maxi(j - 1, 0)
			var nn := (ring[jp] - ring[jm]).cross(next[j] - prev[j])
			if nn.length_squared() < 1e-12:
				nn = ring[j] - mids[i]
			nn = nn.normalized()
			if nn.dot(ring[j] - mids[i]) < 0.0:
				nn = -nn
			nr.append(nn)
		nrm.append(nr)
	var made := {}
	for i in range(count - 1):
		for j in range(m if closed else m - 1):
			var j1 := (j + 1) % m
			var col: Color = part.call(i, j)
			var pid := int(round(col.a * 100.0))
			var q: Array = []
			for ij: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j1), Vector2i(i, j1)]:
				var key := (ij.x * 1000 + ij.y) * 1000 + pid
				if not made.has(key):
					made[key] = cm.vert((rings[ij.x] as PackedVector3Array)[ij.y], (nrm[ij.x] as PackedVector3Array)[ij.y], col, Vector2.ZERO,
						glass_t2 if pid == 75 else t2)
				q.append(made[key])
			var out: Vector3 = ((rings[i] as PackedVector3Array)[j] + (rings[i + 1] as PackedVector3Array)[j1]) * 0.5 - (mids[i] + mids[i + 1]) * 0.5
			cm.tri(q[0], q[1], q[2], out)
			cm.tri(q[0], q[2], q[3], out)

## A car body of a CAR_SHAPES kind, facing +Z, its wheels on y = 0. `extras`: the wheels,
## lights and number plates too (the player's car has its own, which turn and light up).
func _car_body(kind: String, extras: bool) -> CarMesh:
	var shape: Array = CAR_SHAPES[kind]
	var low := PackedVector2Array(shape[0])
	var cab: Array = shape[1]
	var hw: float = shape[2]
	var hl: float = shape[3]
	var wz: float = shape[4]
	var wr: float = shape[5]
	var lift := 0.08 if kind in ["suv", "van"] else (0.12 if kind == "truck" else 0.0)
	var cm := CarMesh.new()
	var paint := Color(1, 1, 1, 1.0)
	var glass := Color(_tone["carglass"], 0.75)
	var trim := Color(_tone["cartrim"], 0.5)
	var wheels := Vector2(wz, wr)
	var zmin := INF
	var zmax := -INF
	for p in low:
		zmin = minf(zmin, p.x)
		zmax = maxf(zmax, p.x)
	# ---- the lower body: 16 stations, closer together toward the ends where it curves
	var rings: Array = []
	var mids := PackedVector3Array()
	var stations := 16
	for i in range(stations):
		var z := lerpf(zmin + 0.004, zmax - 0.004, 0.5 - 0.5 * cos(PI * i / (stations - 1)))
		var sp := _span_at(low, z)
		var yb := sp.x
		var yt := sp.y
		var h := maxf(yt - yb, 0.001)
		var w := _plan_w(z, hw, hl)
		var half: Array = [Vector2(0.0, yb), Vector2(w - 0.12, yb), Vector2(w - 0.03, yb + minf(0.07, h * 0.25)),
			Vector2(w, yb + h * 0.45), Vector2(w - 0.025, yt - minf(0.09, h * 0.25)),
			Vector2(w - 0.09, yt - minf(0.012, h * 0.05)), Vector2(w * 0.55, yt + 0.025), Vector2(0.0, yt + 0.035)]
		var ring := PackedVector3Array()
		for p: Vector2 in half:
			ring.append(Vector3(p.x, p.y, z))
		for k in range(half.size() - 2, 0, -1):
			ring.append(Vector3(-(half[k] as Vector2).x, (half[k] as Vector2).y, z))
		rings.append(ring)
		mids.append(Vector3(0.0, (yb + yt) * 0.5, z))
	_loft(cm, rings, mids, true, func(_i: int, _j: int) -> Color: return paint, wheels)
	# ---- the cabin, from the waist to the roof line
	var c0: Vector2 = cab[0]   # windscreen foot
	var c1: Vector2 = cab[1]   # windscreen top
	var c2: Vector2 = cab[2]   # rear top
	var c3: Vector2 = cab[3]   # rear foot
	var pillars: Array = [-0.26] if kind in ["sedan", "hatch"] else [-0.2, -1.25]
	var zs: Array = []
	for k in range(9):
		zs.append(lerpf(c3.x, c0.x, k / 8.0))
	zs.append_array([c1.x, c2.x])
	for pz: float in pillars:
		zs.append_array([pz - 0.06, pz + 0.06])
	var back_pillar := c2.x + 0.05 if kind in ["sedan", "hatch"] else c3.x + 0.18
	zs.append(back_pillar)
	zs.sort()
	var cz: Array = []
	for z: float in zs:
		if cz.is_empty() or z - float(cz[-1]) > 0.01:
			cz.append(clampf(z, c3.x, c0.x))
	var roof := func(z: float) -> float:
		if z >= c1.x:
			return lerpf(c1.y, c0.y, inverse_lerp(c1.x, c0.x, z))
		if z >= c2.x:
			return lerpf(c2.y, c1.y, inverse_lerp(c2.x, c1.x, z))
		return lerpf(c3.y, c2.y, inverse_lerp(c3.x, c2.x, z))
	rings = []
	mids = PackedVector3Array()
	for z: float in cz:
		var yb := _span_at(low, z).y
		var top := maxf(float(roof.call(z)), yb + 0.004)
		var w := _plan_w(z, hw, hl)
		var wb := w - 0.05
		var wt := w - 0.27
		var gh: Array = [Vector2(wb, yb - 0.01), Vector2(wt, maxf(yb, top - 0.05)), Vector2(wt - 0.07, top), Vector2(0.0, top + 0.02)]
		var ring := PackedVector3Array()
		for p: Vector2 in gh:
			ring.append(Vector3(p.x, p.y, z))
		for k in range(gh.size() - 2, -1, -1):
			ring.append(Vector3(-(gh[k] as Vector2).x, (gh[k] as Vector2).y, z))
		rings.append(ring)
		mids.append(Vector3(0.0, yb - 0.3, z))
	var cab_part := func(i: int, j: int) -> Color:
		var zc := (float(cz[i]) + float(cz[i + 1])) * 0.5
		if j == 1 or j == 4:
			return paint                      # the roof rail, the A- and C-pillars' edges
		if j == 2 or j == 3:
			return glass if (zc > c1.x or zc < c2.x) else paint   # windscreen, rear window / roof
		if zc < back_pillar:
			return paint
		for pz: float in pillars:
			if absf(zc - pz) < 0.06:
				return paint                  # the B-pillar (an SUV's and a van's C too)
		return glass
	# the glass carries where the front seats are -- just behind the windscreen's foot, the
	# cushion a little under the waist -- for the shader's people
	var seats := Vector2(c0.x - (0.75 if kind == "truck" else (1.3 if kind in ["suv", "van"] else 1.15)), _span_at(low, c0.x).y - 0.45)
	_loft(cm, rings, mids, false, cab_part, Vector2.ZERO, seats)
	# ---- trim: bumper lips, the grille, mirrors, door handles
	var tb := Buf.new()
	var zf := _end_at(low, 0.4 + lift, true)
	var zr := _end_at(low, 0.4 + lift, false)
	_box(tb, Vector3(0, 0.32 + lift, zf - 0.07), Vector3((hw - 0.2) * 2.0, 0.1, 0.16))
	_box(tb, Vector3(0, 0.32 + lift, zr + 0.07), Vector3((hw - 0.2) * 2.0, 0.1, 0.16))
	var gy := 0.58 + lift
	_box(tb, Vector3(0, gy, _end_at(low, gy, true) - 0.025), Vector3(0.72, 0.13, 0.06))
	for sx: float in [-1.0, 1.0]:
		for hz: float in ([c0.x - 0.42] if kind == "truck" else [c0.x - 0.42, float(pillars[0]) - 0.4]):
			var hy := _span_at(low, hz).y - 0.11
			_box(tb, Vector3(sx * (_plan_w(hz, hw, hl) + 0.004), hy, hz), Vector3(0.02, 0.035, 0.15))
	cm.add_buf(tb, trim)
	var mb := Buf.new()
	for sx: float in [-1.0, 1.0]:
		_box(mb, Vector3(sx * (hw + 0.07), c0.y + 0.08, c0.x - 0.14), Vector3(0.15, 0.1, 0.08))
	cm.add_buf(mb, paint)
	if not extras:
		return cm
	# ---- wheels: tyres, their sidewalls, five-spoke rims (just proud of the body, in the
	# dark wells the shader paints round them)
	var tyre := Color(_tone["tyre"], 0.3)
	var rim := Color(_tone["rim"], 0.4)
	for wzs: float in [wz, -wz]:
		for sx: float in [-1.0, 1.0]:
			_wheel(cm, Vector3(sx * (hw - 0.09), wr, wzs), wr, sx, tyre, rim)
	# ---- lights: panels laid on the body's front and back, following its rounded corners
	var hy := 0.68 + lift
	var ty := _span_at(low, zmin + 0.12).y - 0.15
	for sx: float in [-1.0, 1.0]:
		_lamp(cm, low, hw, sx * (hw - 0.3), hy, 0.36, 0.12, true, Color(_tone["tank"], 0.1))
		_lamp(cm, low, hw, sx * (hw - 0.27), ty, 0.32, 0.14, false, Color(_tone["tank"], 0.0))
	var plate := Color(Palette.col("warn") if String(_place.get("look", "")) == "med" else Palette.col("ink"), 0.65)
	for front: bool in [true, false]:
		var py := (0.45 if front else 0.6) + lift
		var pz := _end_at(low, py, front) + (0.012 if front else -0.012)
		var s := 1.0 if front else -1.0
		var a := cm.vert(Vector3(-0.26 * s, py - 0.06, pz), Vector3(0, 0, s), plate, Vector2(0, 1))
		var b := cm.vert(Vector3(0.26 * s, py - 0.06, pz), Vector3(0, 0, s), plate, Vector2(1, 1))
		var d := cm.vert(Vector3(0.26 * s, py + 0.06, pz), Vector3(0, 0, s), plate, Vector2(1, 0))
		var e := cm.vert(Vector3(-0.26 * s, py + 0.06, pz), Vector3(0, 0, s), plate, Vector2(0, 0))
		cm.tri(a, b, d, Vector3(0, 0, s))
		cm.tri(a, d, e, Vector3(0, 0, s))
	return cm

## a light panel w x h centred at (cx, cy) on the body's front (or back), each corner set on
## the rounded surface (a hair proud of it), so it bends round the corner as real ones do
func _lamp(cm: CarMesh, low: PackedVector2Array, hw: float, cx: float, cy: float, w: float, h: float, front: bool, col: Color) -> void:
	var s := 1.0 if front else -1.0
	var grid: Array = []
	for row in range(2):
		var y := cy + (float(row) - 0.5) * h
		var line: Array = []
		for k in range(3):
			var x := cx + (float(k) - 1.0) * w * 0.5
			var z := _end_at(low, y, front) - s * (_plan_in(x, hw) - 0.008)
			var nrm := Vector3(x / hw * 0.7, 0.1, s).normalized()
			line.append(cm.vert(Vector3(x, y, z), nrm, col))
		grid.append(line)
	var out := Vector3(cx / hw * 0.7, 0.1, s)
	for k in range(2):
		cm.tri(grid[0][k], grid[0][k + 1], grid[1][k + 1], out)
		cm.tri(grid[0][k], grid[1][k + 1], grid[1][k], out)

## a tyre round the X axis at c, its outer side facing `side` (+1/-1): tread, sidewall, and the
## rim (UV: the disc's own -1..1, for the shader's spokes)
func _wheel(cm: CarMesh, c: Vector3, r: float, side: float, tyre: Color, rim: Color, half := 0.11,
		both := false) -> void:
	var seg := 10
	var rr := r * 0.62
	var out := Vector3(side, 0, 0)
	var tread: Array = []
	for k in range(seg + 1):
		var a := TAU * k / seg
		var dir := Vector3(0, cos(a), sin(a))
		tread.append([cm.vert(c + dir * r - out * half, dir, tyre), cm.vert(c + dir * r + out * half, dir, tyre),
			cm.vert(c + dir * r + out * half, out, tyre), cm.vert(c + dir * rr + out * half, out, tyre)])
	for k in range(seg):
		var a0: Array = tread[k]
		var a1: Array = tread[k + 1]
		var dir := Vector3(0, cos(TAU * (k + 0.5) / seg), sin(TAU * (k + 0.5) / seg))
		cm.tri(a0[0], a1[0], a1[1], dir)
		cm.tri(a0[0], a1[1], a0[1], dir)
		cm.tri(a0[2], a1[2], a1[3], out)
		cm.tri(a0[2], a1[3], a0[3], out)
	for o: Vector3 in ([out, -out] if both else [out]):
		var hub := cm.vert(c + o * (half - 0.004), o, rim, Vector2.ZERO)
		var ring: Array = []
		for k in range(seg + 1):
			var a := TAU * k / seg
			ring.append(cm.vert(c + Vector3(0, cos(a), sin(a)) * rr + o * (half - 0.004), o, rim, Vector2(cos(a), sin(a))))
		for k in range(seg):
			cm.tri(hub, ring[k], ring[k + 1], o)
		if both and o == -out:   # the far side's sidewall too (a scooter is seen from both)
			for k in range(seg):
				var a0 := TAU * k / seg
				var a1 := TAU * (k + 1) / seg
				var p0 := cm.vert(c + Vector3(0, cos(a0), sin(a0)) * r + o * half, o, tyre)
				var p1 := cm.vert(c + Vector3(0, cos(a1), sin(a1)) * r + o * half, o, tyre)
				var q0 := cm.vert(c + Vector3(0, cos(a0), sin(a0)) * rr + o * half, o, tyre)
				var q1 := cm.vert(c + Vector3(0, cos(a1), sin(a1)) * rr + o * half, o, tyre)
				cm.tri(p0, p1, q1, o)
				cm.tri(p0, q1, q0, o)

## parts [Buf, colour with the part code in alpha] as one surface in the car shader
func _car_parts_mesh(parts: Array) -> ArrayMesh:
	var one := Buf.new()
	for pair: Array in parts:
		var b: Buf = pair[0]
		one.v.append_array(b.v)
		one.n.append_array(b.n)
		one.uv.append_array(b.uv)
		one.uv2.append_array(b.uv2)
		for _i in range(b.v.size()):
			one.c.append(pair[1])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, one.arrays())
	am.surface_set_material(0, _car_material())
	return am

## A city bus, 11.8 m: a rounded box -- the body in its colour below and above a band of
## windows all round, pillars between them, a big windscreen with the lit route sign over
## it, glazed doors on the kerb side (the car's -X), the air-conditioning box on the roof,
## the wheels in dark wells. One loft like the cars' (see _car_body), its ends flat faces
## in bands. Faces +Z.
func _bus_mesh() -> ArrayMesh:
	var cm := CarMesh.new()
	var hw := 1.25
	var hl := 5.9
	var rc := 0.3                       # the plan's corner radius
	var paint := Color(1, 1, 1, 1.0)
	var glass := Color(_tone["carglass"], 0.75)
	var trim := Color(_tone["cartrim"], 0.5)
	var wheels := Vector2(3.0, 0.5)     # (both axles' |z|, wheel radius): the wells
	var ys: Array = [0.32, 0.42, 1.0, 2.55, 2.9, 3.05]   # bottom, sill, window foot, top, roof edge, roof
	var pillars: Array = []
	for i in range(9):
		pillars.append(-hl + 0.7 + i * 1.32)
	var doors: Array = [Vector2(3.65, 4.85), Vector2(-0.9, 0.35)]
	var zs: Array = []
	for d: float in [0.0, 0.04, 0.1, 0.18, 0.3]:
		zs.append_array([-hl + d, hl - d])
	for pz: float in pillars:
		zs.append_array([pz - 0.06, pz + 0.06])
	for dz: Vector2 in doors:
		zs.append_array([dz.x, dz.y])
	zs.append_array([-hl + 0.6, hl - 0.6])
	zs.sort()
	var st: Array = []
	for z: float in zs:
		if st.is_empty() or z - float(st[-1]) > 0.01:
			st.append(z)
	var rings: Array = []
	var mids := PackedVector3Array()
	for z: float in st:
		var d := absf(z) - (hl - rc)
		var w := hw if d <= 0.0 else hw - rc + sqrt(maxf(rc * rc - d * d, 0.0))
		var half: Array = [Vector2(0.0, ys[0]), Vector2(w - 0.08, ys[0]), Vector2(w, ys[1]), Vector2(w, ys[2]),
			Vector2(w, ys[3]), Vector2(w, ys[4]), Vector2(w - 0.15, ys[5]), Vector2(0.0, float(ys[5]) + 0.02)]
		var ring := PackedVector3Array()
		for p: Vector2 in half:
			ring.append(Vector3(p.x, p.y, z))
		for k in range(half.size() - 2, 0, -1):
			ring.append(Vector3(-(half[k] as Vector2).x, (half[k] as Vector2).y, z))
		rings.append(ring)
		mids.append(Vector3(0.0, 1.6, z))
	var part := func(i: int, j: int) -> Color:
		var zc := (float(st[i]) + float(st[i + 1])) * 0.5
		var kerb := j >= 7
		var band := j if j < 7 else 13 - j   # the same band on either side
		for dz: Vector2 in doors:
			if kerb and zc > dz.x and zc < dz.y and (band == 2 or band == 3):
				return glass                  # the doors, glazed top to bottom
		if band == 3:
			if absf(zc) > hl - 0.45:
				return paint                  # the corners
			for pz: float in pillars:
				if absf(zc - pz) < 0.06:
					return paint
			return glass
		return trim if band <= 1 else paint
	_loft(cm, rings, mids, true, part, wheels)
	# the two ends: flat faces in bands -- bumper, panel, windscreen (rear window), route sign
	for front: bool in [true, false]:
		var z := hl if front else -hl
		var s := 1.0 if front else -1.0
		var w := hw - rc
		var bands: Array = [[ys[0], ys[1], trim], [ys[1], ys[2], paint], [ys[2], ys[3], glass],
			[ys[3], ys[4], Color(Palette.col("warn"), 0.1) if front else paint], [ys[4], ys[5], paint]]
		for b: Array in bands:
			var y0: float = b[0]
			var y1: float = b[1]
			var w0 := w - (0.08 if y0 <= float(ys[0]) else 0.0)
			var w1 := w - (0.15 if y1 >= float(ys[5]) else 0.0)
			var a := cm.vert(Vector3(-w0, y0, z), Vector3(0, 0, s), b[2])
			var bb := cm.vert(Vector3(w0, y0, z), Vector3(0, 0, s), b[2])
			var c := cm.vert(Vector3(w1, y1, z), Vector3(0, 0, s), b[2])
			var e := cm.vert(Vector3(-w1, y1, z), Vector3(0, 0, s), b[2])
			cm.tri(a, bb, c, Vector3(0, 0, s))
			cm.tri(a, c, e, Vector3(0, 0, s))
	# the roof's air conditioning, the mirrors on their arms
	var tb := Buf.new()
	_box(tb, Vector3(0, 3.2, -1.2), Vector3(1.6, 0.26, 2.8))
	for sx: float in [-1.0, 1.0]:
		_box(tb, Vector3(sx * (hw + 0.12), 2.15, hl - 0.25), Vector3(0.06, 0.4, 0.1))
	cm.add_buf(tb, trim)
	# lights low on the front, tall ones at the back; a plate
	var lamps := Buf.new()
	var tails := Buf.new()
	for sx: float in [-1.0, 1.0]:
		_box(lamps, Vector3(sx * (hw - 0.45), 0.62, hl + 0.01), Vector3(0.36, 0.14, 0.03))
		_box(tails, Vector3(sx * (hw - 0.22), 1.0, -hl - 0.01), Vector3(0.2, 0.42, 0.03))
	cm.add_buf(lamps, Color(_tone["tank"], 0.1))
	cm.add_buf(tails, Color(_tone["tank"], 0.0))
	for wz: float in [wheels.x, -wheels.x]:
		for sx: float in [-1.0, 1.0]:
			_wheel(cm, Vector3(sx * (hw - 0.2), wheels.y, wz), wheels.y, sx, Color(_tone["tyre"], 0.3), Color(_tone["rim"], 0.4), 0.16)
	var am := cm.mesh(_car_material())
	am.custom_aabb = am.get_aabb().grow(0.1)
	_car_meshes["bus"] = am
	return am

## A scooter and its rider, 1.9 m, made of rounded pieces: two small spoked wheels, the
## body and the leg shield in its colour, a dark seat and floorboard, the handlebars, a lamp
## at each end; the rider in a dark jacket and trousers, arms out to the bars, a helmet
## with its visor. Faces +Z.
func _moto_mesh() -> ArrayMesh:
	var cm := CarMesh.new()
	var paint := Color(1, 1, 1, 1.0)
	var trim := Color(_tone["cartrim"], 0.5)
	var jacket := Color(_tone["cartrim"].lerp(_tone["carglass"], 0.3), 0.5)
	var legs := Color(_tone["cartrim"].darkened(0.2), 0.5)
	var helmet := Color(_tone["mark"], 0.5)
	for wz: float in [0.62, -0.62]:
		_wheel(cm, Vector3(0, 0.25, wz), 0.25, 1.0, Color(_tone["tyre"], 0.3), Color(_tone["rim"], 0.4), 0.05, true)
	_blobm(cm, Vector3(0, 0.55, -0.32), Vector3(0.2, 0.2, 0.5), paint)            # the body over the back wheel
	_blobm(cm, Vector3(0, 0.62, 0.42), Vector3(0.22, 0.32, 0.07), paint)          # the leg shield
	_blobm(cm, Vector3(0, 0.44, 0.63), Vector3(0.08, 0.05, 0.2), paint)           # the front mudguard
	_blobm(cm, Vector3(0, 0.77, -0.3), Vector3(0.16, 0.06, 0.38), trim)           # the seat
	var tb := Buf.new()
	_box(tb, Vector3(0, 0.36, 0.08), Vector3(0.32, 0.06, 0.52))                   # the floorboard
	_box(tb, Vector3(0, 0.86, 0.5), Vector3(0.05, 0.46, 0.05))                    # the column
	_box(tb, Vector3(0, 1.08, 0.48), Vector3(0.62, 0.04, 0.04))                   # the bars
	cm.add_buf(tb, trim)
	_blobm(cm, Vector3(0, 0.98, 0.57), Vector3(0.07, 0.06, 0.03), Color(_tone["tank"], 0.1), 8, 4)
	_blobm(cm, Vector3(0, 0.62, -0.84), Vector3(0.07, 0.04, 0.03), Color(_tone["tank"], 0.0), 8, 4)
	# the rider, leaning a little to the bars: a torso, arms bent at the elbow, knees up
	_limb(cm, Vector3(0, 0.98, -0.22), Vector3(0, 1.5, -0.06), 0.16, jacket)
	for sx: float in [-1.0, 1.0]:
		var shoulder := Vector3(sx * 0.18, 1.42, -0.07)
		var elbow := Vector3(sx * 0.26, 1.2, 0.17)
		var hand := Vector3(sx * 0.3, 1.1, 0.45)
		_limb(cm, shoulder, elbow, 0.06, jacket)
		_limb(cm, elbow, hand, 0.05, jacket)
		var hip := Vector3(sx * 0.11, 0.9, -0.2)
		var knee := Vector3(sx * 0.15, 0.93, 0.2)
		var foot := Vector3(sx * 0.14, 0.42, 0.2)
		_limb(cm, hip, knee, 0.08, legs)
		_limb(cm, knee, foot, 0.065, legs)
	_blobm(cm, Vector3(0, 1.66, 0.0), Vector3(0.13, 0.14, 0.14), helmet)          # the helmet
	_blobm(cm, Vector3(0, 1.64, 0.1), Vector3(0.1, 0.055, 0.06), Color(_tone["carglass"], 0.75), 8, 4)   # its visor
	var am := cm.mesh(_car_material())
	am.custom_aabb = am.get_aabb().grow(0.1)
	_car_meshes["moto"] = am
	return am

## A delivery truck, 6.8 m: a van's cab (CAR_SHAPES "truck", built like the cars) with a
## tall white box behind it, its back doors' seam and hinges. Faces +Z.
func _truck_mesh() -> ArrayMesh:
	var cm := _car_body("truck", true)
	var box := Buf.new()
	_box(box, Vector3(0, 2.13, -0.98), Vector3(2.3, 2.36, 4.8))
	cm.add_buf(box, Color(_tone["tank"], 0.5))
	var seam := Buf.new()
	_box(seam, Vector3(0, 2.13, -3.385), Vector3(0.03, 2.2, 0.02))
	for sx: float in [-1.0, 1.0]:
		for hy: float in [1.3, 2.9]:
			_box(seam, Vector3(sx * 1.05, hy, -3.385), Vector3(0.1, 0.06, 0.02))
	cm.add_buf(seam, Color(_tone["cartrim"], 0.5))
	var am := cm.mesh(_car_material())
	am.custom_aabb = am.get_aabb().grow(0.1)
	_car_meshes["truck"] = am
	return am

## a limb from a to b: a long rounded piece, `rad` thick
func _limb(cm: CarMesh, a: Vector3, b: Vector3, rad: float, col: Color) -> void:
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	_blobm(cm, (a + b) * 0.5, Vector3(rad, a.distance_to(b) * 0.5 + rad * 0.6, rad), col, 8, 5, Basis(side, up, fwd))

## a rounded blob (an ellipsoid at c with radii r, turned by `turn`), smooth, in one colour
func _blobm(cm: CarMesh, c: Vector3, r: Vector3, col: Color, seg := 10, rings := 6, turn := Basis()) -> void:
	var first := cm.v.size()
	for i in range(rings + 1):
		var th := PI * i / rings
		for j in range(seg + 1):
			var ph := TAU * j / seg
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			cm.vert(c + turn * (u * r), (turn * (u / r)).normalized(), col)
	for i in range(rings):
		for j in range(seg):
			var a := first + i * (seg + 1) + j
			var b := a + seg + 1
			var out: Vector3 = (cm.v[a] + cm.v[b + 1]) * 0.5 - c
			cm.tri(a, b, b + 1, out)
			cm.tri(a, b + 1, a + 1, out)

## a low cylinder lying along x (a wheel)
func _cyl_x(buf: Buf, c: Vector3, r: float, w: float, seg: int) -> void:
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(0, cos(a0) * r, sin(a0) * r)
		var p1 := Vector3(0, cos(a1) * r, sin(a1) * r)
		var hx := Vector3(w * 0.5, 0, 0)
		var nrm := Vector3(0, cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5))
		buf.tri(c + p0 - hx, c + p1 - hx, c + p1 + hx, nrm, Color.WHITE)
		buf.tri(c + p0 - hx, c + p1 + hx, c + p0 + hx, nrm, Color.WHITE)
		buf.tri(c - hx, c + p0 - hx, c + p1 - hx, Vector3.LEFT, Color.WHITE)
		buf.tri(c + hx, c + p0 + hx, c + p1 + hx, Vector3.RIGHT, Color.WHITE)

## a palm's crown: nine drooping fronds, one mesh
## many copies of one mesh, one MultiMeshInstance3D per square so far ones are not drawn,
## each drawn while the camera is within `range_end` of it. A multimesh is drawn whole or
## not at all, judged by the middle of its box, so the squares are sized to the range:
## 400 m squares for things seen 160 m off drew every parked car in a whole square, and
## none at all from near a corner of one. Optional per-copy colours. Shadows only where
## asked: the shadow map draws every caster again.
## ---- batching: the small things merged ---------------------------------------------------
## A street has dozens of kinds of small things -- sign plates and poles, lamp posts, power
## poles, racks, benches, balconies -- and as a multimesh each, every kind cost a draw call
## in every square of the map in view: hundreds in all. While the city is built, every
## kind that shares a material (most share one of a few: the poles' grey, the one vertex-
## coloured "kit" material) is instead copied, transformed, into ONE mesh per square per
## material and draw range. The copying is the engine's: a Transform3D times a packed array
## of vertices is a single call. Left out: whatever changes at night or moves (lamps, lit
## glass, flags, ads, the cars) and anything so numerous that copying it would be a lot of
## memory (the trees), which stay multimeshes.
var _batching := false
var _batches := {}
var _soups := {}
const BATCH_CELL := 400.0
const BATCH_RANGES := [140.0, 200.0, 270.0, 340.0, 460.0, 700.0, 1150.0]
const BATCH_VERTS := 650000          ## more than this in one call: left as a multimesh (trees, balconies)

## ONE material for every merged mesh: a vertex either carries its colour (alpha 1: signs,
## kits, balconies) or the number of a tone of the palette (alpha 0, the number in red),
## looked up in a table the material holds -- so the asphalt, the grass, the poles and the
## paint of a square are one mesh and one draw, and a new palette is a new table.
## Each tone also has a surface (tone_fx: x patches, y grain, z slab size, w kind): grass
## mottled, asphalt grained and worn in patches, pavements in slabs. The big patches are
## worked out per pixel from the world position; the fine part is a photo (textures/, CC0
## from Poly Haven) for each kind -- asphalt, pavers, grass -- with its bumps. A photo is
## divided by its own average colour and multiplied by the tone, so the palette still sets
## the colour and the photo only adds the grit, cracks and joints. textured = 0 falls back
## to the cheap noise grain (the lowest web quality level).
const TONE_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 tones[64] : source_color;
uniform vec4 tone_fx[64];
uniform float textured = 1.0;
uniform sampler2D asph_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asph_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asph_big : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pave_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pave_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 asph_mean = vec3(0.5);   // each photo's average, as stored (TEX_MEAN)
uniform vec3 big_mean = vec3(0.5);
uniform vec3 pave_mean = vec3(0.5);
uniform vec3 grass_mean = vec3(0.5);
uniform float pave_m = 2.0;            // metres one pave_tex covers, for the pavement's slab size
uniform vec3 wear_col = vec3(0.3);     // what worn road paint shows through: the asphalt
varying vec3 wpos;
varying float wup;                     // how much the face looks up: the photos are laid from above
// a photo's colour over its average: 1 on average, so the tone underneath keeps its colour
vec3 detail(vec3 t, vec3 mean, float k) { return mix(vec3(1.0), clamp(t / max(mean, vec3(0.002)), vec3(0.0), vec3(2.6)), k); }
// a normal map's (x, y), reconstructed to a unit normal: the compressed maps keep only x and y
vec3 unpack(vec2 rg, float k) {
	vec2 xy = (rg * 2.0 - 1.0) * k;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wup = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}
// A tired road crazes into small plates: where a noise says this stretch is old, the edges
// of a Voronoi pattern 45 cm across, a hairline as wide as a pixel allows. 1 where there is
// no crack, darker on one. Only near the eye: further off it is less than a pixel.
float crazing(vec2 p, float dist, float pxw) {
	float tired = smoothstep(0.7, 0.84, noise(p / 9.0 + 3.7)) * (1.0 - smoothstep(30.0, 55.0, dist));
	if (tired <= 0.0) {
		return 1.0;
	}
	vec2 gq = p / 0.45;
	vec2 gi = floor(gq);
	vec2 gf = gq - gi;
	float d1 = 9.0;
	float d2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 pt = o + vec2(hash(gi + o), hash(gi + o + 17.3)) * 0.9 + 0.05;
			float dd = length(gf - pt);
			if (dd < d1) {
				d2 = d1;
				d1 = dd;
			} else if (dd < d2) {
				d2 = dd;
			}
		}
	}
	float edge = (d2 - d1) * 0.22;   // metres to the crack
	// not every edge has cracked: some plates are still joined
	float open = step(0.35, hash(floor(gq + vec2(0.5)) + 41.0));
	float crack = 1.0 - smoothstep(0.0015, 0.0015 + pxw, edge);
	return 1.0 - 0.28 * crack * tired * open;
}
// cells of a Voronoi pattern round q: (distance to the nearest edge, in cells; that cell's id)
vec3 voro(vec2 q) {
	vec2 gi = floor(q);
	vec2 gf = q - gi;
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 id = gi;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 pt = o + vec2(hash(gi + o), hash(gi + o + 17.3)) * 0.8 + 0.1;
			float dd = length(gf - pt);
			if (dd < d1) {
				d2 = d1;
				d1 = dd;
				id = gi + o;
			} else if (dd < d2) {
				d2 = dd;
			}
		}
	}
	return vec3((d2 - d1) * 0.5, id);
}
void fragment() {
	vec3 c = COLOR.rgb;
	vec4 fx = vec4(0.0);
	float lay = 0.0;   // which way slabs are laid: a tone's spare green, 0..1 for 0..180 degrees
	if (COLOR.a < 0.02) {
		int i = int(COLOR.r * 63.0 + 0.5);
		c = tones[i].rgb;
		fx = tone_fx[i];
		lay = COLOR.g * 3.14159265;
	}
	// Texture lookups below sit in branches that differ from one triangle to the next, where
	// a GPU's own mip choice is undefined at the edges: so the slopes are taken here, where
	// every pixel runs, and handed to textureGrad.
	vec2 p = wpos.xz;
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec3 bump = vec3(0.0, 0.0, 1.0);
	if (fx.x + fx.y > 0.0) {
		float near = clamp(1.0 - length(VERTEX) / 90.0, 0.0, 1.0);
		float big = noise(p / 11.0) * 0.6 + noise(p / 3.1) * 0.4;
		float shade = 1.0 + (big - 0.5) * fx.x * 2.0;
		if (fx.w > 0.5 && fx.w < 1.5) {   // grass and ground: drier, yellower patches here and there
			c = mix(c, c * vec3(1.12, 1.07, 0.8), smoothstep(0.56, 0.82, noise(p / 17.0 + 7.0)) * fx.x * 4.0);
		}
		// a wall or a kerb's face stays on the noise: laid from above, a photo runs down it in
		// streaks; kind 0 (a pole's top, a bench, a sign) has no photo at all
		if (fx.w > 3.5 && fx.w < 4.5) {   // kind 4: a wall of rough stones in mortar (garden walls)
			vec2 q = wup > 0.6 ? p : vec2(wpos.x + wpos.z, wpos.y * 1.3);
			vec3 vr = voro(q / 0.24);
			float pxc = (length(dpx) + length(dpy)) / 0.24;
			float mortar = 1.0 - smoothstep(0.04, 0.04 + pxc * 1.5, vr.x);
			c *= 0.84 + 0.3 * hash(vr.yz + 5.1);
			c = mix(c, c * 0.62 + vec3(0.04), mortar * near);
		} else if (textured > 0.5 && wup > 0.6 && fx.w > 0.5) {
			if (fx.w < 1.5) {   // grass, earth, sand: a lawn photo, 2 m across (fading out further
				// off, where its repeat would line up into a grid; see GROUND_SHADER)
				float kd = 1.0 - smoothstep(25.0, 110.0, length(VERTEX));
				vec2 uv = p * 0.5;
				vec3 t = textureGrad(grass_tex, uv, dpx * 0.5, dpy * 0.5).rgb;
				vec3 lw = vec3(0.2126, 0.7152, 0.0722);
				vec3 t_grey = grass_mean * (dot(t, lw) / dot(grass_mean, lw));   // its brightness, the lawn's average colour
				c *= detail(mix(t_grey, t, fx.z), grass_mean, 0.85 * kd);
				bump = unpack(textureGrad(grass_nrm, uv, dpx * 0.5, dpy * 0.5).rg, 0.8 * kd);
			} else if (fx.w < 2.5) {   // asphalt: fine grit 3 m across over 30 m of patches and tyre marks
				vec2 uv = p / 3.0;
				// paint (no patches of its own) takes the grit faintly: it is worn, not gritty
				float k = fx.x > 0.0 ? 1.0 : 0.35;
				c *= detail(textureGrad(asph_tex, uv, dpx / 3.0, dpy / 3.0).rgb, asph_mean, 0.9 * k);
				vec3 b = textureGrad(asph_big, p / 30.0, dpx / 30.0, dpy / 30.0).rgb;
				c *= mix(1.0, clamp(dot(b, vec3(0.333)) / dot(big_mean, vec3(0.333)), 0.0, 2.0), 0.7 * k);
				bump = unpack(textureGrad(asph_nrm, uv, dpx / 3.0, dpy / 3.0).rg, 1.0);
				float dist = length(VERTEX);
				float pxw = length(dpx) + length(dpy);
				if (fx.x > 0.0 && dist < 140.0) {
					// worn, as Givatayim's streets are: one 5 m square in eight patched with
					// newer, darker asphalt and its sealed seam; crazed plates where it is old;
					// the light stones of the mix showing, close up
					vec2 pc = floor(p / 5.0);
					if (hash(pc + 2.3) < 0.13) {
						vec2 lo = (pc + vec2(hash(pc + 4.1), hash(pc + 5.3)) * 0.4) * 5.0;
						vec2 hi = lo + vec2(1.2 + 2.6 * hash(pc + 6.7), 1.0 + 2.2 * hash(pc + 8.9));
						vec2 d = min(p - lo, hi - p);
						float inside = step(0.0, min(d.x, d.y));
						c *= mix(1.0, 0.8, inside);
						c *= 1.0 - 0.4 * inside * (1.0 - smoothstep(0.02, 0.02 + pxw * 2.0, min(d.x, d.y)));
					}
					c *= crazing(p, dist, pxw);
					c *= 1.0 + step(0.94, hash(floor(p / 0.012))) * 0.4 * (1.0 - smoothstep(3.0, 12.0, dist));
				}
				if (fx.x > 0.0) {
					// oil and rubber: a dark blotch in about one 3 m square in six, oval, soft
					vec2 cell = floor(p / 3.0);
					if (hash(cell) > 0.83) {
						vec2 cc = (cell + 0.5 + (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.5) * 3.0;
						float r = 0.35 + 0.55 * hash(cell + 1.3);
						float d = length((p - cc) * vec2(1.0, 1.7));
						c *= 1.0 - 0.5 * smoothstep(r, r * 0.35, d) * (0.6 + 0.4 * noise(p * 3.0));
					}
				} else {
					// paint wears through to the asphalt, in patches and in grains -- a zebra half
					// gone, as most are -- and the road's cracks run through it
					float wear = smoothstep(0.42, 0.8, noise(p * 1.3)) * 0.7 + smoothstep(0.55, 0.9, noise(p * 7.0)) * 0.35;
					c = mix(c, wear_col, clamp(wear, 0.0, 0.92));
					c *= crazing(p, dist, pxw);
				}
			} else if (fx.w < 3.5) {   // pavement and plazas: pavers, bigger in a plaza
				float s = pave_m * fx.z / 0.6;
				vec2 uv = p / s;
				c *= detail(textureGrad(pave_tex, uv, dpx / s, dpy / s).rgb, pave_mean, 0.9);
				bump = unpack(textureGrad(pave_nrm, uv, dpx / s, dpy / s).rg, 1.0);
			} else if (fx.w > 6.5) {   // pavers in rows (kind 7), fx.z long and half that wide,
				// each row half a paver on from the last, laid along `lay`; the joints fade out
				// with distance before they can shimmer
				vec2 q = mat2(vec2(cos(lay), -sin(lay)), vec2(sin(lay), cos(lay))) * p / fx.z;
				q.y *= 2.0;
				q.x += 0.5 * mod(floor(q.y), 2.0);
				vec2 cell = floor(q);
				vec2 f = fract(q);
				float fw = max(length(dpx), length(dpy)) / fx.z;
				c *= 0.9 + 0.2 * hash(cell + 1.7);
				c *= detail(textureGrad(asph_tex, p / 1.5, dpx / 1.5, dpy / 1.5).rgb, asph_mean, 0.25);
				vec2 e = min(f, 1.0 - f) * vec2(1.0, 0.5);
				float joint = 1.0 - smoothstep(0.02, 0.02 + fw * 1.5, min(e.x, e.y));
				c *= 1.0 - 0.3 * joint * (1.0 - smoothstep(0.15, 0.4, fw));
			} else {   // poured concrete slabs (kind 6), fx.z across, laid along `lay`: each a
				// shade of its own, the joints dark, a crack across about one in six
				vec2 q = mat2(vec2(cos(lay), -sin(lay)), vec2(sin(lay), cos(lay))) * p / fx.z;
				vec2 cell = floor(q);
				vec2 f = fract(q);
				float fw = max(length(dpx), length(dpy)) / fx.z;
				c *= 0.94 + 0.1 * hash(cell + 5.3);
				c *= detail(textureGrad(asph_tex, p / 1.5, dpx / 1.5, dpy / 1.5).rgb, asph_mean, 0.3);
				c *= 1.0 - 0.13 * smoothstep(0.5, 0.85, noise(p * 0.45 + 3.0));   // old stains, soft
				vec2 e = min(f, 1.0 - f);
				c *= 1.0 - 0.16 * (1.0 - smoothstep(0.005, 0.005 + fw * 1.5, min(e.x, e.y)));
				if (hash(cell + 9.1) > 0.83) {
					float a = hash(cell + 6.6) * 3.14159;
					vec2 o = vec2(hash(cell + 2.2), hash(cell + 4.4)) * 0.6 + 0.2;
					float d = abs(dot(f - o, vec2(cos(a), sin(a))) + (noise(q * 9.0) - 0.5) * 0.06);
					c *= 1.0 - 0.3 * (1.0 - smoothstep(0.003, 0.003 + fw * 1.5, d));
				}
			}
		} else if (near > 0.0) {
			shade += (noise(p * 1.9) - 0.5) * fx.y * 2.0 * near;
			if (fx.w > 2.5) {   // paving: a grid of slabs, the joints a little darker
				vec2 g = abs(fract(p / fx.z) - 0.5);
				shade -= step(0.45, max(g.x, g.y)) * 0.1 * near;
			}
		}
		c *= shade;
	}
	// the photos are mapped on the world's X and Z, so their frame is the world's: across is
	// +X, the map's "up" is -Z; bent round the surface's own normal for the hills
	// (only on the ground: on a pole or a sign the frame would come out of nothing)
	if (bump.z < 0.99999) {
		vec3 t = (VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
		t = normalize(t - NORMAL * dot(NORMAL, t));
		NORMAL = normalize(t * bump.x + cross(NORMAL, t) * bump.y + NORMAL * bump.z);
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
"""
## the surface each tone gets: [patches, grain, slab size (kind 3) / the lawn photo's colours too
## (kind 1: 1 grass, 0 bare earth: its light and dark only), kind (0 none, 1 soft, 2 grained, 3 slabs,
## 4 rough stones in mortar, 6 poured slabs laid along a line, 7 pavers in rows; the shader tests
## each kind's range on both sides, so a new kind never falls into another's branch)]
const TONE_FX := {
	"grass": [0.16, 0.08, 1.0, 1.0], "pitch": [0.06, 0.05, 1.0, 1.0], "wood": [0.16, 0.07, 1.0, 1.0],
	"bush": [0.1, 0.05, 1.0, 1.0], "ground": [0.1, 0.06, 0.0, 1.0], "sand": [0.08, 0.08, 0.0, 1.0],
	"asphalt": [0.11, 0.075, 0.0, 2.0], "parking": [0.1, 0.06, 0.0, 2.0], "path": [0.06, 0.07, 0.0, 2.0],
	"pavement": [0.04, 0.04, 0.6, 3.0], "plaza": [0.05, 0.04, 1.0, 3.0], "mark": [0.0, 0.04, 0.0, 2.0],
	"pavers_dark": [0.04, 0.04, 0.6, 3.0], "slabs": [0.05, 0.04, 1.0, 6.0], "pavers_grey": [0.04, 0.03, 0.2, 7.0],
	"markyellow": [0.0, 0.04, 0.0, 2.0], "metal": [0.0, 0.0, 0.0, 0.0], "metalrim": [0.0, 0.0, 0.0, 0.0],
	"stonewall": [0.06, 0.04, 0.0, 4.0],
}
var _tone_list: Array = []           ## the table's tone names, in order
var _tone_material: ShaderMaterial

func _tone_mat() -> ShaderMaterial:
	if _tone_material == null:
		_tone_material = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = TONE_SHADER
		_tone_material.shader = sh
		# Israeli pavements are 20 x 10 cm concrete pavers in herringbone, a mix of greys
		# and red-browns (drawn by textures/herringbone.py); Bedford's are poured slabs, the
		# photo's slabs blown up to a metre or so
		var north := String(_place.get("look", "")) == "north"
		var pave := "concrete_pavement" if north else "herringbone_pavers"
		_tone_material.set_shader_parameter("asph_tex", _tex("asphalt_02_diff"))
		_tone_material.set_shader_parameter("asph_nrm", _tex("asphalt_02_nor"))
		_tone_material.set_shader_parameter("asph_big", _tex("aerial_asphalt_01_diff"))
		_tone_material.set_shader_parameter("pave_tex", _tex(pave + "_diff"))
		_tone_material.set_shader_parameter("pave_nrm", _tex(pave + "_nor"))
		_tone_material.set_shader_parameter("grass_tex", _tex("leafy_grass_diff"))
		_tone_material.set_shader_parameter("grass_nrm", _tex("leafy_grass_nor"))
		_tone_material.set_shader_parameter("asph_mean", TEX_MEAN["asphalt_02"])
		_tone_material.set_shader_parameter("big_mean", TEX_MEAN["aerial_asphalt_01"])
		_tone_material.set_shader_parameter("pave_mean", TEX_MEAN[pave])
		_tone_material.set_shader_parameter("grass_mean", TEX_MEAN["leafy_grass"])
		_tone_material.set_shader_parameter("pave_m", 4.0 if north else 2.0)
		_tone_material.set_shader_parameter("textured", 1.0 if _quality > 0 else 0.0)
	return _tone_material

## The photos under the surfaces: CC0 from Poly Haven (textures/CREDITS.md), 1024 px, the
## bump maps 512 -- all but the herringbone pavers, which textures/herringbone.py draws. The shaders divide each by its average colour, so a photo adds detail
## without changing the palette's colour. The averages are of the stored (sRGB) values, and
## the samplers have no source_color, so they read exactly those: in the Compatibility
## renderer source_color does not convert them anyway (measured), and a photo's own smallest
## mipmap, the obvious way to get its average in the shader, read back as junk there.
const TEX_DIR := "res://game/streets/textures/"
const TEX_MEAN := {
	"aerial_asphalt_01": Vector3(0.402, 0.385, 0.406),
	"asphalt_02": Vector3(0.356, 0.353, 0.333),
	"concrete_pavement": Vector3(0.501, 0.457, 0.403),
	"herringbone_pavers": Vector3(0.502, 0.489, 0.483),
	"leafy_grass": Vector3(0.593, 0.516, 0.351),
	"painted_plaster_wall": Vector3(0.671, 0.639, 0.627),
	"bark_brown_02": Vector3(0.373, 0.338, 0.251),
	"palm_tree_bark": Vector3(0.613, 0.565, 0.507),
}

func _tex(file: String) -> Texture2D:
	return load(TEX_DIR + file + ".jpg") as Texture2D

## the photo textures on or off in every shader that has them (off at the lowest web level)
func _set_textured(on: bool) -> void:
	for m: ShaderMaterial in [_tone_material, _wall_mat, _ground_shader_mat, _kerb_mat, _roof_mat]:
		if m != null:
			m.set_shader_parameter("textured", 1.0 if on else 0.0)

func _retint_tone_mat() -> void:
	if _tone_material == null:
		return
	var cols := PackedColorArray()
	cols.resize(64)
	var fxs: Array = []
	fxs.resize(64)
	fxs.fill(Vector4.ZERO)
	for i in range(_tone_list.size()):
		cols[i] = _tone.get(_tone_list[i], Palette.col("warn"))
		var f: Array = TONE_FX.get(_tone_list[i], [0.03, 0.02, 0.0, 0.0])   # (kind 0: no photo)
		fxs[i] = Vector4(f[0], f[1], f[2], f[3])
	_tone_material.set_shader_parameter("tones", cols)
	_tone_material.set_shader_parameter("wear_col", _tone["asphalt"])
	_tone_material.set_shader_parameter("tone_fx", fxs)

## the tone a plain material is (one of _surface's), or "" when it is anything else
func _tone_of(m: Material) -> String:
	var sm := m as StandardMaterial3D
	if sm == null or sm.vertex_color_use_as_albedo or sm.emission_enabled or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return ""
	for t: String in _smat:
		if _smat[t] == m and _tone.has(String(sm.get_meta("tone", t))) and t != "lamp":
			return String(sm.get_meta("tone", t))
	return ""

## how a material's geometry goes into the merged mesh: [colour to fill with, or null to keep
## the vertex colours, the material's own colour to multiply them by (linear)], or [] if it
## is not one for the merged mesh. (A tree's tint is its instance colour times the leaf's.)
func _merge_as(m: Material) -> Array:
	var sm := m as StandardMaterial3D
	if sm != null and sm.vertex_color_use_as_albedo and not sm.emission_enabled and sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		return [null, sm.albedo_color.srgb_to_linear()]
	var t := _tone_of(m)
	if t == "":
		return []
	var i := _tone_list.find(t)
	if i < 0:
		if _tone_list.size() >= 64:
			return []
		_tone_list.append(t)
		i = _tone_list.size() - 1
	return [Color(float(i) / 63.0, 0.0, 0.0, 0.0)]

func _range_class(seen: float) -> float:
	if seen <= 0.0:
		return 100000.0
	for r: float in BATCH_RANGES:
		if r >= seen:
			return r
	return BATCH_RANGES[BATCH_RANGES.size() - 1]

## a whole Buf (already in world space) into the merged meshes
func _batch_buf(buf: Buf, m: Material, how: Array, shadows: bool, seen: float) -> void:
	var rc := _range_class(seen)
	var key := "U|%s|%d" % [shadows, int(rc)]
	if not _batches.has(key):
		_batches[key] = {"mat": _tone_mat(), "shadows": shadows, "range": rc, "cells": {}}
	var cells: Dictionary = _batches[key]["cells"]
	var parts := buf.parts()
	for pk: Vector2i in parts:
		var part: Buf = parts[pk]
		if part.empty():
			continue
		var centre := part.v[0]
		var ck := _tile if _tiled else _cell(Vector2(centre.x, centre.z), BATCH_CELL)
		var bat: Buf = cells.get(ck)
		if bat == null:
			bat = Buf.new()
			cells[ck] = bat
		bat.v.append_array(part.v)
		bat.n.append_array(part.n)
		if how[0] == null:
			var alb: Color = how[1]
			if alb == Color.WHITE:
				bat.c.append_array(part.c)
			else:
				var pc := part.c.duplicate()
				for k in range(pc.size()):
					pc[k] = pc[k] * alb
				bat.c.append_array(pc)
		else:
			var cs := PackedColorArray()
			cs.resize(part.v.size())
			cs.fill(how[0])
			bat.c.append_array(cs)

## the one material for everything coloured in its vertices (signs, kits, balconies)
var _vc_material: StandardMaterial3D
func _vc_mat() -> StandardMaterial3D:
	if _vc_material == null:
		_vc_material = StandardMaterial3D.new()
		_vc_material.vertex_color_use_as_albedo = true
		_vc_material.roughness = 0.75
	return _vc_material

## a mesh's first surface as plain triangles: [vertices, normals, colours, all white?]
func _soup(mesh: Mesh) -> Array:
	var id := mesh.get_instance_id()
	if _soups.has(id):
		return _soups[id]
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if n.size() != v.size():
		n = PackedVector3Array()
		n.resize(v.size())
		n.fill(Vector3.UP)
	if c.size() != v.size():
		c = PackedColorArray()
		c.resize(v.size())
		c.fill(Color.WHITE)
	if not idx.is_empty():
		var v2 := PackedVector3Array()
		var n2 := PackedVector3Array()
		var c2 := PackedColorArray()
		v2.resize(idx.size())
		n2.resize(idx.size())
		c2.resize(idx.size())
		for k in range(idx.size()):
			v2[k] = v[idx[k]]
			n2[k] = n[idx[k]]
			c2[k] = c[idx[k]]
		v = v2
		n = n2
		c = c2
	var white := true
	for col in c:
		if col != Color.WHITE:
			white = false
			break
	var out := [v, n, c, white]
	_soups[id] = out
	return out

func _batchable(mesh: Mesh, m: Material, count: int) -> bool:
	if mesh == null or mesh.get_surface_count() != 1:
		return false
	var mt: Material = m if m != null else mesh.surface_get_material(0)
	if not (mt is StandardMaterial3D):
		return false
	var sm := mt as StandardMaterial3D
	if sm.emission_enabled or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm == _smat.get("lamp"):
		return false
	return (_soup(mesh)[0] as PackedVector3Array).size() * count <= BATCH_VERTS

func _batch_add(mesh: Mesh, xforms: Array, range_end: float, colours: Array, m: Material, shadows: bool) -> void:
	var mt: Material = m if m != null else mesh.surface_get_material(0)
	var rc := _range_class(range_end)
	var how := _merge_as(mt)
	var key := ("U|%s|%d" % [shadows, int(rc)]) if not how.is_empty() else ("%d|%s|%d" % [mt.get_instance_id(), shadows, int(rc)])
	if not _batches.has(key):
		_batches[key] = {"mat": _tone_mat() if not how.is_empty() else mt, "shadows": shadows, "range": rc, "cells": {}}
	var cells: Dictionary = _batches[key]["cells"]
	var soup := _soup(mesh)
	var sv: PackedVector3Array = soup[0]
	var sn: PackedVector3Array = soup[1]
	var sc: PackedColorArray = soup[2]
	var white: bool = soup[3]
	var nv := sv.size()
	for i in range(xforms.size()):
		var t: Transform3D = xforms[i]
		var ck := _tile if _tiled else _cell(Vector2(t.origin.x, t.origin.z), BATCH_CELL)
		var bat: Buf = cells.get(ck)
		if bat == null:
			bat = Buf.new()
			cells[ck] = bat
		bat.v.append_array(t * sv)
		bat.n.append_array(Transform3D(t.basis, Vector3.ZERO) * sn)
		if not how.is_empty() and how[0] != null:   # a plain tone: its number, whatever the instance colour
			var ts := PackedColorArray()
			ts.resize(nv)
			ts.fill(how[0])
			bat.c.append_array(ts)
		elif colours.is_empty() and (how.is_empty() or how[1] == Color.WHITE):
			bat.c.append_array(sc)
		else:
			var col: Color = (colours[i] if not colours.is_empty() else Color.WHITE) * (how[1] if not how.is_empty() else Color.WHITE)
			var cs := PackedColorArray()
			cs.resize(nv)
			if white:
				cs.fill(col)
			else:
				for k in range(nv):
					cs[k] = sc[k] * col
			bat.c.append_array(cs)

func _flush_batches() -> void:
	_batching = false
	_retint_tone_mat()
	var made := 0
	for key: String in _batches:
		var b: Dictionary = _batches[key]
		var rc: float = b["range"]
		for ck: Vector2i in b["cells"]:
			if _over():
				await _pause()
			var bat: Buf = b["cells"][ck]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = bat.v
			arr[Mesh.ARRAY_NORMAL] = bat.n
			arr[Mesh.ARRAY_COLOR] = bat.c
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(0, b["mat"])
			var mi := MeshInstance3D.new()
			mi.mesh = am
			if rc < 99999.0:
				mi.visibility_range_end = rc + BATCH_CELL * 0.71
				mi.visibility_range_end_margin = 20.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b["shadows"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world.add_child(mi)
			made += 1
	_tally("batches", made)
	_batches = {}
	_soups = {}

## _chunked a couple of hundred copies at a time while building in the background (a
## square's trees merged in one go took most of a frame)
func _chunked_paced(mesh: Mesh, xforms: Array, range_end: float, colours: Array = [], m: Material = null, shadows := false) -> void:
	if xforms.size() <= 200 or not (_bg_build and _batching and _batchable(mesh, m, xforms.size())):
		_chunked(mesh, xforms, range_end, colours, m, shadows)
		return
	for i in range(0, xforms.size(), 200):
		if _over():
			await _pause()
		_batch_add(mesh, xforms.slice(i, i + 200), range_end, colours.slice(i, i + 200) if not colours.is_empty() else [],
			m, shadows)

func _chunked(mesh: Mesh, xforms: Array, range_end: float, colours: Array = [], m: Material = null, shadows := false,
		custom := false) -> void:
	if xforms.is_empty():
		return
	if _batching and not custom and _batchable(mesh, m, xforms.size()):
		_batch_add(mesh, xforms, range_end, colours, m, shadows)
		return
	# a square about as big as the range: little things (signs, posts, racks) seen 100-150 m
	# off in 140 m squares were a dozen draws a kind, and a big city tens of thousands of nodes
	var cell := TILE if _tiled else clampf(range_end, 220.0, CHUNK)
	var groups := {}
	for i in range(xforms.size()):
		var t: Transform3D = xforms[i]
		var key := _tile if _tiled else _cell(Vector2(t.origin.x, t.origin.z), cell)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(i)
	for key: Vector2i in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# with custom data, colours on too (all white): this renderer multiplies the vertex
		# colour by the instance colour, and without one that came out as nothing (black)
		mm.use_colors = not colours.is_empty()
		mm.use_custom_data = not colours.is_empty() and custom
		mm.mesh = mesh
		mm.instance_count = list.size()
		for j in range(list.size()):
			mm.set_instance_transform(j, xforms[list[j]])
			if not colours.is_empty():
				if custom:
					mm.set_instance_custom_data(j, Color(colours[list[j]], 0.0))
					mm.set_instance_color(j, Color.WHITE)
				else:
					mm.set_instance_color(j, colours[list[j]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = range_end + cell * 0.71
		mmi.visibility_range_end_margin = 20.0
		if m != null:
			mmi.material_override = m
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mmi)

func _tree_ok(p: Vector2, spacing: float) -> bool:
	if not _bounds.has_point(p):
		return false
	var hit := _nearest_seg(p, 12.0, true)
	if not hit.is_empty() and hit["edge"] < 0.7:
		return false
	if _push_out(p, 1.1, false) != Vector2.ZERO:
		return false
	for i: int in _near(_post_hash, p, spacing, BLD_CELL):
		if _posts[i].distance_to(p) < spacing:
			return false
	return true

## p is at least `margin` metres clear of every drivable road's asphalt (negative: may poke
## that far in). Anything solid is checked with this before it goes down: a bench by a
## footpath that runs beside a road, or a sign by a narrow street where a wide one passes,
## stood in the lane, and autodrive drove into it again and again.
func _off_road(p: Vector2, margin: float) -> bool:
	var hit := _nearest_seg(p, 14.0, true)
	return hit.is_empty() or float(hit["edge"]) >= margin

## nothing round (a tree, a lamp, a sign) stands within `d` metres of p
func _clear_of_posts(p: Vector2, d: float) -> bool:
	for i: int in _near(_post_hash, p, d, BLD_CELL):
		if _posts[i].distance_to(p) < d:
			return false
	return true

## for scripts that build meshes the game's way (furniture.gd)
func new_buf() -> Buf:
	return Buf.new()

func new_cbuf(cell: float) -> CBuf:
	return CBuf.new(cell)

## Thin walls the car and people bump into: fences and railings, hedges, the low garden walls,
## a bus shelter's back. They had no collision at all -- not for performance, they were just
## never added -- and the car drove through them.
var _walls := PackedVector2Array()   ## two points a wall
var _wall_r := PackedFloat32Array()  ## half its thickness
var _wall_hash := {}

func add_wall(a: Vector2, b: Vector2, half: float) -> void:
	if a.distance_squared_to(b) < 0.0001:
		return
	var i := _wall_r.size()
	_walls.append(a)
	_walls.append(b)
	_wall_r.append(half)
	_hash_add(_wall_hash, Rect2(a, Vector2.ZERO).expand(b).grow(half), BLD_CELL, i)

func _add_post(p: Vector2, r: float) -> void:
	var i := _posts.size()
	_posts.append(p)
	_post_r.append(r)
	_hash_add(_post_hash, Rect2(p, Vector2.ZERO).grow(r), BLD_CELL, i)

## a traffic light on the right of every way into a signalled junction, in two groups by
## direction so crossing streets take turns
func _build_signals() -> void:
	var med := String(_place.get("look", "")) == "med"
	var poles: Array = []
	var heads: Array = []
	var bulbs: Array = [[[], [], []], [[], [], []]]
	for node: int in _tile_lit.get(_tile, []):
		if _over():
			await _pause()
		var c := _nodes[node]
		var rn := _node_r[node]
		for e: Vector2i in _node_roads[node]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"]:
				continue
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [-1, 1]:
				var from := e.y + d2
				if from < 0 or from >= pts.size():
					continue
				# arriving from `from` means travelling in direction -d2 along the road
				if r["o"] != 0 and r["o"] != -d2:
					continue
				var dir := (c - pts[from]).normalized()
				var right := Vector2(-dir.y, dir.x)
				_stop_lines.append([c, dir, rn + 1.2, float(r["w"]), r["o"] != 0, ""])
				var p := c - dir * (rn + 1.5) + right * (float(r["w"]) * 0.5 + 0.8)
				if _push_out(p, 0.3, false) != Vector2.ZERO:
					continue
				var on := _nearest_seg(p, 12.0, true)
				if not on.is_empty() and float(on["edge"]) < 0.4:
					continue   # OSM puts the light's node a few metres out; never plant it in a lane
				var g := _light_group(node, dir) - 1
				var face := Basis(Vector3.UP, atan2(-dir.x, -dir.y))   # +Z of the head toward the traffic
				var gy := _h(p)
				poles.append(Transform3D(Basis(), Vector3(p.x, gy + 1.7, p.y)))
				heads.append(Transform3D(face, Vector3(p.x, gy + 3.3, p.y)))
				_light_spots.append([Vector3(p.x, gy + 3.3, p.y), -dir])   # (for tests: where, facing)
				# the blue crossing sign strapped to the pole under the light, as in Israel
				# (Nova Scotia's lights carry walk signals instead): the zebra is just past it
				if med:
					_pole_plates.append(["crossing", Transform3D(face * Basis.from_scale(Vector3.ONE * SIGN_SCALE),
							Vector3(p.x, gy + 2.25, p.y) + Vector3(-dir.x, 0.0, -dir.y) * 0.09)])
				var front := Vector3(-dir.x, 0.0, -dir.y) * 0.17
				for ci in range(3):
					bulbs[g][ci].append(Vector3(p.x, gy + 3.3 + 0.3 - 0.3 * ci, p.y) + front)
				_add_post(p, 0.15)
	if poles.is_empty():
		return
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 3.4
	pole_mesh.radial_segments = 6
	pole_mesh.material = _surface("pole")
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.34, 1.0, 0.3)
	head_mesh.material = _surface("pole")
	_chunked(pole_mesh, poles, LAMP_RANGE)
	_chunked(head_mesh, heads, LAMP_RANGE)
	for g in range(2):
		for ci in range(3):
			if not (bulbs[g][ci] as Array).is_empty():
				_add_bulbs(g, ci, bulbs[g][ci])
	_build_walk_lights(pole_mesh)

var _bulb_mm: Array = []             ## [group][colour] -> the one multimesh of those bulbs, city-wide
var _bulb_at: Array = []             ## [group][colour] -> their transforms, 12 numbers a bulb

## The bulbs of one colour of one group: one multimesh across the whole city, grown square by
## square (a multimesh a square was a hundred more draws, the bulbs having no draw range).
func _add_bulbs(g: int, ci: int, at: Array) -> void:
	if _bulb_mm.is_empty():
		var bulb := SphereMesh.new()
		bulb.radius = 0.11
		bulb.height = 0.22
		bulb.radial_segments = 6
		bulb.rings = 2
		for gg in range(2):
			var mms: Array = []
			var ats: Array = []
			for c in range(3):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = bulb
				var mi := MultiMeshInstance3D.new()
				mi.multimesh = mm
				mi.material_override = _sig_mats[gg][c]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				world.add_child(mi)
				mms.append(mm)
				ats.append(PackedFloat32Array())
			_bulb_mm.append(mms)
			_bulb_at.append(ats)
	var buf: PackedFloat32Array = _bulb_at[g][ci]
	for p: Vector3 in at:
		buf.append_array([1.0, 0.0, 0.0, p.x, 0.0, 1.0, 0.0, p.y, 0.0, 0.0, 1.0, p.z])
	_bulb_at[g][ci] = buf
	var mm: MultiMesh = _bulb_mm[g][ci]
	mm.instance_count = buf.size() / 12
	mm.buffer = buf

## Which junctions have lights, for the whole city at once (traffic and autodrive stop at
## them wherever they are; the poles go up square by square). OSM often maps a light on one
## approach only, a few metres out from the junction; then the other ways in had no light
## and drove on. Each light is taken to the junction it stands at (the nearest within 40 m
## along its road), and the junction gets lights on every way in. A light far from any
## junction (a crossing mid-street) stays as it is.
func _lights_setup() -> void:
	var lit := {}
	for ni in _city_data.get("signals", []):
		var node := int(ni)
		if node < 0 or node >= _nodes.size():
			continue
		var j := _junction_of(node, 40.0)
		lit[j if j >= 0 else node] = true
		_sig_owner[node] = j if j >= 0 else node
		if not _sig_set.has(node):   # its own line still counts (see LIGHT_SKIP)
			_sig_set[node] = true
			_hash_add(_sig_hash, Rect2(_nodes[node], Vector2.ZERO), SEG_CELL, node)
	_lit = lit
	# (before any square puts up its poles: every one reads the same groups) -- the points of
	# one junction together: a divided road's junction is two to four points 10-30 m apart,
	# each with its lights, and judged one by one they disagreed which road was the main one:
	# green both ways across the knot, and the cars met in it
	var knots: Array = []
	var in_knot := {}
	for node: int in lit:
		if in_knot.has(node):
			continue
		var knot: Array = [node]
		in_knot[node] = true
		var k := 0
		while k < knot.size():
			for other: int in lit:
				if not in_knot.has(other) and _nodes[other].distance_to(_nodes[knot[k]]) < 40.0:
					in_knot[other] = true
					knot.append(other)
			k += 1
		knots.append(knot)
	for knot: Array in knots:
		_signal_groups(knot)
		for node: int in knot:
			_sig_knot[node] = knot[0]
	for node: int in lit:
		for e: Vector2i in _node_roads[node]:
			if (_roads[e.x] as Dictionary)["drive"] and not _sig_set.has(node):
				_sig_set[node] = true
				_hash_add(_sig_hash, Rect2(_nodes[node], Vector2.ZERO), SEG_CELL, node)
		_bucket(_tile_lit, _tile_of(_nodes[node]), node)
	if lit.is_empty():
		return
	# the bulbs' colours, shared by every square's lights and switched together
	_sig_mats = []
	for g in range(2):
		var mats: Array = []
		for ci in range(3):
			var m := StandardMaterial3D.new()
			m.roughness = 0.4
			mats.append(m)
		_sig_mats.append(mats)
	_ped_mats = []
	for g in range(2):
		var mats: Array = []
		for ci in range(2):
			var m := StandardMaterial3D.new()
			m.roughness = 0.4
			mats.append(m)
		_ped_mats.append(mats)
	_apply_signals()

## People's lights at each zebra by a junction with lights: a short pole at each end of the
## crossing with a head looking across at whoever waits on the other side -- the red man over
## the green man -- in step with the cars' lights (see _apply_signals). People at those
## crossings go by them (_walk_light).
var _ped_mats: Array = []            ## [group][0 red man, 1 green man]
var _light_spots: Array = []         ## [head, the way it faces] of the cars' lights (for tests)
var _walk_spots: Array = []          ## the same for the people's

var _lit := {}                       ## junctions with lights (all of them, from _lights_setup)
var _walk_mm: Array = []             ## [group][0 red, 1 green] -> one multimesh of those lamps, city-wide
var _walk_at: Array = []

func _build_walk_lights(pole_mesh: Mesh) -> void:
	var poles: Array = []
	var heads: Array = []
	var lamps: Array = [[[], []], [[], []]]
	for ni: int in _crossing_nodes:
		if not _mine(_nodes[ni]):
			continue   # (each zebra's lights put up by the square it is in, once)
		var z := _zebra_geom(ni)
		if z.is_empty():
			continue
		var j := -1
		var jd := 30.0
		for n: int in _near(_sig_hash, z[0], 30.0, SEG_CELL):
			var owner: int = _sig_owner.get(n, n)
			if _lit.has(owner) and _nodes[n].distance_to(z[0]) < jd:
				jd = _nodes[n].distance_to(z[0])
				j = owner
		if j < 0:
			continue
		var span := _zebra_span(z)
		if span.is_empty():
			continue
		var g := _light_group(j, z[3]) - 1
		for k in range(2):
			var here: Vector2 = span[k]
			var there: Vector2 = span[1 - k]
			var across := (there - here).normalized()
			var p := here - across * 0.35
			if _push_out(p, 0.3, true, false) != Vector2.ZERO:
				continue
			var gy := _h(p)
			var face := Basis(Vector3.UP, atan2(across.x, across.y))   # +Z toward the far kerb
			poles.append(Transform3D(Basis.from_scale(Vector3(0.8, 2.7 / 3.4, 0.8)), Vector3(p.x, gy + 1.35, p.y)))
			heads.append(Transform3D(face * Basis.from_scale(Vector3(0.7, 0.55, 0.6)), Vector3(p.x, gy + 2.55, p.y)))
			_walk_spots.append([Vector3(p.x, gy + 2.55, p.y), across])
			var front := Vector3(across.x, 0.0, across.y) * 0.1
			lamps[g][0].append(Vector3(p.x, gy + 2.67, p.y) + front)
			lamps[g][1].append(Vector3(p.x, gy + 2.43, p.y) + front)
			_add_post(p, 0.1)
	_tally("walk_lights", poles.size())
	if poles.is_empty():
		return
	_chunked(pole_mesh, poles, LAMP_RANGE)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.34, 1.0, 0.3)
	head_mesh.material = _surface("pole")
	_chunked(head_mesh, heads, LAMP_RANGE)
	if _walk_mm.is_empty():
		var bulb := SphereMesh.new()
		bulb.radius = 0.08
		bulb.height = 0.16
		bulb.radial_segments = 6
		bulb.rings = 2
		for gg in range(2):
			var mms: Array = []
			var ats: Array = []
			for c in range(2):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = bulb
				var mi := MultiMeshInstance3D.new()
				mi.multimesh = mm
				mi.material_override = _ped_mats[gg][c]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				world.add_child(mi)
				mms.append(mm)
				ats.append(PackedFloat32Array())
			_walk_mm.append(mms)
			_walk_at.append(ats)
	for g in range(2):
		for c in range(2):
			if (lamps[g][c] as Array).is_empty():
				continue
			var buf: PackedFloat32Array = _walk_at[g][c]
			for p: Vector3 in lamps[g][c]:
				buf.append_array([1.0, 0.0, 0.0, p.x, 0.0, 1.0, 0.0, p.y, 0.0, 0.0, 1.0, p.z])
			_walk_at[g][c] = buf
			var mm: MultiMesh = _walk_mm[g][c]
			mm.instance_count = buf.size() / 12
			mm.buffer = buf


## a lit shopfront on the street side of each shop's building, and its name above it
func _build_pois() -> void:
	var k := 1.0 / float(_city_data.get("scale", 10))
	var front := {"glass": [], "post": [], "beam": [], "shutter": []}   ## shop windows and their frames
	var board_cols: Array = []       ## each sign board's colour: dark, white, the shop's, cream
	var awnings := {}                ## colour role -> awning transforms
	var crosses: Array = []          ## pharmacy crosses, sticking out from the wall
	var canopy := {"roof": [], "pillar": [], "pump": [], "band": []}   ## gas stations
	var boards: Array = []           ## the sign boards behind the names
	var terrace := {"top": [], "leg": [], "seat": [], "back": [], "pole": []}
	var shades := {}                 ## role -> umbrella transforms
	var taken := _poi_taken          ## a facade spot already used -> how many there
	var all_pois: Array = _city_data.get("pois", [])
	for pi: int in _tile_pois.get(_tile, []):
		if _over():
			await _pause()
		var p: Array = all_pois[pi]
		var at := Vector2(p[0], p[1]) * k
		var kind := String(p[2])
		if kind in ["shop:vacant", "shop:disused", "shop:no"] or String(p[3]).to_lower() == "vacant":
			continue   # an empty shop: OSM keeps it on the map, and its sign read "vacant"
		var look: Array = _poi_look(kind)
		if look.is_empty():
			continue   # e.g. parking entrances that came in on an address point
		var role: String = look[0]
		var spot := _facade_spot(at)
		var pos: Vector2 = spot[0]
		var n: Vector2 = spot[1]
		var along := Vector2(-n.y, n.x)
		var key := Vector2i((pos / 2.0).round())
		var dup: int = taken.get(key, 0)
		taken[key] = dup + 1
		pos += along * 6.0 * float((dup + 1) / 2) * (1.0 if dup % 2 == 1 else -1.0)
		var face := atan2(n.x, n.y)
		var sub := kind.substr(5) if kind.begins_with("shop:") else ""
		var gy := _h(pos + n * 0.6)
		var station := Vector2.INF
		if kind == "fuel":
			# OSM marks most stations by a point in the shop building: the canopy goes out
			# front, between the building and the street, wherever there is room for it
			for c: Vector2 in [pos + n * 6.0, pos + n * 8.0, at]:
				var on := _nearest_seg(c, 15.0, true)
				if _push_out(c, 3.2, false) == Vector2.ZERO and (on.is_empty() or float(on["edge"]) > 1.5):
					_gas_station(c, n, canopy)
					station = c
					break
		elif spot[2]:
			# a shop window with the light on inside, a dark frame, an awning over it
			var wide := 2.0 if WIDE_SHOPS.has(sub) else 1.0
			var b := Basis(Vector3.UP, face)
			var at3 := func(q: Vector2, out: float, y: float) -> Vector3: return Vector3(q.x + n.x * out, gy + y, q.y + n.y * out)
			front["glass"].append(Transform3D(b * Basis.from_scale(Vector3(wide, 1, 1)), at3.call(pos, 0.05, 1.3)))
			front["beam"].append(Transform3D(b * Basis.from_scale(Vector3(wide, 1, 1)), at3.call(pos, 0.08, 2.62)))
			for sgn: float in [-1.0, 1.0]:
				front["post"].append(Transform3D(b, at3.call(pos + along * 1.56 * wide * sgn, 0.08, 1.3)))
			var hue: String = role if kind != "shop" and sub == "" else AWNINGS[posmod(_hash_i(at), AWNINGS.size())]
			var look_k := posmod(_hash_i(at) >> 4, 100)
			if look_k >= 28:   # most have an awning; some just the sign over the window
				if not awnings.has(hue):
					awnings[hue] = []
				(awnings[hue] as Array).append(Transform3D(b * Basis(Vector3.RIGHT, 0.33) * Basis.from_scale(Vector3(wide, 1, 1)), at3.call(pos, 0.72, 2.9)))
			if look_k < 10 and kind.begins_with("shop"):   # shut: the roller shutter down
				front["shutter"].append(Transform3D(b * Basis.from_scale(Vector3(wide, 1, 1)), at3.call(pos, 0.1, 1.3)))
			if kind == "pharmacy":
				crosses.append(Transform3D(b, at3.call(pos + along * (1.6 * wide + 0.5), 0.5, 3.2)))
		if spot[2] and kind in ["cafe", "restaurant", "fast_food", "ice_cream", "bar", "pub"]:
			_terrace(pos, n, along, role, terrace, shades)
		var name := String(p[3]) if String(p[3]) != "" else (String(p[4]) if String(p[4]) != "" else String(look[1]))
		var sign := Label3D.new()
		sign.text = name
		sign.font = _font
		sign.font_size = 64
		sign.pixel_size = 0.011
		sign.outline_size = 8
		sign.modulate = Palette.col(role)
		sign.outline_modulate = Palette.col("bg")
		var sy := gy + (3.75 if spot[2] else 2.7)
		if station.is_finite():   # the name on the canopy's street edge
			pos = station + n * 3.05
			sy = _h(station) + 5.45
		sign.position = Vector3(pos.x + n.x * 0.16, sy, pos.y + n.y * 0.16)
		sign.rotation.y = face
		var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * 0.011
		boards.append(Transform3D(Basis(Vector3.UP, face) * Basis.from_scale(Vector3(maxf(tw + 0.5, 2.0), 1.0, 1.0)),
			Vector3(pos.x + n.x * 0.1, sy, pos.y + n.y * 0.1)))
		var bk := posmod(_hash_i(at) >> 9, 100)
		board_cols.append(_tone["board"] if bk < 45 else (_tone["mark"] if bk < 68 else
			(Palette.col(role).lerp(Palette.col("bg"), 0.55) if bk < 86 else _tone["wall3"])))
		sign.double_sided = false
		sign.visibility_range_end = SIGN_RANGE
		sign.set_meta("role", role)
		world.add_child(sign)
		_pois.append([at, role, sign])
		if not _life.is_empty():   # (built after the people's map of where life is: it counts there too)
			var lk := _cell(at, LIFE_CELL)
			_life[lk] = float(_life.get(lk, 0.0)) + 4.0
	if not boards.is_empty():
		var plate := BoxMesh.new()
		plate.size = Vector3(1.0, 0.95, 0.08)
		var bmat := _vc_mat()   # each board's own colour (instance colour)
		# cut into squares like everything else (one multimesh across the city is culled by
		# the middle of its box, and the boards vanished away from the town centre)
		_chunked(plate, boards, SIGN_RANGE * 3.0, board_cols, bmat)
	_terrace_meshes(terrace, shades)
	_tally("tables", (terrace["top"] as Array).size())
	_tally("shops", (front["glass"] as Array).size())
	var r := SIGN_RANGE * 2.0
	var glass := BoxMesh.new()
	glass.size = Vector3(3.0, 2.4, 0.06)
	_chunked(glass, front["glass"], r, [], _shop_glass(), false)
	var post := BoxMesh.new()
	post.size = Vector3(0.14, 2.6, 0.14)
	_chunked(post, front["post"], r, [], _surface("cartrim"), false)
	var beam := BoxMesh.new()
	beam.size = Vector3(3.26, 0.2, 0.16)
	_chunked(beam, front["beam"], r, [], _surface("cartrim"), false)
	if not (front["shutter"] as Array).is_empty():
		var shut := BoxMesh.new()
		shut.size = Vector3(3.0, 2.4, 0.05)
		_chunked(shut, front["shutter"], r, [], _surface("shutter"), false)
	var awning := BoxMesh.new()
	awning.size = Vector3(3.3, 0.14, 1.5)
	for hue: String in awnings:
		_chunked(awning, awnings[hue], r, [], mat(hue, 0.3), true)
	if not crosses.is_empty():
		var cross := ArrayMesh.new()
		var cb := Buf.new()
		_box(cb, Vector3.ZERO, Vector3(0.06, 0.78, 0.26))
		_box(cb, Vector3.ZERO, Vector3(0.06, 0.26, 0.78))
		cross.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cb.arrays())
		_chunked(cross, crosses, r, [], mat("friend", 1.3), false)
	if not (canopy["roof"] as Array).is_empty():
		var roof := BoxMesh.new()
		roof.size = Vector3(9.0, 0.45, 6.0)
		_chunked(roof, canopy["roof"], r, [], _surface("tank"))
		var band := BoxMesh.new()
		band.size = Vector3(9.06, 0.2, 6.06)
		_chunked(band, canopy["band"], r, [], mat("player", 0.4), false)
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.3, 4.6, 0.3)
		_chunked(pillar, canopy["pillar"], r, [], _surface("tank"))
		var pump := BoxMesh.new()
		pump.size = Vector3(0.7, 1.6, 0.45)
		_chunked(pump, canopy["pump"], r, [], mat("player", 0.15))

## bus stops: a shelter with a glass back, a roof and a bench, and the stop's pole and
## sign, on the pavement facing the street, its name along the roof edge
func _build_stops() -> void:
	var k := 1.0 / float(_city_data.get("scale", 10))
	var parts := {"back": [], "roof": [], "post": [], "bench": [], "pole": [], "plate": []}
	var all_stops: Array = _city_data.get("stops", [])
	for si: int in _tile_stops.get(_tile, []):
		if _over():
			await _pause()
		var st: Array = all_stops[si]
		var at := Vector2(st[0], st[1]) * k
		var road := _nearest_seg(at, 30.0, true, true)
		if road.is_empty():
			continue
		var q: Vector2 = road["q"]
		var out := (at - q).normalized()
		if out == Vector2.ZERO:
			continue
		var r: Dictionary = _roads[road["road"]]
		var c := q + out * (float(r["w"]) * 0.5 + 1.9)   # on the pavement, whatever the map said
		if _push_out(c, 1.2, false) != Vector2.ZERO:
			continue
		var n := -out                                       # the shelter faces the street
		var along := Vector2(-n.y, n.x)
		if not (_off_road(c - n * 0.6 + along * 1.5, 0.3) and _off_road(c - n * 0.6 - along * 1.5, 0.3)
				and _off_road(c + along * 2.4 + n * 0.5, 0.3)):
			continue   # a corner where another road comes by
		var gy := _h(c)
		var b := Basis(Vector3.UP, atan2(n.x, n.y))
		var P := func(p: Vector2, y: float) -> Vector3: return Vector3(p.x, gy + y, p.y)
		parts["back"].append(Transform3D(b, P.call(c - n * 0.7, 1.25)))
		_hash_add(_stop_hash, Rect2(c, Vector2.ZERO), SEG_CELL, _stop_spots.size())
		_stop_spots.append(c)
		parts["roof"].append(Transform3D(b, P.call(c, 2.55)))
		for sgn: float in [-1.0, 1.0]:
			parts["post"].append(Transform3D(b, P.call(c - n * 0.7 + along * 1.5 * sgn, 1.25)))
		parts["bench"].append(Transform3D(b, P.call(c - n * 0.4, 0.45)))
		var pole := c + along * 2.4 + n * 0.5
		parts["pole"].append(Transform3D(b, P.call(pole, 1.4)))
		parts["plate"].append(Transform3D(b, P.call(pole, 2.45)))
		# a lit ad panel standing at the other end of the shelter, square to it
		var ad := c - along * 2.0 - n * 0.35
		if _off_road(ad, 0.3) and _push_out(ad, 0.5, false) == Vector2.ZERO and _clear_of_posts(ad, 1.0):
			_stop_ads.append(Transform3D(Basis(Vector3.UP, atan2(along.x, along.y)), P.call(ad, 0.0)))
			_add_post(ad, 0.6)
		_add_post(c - n * 0.6 + along * 1.5, 0.2)
		_add_post(c - n * 0.6 - along * 1.5, 0.2)
		add_wall(c - n * 0.7 + along * 1.5, c - n * 0.7 - along * 1.5, 0.08)   # its back
		_add_post(pole, 0.1)
		_add_post(pole, 0.12)
		var name := String(st[2])
		if name != "":
			var lb := Label3D.new()
			lb.text = name
			lb.font = _font
			lb.font_size = 40
			lb.pixel_size = 0.008
			lb.outline_size = 6
			lb.modulate = Palette.col("ink")
			lb.outline_modulate = Palette.col("bg")
			lb.position = P.call(c + n * 0.82, 2.42)
			lb.rotation.y = atan2(n.x, n.y)
			lb.double_sided = false
			lb.visibility_range_end = 60.0
			world.add_child(lb)
	if (parts["back"] as Array).is_empty():
		return
	var r := SIGN_RANGE * 1.6
	_chunked(_boxm(Vector3(3.2, 2.3, 0.05)), parts["back"], r, [], _shop_glass(), false)
	_chunked(_furn.bus_roof_kit(), parts["roof"], r)
	_chunked(_boxm(Vector3(0.08, 2.5, 0.08)), parts["post"], r, [], _surface("pole"))
	_chunked(_boxm(Vector3(2.0, 0.08, 0.42)), parts["bench"], r, [], _surface("furniture"))
	_chunked(_boxm(Vector3(0.07, 2.8, 0.07)), parts["pole"], r, [], _surface("pole"))
	_chunked(_furn.bus_sign_kit(), parts["plate"], r)
	_tally("bus_stops", (parts["back"] as Array).size())

func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

## [colour role, word for an unnamed one] for a place's OSM kind; [] = not shown
func _poi_look(kind: String) -> Array:
	if POI_LOOK.has(kind):
		return POI_LOOK[kind]
	if kind.begins_with("shop:"):
		var t := kind.substr(5)
		return ["accent", SHOP_WORDS.get(t, t.replace("_", " "))]
	return []

## the glass of a shop window: dark glass with the shop's light on inside
func _shop_glass() -> StandardMaterial3D:
	if _smat.has("shopglass"):
		return _smat["shopglass"]
	var m := _surface("glass").duplicate() as StandardMaterial3D
	m.set_meta("tone", "glass")
	m.roughness = 0.12
	m.metallic = 0.3
	m.emission_enabled = true
	m.emission = _tone["shoplight"]
	m.emission_energy_multiplier = 0.7
	_smat["shopglass"] = m
	return m

## a gas station: a canopy on four pillars over two pumps, square to the street
func _gas_station(at: Vector2, n: Vector2, c: Dictionary) -> void:
	var along := Vector2(-n.y, n.x)
	var gy := _h(at)
	var b := Basis(Vector3.UP, atan2(n.x, n.y))
	c["roof"].append(Transform3D(b, Vector3(at.x, gy + 4.85, at.y)))
	c["band"].append(Transform3D(b, Vector3(at.x, gy + 4.85, at.y)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var q := at + along * 3.6 * sx + n * 2.2 * sz
			c["pillar"].append(Transform3D(b, Vector3(q.x, gy + 2.3, q.y)))
			_add_post(q, 0.25)
		var pq := at + along * 1.8 * sx
		c["pump"].append(Transform3D(b, Vector3(pq.x, gy + 0.8, pq.y)))
		_add_post(pq, 0.45)

## tables and chairs on the pavement in front of a cafe or restaurant, umbrellas over
## them in the place's colour -- where there is pavement (not road, not building)
func _terrace(pos: Vector2, n: Vector2, along: Vector2, role: String, t: Dictionary, shades: Dictionary) -> void:
	for off: float in [-2.3, 0.0, 2.3]:
		var c := pos + n * 2.6 + along * off
		if _push_out(c, 0.9, false) != Vector2.ZERO:
			continue
		var on := _nearest_seg(c, 12.0, true)
		if not on.is_empty() and float(on["edge"]) < 0.9:
			continue
		var gy := _h(c)
		var face := atan2(along.x, along.y)
		t["top"].append(Transform3D(Basis(), Vector3(c.x, gy + 0.74, c.y)))
		t["leg"].append(Transform3D(Basis(), Vector3(c.x, gy + 0.37, c.y)))
		for sgn: float in [-1.0, 1.0]:
			var ch := c + along * 0.62 * sgn
			var b := Basis(Vector3.UP, face + (0.0 if sgn > 0.0 else PI))
			t["seat"].append(Transform3D(b, Vector3(ch.x, gy + 0.45, ch.y)))
			var bk := ch + along * 0.2 * sgn
			t["back"].append(Transform3D(b, Vector3(bk.x, gy + 0.68, bk.y)))
		t["pole"].append(Transform3D(Basis(), Vector3(c.x, gy + 1.2, c.y)))
		_table_spots.append(c)
		if not shades.has(role):
			shades[role] = []
		(shades[role] as Array).append(Transform3D(Basis(), Vector3(c.x, gy + 2.35, c.y)))
		_add_post(c, 0.7)

func _terrace_meshes(t: Dictionary, shades: Dictionary) -> void:
	if (t["top"] as Array).is_empty():
		return
	var furn := _surface("furniture")
	var top := CylinderMesh.new()
	top.top_radius = 0.4
	top.bottom_radius = 0.4
	top.height = 0.04
	top.radial_segments = 10
	var leg := CylinderMesh.new()
	leg.top_radius = 0.035
	leg.bottom_radius = 0.035
	leg.height = 0.72
	leg.radial_segments = 5
	var seat := BoxMesh.new()
	seat.size = Vector3(0.42, 0.05, 0.42)
	var back := BoxMesh.new()
	back.size = Vector3(0.42, 0.42, 0.05)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.025
	pole.height = 2.4
	pole.radial_segments = 4
	for pair: Array in [[top, "top"], [leg, "leg"], [seat, "seat"], [back, "back"], [pole, "pole"]]:
		_chunked(pair[0], t[pair[1]], SIGN_RANGE * 1.5, [], furn)
	var shade := CylinderMesh.new()
	shade.top_radius = 0.03
	shade.bottom_radius = 1.25
	shade.height = 0.4
	shade.radial_segments = 10
	for role: String in shades:
		_chunked(shade, shades[role], SIGN_RANGE * 1.5, [], mat(role, 0.15))

## where a place's front goes: [point, outward normal, true if on a building wall]. The
## wall of its building (or the nearest one) closest to the street; otherwise a free-
## standing sign on the spot, facing the street.
func _facade_spot(at: Vector2) -> Array:
	var road := _nearest_seg(at, 60.0, true, true)
	var street: Vector2 = road["q"] if not road.is_empty() else at + Vector2(0, 1)
	var best := INF
	var out: Array = []
	for i: int in _near(_bld_hash, at, 16.0, BLD_CELL):
		if not (_bld_box[i] as Rect2).grow(16.0).has_point(at):
			continue
		var poly: PackedVector2Array = _blds[i]
		var inside := Geometry2D.is_point_in_polygon(at, poly)
		var area := 0.0
		for j in range(poly.size()):
			area += poly[j].x * poly[(j + 1) % poly.size()].y - poly[(j + 1) % poly.size()].x * poly[j].y
		for j in range(poly.size()):
			var a := poly[j]
			var b := poly[(j + 1) % poly.size()]
			if a.distance_to(b) < 2.5:
				continue
			var c := Geometry2D.get_closest_point_to_segment(street, a, b)
			var score := c.distance_to(street) + (0.0 if inside else 2.0 * c.distance_to(at))
			if score < best:
				best = score
				var e := (b - a).normalized()
				out = [c, Vector2(e.y, -e.x) * (1.0 if area > 0.0 else -1.0), true]
	if out.is_empty():
		var face := (street - at).normalized() if street != at else Vector2(0, 1)
		out = [at, face, false]
	return out

func _multi(mesh: Mesh, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	world.add_child(mi)
	return mi

func _signals_tick(dt: float) -> void:
	if _sig_mats.is_empty():
		return
	_sig_t += dt
	var step: Array = SIGNAL_CYCLE[_sig_phase]
	if _sig_t >= float(step[0]):
		_sig_t = 0.0
		_sig_phase = (_sig_phase + 1) % SIGNAL_CYCLE.size()
		_apply_signals()

## ---- paint at junctions, speed limits --------------------------------------------------------
var _stop_lines: Array = []          ## [junction, way in, line before it, road width, one-way, "stop" or ""]

## A solid stop line across the lane at every light and stop sign; STOP painted before a
## stop sign's line (עצור in Givatayim); SLOW (האט) before a crossing near a school.
func _build_road_paint() -> void:
	var paint := CBuf.new(GROUND_CELL)
	var med := String(_place.get("look", "")) == "med"
	for sl: Array in _stop_lines:
		var c: Vector2 = sl[0]
		var dir: Vector2 = sl[1]
		var w: float = sl[3]
		var right := Vector2(-dir.y, dir.x)
		var at := c - dir * float(sl[2])
		var o0 := -(w * 0.5 - 0.25) if sl[4] else 0.15
		var o1 := w * 0.5 - 0.25
		paint.quad3(_g3(at + right * o0, Y_MARK + 0.002), _g3(at + right * o1, Y_MARK + 0.002),
			_g3(at + right * o1 - dir * 0.45, Y_MARK + 0.002), _g3(at + right * o0 - dir * 0.45, Y_MARK + 0.002))
		if sl[5] == "stop":
			_road_word("עצור" if med else "STOP", at - dir * 2.6 + right * ((o0 + o1) * 0.5), dir)
	# SLOW before the crossings near a school or a kindergarten
	var schools := _schools
	for ni: int in _tile_nodes.get(_tile, []):
		if not _crossing_set.has(ni):
			continue
		if _over():
			await _pause()
		var c := _nodes[ni]
		var near := false
		for sc: Vector2 in schools:
			if sc.distance_to(c) < 150.0:
				near = true
				break
		if not near:
			continue
		for e: Vector2i in _node_roads[ni]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"] or r["k"] == "service":
				continue
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [-1, 1]:
				var from := e.y + d2
				if from < 0 or from >= pts.size() or (r["o"] != 0 and r["o"] != -d2):
					continue
				var dir := (c - pts[from]).normalized()
				if c.distance_to(pts[from]) < 16.0:
					continue
				var lane := _lane_off(r)
				_road_word("האט" if med else "SLOW", c - dir * 12.0 + Vector2(-dir.y, dir.x) * lane, dir)
	_add_mesh(paint, _surface("mark"), false, DETAIL_RANGE)

## a word painted on the road, read by a driver going `dir`: flat, stretched long the way
## road lettering is so it reads at a shallow angle
func _road_word(text: String, at: Vector2, dir: Vector2) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.font = _font
	lb.font_size = 96
	lb.pixel_size = 0.012
	lb.outline_size = 0
	lb.modulate = _tone["mark"]
	lb.shaded = true
	lb.double_sided = false
	var right3 := Vector3(-dir.y, 0.0, dir.x)
	var fwd3 := Vector3(dir.x, 0.0, dir.y)
	lb.transform = Transform3D(Basis(right3, fwd3 * 2.2, Vector3.UP), _g3(at, Y_MARK + 0.012))
	lb.visibility_range_end = 70.0
	world.add_child(lb)

## Speed limits on the main roads: a sign a little after each junction, every way the road
## runs. Round and red-rimmed in Givatayim; a white MAXIMUM board in Bedford.
func _build_speed_signs() -> void:
	var med := String(_place.get("look", "")) == "med"
	var poles: Array = []
	var plates: Array = []
	var rims: Array = []
	for ri: int in _tile_roads.get(_tile, []):
		var r: Dictionary = _roads[ri]
		if not r["drive"] or r["pv"] or not MAIN_ROADS.has(r["k"]):
			continue
		if _over():
			await _pause()
		var kmh := int(round(float(r["speed"]) * 3.6 / 10.0)) * 10
		for run: PackedVector2Array in _street_runs(r):
			var cum := PackedFloat32Array([0.0])
			for i in range(1, run.size()):
				cum.append(cum[i - 1] + run[i - 1].distance_to(run[i]))
			var total := cum[cum.size() - 1]
			if total < 120.0:
				continue
			for d2: int in [1, -1]:
				if r["o"] != 0 and r["o"] != d2:
					continue
				var s := 18.0 if d2 > 0 else total - 18.0
				var a := _along(run, cum, s)
				var b := _along(run, cum, s + 1.0 * d2)
				var dir := (b - a).normalized()
				var right := Vector2(-dir.y, dir.x)
				var p := a + right * (float(r["w"]) * 0.5 + 0.9)
				if not _mine(p) or _push_out(p, 0.4, true, false) != Vector2.ZERO or not _off_road(p, 0.4):
					continue
				var gy := _h(p)
				var face := Basis(Vector3.UP, atan2(-dir.x, -dir.y))
				poles.append(Transform3D(Basis(), Vector3(p.x, gy + 1.1, p.y)))
				var mid := Vector3(p.x, gy + 2.35, p.y)
				if med:
					rims.append(Transform3D(face * Basis(Vector3.RIGHT, PI * 0.5), mid))
					plates.append(Transform3D(face * Basis(Vector3.RIGHT, PI * 0.5), mid - Vector3(dir.x, 0, dir.y) * 0.02))
				else:
					rims.append(Transform3D(face, mid))
					plates.append(Transform3D(face, mid - Vector3(dir.x, 0, dir.y) * 0.02))
				_add_post(p, 0.08)
				_landmarks.append([p, "speed", dir])
				var lb := Label3D.new()
				lb.text = str(kmh)
				lb.font = _font
				lb.font_size = 64
				lb.pixel_size = 0.0055 if med else 0.0062
				lb.outline_size = 0
				lb.modulate = Palette.col("bg")
				lb.shaded = true
				lb.double_sided = false
				var front := mid - Vector3(dir.x, 0, dir.y) * 0.045
				lb.position = front + (Vector3.ZERO if med else Vector3(0, -0.08, 0))
				lb.rotation.y = atan2(-dir.x, -dir.y)
				lb.visibility_range_end = 60.0
				world.add_child(lb)
				if not med:
					var top := Label3D.new()
					top.text = "MAXIMUM"
					top.font = _font
					top.font_size = 32
					top.pixel_size = 0.0045
					top.modulate = Palette.col("bg")
					top.shaded = true
					top.double_sided = false
					top.position = front + Vector3(0, 0.24, 0)
					top.rotation.y = lb.rotation.y
					top.visibility_range_end = 45.0
					world.add_child(top)
	if poles.is_empty():
		return
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.035
	pole.height = 2.2
	pole.radial_segments = 6
	pole.rings = 1
	pole.material = _surface("pole")
	_chunked(pole, poles, LAMP_RANGE)
	if med:
		var rim := CylinderMesh.new()
		rim.top_radius = 0.4
		rim.bottom_radius = 0.4
		rim.height = 0.03
		rim.radial_segments = 16
		rim.rings = 1
		rim.material = mat("hazard", 0.15)
		var face := CylinderMesh.new()
		face.top_radius = 0.31
		face.bottom_radius = 0.31
		face.height = 0.03
		face.radial_segments = 16
		face.rings = 1
		face.material = _surface("mark")
		_chunked(rim, rims, LAMP_RANGE)
		_chunked(face, plates, LAMP_RANGE)
	else:
		var border := _boxm(Vector3(0.66, 0.84, 0.02))
		border.material = _surface("pole")
		var board := _boxm(Vector3(0.6, 0.78, 0.03))
		board.material = _surface("mark")
		_chunked(border, rims, LAMP_RANGE)
		_chunked(board, plates, LAMP_RANGE)
	_tally("speed_signs", poles.size())

## ---- the signs every street has ------------------------------------------------------------
## Green street-name plates at the corners (Hebrew and English), a blue roundabout sign on
## every way into one, a blue crossing sign on both sides of each zebra and on every
## traffic-light pole, a P at the car parks, no-entry at the wrong end of a one-way street
## and the blue one-way arrow at its right end, "turn this way" where only one way out is
## allowed, "keep right" where a street splits round an island, and painted lane arrows
## before the junctions of the main roads.
var _sign_meshes := {}
var _pole_plates: Array = []         ## [kind, transform] of plates on poles built elsewhere
const SIGN_SCALE := 1.35
## Street-name plates are thousands; their names are drawn only near the car, by a small
## pool of labels handed to the nearest plates every so often (two thousand labels made up
## front cost a second of loading and a node each).
var _name_signs: Array = []          ## [transform, text]
var _name_hash := {}
var _name_pool: Array = []
var _name_t := 0.0
const NAME_POOL := 18
const NAME_SEEN := 55.0

func _names_tick(dt: float) -> void:
	_name_t -= dt
	if _name_t > 0.0 or _name_signs.is_empty():
		return
	_name_t = 0.4
	if _name_pool.is_empty():
		for i in range(NAME_POOL):
			var lb := Label3D.new()
			lb.font = _font
			lb.font_size = 40
			lb.pixel_size = 0.0058
			lb.outline_size = 0
			lb.modulate = _tone["mark"]
			# crisp and full white, like the reflective letters of a real plate: shaded and
			# blended they came out grey and see-through
			lb.shaded = false
			lb.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
			lb.double_sided = false
			lb.line_spacing = -6.0
			lb.visible = false
			world.add_child(lb)
			_name_pool.append(lb)
	var near: Array = []
	for i: int in _near(_name_hash, _pos, NAME_SEEN, 50.0):
		var xf: Transform3D = _name_signs[i][0]
		var d := Vector2(xf.origin.x, xf.origin.z).distance_to(_pos)
		if d < NAME_SEEN:
			near.append([d, i])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in range(_name_pool.size()):
		var lb: Label3D = _name_pool[k]
		if k < near.size():
			var sg: Array = _name_signs[near[k][1]]
			if lb.text != sg[1]:
				lb.text = sg[1]
				lb.pixel_size = _name_fit(String(sg[1]))
			lb.transform = sg[0]
			lb.visible = true
		else:
			lb.visible = false

## the label size that keeps a street's name inside the green of its plate (about 1.1 by
## 0.26 m before SIGN_SCALE): long names get smaller letters instead of running off the end
func _name_fit(text: String) -> float:
	var w := 1.0
	var lines := text.split("\n")
	for line: String in lines:
		w = maxf(w, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x)
	var h := lines.size() * (_font.get_height(40) - 6.0)
	return minf(0.0058, minf(1.06 / w, 0.25 / maxf(h, 1.0)))

var _planted: Array = []             ## [kind, where, the way its face looks(, road)] of the signs that order

func _build_street_signs() -> void:
	var med := String(_place.get("look", "")) == "med"
	var plates := {}     # kind -> transforms
	var poles: Array = []
	var marks := CBuf.new(GROUND_CELL)
	var plant := func(kind: String, p: Vector2, facing: Basis, h: float) -> void:
		if not plates.has(kind):
			plates[kind] = []
		var gy := _h(p)
		# a third bigger than life: on a screen, at driving distance, life-size is a speck
		(plates[kind] as Array).append(Transform3D(facing * Basis.from_scale(Vector3.ONE * SIGN_SCALE), Vector3(p.x, gy + h, p.y)))
		poles.append(Transform3D(Basis.from_scale(Vector3(1, h / 2.2, 1)), Vector3(p.x, gy + h * 0.5, p.y)))
		_add_post(p, 0.06)
		if kind in ["noentry", "turn_l", "turn_r"]:   # (for tests: which way each one faces)
			_planted.append([kind, p, Vector2((facing * Vector3.BACK).x, (facing * Vector3.BACK).z)])
	var toward := func(dir: Vector2) -> Basis: return Basis(Vector3.UP, atan2(-dir.x, -dir.y))
	var side_spot := func(c: Vector2, dir: Vector2, back: float, w: float) -> Vector2:
		return c - dir * back + Vector2(-dir.y, dir.x) * (w * 0.5 + 0.8)
	var named := 0
	# the crossing signs strapped to the traffic-light poles: their pole is the light's
	for pp: Array in _pole_plates:
		if not plates.has(pp[0]):
			plates[pp[0]] = []
		(plates[pp[0]] as Array).append(pp[1])
	# the point `dist` metres along a road's points from index k, going `step` (+1 or -1)
	var walk := func(pts: PackedVector2Array, k: int, step: int, dist: float) -> Vector2:
		var left := dist
		while k + step >= 0 and k + step < pts.size():
			var seg := pts[k].distance_to(pts[k + step])
			if seg >= left:
				return pts[k].lerp(pts[k + step], left / maxf(seg, 0.001))
			left -= seg
			k += step
		return pts[k]
	var spot_free := func(p: Vector2, margin: float) -> bool:
		return _off_road(p, margin) and _push_out(p, 0.4, true, false) == Vector2.ZERO
	for ni: int in _tile_nodes.get(_tile, []):
		if _over():
			await _pause()
		var ways := _node_ways(ni)
		if ways < 2:
			continue
		var c := _nodes[ni]
		if ways == 3:
			_keep_right_at(ni, walk, spot_free, plant, toward)
		var arrivals: Array = []   # [dir in, road]
		var seen_names := {}
		for e: Vector2i in _node_roads[ni]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"] or r["pv"] or r["k"] == "service":
				continue
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [-1, 1]:
				var from := e.y + d2
				if from < 0 or from >= pts.size():
					continue
				var dir := (c - pts[from]).normalized()
				if r["o"] == 0 or r["o"] == -d2:
					arrivals.append([dir, r, c.distance_to(pts[from])])
				if ways >= 3 and r["o"] == -d2 and not _short_link(r, e.y, d2):
					# a one-way street whose traffic comes out here: driving into it from the
					# junction is against it -- no entry, facing whoever would turn in, on the
					# right and (a wide one) the left. (It stood at the other end, where
					# going in is the way the street runs: autodrive drove in under it.)
					var w: float = r["w"]
					for sd: float in ([1.0, -1.0] if w >= 9.0 else [1.0]):
						var sp: Vector2 = c - dir * (_node_r[ni] + 3.0) + Vector2(dir.y, -dir.x) * sd * (w * 0.5 + 0.8)
						if _off_road(sp, 0.4) and _push_out(sp, 0.4, true, false) == Vector2.ZERO:
							plant.call("noentry", sp, toward.call(-dir), 2.2)
							(_planted.back() as Array).append(e.x)
		if ways < 3:
			continue
		for a: Array in arrivals:
			var dir: Vector2 = a[0]
			var r: Dictionary = a[1]
			var w: float = r["w"]
			# a roundabout ahead
			var ring_ahead := false
			for e: Vector2i in _node_roads[ni]:
				if (_roads[e.x] as Dictionary).get("ring", false) and not r.get("ring", false):
					ring_ahead = true
			if ring_ahead:
				var sp: Vector2 = side_spot.call(c, dir, _node_r[ni] + 6.0, w)
				if _off_road(sp, 0.4) and _push_out(sp, 0.4, true, false) == Vector2.ZERO:
					plant.call("roundabout", sp, toward.call(dir), 2.2)
			# lane arrows before the junctions of the main roads
			if MAIN_ROADS.has(r["k"]) and float(a[2]) > 30.0 and not r.get("ring", false):
				_lane_arrows(marks, ni, dir, r)
			# only one way out (the street across the end is one-way): the blue "turn this
			# way" across the junction, facing the street coming in
			# (not at one point of a junction drawn as several: the ways on from one point
			# are not the junction's -- "turn left" stood where the road runs straight on
			# through the next point)
			if not r.get("ring", false) and not ring_ahead and not _in_knot(ni):
				var mv := _moves(ni, dir)
				if mv.size() == 1 and not mv.has("s"):
					for extra: float in [0.8, 1.8, 2.8, 3.8]:
						var far := c + dir * (_node_r[ni] + extra)
						if spot_free.call(far, 0.4):
							plant.call("turn_r" if mv.has("r") else "turn_l", far, toward.call(dir), 2.2)
							break
		# a one-way street leaving here: the blue arrow at its corner, side-on to the street
		# it leaves from so the cross traffic reads which way it runs (under the name plate
		# when there is one: same corner, same pole)
		for e: Vector2i in _node_roads[ni]:
			var r: Dictionary = _roads[e.x]
			if ways < 3 or r["o"] == 0 or not r["drive"] or r.get("ring", false) or r["k"] == "service" \
					or HIGHWAYS.has(r["k"]) or r["k"] == "primary" or r["k"] == "primary_link":
				continue   # (a one-way primary is mostly half of a dual carriageway: no arrow)
			var nxt: int = e.y + int(r["o"])
			var pts: PackedVector2Array = r["pts"]
			if nxt < 0 or nxt >= pts.size():
				continue
			var along := (pts[nxt] - c).normalized()
			var across := Vector2(-along.y, along.x)
			var w: float = r["w"]
			for side: float in [1.0, -1.0]:
				var corner := c + along * (w * 0.5 + 2.0) + across * side * (w * 0.5 + 1.0)
				if spot_free.call(corner, 0.5):
					plant.call("oneway", corner, Basis(Vector3.UP, atan2(along.x, along.y) - PI * 0.5), 2.0)
					break
		# a street-name plate at a corner for each named street through it, parallel to it,
		# read from the cross street
		for e: Vector2i in _node_roads[ni]:
			var r: Dictionary = _roads[e.x]
			var nm := String(r["name"])
			if nm == "" or seen_names.has(nm) or not r["drive"] or r["k"] == "service" or HIGHWAYS.has(r["k"]):
				continue
			seen_names[nm] = true
			var pts: PackedVector2Array = r["pts"]
			var k2 := e.y + 1 if e.y + 1 < pts.size() else e.y - 1
			var along := (pts[k2] - c).normalized()
			var across := Vector2(-along.y, along.x)
			var corner := c + along * (float(r["w"]) * 0.5 + 2.0) + across * (float(r["w"]) * 0.5 + 1.0)
			if not _off_road(corner, 0.5) or _push_out(corner, 0.5, true, false) != Vector2.ZERO:
				corner = c - along * (float(r["w"]) * 0.5 + 2.0) - across * (float(r["w"]) * 0.5 + 1.0)
				if not _off_road(corner, 0.5) or _push_out(corner, 0.5, true, false) != Vector2.ZERO:
					continue
			var face := Basis(Vector3.UP, atan2(along.x, along.y) - PI * 0.5)   # its face looks across the street it names
			plant.call("street", corner, face, 2.6)
			var en := String(r["en"])
			var text := ("רח' " + nm + ("\n" + en.to_upper() if en != "" else "")) if med else (en if en != "" else nm)
			_hash_add(_name_hash, Rect2(corner, Vector2.ZERO), 50.0, _name_signs.size())
			_name_signs.append([Transform3D(face * Basis.from_scale(Vector3.ONE * SIGN_SCALE), Vector3(corner.x, _h(corner) + 2.6, corner.y) + face * Vector3(0, 0, 0.04)), text])
			named += 1
	# crossing signs, both sides of each zebra
	for ni: int in _tile_nodes.get(_tile, []):
		if not _crossing_set.has(ni):
			continue
		var c := _nodes[ni]
		for e: Vector2i in _node_roads[ni]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"] or r["k"] == "service":
				continue
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [-1, 1]:
				var from := e.y + d2
				if from < 0 or from >= pts.size() or (r["o"] != 0 and r["o"] != -d2):
					continue
				var dir := (c - pts[from]).normalized()
				var sp: Vector2 = side_spot.call(c, dir, 2.5, float(r["w"]))
				if _off_road(sp, 0.4) and _push_out(sp, 0.4, true, false) == Vector2.ZERO:
					plant.call("crossing", sp, toward.call(dir), 2.4)
			break
	# car parks: a P by the road at the corner nearest it
	for ring: PackedVector2Array in _rings_near("parking"):
		if _area(ring) < 300.0 or not _ring_mine(ring):
			continue
		var best := INF
		var at := Vector2.ZERO
		var dir := Vector2.ZERO
		for q in ring:
			var hit := _nearest_seg(q, 25.0, true, true)
			if not hit.is_empty() and float(hit["edge"]) < best and float(hit["edge"]) > 0.6:
				best = float(hit["edge"])
				at = q
				dir = ((hit["q"] as Vector2) - q).normalized()
		if best < INF and _push_out(at, 0.4, true, false) == Vector2.ZERO:
			plant.call("parking", at, Basis(Vector3.UP, atan2(dir.x, dir.y)), 2.3)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.035
	pole.height = 2.2
	pole.radial_segments = 6
	pole.rings = 1
	pole.material = _surface("pole")
	_chunked(pole, poles, LAMP_RANGE)
	for kind: String in plates:
		_chunked(_street_sign_mesh(kind), plates[kind], LAMP_RANGE)
		_tally("sign_" + kind, (plates[kind] as Array).size())
	_add_mesh(marks, _surface("mark"), false, DETAIL_RANGE)
	_tally("street_signs", poles.size())
	_tally("street_names", named)

## A two-way street splitting into a pair of one-way carriageways at node `ni` (three ways:
## the street in, one carriageway out and one back): a blue "keep right" on the nose of the
## island between them, facing the street coming in.
func _keep_right_at(ni: int, walk: Callable, spot_free: Callable, plant: Callable, toward: Callable) -> void:
	var c := _nodes[ni]
	var two: Array = []      # direction coming in on the two-way street
	var outs: Array = []     # [points, index, step] of the carriageway leaving
	var ins: Array = []      # ...and the one coming back
	for e: Vector2i in _node_roads[ni]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		if r["k"] == "service" or r.get("ring", false):
			return
		var pts: PackedVector2Array = r["pts"]
		for d2: int in [-1, 1]:
			var k := e.y + d2
			if k < 0 or k >= pts.size():
				continue
			if r["o"] == 0:
				two.append((c - pts[k]).normalized())
			elif r["o"] == d2:
				outs.append([pts, e.y, d2])
			else:
				ins.append([pts, e.y, d2])
	if two.size() != 1 or outs.size() != 1 or ins.size() != 1:
		return
	var dir: Vector2 = two[0]
	for dist: float in [8.0, 12.0, 16.0, 20.0]:
		var pa: Vector2 = walk.call(outs[0][0], outs[0][1], outs[0][2], dist)
		var pb: Vector2 = walk.call(ins[0][0], ins[0][1], ins[0][2], dist)
		var nose := (pa + pb) * 0.5
		if pa.distance_to(pb) > 24.0 or (nose - c).dot(dir) < dist * 0.6:
			return   # not a pair carrying on ahead side by side: a junction, not a split
		if spot_free.call(nose, 0.3):
			plant.call("keepright", nose, toward.call(dir), 1.6)
			return

## painted arrows in the lane(s) coming into junction `ni` going `dir`: straight, right,
## left -- whichever ways out there are from it
func _lane_arrows(buf: Buf, ni: int, dir: Vector2, r: Dictionary) -> void:
	var c := _nodes[ni]
	var moves := _moves(ni, dir)
	if moves.is_empty():
		return
	var w: float = r["w"]
	var lanes: Array = []
	if r["o"] == 0:
		lanes = [clampf(w * 0.25, 1.2, 1.9)]
	else:
		var n := maxi(1, int(r["l"]) if int(r["l"]) > 0 else int(w / 3.4))
		for i in range(n):
			lanes.append(-w * 0.5 + w * (i + 0.5) / n)
	var right := Vector2(-dir.y, dir.x)
	var y := Y_MARK + 0.004
	for lane: float in lanes:
		var a := c - dir * (_node_r[ni] + 16.0) + right * lane
		var quad := func(p0: Vector2, p1: Vector2, half: float) -> void:
			var d := (p1 - p0).normalized()
			var n := Vector2(-d.y, d.x) * half
			buf.quad3(_g3(p0 - n, y), _g3(p1 - n, y), _g3(p1 + n, y), _g3(p0 + n, y))
		var head := func(base: Vector2, d: Vector2) -> void:
			var n := Vector2(-d.y, d.x)
			buf.tri(_g3(base - n * 0.38, y), _g3(base + n * 0.38, y), _g3(base + d * 1.1, y), Vector3.UP, Color.WHITE)
		quad.call(a - dir * 2.6, a + dir * 0.4, 0.09)
		if moves.has("s"):
			quad.call(a + dir * 0.4, a + dir * 1.0, 0.09)
			head.call(a + dir * 1.0, dir)
		for t: String in ["r", "l"]:
			if moves.has(t):
				var sd := right if t == "r" else -right
				quad.call(a + dir * 0.2, a + dir * 0.2 + sd * 0.75, 0.09)
				head.call(a + dir * 0.2 + sd * 0.75, sd)

## the ways out of junction `ni` for a car arriving going `dir`: "s" straight on, "r" right,
## "l" left (never back the way it came, never the wrong way down a one-way)
## a short piece (under 30 m) from point k of road r going `step` to another junction: a link
## inside a junction drawn as several points, not a street
func _short_link(r: Dictionary, k: int, step: int) -> bool:
	var pts: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	var run := 0.0
	var i := k
	while i + step >= 0 and i + step < pts.size():
		run += pts[i].distance_to(pts[i + step])
		i += step
		if run > 30.0:
			return false
		if _node_ways(ids[i]) >= 3:
			return true
	return false

## node ni is one point of a junction drawn as several: another junction point within 30 m
## along one of its roads
func _in_knot(ni: int) -> bool:
	for e: Vector2i in _node_roads[ni]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		for step: int in [1, -1]:
			if _short_link(r, e.y, step):
				return true
	return false

func _moves(ni: int, dir: Vector2) -> Dictionary:
	var c := _nodes[ni]
	var moves := {}
	for e: Vector2i in _node_roads[ni]:
		var r2: Dictionary = _roads[e.x]
		if not r2["drive"] or r2["pv"] or r2["k"] == "service":
			continue
		var p2: PackedVector2Array = r2["pts"]
		for d2: int in [1, -1]:
			var nxt := e.y + d2
			if nxt < 0 or nxt >= p2.size() or (r2["o"] != 0 and r2["o"] != d2):
				continue
			var go := (p2[nxt] - c).normalized()
			var turn := dir.angle_to(go)
			if absf(turn) > 2.6:
				continue   # back the way it came
			moves["s" if absf(turn) < 0.5 else ("r" if turn > 0.0 else "l")] = true
	return moves

## a sign's plate as one surface (its colours in the vertex colours), facing +Z, grey behind
## (the one-way arrow is painted on both faces: it stands side-on to the cross street)
func _street_sign_mesh(kind: String) -> ArrayMesh:
	if _sign_meshes.has(kind):
		return _sign_meshes[kind]
	var b := Buf.new()
	var blue: Color = _tone["signblue"]
	var white: Color = _tone["mark"]
	var red: Color = _tone["signred"]
	var green: Color = _tone["signgreen"]
	var back: Color = _tone["pole"]
	var flat := func(pts: Array, z: float, col: Color) -> void:
		for i in range(1, pts.size() - 1):
			var p0: Vector2 = pts[0]
			var p1: Vector2 = pts[i]
			var p2: Vector2 = pts[i + 1]
			b.tri(Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z), Vector3(p2.x, p2.y, z), Vector3.BACK, col)
			if z < 0.005:   # the back
				b.tri(Vector3(p0.x, p0.y, z - 0.01), Vector3(p2.x, p2.y, z - 0.01), Vector3(p1.x, p1.y, z - 0.01), Vector3.FORWARD, back)
	var circle := func(r: float) -> Array:
		var out: Array = []
		for i in range(16):
			out.append(Vector2(cos(TAU * i / 16.0), sin(TAU * i / 16.0)) * r)
		return out
	var box := func(cx: float, cy: float, w: float, h: float) -> Array:
		return [Vector2(cx - w * 0.5, cy - h * 0.5), Vector2(cx + w * 0.5, cy - h * 0.5), Vector2(cx + w * 0.5, cy + h * 0.5), Vector2(cx - w * 0.5, cy + h * 0.5)]
	# both faces in the same colour, for a plate seen from either side
	var both := func(pts: Array, z: float, col: Color) -> void:
		for i in range(1, pts.size() - 1):
			var p0: Vector2 = pts[0]
			var p1: Vector2 = pts[i]
			var p2: Vector2 = pts[i + 1]
			b.tri(Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z), Vector3(p2.x, p2.y, z), Vector3.BACK, col)
			b.tri(Vector3(p0.x, p0.y, -z - 0.01), Vector3(p2.x, p2.y, -z - 0.01), Vector3(p1.x, p1.y, -z - 0.01), Vector3.FORWARD, col)
	# left-right mirror of a polygon, wound the same way round
	var mirror := func(pts: Array) -> Array:
		var out: Array = []
		for i in range(pts.size() - 1, -1, -1):
			out.append(Vector2(-(pts[i] as Vector2).x, (pts[i] as Vector2).y))
		return out
	match kind:
		"oneway":
			both.call(box.call(0, 0, 0.7, 0.3), 0.0, blue)
			both.call(box.call(-0.07, 0.0, 0.4, 0.07), 0.006, white)
			both.call([Vector2(0.12, -0.11), Vector2(0.29, 0.0), Vector2(0.12, 0.11)], 0.006, white)
		"turn_r", "turn_l":
			# the blue "this way only": up from the bottom, then round the corner
			flat.call(circle.call(0.32), 0.0, blue)
			var parts: Array = [box.call(-0.06, -0.06, 0.08, 0.3), box.call(0.02, 0.05, 0.24, 0.08),
					[Vector2(0.12, -0.07), Vector2(0.27, 0.05), Vector2(0.12, 0.17)]]
			for pts: Array in parts:
				flat.call(pts if kind == "turn_r" else mirror.call(pts), 0.006, white)
		"keepright":
			# the blue "keep right" on the nose of a traffic island: an arrow down to the right
			flat.call(circle.call(0.32), 0.0, blue)
			var d := Vector2(1, -1).normalized()
			var n := Vector2(-d.y, d.x)
			var a := -d * 0.17
			var t := d * 0.07
			flat.call([a - n * 0.04, t - n * 0.04, t + n * 0.04, a + n * 0.04], 0.006, white)
			flat.call([t - n * 0.12, t + d * 0.15, t + n * 0.12], 0.006, white)
		"roundabout":
			flat.call(circle.call(0.32), 0.0, blue)
			for k in range(3):   # three white arrows chasing round
				var a0 := TAU * k / 3.0
				for j in range(4):
					var t0 := a0 + j * 0.32
					var t1 := t0 + 0.32
					flat.call([Vector2(cos(t0), sin(t0)) * 0.15, Vector2(cos(t0), sin(t0)) * 0.21, Vector2(cos(t1), sin(t1)) * 0.21, Vector2(cos(t1), sin(t1)) * 0.15], 0.006, white)
				var tip := a0 + 1.5
				flat.call([Vector2(cos(tip - 0.25), sin(tip - 0.25)) * 0.1, Vector2(cos(tip - 0.25), sin(tip - 0.25)) * 0.26, Vector2(cos(tip), sin(tip)) * 0.18], 0.006, white)
		"crossing":
			flat.call(box.call(0, 0, 0.56, 0.56), 0.0, blue)
			flat.call([Vector2(0, 0.22), Vector2(-0.23, -0.18), Vector2(0.23, -0.18)], 0.006, white)
			flat.call(box.call(0.0, -0.05, 0.05, 0.16), 0.012, back)
			flat.call(box.call(0.0, 0.06, 0.06, 0.06), 0.012, back)
		"noentry":
			flat.call(circle.call(0.32), 0.0, red)
			flat.call(box.call(0, 0, 0.44, 0.1), 0.006, white)
		"parking":
			flat.call(box.call(0, 0, 0.5, 0.5), 0.0, blue)
			flat.call(box.call(-0.06, 0.0, 0.07, 0.34), 0.006, white)
			flat.call(box.call(0.03, 0.08, 0.2, 0.18), 0.006, white)
			flat.call(box.call(0.03, 0.08, 0.09, 0.07), 0.012, blue)
		"street":
			flat.call([Vector2(-0.66, -0.17), Vector2(0.58, -0.17), Vector2(0.7, 0.0), Vector2(0.58, 0.17), Vector2(-0.66, 0.17)], 0.0, white)
			flat.call([Vector2(-0.63, -0.14), Vector2(0.56, -0.14), Vector2(0.66, 0.0), Vector2(0.56, 0.14), Vector2(-0.63, 0.14)], 0.006, green)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	am.surface_set_material(0, _vc_mat())
	_sign_meshes[kind] = am
	return am

## the junction a node belongs to: itself if three or more ways meet there, else the first
## such node within `reach` metres along a road through it (-1 if none)
func _junction_of(node: int, reach: float) -> int:
	if _node_ways(node) >= 3:
		return node
	var best := -1
	var best_d := INF
	for e: Vector2i in _node_roads[node]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		var ids: PackedInt32Array = r["ids"]
		var pts: PackedVector2Array = r["pts"]
		for step: int in [-1, 1]:
			var d := 0.0
			var k := e.y
			while k + step >= 0 and k + step < ids.size():
				d += pts[k].distance_to(pts[k + step])
				k += step
				if d > reach:
					break
				if _node_ways(ids[k]) >= 3:
					if d < best_d:
						best_d = d
						best = ids[k]
					break
	return best

## Stop and give-way signs: a pole and a plate on the right of each way in they are for.
## Which ways: the one OSM says (direction=forward/backward); else, at a junction, the
## minor roads into it (all of them if they are all alike); on a plain stretch, both ways.
func _build_signs() -> void:
	var poles: Array = []
	var plates := {"stop": [], "give_way": []}
	var all_signs: Array = _city_data.get("signs", [])
	for si: int in _tile_signs.get(_tile, []):
		if _over():
			await _pause()
		var sg: Array = all_signs[si]
		var node := int(sg[0])
		if node < 0 or node >= _nodes.size():
			continue
		var kind := String(sg[1])
		if not plates.has(kind):
			continue
		var facing := Vector2(float(sg[2]), float(sg[3])) / 100.0
		var c := _nodes[node]
		var junction := _node_ways(node) >= 3
		var top := 0
		var bottom := 99
		for e: Vector2i in _node_roads[node]:
			var r: Dictionary = _roads[e.x]
			if r["drive"]:
				top = maxi(top, int(ROAD_RANK.get(r["k"], 1)))
				bottom = mini(bottom, int(ROAD_RANK.get(r["k"], 1)))
		var rules: Array = []
		for e: Vector2i in _node_roads[node]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"] or r["pv"]:
				continue
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [-1, 1]:
				var from := e.y + d2
				if from < 0 or from >= pts.size():
					continue
				if r["o"] != 0 and r["o"] != -d2:
					continue   # arriving from `from` is travelling -d2 along the road
				var way_in := (c - pts[from]).normalized()
				if facing != Vector2.ZERO:
					if way_in.dot(facing) < 0.7:
						continue
				elif junction and top != bottom and int(ROAD_RANK.get(r["k"], 1)) >= top:
					continue   # the main road through has the right of way
				var line := _node_r[node] + 2.0 if junction else 1.0
				rules.append([kind, way_in, line])
				if kind == "stop":
					_stop_lines.append([c, way_in, line, float(r["w"]), r["o"] != 0, "stop"])
				var right := Vector2(-way_in.y, way_in.x)
				var p := c - way_in * (line + 0.4) + right * (float(r["w"]) * 0.5 + 0.7)
				if _push_out(p, 0.3, false) != Vector2.ZERO or not _off_road(p, 0.3):
					continue
				var gy := _h(p)
				poles.append(Transform3D(Basis(), Vector3(p.x, gy + 1.1, p.y)))
				(plates[kind] as Array).append(Transform3D(Basis(Vector3.UP, atan2(-way_in.x, -way_in.y)) * Basis.from_scale(Vector3.ONE * SIGN_SCALE), Vector3(p.x, gy + 2.3, p.y)))
				_add_post(p, 0.08)
				if kind == "stop" and String(_place.get("look", "")) != "med":
					var word := Label3D.new()   # a North American stop sign says so
					word.text = "STOP"
					word.font = _font
					word.font_size = 48
					word.pixel_size = 0.0058 * SIGN_SCALE
					word.outline_size = 0
					word.modulate = _tone["mark"]
					word.shaded = true
					word.double_sided = false
					word.rotation.y = atan2(-way_in.x, -way_in.y)
					word.position = Vector3(p.x, gy + 2.3, p.y) - Vector3(way_in.x, 0, way_in.y) * 0.03
					word.visibility_range_end = 60.0
					world.add_child(word)
		if not rules.is_empty():
			_signs[node] = rules
			_hash_add(_sign_hash, Rect2(c, Vector2.ZERO), SEG_CELL, node)
	if poles.is_empty():
		return
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.035
	pole.height = 2.2
	pole.radial_segments = 6
	pole.rings = 1
	pole.material = _surface("pole")
	_chunked(pole, poles, LAMP_RANGE)
	for kind: String in plates:
		if not (plates[kind] as Array).is_empty():
			_chunked(_sign_plate(kind), plates[kind], LAMP_RANGE)
	_tally("signs", poles.size())

## the plate, facing +Z: a red octagon in a thin white rim, or a white triangle point down
## in a red one; grey behind
func _sign_plate(kind: String) -> ArrayMesh:
	var outer: Array = []
	var inner: Array = []
	if kind == "stop":
		for i in range(8):
			var a := TAU * (float(i) + 0.5) / 8.0
			outer.append(Vector2(cos(a), sin(a)) * 0.38)
			inner.append(Vector2(cos(a), sin(a)) * 0.34)
	else:
		for v: Vector2 in [Vector2(0, -0.42), Vector2(0.46, 0.38), Vector2(-0.46, 0.38)]:
			outer.append(v)
			inner.append(Vector2(v.x, v.y + 0.035) * 0.62)
	var rim := Buf.new()
	var face := Buf.new()
	var back := Buf.new()
	if kind == "stop" and String(_place.get("look", "")) == "med":
		# Israel's stop sign carries a white hand, palm out
		var z := 0.02
		var hand: Array = [[-0.085, -0.13, 0.17, 0.17]]   # palm: x, y (bottom), w, h
		for f: Array in [[-0.085, 0.13], [-0.04, 0.16], [0.005, 0.155], [0.05, 0.13]]:
			hand.append([f[0], 0.03, 0.038, f[1]])
		for hb: Array in hand:
			var x0: float = hb[0]
			var y0: float = hb[1]
			_poly(rim, [Vector3(x0, y0, z), Vector3(x0 + hb[2], y0, z), Vector3(x0 + hb[2], y0 + hb[3], z), Vector3(x0, y0 + hb[3], z)], Vector3.BACK)
		_poly(rim, [Vector3(0.085, -0.06, z), Vector3(0.15, 0.0, z), Vector3(0.13, 0.03, z), Vector3(0.07, -0.01, z)], Vector3.BACK)   # thumb
	_poly(rim, outer.map(func(v): return Vector3(v.x, -v.y, 0.012)), Vector3.BACK)
	_poly(face, inner.map(func(v): return Vector3(v.x, -v.y, 0.016)), Vector3.BACK)
	_poly(back, outer.map(func(v): return Vector3(v.x, -v.y, 0.0)), Vector3.FORWARD)
	var red := mat("hazard", 0.15)
	var white := _surface("mark")
	var am := ArrayMesh.new()
	for pair: Array in [[rim, white if kind == "stop" else red], [face, red if kind == "stop" else white],
			[back, _surface("pole")]]:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (pair[0] as Buf).arrays())
		am.surface_set_material(am.get_surface_count() - 1, pair[1])
	return am

## how many ways a car can leave a graph node by (3 or more: a junction)
func _node_ways(n: int) -> int:
	var count := 0
	for e: Vector2i in _node_roads[n]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		if e.y > 0:
			count += 1
		if e.y < (r["pts"] as PackedVector2Array).size() - 1:
			count += 1
	return count

## the sign for traffic arriving at node `n` going `dir`: [kind, line before the node] or []
func _sign_rule(n: int, dir: Vector2) -> Array:
	var rules: Array = _signs.get(n, [])
	if rules.is_empty() or dir == Vector2.ZERO:
		return []
	var d := dir.normalized()
	for rule: Array in rules:
		if d.dot(rule[1]) > 0.7:
			return [rule[0], rule[2]]
	return []

## the player through a stop sign without stopping: called out, like a red light
func _check_stop_signs() -> void:
	if absf(_v) < 0.8:
		_stopped_odo = _odo
	if _signs.is_empty() or _v < 2.0 or _odo - _sign_odo < 20.0:
		return
	for n: int in _near(_sign_hash, _pos, 20.0, SEG_CELL):
		var rule := _sign_rule(n, _fwd())
		if rule.is_empty() or rule[0] != "stop":
			continue
		if _nodes[n].distance_to(_pos) > float(rule[1]) + 0.6:
			continue
		_sign_odo = _odo
		if _odo - _stopped_odo > 12.0:
			_show_banner("didn't stop at the stop sign", 1.8)
			Probe.event("stop_sign", {"street": _on_name, "kmh": int(_v * 3.6), "auto": _auto})
		return

## autodrive at signs on its lane: a full stop at a stop sign's line (a moment, then on),
## slow to walking pace for a give-way
func _ap_sign_v(dt: float) -> float:
	if _signs.is_empty() or _ap_pts.size() < 2:
		return INF
	var best := INF
	for n: int in _near(_sign_hash, _pos, 60.0, SEG_CELL):
		var c := _nodes[n]
		var base := -_ap_pts[0].distance_to(Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[0], _ap_pts[1]))
		for j in range(_ap_pts.size() - 1):
			if base > 60.0:
				break
			var a := _ap_pts[j]
			var b := _ap_pts[j + 1]
			var cp := Geometry2D.get_closest_point_to_segment(c, a, b)
			if cp.distance_to(c) < 4.5:
				var rule := _sign_rule(n, b - a)
				if rule.is_empty():
					break
				var line := base + a.distance_to(cp) - float(rule[1])
				if line < -1.0:
					break
				if rule[0] == "give_way":
					best = minf(best, sqrt(16.0 + 2.0 * 2.6 * maxf(line, 0.0)))
				elif _ap_sign_done != n:
					if line < 2.5 and _v < 0.3:
						_ap_sign_wait += dt
						if _ap_sign_wait > 0.8:
							_ap_sign_done = n
							_ap_sign_wait = 0.0
						best = 0.0
					else:
						best = minf(best, sqrt(2.0 * 2.6 * maxf(line - 0.4, 0.0)))
				break
			base += a.distance_to(b)
	return best

## the car going through a junction with lights: note it (the far side's lights are the
## same junction), and whether it went through on red
var _reds := 0

var _came_at := Vector2.INF            ## where the car was a few metres back
var _came_dir := Vector2.ZERO          ## and the way it has come since: how it arrived

func _through_lights() -> void:
	if _came_at == Vector2.INF or _pos.distance_to(_came_at) > 6.0:
		if _came_at != Vector2.INF:
			_came_dir = (_pos - _came_at).normalized()
		_came_at = _pos
	if _odo - _light_odo < LIGHT_SKIP or _v < 1.0:
		return
	for n: int in _near(_sig_hash, _pos, 16.0, SEG_CELL):
		if _nodes[n].distance_to(_pos) > _node_r[n] + 2.5:
			continue
		_light_odo = _odo
		# (the light of the way it came in: by its heading mid-turn, a turn on green read
		# the cross street's red)
		if _light_at(n, _came_dir if _came_dir != Vector2.ZERO else _fwd()) == "r" and _v > 2.5:
			_reds += 1
			_show_banner("ran a red light", 1.8)
			shake3d(1.5)
			Probe.event("red_light", {"street": _on_name, "kmh": int(_v * 3.6), "auto": _auto})
			_log.event("red light")
		return

## autodrive: the first light on the planned lane that counts. Red: come to a stop at its
## line. Amber: stop if there is room to, else through. The speed allowed now (INF: none).
func _ap_light_v() -> float:
	if _sig_set.is_empty() or _ap_pts.size() < 2:
		return INF
	var found: Array = []   # [along the lane, node, direction]
	for n: int in _near(_sig_hash, _pos, 90.0, SEG_CELL):
		var c := _nodes[n]
		var base := -_ap_pts[0].distance_to(Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[0], _ap_pts[1]))
		for j in range(_ap_pts.size() - 1):
			if base > 90.0:
				break
			var a := _ap_pts[j]
			var b := _ap_pts[j + 1]
			var cp := Geometry2D.get_closest_point_to_segment(c, a, b)
			if cp.distance_to(c) < 4.5:
				# the way in, a few metres back (mid-turn the lane runs diagonally across)
				var k := j
				var back := a.distance_to(cp)
				while k > 0 and back < 6.0:
					back += _ap_pts[k - 1].distance_to(_ap_pts[k])
					k -= 1
				found.append([base + a.distance_to(cp), n, cp - _ap_pts[k]])
				break
			base += a.distance_to(b)
	if found.is_empty():
		return INF
	found.sort_custom(func(x, y): return x[0] < y[0])
	var counted := -(_odo - _light_odo)   # where the last light went by, on the same scale
	for f: Array in found:
		var along: float = f[0]
		if along - counted < LIGHT_SKIP:
			continue
		var n: int = f[1]
		var stop := along - (_node_r[n] + 2.2 + CAR_LEN * 0.5)   # (the nose at the stop line)
		if stop < -1.5 and (_v > 2.0 or along - CAR_LEN * 0.5 < _node_r[n]):
			return INF   # over the line already, rolling (or in the junction): through
		# (standing a little over the line -- stopped there for people on a crossing -- is
		# not through: it waits for its green where it stands)
		var state := _light_at(n, f[2])
		if state == "g":
			return INF
		if state == "y" and _v * _v > 2.0 * 3.0 * maxf(stop, 0.1):
			return INF   # too late to stop on amber
		return sqrt(2.0 * 2.6 * maxf(stop - 0.5, 0.0))
	return INF

## the light facing traffic that arrives at node `n` going `dir`: "g", "y" or "r", or ""
## where there is none. The two groups are the streets running more east-west and those
## running more north-south, as the lights are drawn.
func _light_at(n: int, dir: Vector2) -> String:
	if not _sig_set.has(n):
		return ""
	var step: Array = SIGNAL_CYCLE[_sig_phase]
	return step[_light_group(n, dir)]

## Which of the two signal groups (1 or 2, the columns of SIGNAL_CYCLE) the traffic arriving at
## node n going `dir` belongs to. Each junction's own: its main road's ways in are one group,
## every other way in the other (by name, else by the angle to the main road). It was the
## city's east-west against north-south, so at a skewed junction both streets could have
## green at once, and the cars met in the middle.
func _light_group(n: int, dir: Vector2) -> int:
	var j: int = _sig_owner.get(n, n)
	var ap: Array = _sig_ap.get(j, [])
	if ap.is_empty():
		return 1 if absf(dir.x) >= absf(dir.y) else 2
	var d := dir.normalized()
	var best := -2.0
	var grp := 1
	for a: Array in ap:
		var dt := (a[0] as Vector2).dot(d)
		if dt > best:
			best = dt
			grp = a[1]
	return grp

var _sig_ap := {}                    ## junction node -> [[way in (unit), group], ...]
var _sig_owner := {}                 ## a node with a light of its own -> the junction it belongs to
var _sig_knot := {}                  ## a junction's point -> the one id of all its points (a divided road's
                                     ## junction is several points 10-30 m apart: one junction)

## the ways in at the points of one junction (one point, or the few of a junction drawn as
## several) and their signal groups: the main road -- the busiest kind, then the widest --
## chosen once for all of them
func _signal_groups(knot: Array) -> void:
	var by_node := {}
	var main: Array = []
	for node: int in knot:
		var c := _nodes[node]
		var arms: Array = []   # [way in, rank, name, width]
		for e: Vector2i in _node_roads[node]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"]:
				continue
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [-1, 1]:
				var from := e.y + d2
				if from < 0 or from >= pts.size():
					continue
				var a := [(c - pts[from]).normalized(), int(ROAD_RANK.get(r["k"], 1)), String(r["name"]), float(r["w"])]
				arms.append(a)
				if main.is_empty() or int(a[1]) > int(main[1]) or (int(a[1]) == int(main[1]) and float(a[3]) > float(main[3])):
					main = a
		by_node[node] = arms
	if main.is_empty():
		return
	var axis: Vector2 = main[0]
	for node: int in knot:
		var ap: Array = []
		for a: Array in by_node[node]:
			var same: bool = String(main[2]) != "" and String(a[2]) == String(main[2])
			if String(main[2]) == "" or String(a[2]) == "":
				same = absf((a[0] as Vector2).dot(axis)) >= 0.7
			ap.append([a[0], 1 if same else 2])
		_sig_ap[node] = ap

## A signal's colours are what a driver reads, so they are red, amber and green whatever the
## palette: each keeps the palette's strength of colour but takes the signal's own hue (the
## palette's pink "red", yellow and mint "green" read as anything but a traffic light). Lit:
## glowing; out: nearly black behind the glass.
func _signal_cols() -> Array:
	var sat := clampf(maxf(Palette.col("hazard").s, Palette.col("friend").s), 0.8, 1.0)
	return [Color.from_hsv(0.0, sat, 1.0), Color.from_hsv(0.11, sat, 1.0), Color.from_hsv(0.40, sat, 0.95)]

func _light_lamp(m: StandardMaterial3D, col: Color, on: bool) -> void:
	# (a strong glow came out white: the film-like tone curve bleaches anything much over 1,
	# so the lamp keeps its colour in the glass and glows only a little past it)
	m.albedo_color = col * 0.5 if on else col.lerp(Palette.col("bg").darkened(0.6), 0.9)
	m.emission_enabled = on
	m.emission = col
	m.emission_energy_multiplier = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL

func _apply_signals() -> void:
	var step: Array = SIGNAL_CYCLE[_sig_phase]
	var cols := _signal_cols()
	var keys := ["r", "y", "g"]
	for g in range(_sig_mats.size()):
		for ci in range(3):
			_light_lamp(_sig_mats[g][ci], cols[ci], step[1 + g] == keys[ci])
	# the people's lights: the green man while the road they cross is held at red and the
	# other way has its green; the red man the rest of the time (amber, all-red included)
	for g in range(_ped_mats.size()):
		var walk: bool = step[1 + g] == "r" and step[2 - g] == "g"
		_light_lamp(_ped_mats[g][0], cols[0], not walk)
		_light_lamp(_ped_mats[g][1], cols[2], walk)

## ---- the sky: a photograph -----------------------------------------------------------------
## By day the sky is a photo (textures/sky_day.jpg: the upper half of Poly Haven's CC0
## "kloofendal_48d_partly_cloudy_puresky", tonemapped by textures/hdr_sky.py), on a dome that
## follows the camera, drawn unlit and through no fog. It is turned so the sun in it stands
## where the sunlight comes from, and fades into the fog at the horizon. The shell keeps its
## own procedural sky behind it (it retints that on a palette change), which shows at night,
## when the dome is hidden. The palette's sky tone tints it lightly, as it does everything.
const SKY_SUN_U := 0.595             ## where the photo's sun is, across it (0..1)
const SKY_MEAN := Vector3(0.626, 0.686, 0.792)      ## its average colour, as stored
const SKY_HORIZON := Vector3(0.742, 0.758, 0.801)   ## its colour along the horizon
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, shadows_disabled;
uniform sampler2D photo : filter_linear, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform vec3 horizon = vec3(0.75);
uniform float turn = 0.0;
varying vec3 dir;
void vertex() { dir = VERTEX; }
void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, 0.0, 1.0);
	float u = atan(d.x, -d.z) / 6.2831853 + 0.5 + turn;
	float v = 1.0 - asin(up) / 1.5707963;
	vec3 c = texture(photo, vec2(u, v)).rgb;
	ALBEDO = mix(horizon, c * tint, smoothstep(0.0, 0.07, up));
}
"""
var _sky_dome: MeshInstance3D
var _sky_mat: ShaderMaterial

## the palette's say in the sky: its sky tone's hue (not its brightness) over the photo's
func _sky_tint() -> Vector3:
	var t: Color = _tone.get("sky", Color(0.6, 0.7, 0.8))
	var lt := maxf(t.get_luminance(), 0.01)
	var m := SKY_MEAN
	var lm := m.dot(Vector3(0.2126, 0.7152, 0.0722))
	var ratio := Vector3(t.r / lt, t.g / lt, t.b / lt) / (m / lm)
	return Vector3.ONE.lerp(ratio, 0.25)

## one of the photo's colours, tinted as the dome draws it
func _sky_col(c: Vector3) -> Color:
	var t := _sky_tint()
	return Color(c.x * t.x, c.y * t.y, c.z * t.z)

## what the glass and the paint reflect: [overhead, horizon], the photo's by day
func _sky_reflect() -> Array:
	if _night or _sky_dome == null:
		var sk := env.sky.sky_material as ProceduralSkyMaterial
		return [sk.sky_top_color, sk.sky_horizon_color]
	return [_sky_col(SKY_MEAN), _sky_col(SKY_HORIZON)]

func _build_sky_dome() -> void:
	var tex := load(TEX_DIR + "sky_day.jpg") as Texture2D
	if tex == null:
		return
	_sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	_sky_mat.shader = sh
	_sky_mat.set_shader_parameter("photo", tex)
	var mesh := SphereMesh.new()
	mesh.radius = 1900.0
	mesh.height = 1900.0
	mesh.is_hemisphere = true
	mesh.radial_segments = 32
	mesh.rings = 10
	mesh.material = _sky_mat
	_sky_dome = MeshInstance3D.new()
	_sky_dome.mesh = mesh
	_sky_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky_dome.extra_cull_margin = 4000.0
	world.add_child(_sky_dome)
	_retint_sky_dome()

## the dome round the camera, wherever it went this frame
func _sky_follow() -> void:
	if _sky_dome != null:
		_sky_dome.global_position = cam.global_position

func _retint_sky_dome() -> void:
	if _sky_dome == null:
		return
	_sky_dome.visible = not _night
	var t := _sky_tint()
	_sky_mat.set_shader_parameter("tint", t)
	_sky_mat.set_shader_parameter("horizon", Vector3(SKY_HORIZON.x * t.x, SKY_HORIZON.y * t.y, SKY_HORIZON.z * t.z))
	# turn the photo so its sun is where the light comes from (the light shines down its -Z)
	var to_sun := sun.global_transform.basis.z if sun.is_inside_tree() else Basis.from_euler(sun.rotation).z
	_sky_mat.set_shader_parameter("turn", SKY_SUN_U - (atan2(to_sun.x, -to_sun.z) / TAU + 0.5))

## ---- look: every colour is a palette role, mixed for daylight ---------------------------
## The kit's palettes are neon on dark. A street in daylight is greys, creams and greens, so
## each tone, still mixed from the palette's roles (so /look still reskins it), keeps only
## part of its colour (NATURAL: the share of its saturation kept, the rest going to its own
## brightness): asphalt, pavements, kerbs and concrete nearly none, walls about half, plants
## more -- and plants lean from the palette's "friend" toward its "warn", which takes a mint
## to a grass green. Signs, kerb paint, lights and the cars' colours keep theirs: real ones
## are bright.
const NATURAL := {
	"ground": 0.3, "rock": 0.3, "path": 0.15, "asphalt": 0.08, "parking": 0.08, "plaza": 0.2,
	"grass": 0.6, "pitch": 0.6, "wood": 0.6, "leaf": 0.62, "bush": 0.6, "water": 0.5, "sand": 0.6,
	"mark": 0.3, "wall": 0.5, "wall2": 0.45, "wall3": 0.6, "wall4": 0.6, "wall5": 0.5, "wall6": 0.3,
	"glass": 0.5, "glass2": 0.5, "glass3": 0.5, "glass4": 0.5, "shutter": 0.3, "recess": 0.3, "lobby": 0.35, "flowers": 0.8,
	"roof": 0.2, "trunk": 0.45, "pole": 0.2, "haze": 0.45, "sky": 0.6, "board": 0.4, "solar": 0.5,
	"tank": 0.3, "furniture": 0.3, "pavement": 0.2, "pavers_dark": 0.15, "slabs": 0.15, "pavers_grey": 0.1, "kerb": 0.15, "stonewall": 0.45, "roofroom": 0.4,
	"gable": 0.5, "carglass": 0.4, "cartrim": 0.2, "tyre": 0.15, "rim": 0.2, "concrete": 0.15,
	"insulator": 0.3, "trafo": 0.4, "cable": 0.2, "railing": 0.3, "brick": 0.7, "rubber": 0.6,
	"metal": 0.1, "metalrim": 0.1, "skin": 0.75, "hair": 0.5, "shirt_a": 0.6, "shirt_b": 0.4,
}

## a palette colour with only `keep` of its saturation, the rest toward its own brightness
static func _natural(c: Color, keep: float) -> Color:
	var l := c.get_luminance()
	return Color(lerpf(l, c.r, keep), lerpf(l, c.g, keep), lerpf(l, c.b, keep), c.a)

## a palette colour with most of its tint taken out (`k` 1: grey of the same brightness) --
## concrete is grey, whatever colour the palette's light is
func _greyed(c: Color, k: float) -> Color:
	var l := c.get_luminance()
	return c.lerp(Color(l, l, l, c.a), k)

func _tones() -> void:
	var bg := Palette.col("bg")
	var alt := Palette.col("bg_alt")
	var ink := Palette.col("ink")
	var pl := Palette.col("player")
	var fr := Palette.col("friend")
	var wn := Palette.col("warn")
	var ac := Palette.col("accent")
	var pz := Palette.col("prize")
	var veg := fr.lerp(wn, 0.3)   # what grows: the palette's green, leaning toward its yellow
	_tone = {
		"ground": alt.lerp(ink, 0.42),
		"rock": alt.lerp(ink, 0.3).lerp(wn, 0.2),
		"path": alt.lerp(ink, 0.62),
		"asphalt": alt.lerp(ink, 0.27),   # (pale grey, as sun-bleached asphalt is)
		"parking": alt.lerp(ink, 0.32),
		"plaza": alt.lerp(ink, 0.58).lerp(wn, 0.08),
		"grass": veg.lerp(bg, 0.48),
		"pitch": veg.lerp(bg, 0.36),
		"wood": veg.lerp(bg, 0.6),
		"water": pl.lerp(bg, 0.42),
		"mark": ink,
		"wall": ink.lerp(wn, 0.1),
		"wall2": ink.lerp(ac, 0.28),
		"wall3": ink.lerp(wn, 0.38).lerp(alt, 0.06),
		"wall4": ink.lerp(wn, 0.5).lerp(pz, 0.05),
		"wall5": ink.lerp(Palette.col("hazard"), 0.2).lerp(wn, 0.18),
		"wall6": ink.lerp(alt, 0.34),
		"glass2": alt.lerp(pl, 0.55),
		"glass3": alt.lerp(fr, 0.45),
		"glass4": ink.lerp(alt, 0.45).lerp(pl, 0.1),
		"glass": alt.lerp(pl, 0.3),
		"shutter": ink.lerp(alt, 0.22),
		"recess": alt.lerp(bg, 0.25),
		"lobby": ink.lerp(wn, 0.22).lerp(alt, 0.12),   # the tiled walls of a lobby under a block on columns
		"flowers": Palette.col("hazard").lerp(Palette.col("accent"), 0.35),   # bougainvillea
		"roof": ink.lerp(alt, 0.42),
		"leaf": veg.lerp(bg, 0.52),
		"trunk": alt.lerp(wn, 0.3),
		"pole": alt.lerp(ink, 0.3),
		"sky": pl.lerp(pz, 0.35).lerp(bg, 0.32),
		"haze": ink.lerp(pl, 0.3),
		"beacon": Color(ac, 0.35),
		"board": bg.lerp(alt, 0.5),
		"solar": alt.lerp(pl, 0.35).lerp(bg, 0.2),
		"tank": ink.lerp(alt, 0.08),
		"lamp": ink.lerp(wn, 0.25),
		"furniture": alt.lerp(ink, 0.35),
		"paint": pl.lerp(alt, 0.5).lerp(ink, 0.12),
		"shoplight": ink.lerp(wn, 0.45),
		"pavement": _greyed(ink.lerp(alt, 0.48).lerp(wn, 0.04), 0.65),
		# a filmed street's details (details.gd): charcoal pavers under an arcade, a forecourt
		# of pale poured slabs
		"pavers_dark": _greyed(ink.lerp(alt, 0.8), 0.85),
		"slabs": _greyed(ink.lerp(alt, 0.52).lerp(wn, 0.16), 0.5),
		"pavers_grey": _greyed(ink.lerp(alt, 0.5), 0.85),
		"kerb": ink.lerp(alt, 0.45),
		"stonewall": ink.lerp(wn, 0.3).lerp(alt, 0.2),
		"woodfence": alt.lerp(wn, 0.35).lerp(bg, 0.4),
		"bush": veg.lerp(bg, 0.58),
		"roofroom": ink.lerp(wn, 0.12).lerp(alt, 0.1),
		"gable": ink.lerp(wn, 0.15),
		"carglass": bg.lerp(pl, 0.12),
		"cartrim": bg.lerp(alt, 0.4),
		"tyre": bg.lerp(alt, 0.2),
		"rim": ink.lerp(alt, 0.35),
		"lit": ink.lerp(wn, 0.55),
		"litcool": ink.lerp(pl, 0.2),
		"lamplight": ink.lerp(wn, 0.45),
		"brick": Palette.col("hazard").lerp(bg, 0.45).lerp(alt, 0.15),
		"markyellow": wn.lerp(ink, 0.2),
		"signblue": pl.lerp(bg, 0.4),
		"signgreen": fr.lerp(bg, 0.45),
		"signred": Palette.col("hazard").lerp(bg, 0.1),
		"rubber": ac.lerp(alt, 0.55).lerp(bg, 0.25),
		"sand": wn.lerp(ink, 0.45).lerp(alt, 0.1),
		"concrete": ink.lerp(alt, 0.32).lerp(wn, 0.04),
		"insulator": ink.lerp(alt, 0.15),
		"trafo": alt.lerp(ink, 0.4).lerp(fr, 0.08),
		"cable": bg.lerp(alt, 0.35),
		"lampgreen": fr.lerp(bg, 0.74),
		"fencegreen": fr.lerp(bg, 0.55),
		"railing": ink.lerp(alt, 0.12),
		"skin": ink.lerp(wn, 0.38).lerp(Palette.col("hazard"), 0.12).lerp(bg, 0.2),   # people in the cars
		"hair": bg.lerp(alt, 0.5).lerp(wn, 0.08),
		"shirt_a": pl.lerp(bg, 0.45).lerp(ink, 0.15),
		"shirt_b": ink.lerp(alt, 0.25),
		"metal": alt.lerp(ink, 0.22),          # cast iron: manhole covers, drain grates
		"metalrim": alt.lerp(ink, 0.32),
	}
	for k: String in NATURAL:
		if _tone.has(k):
			_tone[k] = _natural(_tone[k], float(NATURAL[k]))

func _retint_city() -> void:
	_tones()
	for t: String in _smat:
		var sm := _smat[t] as StandardMaterial3D
		sm.albedo_color = _tone[sm.get_meta("tone", t)]
	if _smat.has("shopglass"):
		(_smat["shopglass"] as StandardMaterial3D).emission = _tone["shoplight"]
	_retint_trees()
	if _wall_mat != null:
		_wall_mat.set_shader_parameter("wall_a", _tone["wall"])
		_wall_mat.set_shader_parameter("wall_b", _tone["wall2"])
		_wall_mat.set_shader_parameter("glass", _tone["glass"])
		_wall_mat.set_shader_parameter("wall_c", _tone["wall3"])
		_wall_mat.set_shader_parameter("wall_d", _tone["wall4"])
		_wall_mat.set_shader_parameter("wall_e", _tone["wall5"])
		_wall_mat.set_shader_parameter("wall_f", _tone["wall6"])
		_wall_mat.set_shader_parameter("glass_b", _tone["glass2"])
		_wall_mat.set_shader_parameter("glass_c", _tone["glass3"])
		_wall_mat.set_shader_parameter("glass_d", _tone["glass4"])
		_wall_mat.set_shader_parameter("shutter", _tone["shutter"])
		_wall_mat.set_shader_parameter("dark", _tone["recess"])
	if env != null:
		# by day the photo sky (_sky_dome) sets the haze: the fog takes its horizon, so far
		# streets melt into the sky, and the shade its blue
		var hor := _sky_col(SKY_HORIZON)
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = _sky_col(SKY_MEAN)
		sky.sky_horizon_color = hor
		sky.ground_horizon_color = hor
		sky.ground_bottom_color = _tone["ground"]
		sky.sky_curve = 0.12
		env.background_color = hor
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = _sky_col(SKY_MEAN).lerp(_tone["haze"], 0.4)
		env.ambient_light_energy = 0.55
		env.fog_enabled = true
		env.fog_light_color = hor
		env.fog_density = 0.0018
		env.fog_sky_affect = 0.0
		# a film-like curve: the bright walls roll off instead of clipping, the shade deepens
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.0
	if sun != null:
		sun.light_color = Palette.col("ink").lerp(Palette.col("warn"), 0.22)
		sun.light_energy = 1.1
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_retint_sky_dome()
	if _wall_mat != null:
		_wall_mat.set_shader_parameter("lit", _tone["lit"])
		_wall_mat.set_shader_parameter("lit_cool", _tone["litcool"])
		_wall_mat.set_shader_parameter("night", 1.0 if _night else 0.0)
		_wall_mat.set_shader_parameter("trim", _tone["mark"])
		_wall_mat.set_shader_parameter("siding", 1.0 if String(_place.get("look", "")) == "north" else 0.0)
	for m: ShaderMaterial in _glow_mats.values():
		m.set_shader_parameter("col", _tone[m.get_meta("tone")])
	if _furn != null:
		_furn.retint()
	_retint_tone_mat()
	var lamp := _surface("lamp")
	lamp.emission_enabled = _night
	lamp.emission = _tone["lamplight"]
	lamp.emission_energy_multiplier = 2.4
	if _smat.has("shopglass"):
		(_smat["shopglass"] as StandardMaterial3D).emission_energy_multiplier = 2.0 if _night else 0.7
	if _night and env != null:
		var bg := Palette.col("bg")
		var pl := Palette.col("player")
		var ink := Palette.col("ink")
		var haze := bg.lerp(pl, 0.3).lerp(ink, 0.06)
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = bg.lerp(pl, 0.05)
		sky.sky_horizon_color = haze
		sky.ground_horizon_color = haze
		sky.ground_bottom_color = bg
		env.background_color = haze
		env.ambient_light_color = bg.lerp(pl, 0.5).lerp(ink, 0.25)
		env.ambient_light_energy = 0.42
		env.fog_light_color = haze
		env.fog_density = 0.0026
		sun.light_color = ink.lerp(pl, 0.4)
		sun.light_energy = 0.18
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # no sun disc in a night sky
	if _car_shader_mat != null:   # the cars' reflections, lamps and wells
		_car_material()
	if _wall_mat != null and env != null:   # what the windows reflect: the sky as it is now
		var rs := _sky_reflect()
		_wall_mat.set_shader_parameter("sky_top", rs[0])
		_wall_mat.set_shader_parameter("sky_hor", rs[1])
	_apply_signals_safe()
	_retint_kerbs()
	_retint_ground()
	_retint_edge()
	if _blob_plane != null:
		(_blob_plane.material as ShaderMaterial).set_shader_parameter("tint", Palette.col("bg"))
	for poi: Array in _pois:
		var lb := poi[2] as Label3D
		lb.modulate = Palette.col(poi[1])
		lb.outline_modulate = Palette.col("bg")
	for lb: Label3D in _names:
		lb.modulate = Palette.col(lb.get_meta("role"))
		lb.outline_modulate = Palette.col("bg")
	_retint_hud()

func _apply_signals_safe() -> void:
	if not _sig_mats.is_empty():
		_apply_signals()

## ---- the car ------------------------------------------------------------------------------

func _build_car() -> void:
	_car = Node3D.new()
	_car.name = "car"
	world.add_child(_car)
	_body = Node3D.new()
	_car.add_child(_body)
	_sedan_node = _sedan("paint")
	_body.add_child(_sedan_node)
	var beam := MeshInstance3D.new()
	beam.mesh = _beam_mesh()
	beam.material_override = _glow_mat("lamplight", 0.55)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = _night
	_car.add_child(beam)
	_beam_node = beam
	_lights_on = _night
	_blob = MeshInstance3D.new()
	_blob.mesh = blob_mesh()
	_blob.scale = Vector3(2.7, 1.0, 5.6)
	_blob.position = Vector3(0, 0.02, 0)
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.visible = _blobs_on
	_car.add_child(_blob)
	_build_cockpit()
	_build_car_signals()

## Where the real shadows are off (the lowest quality: a phone that could not keep up), a
## soft dark patch under each car keeps it standing on the road. Without them the street
## went flat the moment the game stepped down, and the cars floated over it.
var _blobs_on := false
var _blob: MeshInstance3D
var _blob_plane: PlaneMesh
const BLOB_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.0);
void fragment() {
	vec2 q = abs(UV - 0.5) * 2.0;   // 0 in the middle, 1 at the rim
	float d = length(max(q - vec2(0.5, 0.68), 0.0) / vec2(0.5, 0.32));
	ALBEDO = tint;
	ALPHA = (1.0 - smoothstep(0.0, 1.0, d)) * 0.62;
}
"""

## a 1 m square lying flat, the patch's shape and fade in its shader (scaled to each car)
func blob_mesh() -> PlaneMesh:
	if _blob_plane == null:
		_blob_plane = PlaneMesh.new()
		_blob_plane.size = Vector2(1.0, 1.0)
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = BLOB_SHADER
		m.shader = sh
		m.set_shader_parameter("tint", Palette.col("bg"))
		_blob_plane.material = m
	return _blob_plane

func _set_blobs(on: bool) -> void:
	_blobs_on = on
	if _blob != null:
		_blob.visible = on
	if _traffic != null:
		_traffic.show_blobs(on)

func _fwd() -> Vector2:
	return Vector2(cos(_yaw), sin(_yaw))

## The right-hand lane's line, this far right of a two-way road's middle. Every two-way
## street has two lanes, however narrow; the line sits a little past the lane's own middle,
## toward the kerb, as drivers do -- at w/4 cars ran close to the centre line and met the
## traffic coming the other way in it. A one-way road of one lane: its middle; of several:
## the middle of the right-hand one, where traffic drives (autodrive used to take the middle
## of the road, astride two lanes, and ran in between the cars in them).
func _lane_off(r: Dictionary) -> float:
	var w := float(r["w"])
	if int(r["o"]) != 0:
		var n := _lanes_each_way(r)
		return 0.0 if n <= 1 else w * 0.5 - w / n * 0.5
	return clampf(minf(w * 0.25 + 0.25, w * 0.5 - 0.95), 0.9, 2.6)

## lanes each way: a one-way road's all, half a two-way road's (by the tag, else the width)
func _lanes_each_way(r: Dictionary) -> int:
	var l := int(r.get("l", 0))
	var w := float(r["w"])
	var n := 1
	if int(r["o"]) != 0:
		n = mini(l if l > 0 else int(w / 3.3), int(w / 2.8))
	else:
		n = mini(l / 2 if l > 1 else int(w / 6.6), int(w / 5.6))
	return clampi(n, 1, 4)   # (no more than the width holds: a tagged two lanes narrowed to 4 m is one)

## of road r's lanes going one way, the line of the one nearest `off` metres right of the
## road's middle
func _nearest_lane(r: Dictionary, off: float) -> float:
	var best := _lane_off(r)
	var n := _lanes_each_way(r)
	var w := float(r["w"])
	var span := w if int(r["o"]) != 0 else w * 0.5
	for i in range(n if n > 1 else 0):
		var c := w * 0.5 - span / n * (i + 0.5)
		if absf(c - off) < absf(best - off):
			best = c
	return best

## ---- the driver's seat ----------------------------------------------------------------------
## The view from behind the wheel, like a dashcam a little lower: the bonnet through the
## windscreen (the body's own faces point out, so from inside only the bonnet and the mirrors
## show), and inside, the dashboard, a steering wheel that turns with the front wheels, the
## windscreen pillars, the roof's edge and the mirror. Left-hand drive: the seat is on the
## car's left (+X, the car facing +Z).
const SEAT := Vector3(0.37, 1.2, -0.32)

func _build_cockpit() -> void:
	_cockpit_node = Node3D.new()
	_cockpit_node.visible = false
	_body.add_child(_cockpit_node)
	var dark: Color = _tone["cartrim"]
	var b := Buf.new()
	var box := func(c: Vector3, sz: Vector3, col: Color) -> void:
		var h := sz * 0.5
		for f: Array in [[Vector3(h.x, 0, 0), Vector3(0, h.y, 0), Vector3(0, 0, h.z)], [Vector3(-h.x, 0, 0), Vector3(0, h.y, 0), Vector3(0, 0, h.z)],
				[Vector3(0, h.y, 0), Vector3(h.x, 0, 0), Vector3(0, 0, h.z)], [Vector3(0, -h.y, 0), Vector3(h.x, 0, 0), Vector3(0, 0, h.z)],
				[Vector3(0, 0, h.z), Vector3(h.x, 0, 0), Vector3(0, h.y, 0)], [Vector3(0, 0, -h.z), Vector3(h.x, 0, 0), Vector3(0, h.y, 0)]]:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var o: Vector3 = c + n
			b.tri(o - u - v, o + u - v, o + u + v, n.normalized(), col)
			b.tri(o - u - v, o + u + v, o - u + v, n.normalized(), col)
	# the dashboard under the windscreen (down to the footwell), the instrument hood in
	# front of the driver, the centre console, and the doors' insides below the windows
	box.call(Vector3(0, 0.7, 0.78), Vector3(1.7, 0.5, 0.62), dark)
	box.call(Vector3(0.37, 1.0, 0.55), Vector3(0.44, 0.1, 0.16), dark.darkened(0.2))   # the binnacle
	box.call(Vector3(0, 0.5, 0.2), Vector3(0.3, 0.3, 0.6), dark.lightened(0.05))
	for sx: float in [-1.0, 1.0]:
		box.call(Vector3(sx * 0.84, 0.66, 0.05), Vector3(0.05, 0.56, 1.9), dark.lightened(0.08))
	box.call(Vector3(0, 1.36, 0.36), Vector3(0.24, 0.07, 0.03), dark)           # the mirror
	box.call(Vector3(0, 1.4, 0.32), Vector3(0.03, 0.06, 0.03), dark)
	# the pillars beside the windscreen and the roof's edge over it, seen from inside
	var shape: Array = CAR_SHAPES["sedan"]
	var hw: float = shape[2]
	var c0: Vector2 = shape[1][0]
	var c1: Vector2 = shape[1][1]
	var lo := hw - 0.06
	var up := hw - 0.24
	var quad2 := func(a: Vector3, e: Vector3, f: Vector3, d: Vector3, col: Color) -> void:
		var n := (e - a).cross(d - a).normalized()
		for sg: float in [1.0, -1.0]:
			b.tri(a, e, f, n * sg, col)
			b.tri(a, f, d, n * sg, col)
	for sx: float in [-1.0, 1.0]:
		var foot := Vector3(lo * sx, c0.y, c0.x)
		var top := Vector3(up * sx, c1.y, c1.x)
		var inw := Vector3(-sx * 0.11, 0, 0)
		quad2.call(foot, top, top + inw + Vector3(0, -0.02, -0.03), foot + inw + Vector3(0, 0, -0.04), dark)
	quad2.call(Vector3(-up, c1.y - 0.01, c1.x), Vector3(up, c1.y - 0.01, c1.x), Vector3(up, c1.y + 0.01, c1.x - 0.5),
			Vector3(-up, c1.y + 0.01, c1.x - 0.5), dark.lightened(0.1))
	# the bonnet through the windscreen, in the car's paint (the body itself is hidden here:
	# it is built to be seen from outside, and from inside it showed its backs)
	var low: Array = shape[0]
	var hb := Buf.new()
	var hood: Array = []
	for q: Vector2 in low:
		if q.x > c0.x - 0.05 and q.y > 0.5:
			hood.append(q)
	hood.sort_custom(func(a: Vector2, e: Vector2): return a.x < e.x)
	for i in range(hood.size() - 1):
		var a: Vector2 = hood[i]
		var e: Vector2 = hood[i + 1]
		var n := Vector3(0, e.x - a.x, -(e.y - a.y)).normalized()
		if n.y < 0.0:
			n = -n
		hb.tri(Vector3(-hw, a.y, a.x), Vector3(hw, a.y, a.x), Vector3(hw, e.y, e.x), n, Color.WHITE)
		hb.tri(Vector3(-hw, a.y, a.x), Vector3(hw, e.y, e.x), Vector3(-hw, e.y, e.x), n, Color.WHITE)
	var hmi := MeshInstance3D.new()
	var ham := ArrayMesh.new()
	ham.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hb.arrays())
	ham.surface_set_material(0, _car_mat("paint", "paint"))
	hmi.mesh = ham
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cockpit_node.add_child(hmi)
	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	am.surface_set_material(0, m)
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cockpit_node.add_child(mi)
	# the wheel: a ring and three spokes, tilted back toward the driver, turned with the
	# front wheels (about 15 turns of it to one of theirs)
	# the speedometer and rev counter in the binnacle, facing the driver, and the green
	# indicator arrows between them
	var face_c: Color = _tone["tyre"].darkened(0.4)
	var tick_c: Color = _tone["mark"]
	var dial_at := [Vector3(0.465, 1.03, 0.43), Vector3(0.275, 1.03, 0.43)]
	var dial_b := Basis(Vector3.RIGHT, 0.32)   # tipped back toward the eyes
	var b0: Buf = b
	b = Buf.new()   # (the cockpit's own mesh is built already: the dials get one of theirs)
	for di in range(2):
		var c: Vector3 = dial_at[di]
		var R := 0.052
		for i in range(16):
			var a0 := TAU * i / 16.0
			var a1 := TAU * (i + 1) / 16.0
			var e0 := Vector3(cos(a0), sin(a0), 0)
			var e1 := Vector3(cos(a1), sin(a1), 0)
			b.tri(c, c + dial_b * (e0 * R), c + dial_b * (e1 * R), dial_b * Vector3.FORWARD, face_c)
			# a bright rim round it, so the dial reads in a dark cabin
			var z := Vector3(0, 0, -0.001)
			b.tri(c + dial_b * (e0 * R + z), c + dial_b * (e0 * (R + 0.006) + z), c + dial_b * (e1 * (R + 0.006) + z), dial_b * Vector3.FORWARD, tick_c)
			b.tri(c + dial_b * (e0 * R + z), c + dial_b * (e1 * (R + 0.006) + z), c + dial_b * (e1 * R + z), dial_b * Vector3.FORWARD, tick_c)
		for i in range(9):
			var a := 2.2 - 4.4 * i / 8.0 + PI * 0.5
			var d := Vector3(cos(a), sin(a), 0)
			var nn := Vector3(-d.y, d.x, 0) * 0.003
			var p0 := d * R * 0.78
			var p1 := d * R * 0.95
			b.tri(c + dial_b * (p0 - nn + Vector3(0, 0, -0.002)), c + dial_b * (p1 - nn + Vector3(0, 0, -0.002)), c + dial_b * (p1 + nn + Vector3(0, 0, -0.002)), dial_b * Vector3.FORWARD, tick_c)
			b.tri(c + dial_b * (p0 - nn + Vector3(0, 0, -0.002)), c + dial_b * (p1 + nn + Vector3(0, 0, -0.002)), c + dial_b * (p0 + nn + Vector3(0, 0, -0.002)), dial_b * Vector3.FORWARD, tick_c)
		var pivot := Node3D.new()
		pivot.position = c + dial_b * Vector3(0, 0, -0.004)
		pivot.basis = dial_b
		_cockpit_node.add_child(pivot)
		var needle := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.004, 0.05, 0.002)
		needle.mesh = nm
		needle.position = Vector3(0, 0.022, 0)
		needle.material_override = mat("hazard", 1.4)
		pivot.add_child(needle)
		if di == 0:
			_dial_speed = pivot
		else:
			_dial_rpm = pivot
	var dmi := MeshInstance3D.new()
	var dam := ArrayMesh.new()
	dam.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	dam.surface_set_material(0, m)
	dmi.mesh = dam
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cockpit_node.add_child(dmi)
	b = b0
	for side: int in [-1, 1]:
		var arrow := MeshInstance3D.new()
		var ab := Buf.new()
		var sx := -float(side)   # the car's right is -X
		var c := Vector3(0.37 + sx * 0.03, 1.03, 0.43)
		ab.tri(c + dial_b * Vector3(sx * 0.018, 0, -0.003), c + dial_b * Vector3(-sx * 0.01, 0.013, -0.003), c + dial_b * Vector3(-sx * 0.01, -0.013, -0.003), dial_b * Vector3.FORWARD, Color.WHITE)
		var aam := ArrayMesh.new()
		aam.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ab.arrays())
		arrow.mesh = aam
		arrow.material_override = mat("friend", 2.2)
		arrow.visible = false
		_cockpit_node.add_child(arrow)
		_dash_arrows[side] = arrow
	_wheel_node = Node3D.new()
	_wheel_node.position = Vector3(0.37, 0.94, 0.3)
	_wheel_node.rotation.x = -0.45
	_cockpit_node.add_child(_wheel_node)
	var wb := Buf.new()
	var rim := dark.darkened(0.3)
	var R := 0.185
	for i in range(14):
		var a0 := TAU * i / 14.0
		var a1 := TAU * (i + 1) / 14.0
		var p0 := Vector3(cos(a0) * R, sin(a0) * R, 0)
		var p1 := Vector3(cos(a1) * R, sin(a1) * R, 0)
		var r0 := p0.normalized() * 0.022
		var r1 := p1.normalized() * 0.022
		for side: float in [1.0, -1.0]:
			var zz := Vector3(0, 0, 0.022 * side)
			wb.tri(p0 + zz - r0, p1 + zz - r1, p1 + zz + r1, Vector3(0, 0, side), rim)
			wb.tri(p0 + zz - r0, p1 + zz + r1, p0 + zz + r0, Vector3(0, 0, side), rim)
			wb.tri(p0 + r0 * side - zz, p1 + r1 * side - zz, p1 + r1 * side + zz, p0.normalized() * side, rim)
			wb.tri(p0 + r0 * side - zz, p1 + r1 * side + zz, p0 + r0 * side + zz, p0.normalized() * side, rim)
	for a: float in [PI * 0.5 + PI, 0.0, PI]:
		var d := Vector3(cos(a), sin(a), 0) * R
		var n := Vector3(-d.y, d.x, 0).normalized() * 0.02
		for side: float in [1.0, -1.0]:
			var zz := Vector3(0, 0, 0.012 * side)
			wb.tri(zz - n, d + zz - n, d + zz + n, Vector3(0, 0, side), rim)
			wb.tri(zz - n, d + zz + n, zz + n, Vector3(0, 0, side), rim)
	var wmi := MeshInstance3D.new()
	var wam := ArrayMesh.new()
	wam.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wb.arrays())
	wam.surface_set_material(0, m)
	wmi.mesh = wam
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wheel_node.add_child(wmi)

## ---- on foot ---------------------------------------------------------------------------------
## Out of the car (the "walk" button, or F): the driver steps out of the door onto the
## street and walks the same city -- arrows or the stick to walk and turn, held action
## (space) to run. Out of a moving car you jump: you tumble out of the door with the car's
## speed, roll, and get up; the car rolls on driverless, slowing, until it stops or hits
## something. Traffic goes round it; traffic stops for you on the road the way it does for
## the car. Back at the car, the same button gets you in.
var _car_v := 0.0                    ## the empty car still rolling (m/s, along its heading)
var _tumble := 0.0                   ## s left of a tumble out of a moving car (no control)
var _jump_v := Vector2.ZERO          ## the tumble's slide

func _get_out() -> void:
	var moving := absf(_v) > 1.0
	if _auto:
		_set_auto(false)
	_set_blink(0)
	_horn_held = false
	_throttle_in = 0.0
	_car_at = _pos
	_car_yaw_at = _yaw
	_car_y_at = _y
	var fwd := _fwd()
	var left := Vector2(fwd.y, -fwd.x)
	var door := _pos + left * 1.4
	if _push_out(door, 0.35, true) != Vector2.ZERO:
		door = _pos - left * 1.4   # a wall on that side: out of the other door
	if _me == null:
		_me = Actor3D.new()
		world.add_child(_me)
		_me.set_character(PEOPLE[1], 1.76)
		_humanize(_me, hash(_me.get_instance_id()))
	_me.visible = true
	_me_anim = ""
	_walking = true
	_car_material()   # (you, seen through the windows, get in or out)
	_set_cockpit(_cockpit)   # (from the eyes if the seat view was on)
	if _cockpit_node != null:
		_cockpit_node.visible = false
	if _sedan_node != null:   # the car seen from outside again, whatever the view
		for gi: GeometryInstance3D in _sedan_node.find_children("*", "GeometryInstance3D", true, false):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_pos = door
	_prev_pos = door
	_car_v = _v if moving else 0.0
	_tumble = 0.0
	_jump_v = Vector2.ZERO
	if moving:
		# out of the door with the car's speed (a little less: you push off it) and away
		# from it; a roll, and up again
		var side := (door - _car_at).normalized()
		_jump_v = fwd * _v * 0.75 + side * 2.2
		_tumble = clampf(0.5 + absf(_v) * 0.05, 0.5, 1.5)
		_me.play("Roll" if absf(_v) > 4.0 else "RecieveHit", false, 1.0)
		_me_anim = "tumble"
		_yaw = _jump_v.angle()
		_prev_yaw = _yaw
	_v = 0.0
	_y = _walk_y(door)
	_prev_y = _y
	_cam_dist = 3.4
	Probe.event("walk", {"on": true, "jumped": moving, "kmh": int(absf(_car_v) * 3.6)})
	_show_banner("jumped out!" if moving else "on foot", 1.0)

func _get_in() -> void:
	var d := _pos.distance_to(_car_at)
	if d > 3.6:
		_show_banner("walk back to the car (%d m)" % int(d), 1.4)
		return
	_walking = false
	_car_material()   # (you, seen through the windows, get in or out)
	_me.visible = false
	_set_cockpit(_cockpit)   # back to the view it was in
	_pos = _car_at
	_prev_pos = _car_at
	_yaw = _car_yaw_at
	_prev_yaw = _yaw
	_y = _car_y_at
	_v = _car_v   # (caught it still rolling: it rolls on with you in it)
	_car_v = 0.0
	_gear = 1
	Probe.event("walk", {"on": false})
	_show_banner("driving", 1.0)

## ---- a filmed walk, replayed ------------------------------------------------------------------
## A place in LEVELS with a "walk" replays a walk someone filmed: in first person, from the
## eyes of someone holding a phone at the chest, on its own, with no controls and no driving
## HUD. The route is in the city's details file (details.gd) as [seconds, x, z] points timed
## to the film, so it passes each place when the film did and the two can be watched side
## by side. At the end it stands still.
## The head is not the body: it looks where the walk is going and turns into a bend a moment
## before the feet do, and the walk's "looks" turn it to see the traffic before a crossing.
## While the walk waits at a crossing or is on it ("zebras"), it counts as someone on the
## zebra, so cars stop for it; "cars" sends a car down a street at a set second, so there is
## traffic to stop when it gets there.

var _film: Array = []                ## Vector3(x, z, seconds): the route, in time order
var _film_t := 0.0
var _film_step := 0.0                ## metres walked: the head bobs with the steps
var _film_done := false
var _film_look := 0.0                ## the head turned from the body (radians, + right)
var _film_looks: Array = []          ## Vector3(from, to, radians): a glance to one side
var _film_zebras: Array = []         ## [from, to, kerb, kerb]: on a crossing (or waiting at it)
var _film_cars: Array = []           ## [second, at, heading]: a car sent down a street
var _film_sent := 0

func _film_begin(id: String) -> void:
	var walks: Dictionary = _details.data.get("walks", {}) if _details != null else {}
	var pts: Array = (walks.get(id, {}) as Dictionary).get("points", [])
	if pts.size() < 2:
		Probe.note("no walk '%s' in this city's details file" % id)
		return
	for p: Array in pts:
		_film.append(Vector3(float(p[1]), float(p[2]), float(p[0])))
	var w: Dictionary = walks[id]
	for l: Array in w.get("looks", []):
		_film_looks.append(Vector3(float(l[0]), float(l[1]), deg_to_rad(float(l[2]))))
	for z: Array in w.get("zebras", []):
		_film_zebras.append([float(z[0]), float(z[1]), Vector2(z[2][0], z[2][1]), Vector2(z[3][0], z[3][1])])
	for c: Array in w.get("cars", []):
		_film_cars.append([float(c[0]), Vector2(c[1][0], c[1][1]), Vector2(c[2][0], c[2][1])])
	_film_cars.sort_custom(func(a, b): return a[0] < b[0])
	var p0 := _film_at(0.0)
	_pos = p0
	_yaw = (_film_at(1.5) - p0).angle()
	_v = 0.0
	_snap_pose()
	_cockpit = true
	_get_out()
	_car.visible = false
	_pos = p0
	_prev_pos = p0
	_cam_yaw = _yaw
	_hud.visible = false
	Probe.event("film", {"walk": id, "seconds": _film[_film.size() - 1].z})

func _film_tick(dt: float) -> void:
	_film_t += dt
	var p := _film_at(_film_t)
	var moved := p.distance_to(_pos)
	_film_step += moved
	_v = moved / maxf(dt, 0.001)
	_pos = p
	_y = _h(p)
	var ahead := _film_at(_film_t + 1.6)
	if ahead.distance_to(p) > 0.3:
		_yaw = lerp_angle(_yaw, (ahead - p).angle(), 1.0 - exp(-dt * 2.2))
	# the head: into a bend before the feet (where the walk is 3.4 s on, against 1.6 s), and
	# off to the side for each glance, easing in and out over half a second
	var turn := 0.0
	var far := _film_at(_film_t + 3.4)
	if ahead.distance_to(p) > 0.3 and far.distance_to(p) > 0.6:
		turn = clampf(angle_difference((ahead - p).angle(), (far - p).angle()) * 0.7, -0.6, 0.6)
	for l: Vector3 in _film_looks:
		if _film_t > l.x and _film_t < l.y:
			turn += l.z * smoothstep(l.x, l.x + 0.5, _film_t) * (1.0 - smoothstep(l.y - 0.5, l.y, _film_t))
	_film_look = lerp_angle(_film_look, turn, 1.0 - exp(-dt * 6.0))
	while _film_sent < _film_cars.size() and _film_t >= float(_film_cars[_film_sent][0]):
		var fc: Array = _film_cars[_film_sent]
		_film_sent += 1
		if _traffic != null and not _traffic.send(fc[1], fc[2]):
			Probe.note("film: no street to send a car down at %s" % fc[1])
	var anim := "Idle" if _v < 0.15 else "Walk"
	if anim != _me_anim:
		_me_anim = anim
		_me.play(anim, true, 1.0 if anim == "Idle" else maxf(_v / WALK, 0.5))
	if _film_t >= _film[_film.size() - 1].z and not _film_done:
		_film_done = true
		Probe.event("film_end", {"at": Vector2i(p)})

## the crossings the walk is waiting at or on, in with the people on zebras (tagged, so the
## last tick's go: the list is only rebuilt where a town has people crossing)
func _film_on_zebras() -> void:
	_zebras_on = _zebras_on.filter(func(z: Array) -> bool: return z.size() < 4)
	for z: Array in _film_zebras:
		if _film_t >= float(z[0]) and _film_t <= float(z[1]):
			var a: Vector2 = z[2]
			var b: Vector2 = z[3]
			_zebras_on.append([(a + b) * 0.5, a.distance_to(b) * 0.5 - 0.1, (b - a).normalized(), "film"])

## where the walk is at time t: a smooth curve (Catmull-Rom) through the timed points
func _film_at(t: float) -> Vector2:
	var n := _film.size()
	if t <= _film[0].z:
		return Vector2(_film[0].x, _film[0].y)
	if t >= _film[n - 1].z:
		return Vector2(_film[n - 1].x, _film[n - 1].y)
	var i := 0
	while i < n - 2 and _film[i + 1].z <= t:
		i += 1
	var a: Vector3 = _film[maxi(i - 1, 0)]
	var b: Vector3 = _film[i]
	var c: Vector3 = _film[i + 1]
	var d: Vector3 = _film[mini(i + 2, n - 1)]
	if Vector2(b.x, b.y).distance_to(Vector2(c.x, c.y)) < 0.05:
		return Vector2(b.x, b.y)   # waiting (at a kerb): the curve would wander off and back
	# a stop either side: no swing past it into the waiting spot or out of it
	if Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) < 0.05:
		a = b - (c - b)
	if Vector2(c.x, c.y).distance_to(Vector2(d.x, d.y)) < 0.05:
		d = c + (c - b)
	var u := (t - b.z) / maxf(c.z - b.z, 0.001)
	return Vector2(b.x, b.y).cubic_interpolate(Vector2(c.x, c.y), Vector2(a.x, a.y), Vector2(d.x, d.y), u)

## the empty car rolling on after you jumped out: no driver, so no steering and no power,
## slowing as a car in gear does with the foot off (a couple of m/s each second); into a
## wall or a car it stops short, with a bang
func _coast_car(dt: float) -> void:
	if _car_v == 0.0:
		return
	var fwd := Vector2(cos(_car_yaw_at), sin(_car_yaw_at))
	_car_v = move_toward(_car_v, 0.0, (1.6 + 0.012 * _car_v * _car_v) * dt)
	_car_at += fwd * _car_v * dt
	var push := Vector2.ZERO
	for off: float in [CAR_OFF, -CAR_OFF]:
		var c := _car_at + fwd * off
		var p := _push_out(c, CAR_R, true, false)
		if _traffic != null:
			p += _traffic.push(c + p, CAR_R)
		if p.length() > push.length():
			push = p
	var rim := _bounds.grow(-EDGE - CAR_R - CAR_OFF)
	push += _car_at.clamp(rim.position, rim.end) - _car_at
	if push != Vector2.ZERO:
		_car_at += push
		var into := -push.normalized().dot(fwd * signf(_car_v)) * absf(_car_v)
		if into > 1.5:
			Audio.play("impact_metal" if into > 8.0 else "impact_punch")
			Probe.event("crash", {"kmh": int(into * 3.6), "hit": "driverless", "auto": false})
		_car_v *= 0.15 if into > 1.5 else 0.6
		if absf(_car_v) < 0.3:
			_car_v = 0.0
	_car_y_at = _h(_car_at)

func _walk(dt: float) -> void:
	_coast_car(dt)
	if _tumble > 0.0:
		# tumbling out of a moving car: sliding, slowing, no control, then up
		_tumble -= dt
		_pos += _jump_v * dt
		_jump_v *= exp(-dt * 3.2)
		_pos += _push_out(_pos, 0.3, true)
		_keep_inside(0.3, false)
		_y = _walk_y(_pos)
		if _tumble <= 0.0:
			_me_anim = ""
		return
	var turn := PInput.axis("move_left", "move_right")
	var go := (1.0 if PInput.pressed("move_up") else 0.0) - (1.0 if PInput.pressed("move_down") else 0.0)
	if _stick_id >= 0:
		turn = signf(_stick.x) * _dead(absf(_stick.x))
		go = -signf(_stick.y) * _dead(absf(_stick.y))
	var run := PInput.pressed("action_a") or (_stick_id >= 0 and _stick.length() > 0.92)
	_yaw = wrapf(_yaw + turn * TURN_ON_FOOT * dt, -PI, PI)
	var want := go * (RUN if run and go > 0.0 else WALK) * (0.6 if go < 0.0 else 1.0)
	_v = move_toward(_v, want, 9.0 * dt)
	_pos += _fwd() * _v * dt
	# walls, trees and posts; the cars going by; the car you left
	var push := _push_out(_pos, 0.3, true)
	push += _steep_push(_pos + push, 0.3)
	_pos += push
	_pos += _traffic.push(_pos, 0.3)
	var cf := Vector2(cos(_car_yaw_at), sin(_car_yaw_at))
	for off: float in [CAR_OFF, -CAR_OFF]:
		var d := _pos - (_car_at + cf * off)
		if d.length() < CAR_R + 0.3 and d.length() > 0.001:
			_pos += d.normalized() * (CAR_R + 0.3 - d.length())
	_keep_inside(0.3, false)
	_y = lerpf(_y, _walk_y(_pos), 1.0 - exp(-dt * 12.0))   # up and down kerbs in a step, not a jump
	var anim := "Idle" if absf(_v) < 0.15 else ("Run" if absf(_v) > WALK + 0.5 else "Walk")
	if anim != _me_anim:
		_me_anim = anim
		_me.play(anim, true, 1.0 if anim == "Idle" else maxf(absf(_v) / (WALK if anim == "Walk" else RUN * 0.8), 0.5))
	elif anim != "Idle":
		_me.anim.speed_scale = maxf(absf(_v) / (WALK if anim == "Walk" else RUN * 0.8), 0.5)

## the camera on foot: over the shoulder, a few metres back (kept out of walls), or from the
## eyes when the seat view is chosen
func _foot_camera(dt: float) -> void:
	var p := _view_pos
	var gy := _view_y
	if _cockpit:
		var fwd := Vector2(cos(_view_yaw + _film_look), sin(_view_yaw + _film_look))
		var eye := Vector3(p.x + fwd.x * 0.15, gy + 1.64, p.y + fwd.y * 0.15)
		var down := -0.08
		if not _film.is_empty():   # a phone held at the chest, looking a little down, bobbing with each step
			eye.y += -0.2 + sin(_film_step * PI / 0.72) * 0.022 * clampf(_v / 1.2, 0.0, 1.0)
			down = -0.2
		look_from(eye, eye + Vector3(fwd.x, down, fwd.y) * 10.0)
		cam.fov = 70.0
		return
	_cam_yaw = lerp_angle(_cam_yaw, _view_yaw, 1.0 - exp(-dt * 4.0))
	var back := Vector2(cos(_cam_yaw), sin(_cam_yaw))
	var clear := _clear_behind(p, -back, 3.4)
	_cam_dist = clear if clear < _cam_dist else lerpf(_cam_dist, clear, 1.0 - exp(-dt * 2.0))
	var e2 := p - back * _cam_dist
	var eye := Vector3(e2.x, maxf(gy + 2.0, _h(e2) + 1.3), e2.y)
	look_from(eye, Vector3(p.x + back.x * 2.0, gy + 1.35, p.y + back.y * 2.0))
	cam.fov = 66.0

## the indicators at the car's four corners, and the reverse lights (+X is the car's left)
func _build_car_signals() -> void:
	var amber := mat("warn", 2.6)
	for side: int in [-1, 1]:
		var x := -0.8 * float(side)
		var lamps: Array = []
		# on the body's rounded corners (CAR_CORNER), front and back
		for at: Vector3 in [Vector3(x, 0.66, 2.08), Vector3(x, 0.84, -2.05)]:
			var l := _part(BoxMesh, at, Vector3(0.16, 0.1, 0.07), amber)
			l.visible = false
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body.add_child(l)
			lamps.append(l)
		_blink_nodes[side] = lamps
	for sx: float in [-1.0, 1.0]:
		var r := _part(BoxMesh, Vector3(sx * 0.4, 0.84, -2.2), Vector3(0.16, 0.09, 0.04), mat("ink", 1.6))
		r.visible = false
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(r)
		_reverse_nodes.append(r)

## the indicator's tick and the horn, made here like the engine: a click, and two tones
## buzzing together
func _build_signal_sounds() -> void:
	var rate := 22050
	var click := PackedFloat32Array()
	click.resize(int(rate * 0.035))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in range(click.size()):
		var t := float(i) / rate
		click[i] = exp(-t * 260.0) * (sin(TAU * 1700.0 * t) + 0.4 * (rng.randf() * 2.0 - 1.0))
	_snd_tick = AudioStreamPlayer.new()
	_snd_tick.stream = _wav(click, rate, false)
	add_child(_snd_tick)
	var horn := PackedFloat32Array()
	horn.resize(int(rate * 0.5))   # 205 and 257.5 cycles: both tones loop seamlessly
	for i in range(horn.size()):
		var t := float(i) / rate
		horn[i] = tanh(2.2 * sin(TAU * 410.0 * t)) + tanh(2.2 * sin(TAU * 515.0 * t)) * 0.85
	_snd_horn = AudioStreamPlayer.new()
	_snd_horn.stream = _wav(horn, rate, true)
	add_child(_snd_horn)

func _wav(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.8, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w

func _set_blink(side: int) -> void:
	_blink = side
	_blink_t = 0.0
	_blink_yaw = _yaw
	if side != 0:
		Probe.event("indicator", {"side": "right" if side > 0 else "left", "auto": _auto})

func _toggle_walk() -> void:
	if _walking:
		_get_in()
	else:
		_get_out()

func _set_lights(on: bool) -> void:
	_lights_on = on
	if _beam_node != null:
		_beam_node.visible = on
	_show_banner("lights on" if on else "lights off", 0.8)

## every tick: the indicator blinks (and ticks), and goes off by itself once the turn it was
## for is done; the reverse lights; the horn
func _controls_tick(dt: float) -> void:
	if _blink != 0:
		_blink_t += dt
		var turned := angle_difference(_blink_yaw, _yaw)   # + : turned right
		if (turned * _blink > 0.6 and absf(_steer) < 0.08) or _blink_t > 20.0:
			_set_blink(0)
	var lit := _blink != 0 and fmod(_blink_t, 0.7) < 0.36
	if lit != _blink_lit:
		_blink_lit = lit
		if _blink != 0 or not lit:
			var base := linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8))))
			if not Audio.muted() and _snd_tick != null and (_blink != 0):
				_snd_tick.volume_db = base - 14.0
				_snd_tick.pitch_scale = 1.0 if lit else 0.82
				_snd_tick.play()
	for side: int in _blink_nodes:
		for l: MeshInstance3D in _blink_nodes[side]:
			l.visible = lit and side == _blink
		if _dash_arrows.has(side):
			(_dash_arrows[side] as Node3D).visible = lit and side == _blink
	for r: MeshInstance3D in _reverse_nodes:
		r.visible = _gear < 0
	_horn_t = maxf(0.0, _horn_t - dt)
	var honk := (_horn_held or _horn_t > 0.0) and not Audio.muted() and not finished
	if _snd_horn != null:
		if honk and not _snd_horn.playing:
			_snd_horn.volume_db = linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8)))) - 8.0
			_snd_horn.play()
			_on_horn()
		elif not honk and _snd_horn.playing:
			_snd_horn.stop()

## what the horn does: people on a crossing ahead hurry, a car standing in a standoff in
## front of you goes
func _on_horn() -> void:
	Probe.event("horn", {})
	for cr: Dictionary in _crossers:
		if cr["state"] == "cross" and (cr["a"] as Vector2).distance_to(_pos) < 30.0:
			cr["speed"] = float(cr["speed"]) * 1.8
	if _traffic != null:
		for c in _traffic.cars:
			if c.alive and c.v < 0.3 and c.wait > 1.5 and c.pos.distance_to(_pos) < 15.0 and (c.pos - _pos).dot(_fwd()) > 0.0:
				c.ignore = 2.5

## autodrive: the turn the plan makes within 35 m, for the indicator (-1, 1, or 0)
func _ap_turn_ahead() -> int:
	var n := _ap_pts.size()
	var dist := 0.0
	for j in range(1, n - 1):
		dist += _ap_pts[j - 1].distance_to(_ap_pts[j])
		if dist > 35.0:
			break
		var din := (_ap_pts[j] - _ap_pts[maxi(j - 3, 0)]).normalized()
		var dout := (_ap_pts[mini(j + 3, n - 1)] - _ap_pts[j]).normalized()
		var a := din.angle_to(dout)
		if absf(a) > 0.7:
			return 1 if a > 0.0 else -1
	return 0

func _set_cockpit(on: bool) -> void:
	_cockpit = on
	if _cockpit_node != null:
		_cockpit_node.visible = on and not _walking
	if _sedan_node != null:
		for gi: GeometryInstance3D in _sedan_node.find_children("*", "GeometryInstance3D", true, false):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on and not _walking \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	cam.near = 0.05 if on else 0.3   # (further out: finer depth for the ground's thin layers)
	if _me != null:   # on foot, from the eyes: no looking out through your own hair
		for gi: GeometryInstance3D in _me.find_children("*", "GeometryInstance3D", true, false):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on and _walking \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_show_banner(("eyes" if on else "over the shoulder") if _walking else ("driver's seat" if on else "chase cam"), 1.0)
	Probe.event("view", {"cockpit": on})

## A sedan at real size (4.6 x 1.8 x 1.45 m), built in code: a body lofted from its side
## profile, a narrower glass cabin on it, bumpers, lights, mirrors, plates and four
## wheels that turn and roll. Faces +Z (forward), like the kit's models.
## `paint` is a tone name; the front wheels land in _wheels, all four in _spinners.
## the player's car: the same body as the traffic's (no wheels, lights or plates: _sedan_rest
## adds its own, which steer, roll and light up), in its own copy of the car shader whose
## paint is the player's colour
func _sedan(paint: String) -> Node3D:
	var root := Node3D.new()
	_car_material()
	_player_car_mat = _car_shader_mat.duplicate() as ShaderMaterial
	_player_car_mat.set_meta("paint", paint)
	_car_material()   # (sets its parameters, the paint among them)
	var mi := MeshInstance3D.new()
	mi.mesh = _car_body("sedan", false).mesh(_player_car_mat)
	root.add_child(mi)
	return _sedan_rest(root, paint)

## Car shapes: [side outline of the lower body (z forward, y up), the four cabin corners
## (windscreen foot, windscreen top, rear top, rear foot), half-width, half-length, wheel
## base half, wheel radius]. The sedan is the player's; parked cars and traffic mix all four.
const CAR_SHAPES := {
	"truck": [[Vector2(-3.4, 0.42), Vector2(3.32, 0.42), Vector2(3.4, 0.8), Vector2(3.3, 1.12), Vector2(2.6, 1.18),
		Vector2(1.5, 1.2), Vector2(1.45, 0.95), Vector2(-3.4, 0.95)],
		[Vector2(2.55, 1.18), Vector2(2.05, 2.3), Vector2(1.55, 2.32), Vector2(1.5, 1.2)], 1.1, 3.4, 2.2, 0.42],
	"sedan": [[Vector2(-2.24, 0.24), Vector2(2.22, 0.24), Vector2(2.3, 0.6), Vector2(2.16, 0.78), Vector2(1.08, 0.93),
		Vector2(-1.62, 1.0), Vector2(-2.16, 0.97), Vector2(-2.3, 0.62)],
		[Vector2(1.06, 0.93), Vector2(0.28, 1.42), Vector2(-0.86, 1.44), Vector2(-1.6, 1.0)], 0.9, 2.3, 1.38, 0.33],
	"hatch": [[Vector2(-1.9, 0.24), Vector2(1.95, 0.24), Vector2(2.02, 0.6), Vector2(1.9, 0.78), Vector2(0.95, 0.92),
		Vector2(-1.82, 0.98), Vector2(-1.98, 0.62)],
		[Vector2(0.92, 0.92), Vector2(0.2, 1.43), Vector2(-1.55, 1.42), Vector2(-1.84, 0.98)], 0.86, 2.0, 1.25, 0.31],
	"suv": [[Vector2(-2.3, 0.34), Vector2(2.28, 0.34), Vector2(2.36, 0.74), Vector2(2.24, 0.98), Vector2(1.2, 1.1),
		Vector2(-2.24, 1.14), Vector2(-2.36, 0.74)],
		[Vector2(1.18, 1.1), Vector2(0.45, 1.74), Vector2(-2.0, 1.76), Vector2(-2.24, 1.14)], 0.96, 2.36, 1.42, 0.38],
	"van": [[Vector2(-2.45, 0.3), Vector2(2.42, 0.3), Vector2(2.5, 0.7), Vector2(2.4, 0.95), Vector2(1.7, 1.05),
		Vector2(-2.45, 1.08), Vector2(-2.5, 0.7)],
		[Vector2(1.68, 1.05), Vector2(1.05, 1.98), Vector2(-2.38, 2.0), Vector2(-2.45, 1.1)], 0.98, 2.5, 1.55, 0.35],
}

## lights, plates and the four wheels on a sedan body
func _sedan_rest(root: Node3D, paint: String) -> Node3D:
	# lights and plates
	# head and tail lights laid on the body's rounded corners, like the traffic's (_lamp)
	var low := PackedVector2Array(CAR_SHAPES["sedan"][0])
	var heads := CarMesh.new()
	var tails := CarMesh.new()
	for sx: float in [-1.0, 1.0]:
		_lamp(heads, low, 0.9, sx * 0.6, 0.68, 0.36, 0.12, true, Color.WHITE)
		_lamp(tails, low, 0.9, sx * 0.63, 0.82, 0.32, 0.14, false, Color.WHITE)
	for pair: Array in [[heads, mat("ink", 1.2)], [tails, mat("hazard", 1.0)]]:
		var lm := MeshInstance3D.new()
		lm.mesh = (pair[0] as CarMesh).mesh(pair[1])
		root.add_child(lm)
	var plate := "warn" if String(_place.get("look", "")) == "med" else "ink"   # Israeli plates are yellow
	root.add_child(_part(BoxMesh, Vector3(0, 0.45, 2.28), Vector3(0.52, 0.12, 0.02), mat(plate, 0.1)))
	root.add_child(_part(BoxMesh, Vector3(0, 0.6, -2.3), Vector3(0.52, 0.12, 0.02), mat(plate, 0.1)))
	# wheels: a pivot each (front ones steer), a tyre and a rim that roll inside it
	_wheels.clear()
	_spinners.clear()
	for wz: float in [1.38, -1.38]:
		for sx: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(sx * 0.8, 0.33, wz)
			root.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			# the same tyre and five-spoke rim as the traffic's, in the player's car shader:
			# the spokes are in the rim's own coordinates, so they turn with it
			var wm := CarMesh.new()
			_wheel(wm, Vector3.ZERO, 0.33, sx, Color(_tone["tyre"], 0.3), Color(_tone["rim"], 0.4))
			var wheel := MeshInstance3D.new()
			wheel.mesh = wm.mesh(_player_car_mat)
			spin.add_child(wheel)
			_spinners.append(spin)
			if wz > 0.0:
				_wheels.append([pivot, 0.0])
	return root

func _car_mat(k: String, paint: String) -> StandardMaterial3D:
	var key := "car_%s_%s" % [k, paint]
	if _smat.has(key):
		return _smat[key]
	var m := _surface({"paint": paint, "glass": "carglass", "trim": "cartrim", "tyre": "tyre", "rim": "rim"}[k])
	m = m.duplicate()
	match k:
		"paint":
			m.metallic = 0.45
			m.roughness = 0.28
		"glass":
			m.metallic = 0.6
			m.roughness = 0.08
		"rim":
			m.metallic = 0.7
			m.roughness = 0.3
	m.set_meta("tone", {"paint": paint, "glass": "carglass", "trim": "cartrim", "tyre": "tyre", "rim": "rim"}[k])
	_smat[key] = m
	return m

## a primitive part: BoxMesh with `size`, or CylinderMesh with (radius, height)
func _part(kind: Variant, at: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if kind == BoxMesh:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = size.x
		cm.bottom_radius = size.x
		cm.height = size.y
		cm.radial_segments = 14
		cm.rings = 1
		mi.mesh = cm
	mi.material_override = m
	mi.position = at
	return mi

## a convex polygon (in order around it), facing `out`
func _poly(buf: Buf, pts: Array, out: Vector3) -> void:
	var n: Vector3 = ((pts[1] as Vector3) - pts[0]).cross((pts[2] as Vector3) - pts[0]).normalized()
	if n.dot(out) < 0.0:
		n = -n
	for i in range(1, pts.size() - 1):
		buf.tri(pts[0], pts[i], pts[i + 1], n, Color.WHITE)

## an axis-aligned box centred at c
func _box(buf: Buf, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	for ax in range(3):
		for sg: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sg
			var u := Vector3.ZERO
			u[(ax + 1) % 3] = h[(ax + 1) % 3]
			var w := Vector3.ZERO
			w[(ax + 2) % 3] = h[(ax + 2) % 3]
			var f := c + n * h[ax]
			_poly(buf, [f - u - w, f + u - w, f + u + w, f - u + w], n)

## start at the place's `start` corner, else on a through road near the middle of town; always in
## the right-hand lane, facing the way traffic goes
func _place_start() -> void:
	_find_start()
	_cam_yaw = _yaw
	_snap_pose()

## where the car starts (_pos, _yaw): the level's corner, else a main road near the middle
func _find_start() -> void:
	# a filmed walk starts where its film does: the squares round there are built first, or
	# its first seconds walked over bare grass while the town built round somewhere else
	if _place.has("walk") and _details != null:
		var pts: Array = ((_details.data.get("walks", {}) as Dictionary).get(String(_place["walk"]), {}) as Dictionary).get("points", [])
		if pts.size() >= 2:
			_pos = Vector2(float(pts[0][1]), float(pts[0][2]))
			_yaw = (Vector2(float(pts[1][1]), float(pts[1][2])) - _pos).angle()
			return
	var spot: Array = _place.get("start", []) if _place.get("city") == _city_id else []
	if spot.size() == 2 and _start_on(spot[0], spot[1]):
		return
	var mid := _bounds.get_center()
	if not _boundary.is_empty():
		var box := Rect2((_boundary[0] as PackedVector2Array)[0], Vector2.ZERO)
		for ring: PackedVector2Array in _boundary:
			for p in ring:
				box = box.expand(p)
		mid = box.get_center()
	var best := INF
	var at := mid
	var dir := Vector2.RIGHT
	for r: Dictionary in _roads:
		if not r["drive"] or not (r["k"] in ["primary", "secondary", "tertiary"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			var L := pts[j].distance_to(pts[j + 1])
			if L < 25.0:
				continue
			var c := (pts[j] + pts[j + 1]) * 0.5
			var d := c.distance_to(mid)
			if d < best:
				best = d
				dir = (pts[j + 1] - pts[j]).normalized()
				if r["o"] == -1:
					dir = -dir
				var lane := _lane_off(r)
				at = c + Vector2(-dir.y, dir.x) * lane
	_pos = at
	_yaw = dir.angle()

## put the car on `street` a few metres past where it meets `cross`; false if they never meet
func _start_on(street: String, cross: String) -> bool:
	for i in range(_nodes.size()):
		var on_street: Array = []
		var on_cross := false
		for e: Vector2i in _node_roads[i]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"]:
				continue
			if r["name"] == street:
				on_street.append(e)
			elif r["name"] == cross:
				on_cross = true
		if not on_cross:
			continue
		for e: Vector2i in on_street:
			var r: Dictionary = _roads[e.x]
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [1, -1]:
				var nxt := e.y + d2
				if nxt < 0 or nxt >= pts.size() or (r["o"] != 0 and r["o"] != d2):
					continue
				var dir := (pts[nxt] - pts[e.y]).normalized()
				var lane := _lane_off(r)
				var into := minf(_node_r[i] + 6.0, pts[e.y].distance_to(pts[nxt]) * 0.6)
				_pos = pts[e.y] + dir * into + Vector2(-dir.y, dir.x) * lane
				_yaw = dir.angle()
				return true
	Probe.note("start corner: %s never meets %s in %s" % [street, cross, _city_id])
	return false

func _physics_process(dt: float) -> void:
	_prev_pos = _pos   # where the car was at the last tick, for _frame() to blend from
	_prev_yaw = _yaw
	_prev_y = _y
	if not _loaded or finished or _picker != null:
		return   # the address picker is open: the world waits
	_p0()
	_signals_tick(dt)
	_crash_cool = maxf(0.0, _crash_cool - dt)
	_touch_t = maxf(0.0, _touch_t - dt)
	_p("lights")
	if _walking:
		_traffic.tick(dt)
		_p("traffic")
		if not _film.is_empty():
			_film_tick(dt)
		else:
			_walk(dt)
			_controls_tick(dt)
		_p("walk")
		_names_tick(dt)
		_p("names")
		_engine_tick(dt)
		_p("sound")
		_people_tick(dt)
		_p("people")
		_crossers_tick(dt)
		if not _film.is_empty():
			_film_on_zebras()
		_p("crossers")
		_explore(dt)
		_p("explore")
		_log.tick(self, dt)
		return
	if PInput.just_pressed("action_a") and not _auto:
		_set_auto(true)
	elif PInput.just_pressed("action_b") and _auto:
		_set_auto(false)
	_traffic.tick(dt)
	_p("traffic")
	var ctl: Array = _autodrive(dt) if _auto else _manual(dt)
	if _auto:
		var turn := _ap_turn_ahead()
		if turn != 0 and _blink != turn:
			_set_blink(turn)
	_p("autodrive")
	_controls_tick(dt)
	_drive(dt, ctl[0], ctl[1], ctl[2])
	_p("car")
	_through_lights()
	_check_stop_signs()
	_p("rules")
	_names_tick(dt)
	_p("names")
	_engine_tick(dt)
	_p("sound")
	_people_tick(dt)
	_p("people")
	_crossers_tick(dt)
	_p("crossers")
	_check_arrival(dt)
	_explore(dt)
	_p("explore")
	_log.tick(self, dt)
	_p("log")

## ---- every drawn frame -------------------------------------------------------------------
## The car moves in fixed physics ticks (60 a second). Drawn as it was at the last tick,
## a screen that draws 75 or 144 times a second, or a browser that misses some, shows it
## (and the camera tied to it) stepping unevenly: choppy even at a good frame rate. So the
## car and camera are drawn where the car is BETWEEN the last two ticks, every frame.

var _prev_pos := Vector2.ZERO
var _prev_yaw := 0.0
var _view_pos := Vector2.ZERO        ## where the car is drawn this frame (the minimap too)
var _view_yaw := 0.0

func _frame() -> void:
	_prof_frame()
	if not _loaded or _car == null or _picker != null:
		return
	_p0()
	var dt := get_process_delta_time()
	if _bg_wait:   # the city still building round you: its few milliseconds (_pause)
		_bg_wait = false
		_build_us = BUILD_US if dt < 0.022 else BUILD_US / 2
		_build_tick.emit()
		_p("building")
	_watch_fps(dt)
	var f := Engine.get_physics_interpolation_fraction()
	_view_pos = _prev_pos.lerp(_pos, f)
	_view_yaw = lerp_angle(_prev_yaw, _yaw, f)
	_view_y = lerpf(_prev_y, _y, f)
	if _walking:
		_pose_car(_car_at, _car_yaw_at, _car_y_at)
		_me.position = Vector3(_view_pos.x, _view_y, _view_pos.y)
		_me.face(Vector3(cos(_view_yaw), 0, sin(_view_yaw)))
		_traffic.draw(f)
		_p("traffic draw")
		_foot_camera(dt)
		_sky_follow()
		_tick_hud()
		_p("camera, hud")
		return
	_pose_car(_view_pos, _view_yaw, _view_y)
	_traffic.draw(f)
	_p("traffic draw")
	_camera(dt, _view_pos, _view_yaw)
	_sky_follow()
	_tick_hud()
	_p("camera, hud")

## ---- render quality: the web build watches its own frame rate and steps down ---------------
## Per level: edge smoothing (MSAA), how far shadows reach (0: none), the 3D resolution.
const QUALITY := [
	[Viewport.MSAA_DISABLED, 0.0, 0.7],
	[Viewport.MSAA_DISABLED, 45.0, 0.85],
	[Viewport.MSAA_2X, 60.0, 1.0],
	[Viewport.MSAA_4X, 75.0, 1.0],
]
const QUALITY_WEB := 2               ## where a browser starts
## A step down: two 2-second spells in a row under FPS_LOW, or with more than STUTTER of their
## frames slower than 33 ms. A step back up: STEP_UP_S seconds at the display's own rate
## (FPS_FULL) -- unless that level failed lately: then not before its wait is up, a wait
## that doubles each time it fails again. Hitches (frames over HITCH_S: loading, a shader
## compiling) are left out of the reckoning: one half-second stall in a spell made a
## smooth 50 fps read as 38, and a PC stepped itself down to nothing and stayed there.
const FPS_LOW := 45.0
const FPS_FULL := 56.0
const STUTTER := 0.1
const HITCH_S := 0.25
const STEP_UP_S := 8.0
var _quality := 3
var _shadow_web := false
var _fps_t := 0.0
var _fps_frames := 0
var _fps_long := 0                   ## frames over 33 ms in this spell: stutter, not just slow
var _fps_low := 0
var _fps_good := 0.0                 ## seconds at the full rate at this level
var _fps_wait := 6.0                 ## the first seconds compile shaders and stutter anyway
var _q_retry_at := {}                ## level -> when it may be tried again (s), after it failed
var _q_fails := {}                   ## level -> how often it has failed
var _q_clock := 0.0

func _set_quality(q: int) -> void:
	if OS.has_feature("web") and not _shadow_web:
		# a 2048 map is plenty over 60 m, and a cheap filter: the 4096 default and its soft
		# filter cost a laptop's graphics chip more than the shadows are worth
		_shadow_web = true
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
	_quality = clampi(q, 0, QUALITY.size() - 1)
	var row: Array = QUALITY[_quality]
	view.msaa_3d = row[0]
	_set_textured(_quality > 0)
	_tree_quality()
	sun.shadow_enabled = float(row[1]) > 0.0
	sun.directional_shadow_max_distance = maxf(float(row[1]), 1.0)
	view.scaling_3d_scale = row[2]
	_set_blobs(not sun.shadow_enabled)

## Only on the web: a desktop build has a real GPU, and test runs on a software renderer
## would step themselves down to nothing.
func _watch_fps(dt: float) -> void:
	if not OS.has_feature("web"):
		return
	if _bg_build:   # the city still building round you is not this machine being slow
		_fps_t = 0.0
		_fps_frames = 0
		_fps_long = 0
		return
	_judge_fps(dt)

func _judge_fps(dt: float) -> void:
	_q_clock += dt
	if _fps_wait > 0.0:
		_fps_wait -= dt
		return
	if dt > HITCH_S:
		return   # a hitch: not the frame rate
	_fps_t += dt
	_fps_frames += 1
	if dt > 0.033:
		_fps_long += 1
	if _fps_t < 2.0:
		return
	var fps := _fps_frames / _fps_t
	var stutter := float(_fps_long) / maxf(_fps_frames, 1)
	_fps_t = 0.0
	_fps_frames = 0
	_fps_long = 0
	if fps < FPS_LOW or stutter > STUTTER:
		_fps_good = 0.0
		_fps_low += 1
		if _fps_low >= 2 and _quality > 0:
			_fps_low = 0
			var failed := _quality
			_q_fails[failed] = int(_q_fails.get(failed, 0)) + 1
			_q_retry_at[failed] = _q_clock + minf(30.0 * pow(2.0, float(_q_fails[failed]) - 1.0), 300.0)
			_set_quality(_quality - 1)
			_fps_wait = 3.0   # (new shaders compile)
			Probe.event("quality", {"level": _quality, "fps": int(fps), "down": true})
		_log.event("quality", _quality)
		return
	_fps_low = 0
	if fps < FPS_FULL or stutter > 0.03:
		_fps_good = 0.0
		return
	_fps_good += 2.0
	var up := _quality + 1
	if up < QUALITY.size() and _fps_good >= STEP_UP_S and _q_clock >= float(_q_retry_at.get(up, 0.0)):
		_fps_good = 0.0
		_set_quality(up)
		_fps_wait = 3.0
		Probe.event("quality", {"level": _quality, "fps": int(fps), "down": false})

## ---- where a frame's time goes ------------------------------------------------------------
## Every part of a physics tick and of a drawn frame is timed (the script's own work, in
## microseconds). The time from one drawn frame to the next that no part accounts for is
## the engine's: drawing the 3D, the shadows, the browser. A frame much slower than the ones
## round it is a hitch: the parts that took its time are kept (the perf view, P or a tap on
## the fps text, shows them with a graph of the last frames) and reported as a "hitch" event
## and a [hitch] line, so a playtest names what chokes.
const PERF_FRAMES := 150
const PERF_RECT := Rect2(486, 74, 146, 20)   ## the fps text: tap it for the perf view
var _prof := {}                      ## part -> microseconds since the last drawn frame began
var _prof_t := 0
var _frame_at := 0
var _frame_ms := PackedFloat32Array()   ## the last frames' times, ms, oldest overwritten first
var _frame_i := 0
var _hitches: Array = []             ## newest first, a few: "12.3 s  95 ms  people 61 · rest 30"
var _hitch_n := 0
var _prof_sum := {}                  ## part -> microseconds over the current 2 s spell
var _prof_n := 0                     ## frames in it
var _prof_wall := 0.0                ## their total time, ms
var _prof_spell := 0
var _prof_avg := ""                  ## the last spell's average frame, part by part
var _perf_view := false
var _perf_lbl: Label

func _p0() -> void:
	_prof_t = Time.get_ticks_usec()

## the part that just finished: its time goes to `part`, and the next part starts now
func _p(part: String) -> void:
	var t := Time.get_ticks_usec()
	_prof[part] = int(_prof.get(part, 0)) + (t - _prof_t)
	_prof_t = t

## at the start of every drawn frame: the one before is done (its drawing, then this frame's
## physics ticks), so its time and its parts are complete
func _prof_frame() -> void:
	var now := Time.get_ticks_usec()
	if _frame_at == 0:
		_frame_at = now
		_prof = {}
		return
	var ms := (now - _frame_at) / 1000.0
	_frame_at = now
	if _frame_ms.size() < PERF_FRAMES:
		_frame_ms.append(ms)
	else:
		_frame_ms[_frame_i] = ms
		_frame_i = (_frame_i + 1) % PERF_FRAMES
	if ms > 25.0 and _frame_ms.size() > 30:
		var sorted := _frame_ms.duplicate()
		sorted.sort()
		var typical := sorted[sorted.size() / 2]
		if ms > maxf(25.0, typical * 2.0 + 8.0):
			_hitch(ms, typical)
	# the average frame over a 2 s spell, part by part: what it costs all the time, not in spikes
	for k: String in _prof:
		_prof_sum[k] = int(_prof_sum.get(k, 0)) + int(_prof[k])
	_prof_n += 1
	_prof_wall += ms
	if now - _prof_spell > 2000000 and _prof_n > 0:
		var parts: Array = []
		var script_ms := 0.0
		for k: String in _prof_sum:
			var pm := float(_prof_sum[k]) / 1000.0 / _prof_n
			if not ":" in k:
				script_ms += pm
			parts.append([pm, k])
		parts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var words: Array = []
		for i in range(mini(5, parts.size())):
			words.append("%s %.1f" % [parts[i][1], float(parts[i][0])])
		_prof_avg = "average %.1f ms: drawing and engine %.1f · script %.1f (%s)" % [_prof_wall / _prof_n,
			_prof_wall / _prof_n - script_ms, script_ms, ", ".join(words)]
		_prof_sum = {}
		_prof_n = 0
		_prof_wall = 0.0
		_prof_spell = now
	_prof = {}

func _hitch(ms: float, typical: float) -> void:
	var parts: Array = []
	var script_ms := 0.0
	for k: String in _prof:
		var pm := float(_prof[k]) / 1000.0
		if not ":" in k:   # "traffic: route" is already inside "traffic"
			script_ms += pm
		parts.append([pm, k])
	parts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var words: Array = []
	for i in range(mini(5, parts.size())):
		if float(parts[i][0]) >= 1.0:
			words.append("%s %d" % [parts[i][1], int(round(float(parts[i][0])))])
	words.append("rest %d" % int(round(ms - script_ms)))
	var line := "%.1f s  %d ms (usual %d)  %s" % [Time.get_ticks_msec() / 1000.0, int(ms), int(typical), " · ".join(words)]
	_hitches.push_front(line)
	if _hitches.size() > 4:
		_hitches.pop_back()
	_hitch_n += 1
	print("[hitch] ", line)
	if _hitch_n <= 40:
		Probe.event("hitch", {"ms": int(ms), "usual": int(typical), "parts": " · ".join(words),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})

## the slowest of the last frames (ms)
func _worst_ms() -> float:
	var w := 0.0
	for v in _frame_ms:
		w = maxf(w, v)
	return w

## after a jump (the start, "back on the road"): no blending from where it was, camera
## straight behind
func _snap_pose() -> void:
	_air = false
	_y = _h(_pos)
	_vy = 0.0
	_spin = 0.0
	_ground_was = _y
	_prev_y = _y
	_view_y = _y
	_prev_pos = _pos
	_prev_yaw = _yaw
	_view_pos = _pos
	_view_yaw = _yaw
	_cam_yaw = _yaw
	_place_car(0.016)
	_camera(1.0, _pos, _yaw)

## keys and touch -> [throttle, brake, wheel angle]. Down brakes, and once stopped, holding
## it selects reverse; then down drives backwards and up brakes, like a real automatic.
func _manual(dt: float) -> Array:
	var steer_t := PInput.axis("move_left", "move_right")
	var up := 1.0 if PInput.pressed("move_up") else 0.0
	var down := 1.0 if PInput.pressed("move_down") else 0.0
	if _stick_id >= 0:
		# the touch stick is analog: a little off centre is a little gas or a little lock,
		# and steering is eased near the middle so small corrections stay small
		var k := _stick
		up = maxf(up, _dead(-k.y))
		down = maxf(down, _dead(k.y))
		var sx := _dead(absf(k.x))
		_steer_in = signf(k.x) * pow(sx, 1.4)
	else:
		var rate := STEER_RATE if absf(steer_t) > 0.0 and signf(steer_t) == signf(_steer_in) else STEER_RATE * 1.8
		_steer_in = move_toward(_steer_in, steer_t, rate * dt)
	var lock := MAX_STEER / (1.0 + pow(absf(_v) / STEER_V, 2.0))
	var steer := _steer_in * lock
	if _assist and _v > 1.5:
		steer += _assist_steer() * clampf(1.0 - absf(_steer_in) / ASSIST_FADE, 0.0, 1.0)
	var throttle := 0.0
	var brake := 0.0
	if _gear > 0:
		throttle = up
		brake = down
		if down > 0.0 and up == 0.0 and _v < 0.4:
			_rev_hold += dt
			# nose against something: straight into reverse, no waiting
			if _rev_hold > (0.06 if _touch_t > 0.0 else 0.3):
				_gear = -1
				Probe.event("reverse")
		else:
			_rev_hold = 0.0
	else:
		throttle = down
		brake = up
		if up > 0.0 and down == 0.0 and _v > -0.4:
			_gear = 1
	if _assist and _gear > 0 and _v > 2.0 and _blocked_ahead():
		throttle = 0.0
		brake = maxf(brake, clampf((_v - 1.0) / 7.0, 0.35, 1.0))
	# stuck: a pedal down against something and the car getting nowhere -- nose in a
	# corner, wedged on a tree, rocking between two parked cars. With or without the assist:
	# nobody wants to sit there.
	if up + down > 0.5 and _touch_t > 0.0:
		_pinned_t += dt
		if _pos.distance_to(_pin_at) > 1.2:   # backing out (or sliding off) is working
			_pin_at = _pos
			_pinned_t = 0.0
		elif _pinned_t > RESCUE_AFTER:
			_rescue()
	else:
		_pinned_t = 0.0
		_pin_at = _pos
	return [throttle, brake, steer]

## the assist's nudge: toward the street's direction and the middle of its lane, while
## the car is roughly following the street (not crossing it or turning off it)
func _assist_steer() -> float:
	var hit := _nearest_seg(_pos, 12.0, true, true)
	if hit.is_empty():
		return 0.0
	var r: Dictionary = _roads[hit["road"]]
	var pts: PackedVector2Array = r["pts"]
	var sj: int = hit["seg"]
	var d := (pts[sj + 1] - pts[sj]).normalized()
	var fwd := _fwd()
	if d.dot(fwd) < 0.0:
		d = -d
	var err := fwd.angle_to(d)
	if absf(err) > 0.6:
		return 0.0
	var right := Vector2(-d.y, d.x)
	var lat := (_pos - (hit["q"] as Vector2)).dot(right)
	var off := lat - _nearest_lane(r, lat)   # (the lane it is in, of several)
	return clampf(err * ASSIST_ALIGN - off * ASSIST_LANE, -ASSIST_MAX, ASSIST_MAX)

## something solid where the car will be in about half a second
func _blocked_ahead() -> bool:
	var fwd := _fwd()
	for k: float in [0.6, 1.0]:
		var p := _pos + fwd * (CAR_LEN * 0.5 + 0.8 + _v * 0.45 * k) + Vector2(-fwd.y, fwd.x) * _steer * 3.0 * k
		if _push_out(p, 0.6, true) != Vector2.ZERO or _steep_push(p, 0.6) != Vector2.ZERO:
			return true
	return false

## back into the nearest lane, facing along the street the way the car was facing
func _rescue() -> void:
	_pinned_t = 0.0
	if _land_on_road(_pos, 80.0, _fwd()):
		_show_banner("back on the road", 1.4)
		Probe.event("rescue")

## put the car down, stopped, in the right-hand lane of the street nearest `near` (within
## `reach`), clear of parked cars and trees; facing `prefer` where the street allows,
## else (prefer = zero) the way that has `near` on the kerb side. False if no street.
func _land_on_road(near: Vector2, reach: float, prefer: Vector2) -> bool:
	var hit := _nearest_seg(near, reach, true, true)
	if hit.is_empty():
		return false
	var r: Dictionary = _roads[hit["road"]]
	var pts: PackedVector2Array = r["pts"]
	var sj: int = hit["seg"]
	var d := (pts[sj + 1] - pts[sj]).normalized()
	if r["o"] != 0:
		d *= float(r["o"])
	elif prefer != Vector2.ZERO:
		if d.dot(prefer) < 0.0:
			d = -d
	elif (near - (hit["q"] as Vector2)).dot(Vector2(-d.y, d.x)) < 0.0:
		d = -d   # the address on the right, the kerb side
	var lane := _lane_off(r)
	var at := (hit["q"] as Vector2) + Vector2(-d.y, d.x) * lane
	# not on top of a parked car or a tree: a little along the street until both ends of
	# the car are clear
	for s: float in [0.0, 5.0, -5.0, 10.0, -10.0, 15.0, -15.0, 20.0]:
		var p := at + d * s
		if _push_out(p + d * CAR_OFF, CAR_R, true) == Vector2.ZERO \
				and _push_out(p - d * CAR_OFF, CAR_R, true) == Vector2.ZERO:
			at = p
			break
	_pos = at
	_yaw = d.angle()
	_v = 0.0
	_v_lat = 0.0
	_yaw_rate = 0.0
	_gear = 1
	_steer_in = 0.0
	_pin_at = _pos
	_snap_pose()
	return true

## 0 inside the dead zone, then 0..1 to the rim
func _dead(v: float) -> float:
	return clampf((v - STICK_DEAD) / (1.0 - STICK_DEAD), 0.0, 1.0)

func _drive(dt: float, throttle: float, brake: float, steer: float) -> void:
	_steer = steer
	_throttle_in = throttle
	var v := _v
	var f := 0.0
	if _air:
		throttle = 0.0   # wheels in the air: the engine just revs
		brake = 0.0
	if _gear > 0:
		f = throttle * minf(ENGINE_F, POWER / maxf(absf(v), 0.1))
	elif v > -REVERSE_MAX:
		f = -throttle * REVERSE_F
	var resist := DRAG * v * absf(v) + ROLL * signf(v)
	if throttle <= 0.01:
		resist += ENGINE_BRAKE * signf(v)
	if _hnx > 0 and not _air:   # gravity along the road: uphill slows you, downhill pulls
		var fwd0 := _fwd()
		_slope = atan2(_h(_pos + fwd0 * 1.4) - _h(_pos - fwd0 * 1.4), 2.8)
		resist += MASS * 9.81 * sin(_slope)
	var nv := v + (f - resist) / MASS * dt
	if v != 0.0 and signf(nv) != signf(v) and throttle <= 0.01:
		nv = 0.0   # resistance stops you; it never pushes you backwards
	if throttle <= 0.01 and absf(nv) < 0.3 and absf(_slope) < 0.14:
		nv = 0.0   # stopped on a gentle slope: the car holds (an automatic on the brake)
	nv = move_toward(nv, 0.0, brake * BRAKE_F / MASS * dt)
	_a_long = (nv - v) / dt
	_v = nv
	_odo += absf(_v) * dt
	# bicycle model turning about the rear axle, capped by what the tyres can hold
	var want := _v * tan(_steer) / WHEELBASE
	var cap := GRIP / maxf(absf(_v), 1.0)
	want = clampf(want, -cap, cap)
	if not _air:   # no steering in the air: it keeps the turn it took off with
		_yaw_rate = lerpf(_yaw_rate, want, 1.0 - exp(-dt * 10.0))
	_spin *= exp(-dt * 2.2)
	_yaw = wrapf(_yaw + (_yaw_rate + _spin) * dt, -PI, PI)
	_v_lat *= exp(-dt * 5.0)
	var fwd := _fwd()
	var right := Vector2(-fwd.y, fwd.x)
	_pos += (fwd * _v + right * (_v_lat + _yaw_rate * WHEELBASE * 0.5)) * dt
	_collide()
	_keep_inside(CAR_R, true)
	_fly(dt)
	_place_car(dt)

## The edge of the map: a striped barrier EDGE metres in from the baked area's rim, with a
## glowing curtain over it that shows as you come near (it used to be an invisible wall the
## car stopped dead against). The car's circles (or a walker, r 0.3) are kept off it.
const EDGE := 6.0
const EDGE_BAND := 1.1                ## the barrier's height
const EDGE_CURTAIN := 7.0             ## the curtain's top
var _edge_mats: Array = []
var _edge_warned := 0.0

func _keep_inside(r: float, car: bool) -> void:
	var inside := _bounds.grow(-EDGE - r)
	var push := Vector2.ZERO
	var circles: Array = [_pos + _fwd() * CAR_OFF, _pos - _fwd() * CAR_OFF] if car else [_pos]
	for q: Vector2 in circles:
		var d := q.clamp(inside.position, inside.end) - q
		if absf(d.x) > absf(push.x):
			push.x = d.x
		if absf(d.y) > absf(push.y):
			push.y = d.y
	if push == Vector2.ZERO:
		return
	_pos += push
	if car:
		var into := -push.normalized().dot(_fwd() * signf(_v)) * absf(_v)
		_v *= 0.4
		if into > 0.5:
			_last_hit = "edge"
			_crash(into)
	if Time.get_ticks_msec() * 0.001 > _edge_warned:
		_edge_warned = Time.get_ticks_msec() * 0.001 + 6.0
		_show_banner("the edge of the map", 1.4)
		Probe.event("map_edge", {"at": Vector2i(_pos)})

## the barrier and curtain along the four sides, following the ground, a few metres a piece
func _build_edge() -> void:
	_edge_mats = []
	for curtain: bool in [false, true]:
		var sh := Shader.new()   # (two: the barrier opaque, only the curtain see-through)
		sh.code = ("#define CURTAIN\n" if curtain else "") + EDGE_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("band", EDGE_BAND)
		m.set_shader_parameter("top", EDGE_CURTAIN)
		m.render_priority = 1 if curtain else 0
		_edge_mats.append(m)
	_retint_edge()
	var rim := _bounds.grow(-EDGE)
	var corners := [rim.position, Vector2(rim.end.x, rim.position.y), rim.end, Vector2(rim.position.x, rim.end.y)]
	for side in range(4):
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var L := a.distance_to(b)
		var n := maxi(1, ceili(L / 4.0))
		for curtain: bool in [false, true]:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for k in range(n):
				var p0 := a.lerp(b, float(k) / n)
				var p1 := a.lerp(b, float(k + 1) / n)
				var g0 := _h(p0)
				var g1 := _h(p1)
				var lo0 := g0 + (EDGE_BAND if curtain else -0.4)
				var lo1 := g1 + (EDGE_BAND if curtain else -0.4)
				var hi0 := g0 + (EDGE_CURTAIN if curtain else EDGE_BAND)
				var hi1 := g1 + (EDGE_CURTAIN if curtain else EDGE_BAND)
				var s0 := L * float(k) / n
				var s1 := L * float(k + 1) / n
				var v: Array = [Vector3(p0.x, lo0, p0.y), Vector3(p1.x, lo1, p1.y), Vector3(p1.x, hi1, p1.y), Vector3(p0.x, hi0, p0.y)]
				var uv: Array = [Vector2(s0, lo0 - g0), Vector2(s1, lo1 - g1), Vector2(s1, hi1 - g1), Vector2(s0, hi0 - g0)]
				for i: int in [0, 1, 2, 0, 2, 3]:
					st.set_uv(uv[i])
					st.add_vertex(v[i])
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = _edge_mats[1 if curtain else 0]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world.add_child(mi)

func _retint_edge() -> void:
	for m: ShaderMaterial in _edge_mats:
		m.set_shader_parameter("stripe", Palette.col("hazard"))
		m.set_shader_parameter("ink", Palette.col("ink"))

const EDGE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float band = 1.1;
uniform float top = 7.0;
uniform vec3 stripe : source_color = vec3(1.0, 0.2, 0.4);
uniform vec3 ink : source_color = vec3(1.0);
varying float dist;
void vertex() {
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
void fragment() {
#ifndef CURTAIN
	// chevrons on the barrier: the hazard colour and white, a bright line along its top
	float s = fract((UV.x + UV.y) / 1.6);
	vec3 c = s < 0.5 ? stripe : ink;
	c = mix(c, ink, smoothstep(band - 0.12, band - 0.04, UV.y));
	ALBEDO = c;
#else
	// the curtain: glowing at the barrier, fading up, with faint upright lines; only when
	// near (a ring of light round the town on the horizon is no help)
	float h = clamp((UV.y - band) / (top - band), 0.0, 1.0);
	float lines = 0.75 + 0.25 * step(0.85, fract(UV.x / 3.0));
	float near = 1.0 - smoothstep(60.0, 180.0, dist);
	ALBEDO = mix(stripe, ink, 0.25);
	ALPHA = (1.0 - h) * (1.0 - h) * 0.55 * lines * near;
#endif
}
"""

## up and down: on the ground the car rides it; over a crest the ground can fall away
## faster than the car comes down, and then it flies, with a little lift for the fun of it,
## and lands with a thump (and a bounce if it came down hard)
func _fly(dt: float) -> void:
	var ground := _h(_pos)
	var gv := (ground - _ground_was) / maxf(dt, 0.001)   # the ground's own rise or fall, under the car
	_ground_was = ground
	if _air:
		_vy -= AIR_G * dt
		_y += _vy * dt
		if _y <= ground:
			var hit := gv - _vy   # how fast it met the ground
			_y = ground
			if hit > 5.0:
				_vy = gv + hit * 0.3   # a hard landing bounces
				_crash(hit * 0.8)
				_pitch = clampf(_pitch + 0.08, -0.15, 0.15)
			else:
				_air = false
				_vy = gv
				if hit > 2.0:
					shake3d(hit * 0.5)
					Audio.play("impact_soft", 0.1, -4.0)
					Probe.event("landed", {"kmh": int(_v * 3.6), "hit": snappedf(hit, 0.1)})
				_pitch = clampf(_pitch + hit * 0.012, -0.1, 0.1)   # the nose dips onto its springs
		return
	if _vy - gv > LIFTOFF and absf(_v) > 7.0:
		_air = true
		_vy = _vy * 1.1 + 0.6
		_y = ground
		Probe.event("airborne", {"kmh": int(_v * 3.6)})
		return
	_y = ground
	_vy = lerpf(_vy, gv, 0.5)

## knocked off the ground (a hard hit): up it goes, a little
func _hop(up: float) -> void:
	if not _air:
		_air = true
		_y = _h(_pos)
	_vy = maxf(_vy, up)

func _place_car(dt: float) -> void:
	_pose_car(_pos, _yaw, _y)
	var k := 1.0 - exp(-dt * 6.0)
	_roll = lerpf(_roll, clampf(-_v * _yaw_rate * 0.006, -0.07, 0.07), k)
	_pitch = lerpf(_pitch, clampf(-_a_long * 0.005, -0.05, 0.05), k)
	_body.rotation = Vector3(_pitch, 0.0, _roll)
	for w: Array in _wheels:
		(w[0] as Node3D).rotation.y = float(w[1]) - _steer
	for sp: Node3D in _spinners:
		sp.rotation.x += _v * dt / 0.33

## the car's body where the map says, sitting on the slope: nose up a hill, leaning across
## a camber
func _pose_car(p: Vector2, yaw: float, y := NAN) -> void:
	_car.position = Vector3(p.x, (_h(p) if is_nan(y) else maxf(y, _h(p))) + road_top(), p.y)
	_car.rotation.y = PI * 0.5 - yaw
	if _air:   # in the air the nose follows the flight
		_car.rotation.x = lerp_angle(_car.rotation.x, -atan2(_vy, maxf(absf(_v), 3.0)) * 0.8, 0.15)
		return
	if _hnx > 0:
		var fwd := Vector2(cos(yaw), sin(yaw))
		var side := Vector2(-fwd.y, fwd.x)
		var pitch := atan2(_h(p + fwd * 1.4) - _h(p - fwd * 1.4), 2.8)
		var roll := atan2(_h(p - side * 0.8) - _h(p + side * 0.8), 1.6)
		_car.rotation.x = -pitch
		_car.rotation.z = roll

## ---- the engine's sound ----------------------------------------------------------------------
## Made here, not from a file: a half-second loop of a four-cylinder's firing pulses at
## 1200 rpm (40 a second, uneven from cylinder to cylinder, a half-order shake under them),
## low-passed. Every part repeats a whole number of times in the loop, so it has no seam.
## Played at a pitch of rpm / 1200, with a simple automatic gearbox giving the rpm; a second,
## brighter loop (hiss and higher harmonics on each firing) comes in with the throttle. A
## looping clip with its pitch changed is cheap and smooth in a browser, where pushing
## generated audio every frame stutters whenever a frame is late.

const ENGINE_RATE := 22050
const ENGINE_F0 := 40.0
const IDLE_RPM := 800.0
const GEAR_RPM := [420.0, 240.0, 165.0, 122.0, 96.0]   ## rpm per m/s, first to fifth
var _engine: Array = []              ## [rumble, load, traffic going by]
var _rpm := IDLE_RPM
var _gear_n := 1
var _load := 0.0

func _build_engine() -> void:
	for bright: bool in [false, true, false]:
		var p := AudioStreamPlayer.new()
		p.stream = _engine_loop(bright)
		p.volume_db = -80.0
		add_child(p)
		_engine.append(p)

func _engine_loop(bright: bool) -> AudioStreamWAV:
	var n := int(ENGINE_RATE * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 if bright else 3
	var lump := [1.0, 0.82, 0.93, 0.78]   # no two cylinders fire quite alike
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in range(n):
		var t := float(i) / ENGINE_RATE
		var cyc := t * ENGINE_F0
		var k := int(cyc)
		var ph := cyc - float(k)
		var pulse: float = exp(-ph * (9.0 if bright else 5.0)) * float(lump[k % 4])
		var v := pulse + 0.25 * sin(TAU * ENGINE_F0 * 0.5 * t)
		if bright:
			v += (rng.randf() * 2.0 - 1.0) * 0.6 * pulse
			v += 0.3 * sin(TAU * ENGINE_F0 * 3.0 * t) * pulse
		raw[i] = v
	# a one-pole low-pass, round the loop twice so its end runs into its start
	var cut := 0.35 if bright else 0.12
	var y := 0.0
	var out := PackedFloat32Array()
	out.resize(n)
	for pass_i in range(2):
		for i in range(n):
			y += (raw[i] - y) * cut
			out[i] = y
	var mean := 0.0
	for i in range(n):
		mean += out[i]
	mean /= n
	var peak := 0.0001
	for i in range(n):
		peak = maxf(peak, absf(out[i] - mean))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		data.encode_s16(i * 2, int(clampf((out[i] - mean) / peak * 0.85, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = ENGINE_RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

func _engine_tick(dt: float) -> void:
	if _engine.is_empty():
		return
	var off := Audio.muted() or finished
	for p: AudioStreamPlayer in _engine:
		if off and p.playing:
			p.stop()
		elif not off and not p.playing:
			p.play()
	if off:
		return
	# the gearbox: up a gear sooner on a light foot, later with it down; down below 1250
	var v := 0.0 if _walking else absf(_v)   # on foot: the car idles where it was left
	if _gear > 0:
		var up_at := 2000.0 + 1700.0 * _throttle_in
		if v * float(GEAR_RPM[_gear_n - 1]) > up_at and _gear_n < GEAR_RPM.size():
			_gear_n += 1
		elif v * float(GEAR_RPM[_gear_n - 1]) < 1250.0 and _gear_n > 1:
			_gear_n -= 1
	else:
		_gear_n = 1
	var want := maxf(IDLE_RPM, v * float(GEAR_RPM[_gear_n - 1]))
	if v < 1.5:   # pulling away: the clutch lets the revs rise with the pedal
		want = maxf(want, IDLE_RPM + 1500.0 * _throttle_in)
	_rpm = lerpf(_rpm, want, 1.0 - exp(-dt * 7.0))
	_load = lerpf(_load, _throttle_in, 1.0 - exp(-dt * 6.0))
	var base := linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8))))
	var pitch := clampf(_rpm / 1200.0, 0.3, 4.0)
	var rumble: AudioStreamPlayer = _engine[0]
	var load: AudioStreamPlayer = _engine[1]
	rumble.pitch_scale = pitch
	load.pitch_scale = pitch
	rumble.volume_db = base - 7.0 + 4.0 * clampf((_rpm - IDLE_RPM) / 3500.0, 0.0, 1.0)
	load.volume_db = base - 34.0 + 30.0 * sqrt(_load)
	if _walking:   # idling behind you, quieter the further you walk
		rumble.volume_db -= 4.0 + _pos.distance_to(_car_at) * 0.9
		load.volume_db = -80.0
	# the nearest car going by: louder as it nears, its pitch with its speed
	var by: AudioStreamPlayer = _engine[2]
	var near := INF
	var nv := 0.0
	if _traffic != null:
		for c in _traffic.cars:
			if c.alive and c.v > 1.0:
				var d: float = c.pos.distance_to(_pos)
				if d < near:
					near = d
					nv = c.v
	if near < 45.0:
		by.pitch_scale = clampf((IDLE_RPM + nv * 150.0) / 1200.0, 0.4, 3.0)
		by.volume_db = base - 12.0 - near * 0.55
	else:
		by.volume_db = -80.0

## ---- people ----------------------------------------------------------------------------------

func _spawn_people() -> void:
	_build_life()
	_people_rng.seed = hash(_city_name) + 7
	for i in range(WALKERS):
		var a := Actor3D.new()
		world.add_child(a)
		a.set_character(PEOPLE[i % PEOPLE.size()], _people_rng.randf_range(1.62, 1.88))
		_humanize(a, hash(a.get_instance_id()))
		_people_lod(a)
		var w := {"actor": a, "line": PackedVector2Array(), "cum": PackedFloat32Array(), "s": 0.0,
			"dir": 1.0, "speed": _people_rng.randf_range(1.1, 1.6), "dodge": 0.0,
			"carry": _people_rng.randf() < 0.22}
		_walkers.append(w)
		_place_walker(w, true)
	for i in range(CHATTERS):
		var a := Actor3D.new()
		world.add_child(a)
		a.set_character(PEOPLE[(i + 2) % PEOPLE.size()], _people_rng.randf_range(1.62, 1.88))
		_humanize(a, hash(a.get_instance_id()))
		_people_lod(a)
		a.play("Idle", true, _people_rng.randf_range(0.8, 1.1))
		a.visible = false
		_chatters.append({"actor": a, "spot": Vector2.INF})
	_seat_chatters()

## A person is about eight meshes (body, head, hair, clothes...), each its own draw call
## and its own skinning every frame: thirty-six of them were three hundred draws, more
## than the whole city. Past PEOPLE_SEEN they are a few pixels tall, so there they are
## not drawn (the renderer drops them by range) and do not animate (_people_tick).
func _people_lod(a: Actor3D) -> void:
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = PEOPLE_SEEN
		mi.visibility_range_end_margin = 5.0

func _people_awake(a: Actor3D, p: Vector2) -> void:
	var near := p.distance_to(_pos) < PEOPLE_SEEN + 8.0
	if a.anim != null and a.anim.active != near:
		a.anim.active = near

## How lived-in a place is, 0..1, from what is within 60 m of it: buildings (homes,
## offices) and places (shops, cafes, schools count for more). A busy town street is 1; a
## verge out by the motorway is next to nothing, and people turn up there accordingly.
var _life := {}                       ## 60 m cell -> score
const LIFE_CELL := 60.0

func _build_life() -> void:
	_life = {}
	for box: Rect2 in _bld_box:
		var k := _cell(box.get_center(), LIFE_CELL)
		_life[k] = float(_life.get(k, 0.0)) + 1.0
	for poi: Array in _pois:
		var k := _cell(poi[0], LIFE_CELL)
		_life[k] = float(_life.get(k, 0.0)) + 4.0

func _liveliness(p: Vector2) -> float:
	var c := _cell(p, LIFE_CELL)
	var sum := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			sum += float(_life.get(c + Vector2i(dx, dz), 0.0))
	return clampf(sum / 40.0, 0.04, 1.0)

## a walker onto a pavement near the car (ahead of it rather than behind when it moves)
func _place_walker(w: Dictionary, anywhere: bool) -> void:
	var a: Actor3D = w["actor"]
	# a few tries a call, not a dozen: each walks a whole street's pavement, and a walker that
	# found nothing is simply tried again on a later tick (one walker a tick, _people_tick)
	for _try in range(12 if anywhere else 4):
		var ang := _people_rng.randf() * TAU
		if not anywhere and absf(_v) > 2.0:
			ang = _yaw + _people_rng.randf_range(-0.9, 0.9)
		var d := _people_rng.randf_range(25.0 if anywhere else PEOPLE_SEEN + 8.0, PEOPLE_RANGE * 0.9)
		var hit := _nearest_seg(_pos + Vector2(cos(ang), sin(ang)) * d, 40.0, true, true)
		if hit.is_empty():
			continue
		var r: Dictionary = _roads[hit["road"]]
		if not _kerbed(r):
			continue   # no pavement: a motorway, a slip road, a service lane, a private way
		# as many people as the place has life: by its homes, shops and cafes
		if _people_rng.randf() > _liveliness(hit["q"]):
			continue
		var runs := _street_runs(r)
		if runs.is_empty():
			continue
		var run: PackedVector2Array = runs[_people_rng.randi() % runs.size()]
		# a divided road's pavement is on its outer side: the inner one is the median, and
		# a step past it the other carriageway
		var side := float(r["o"]) if r.has("median") else (1.0 if _people_rng.randf() < 0.5 else -1.0)
		# the back half of the pavement: the parked cars stand on the front of it
		var line := _offset_line(run, (float(r["w"]) * 0.5 + _people_rng.randf_range(1.85, 2.2)) * side)
		line = _pavement_piece(line)
		if line.size() < 2:
			continue
		var cum := PackedFloat32Array([0.0])
		for i in range(1, line.size()):
			cum.append(cum[i - 1] + line[i - 1].distance_to(line[i]))
		if cum[cum.size() - 1] < 8.0:
			continue
		var s0 := _people_rng.randf() * cum[cum.size() - 1]
		if not anywhere and not _unseen(_along(line, cum, s0)):
			continue   # never appear in view: only where nobody is drawn (or behind you)
		w["line"] = line
		w["cum"] = cum
		w["s"] = s0
		w.erase("yaw")
		w["dir"] = 1.0 if _people_rng.randf() < 0.5 else -1.0
		a.play("Walk_Carry" if w["carry"] else "Walk", true, float(w["speed"]) / 1.35)
		a.visible = true
		return
	a.visible = false

## Somewhere to walk along a pavement line: the longest-but-random stretch of it that keeps
## off every road's asphalt and out of the buildings. A driveway's mouth, a few metres, is
## walked over; a service lane or a car park's lane running alongside, the other half of a
## divided road, the next street where two meet at an angle are not -- people walked down
## all of those. [] when nothing is left 8 m long.
func _pavement_piece(line: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(line.size() - 1):
		var n := maxi(1, ceili(line[i].distance_to(line[i + 1]) / 1.5))
		for k in range(n):
			pts.append(line[i].lerp(line[i + 1], float(k) / n))
	pts.append(line[line.size() - 1])
	var n := pts.size()
	var bad := PackedByteArray()   # 0 clear, 1 asphalt, 2 a building
	bad.resize(n)
	for i in range(n):
		if _push_out(pts[i], 0.35, false) != Vector2.ZERO:
			bad[i] = 2
		elif not _off_road(pts[i], 0.3):
			bad[i] = 1
	# forgive short stretches of asphalt between clear ground (a driveway, an alley's mouth)
	var i := 0
	while i < n:
		if bad[i] != 1:
			i += 1
			continue
		var j := i
		while j < n and bad[j] == 1:
			j += 1
		if i > 0 and j < n and bad[i - 1] == 0 and bad[j] == 0 and j - i <= 4:
			for k in range(i, j):
				bad[k] = 0
		i = j
	var pieces: Array = []
	var cur := PackedVector2Array()
	var length := 0.0
	for k in range(n + 1):
		if k < n and bad[k] == 0:
			if not cur.is_empty():
				length += cur[cur.size() - 1].distance_to(pts[k])
			cur.append(pts[k])
			continue
		if length >= 8.0:
			pieces.append(cur)
		cur = PackedVector2Array()
		length = 0.0
	if pieces.is_empty():
		return PackedVector2Array()
	return pieces[_people_rng.randi() % pieces.size()]

## People by the cafe tables near the car, standing about. Re-seated at the nearest tables
## every second and a half, they jumped from table to table in plain view as the car moved;
## now one stays put while it can be seen, and only one out of sight moves -- to a table
## that is also out of sight, so tables ahead are taken before they come into view.
func _seat_chatters() -> void:
	if _table_spots.is_empty():
		return
	var taken := {}
	for c: Dictionary in _chatters:
		if (c["actor"] as Actor3D).visible:
			taken[c["spot"]] = true
	var first := not _chatters_sat   # (the first time, as the city appears: anywhere near)
	_chatters_sat = true
	var free_spots: Array = _table_spots.filter(func(t): return t.distance_to(_pos) < PEOPLE_RANGE and not taken.has(t) and (first or _unseen(t)))
	var fwd := _fwd()
	free_spots.sort_custom(func(a, b): return (a - _pos).dot(fwd) - a.distance_to(_pos) * 0.5 > (b - _pos).dot(fwd) - b.distance_to(_pos) * 0.5)
	for i in range(_chatters.size()):
		var c: Dictionary = _chatters[i]
		var a: Actor3D = c["actor"]
		var at: Vector2 = c["spot"]
		if a.visible and not first and not _unseen(at) and at.distance_to(_pos) < PEOPLE_RANGE:
			continue   # in view: stays
		if free_spots.is_empty():
			if a.visible and at.distance_to(_pos) >= PEOPLE_RANGE:
				a.visible = false
			continue
		var t: Vector2 = free_spots.pop_front()
		c["spot"] = t
		var off := Vector2(cos(i * 2.4), sin(i * 2.4)) * 0.95
		var q := t + off
		a.position = Vector3(q.x, _walk_y(q), q.y)
		a.face(Vector3(-off.x, 0, -off.y))
		a.visible = true

var _chatters_sat := false

## somewhere nobody would see a person appear or go: beyond the distance people are drawn
## at, or well behind the car (and its camera)
func _unseen(p: Vector2) -> bool:
	var to := p - _pos
	var d := to.length()
	return d > PEOPLE_SEEN + 4.0 or (d > 18.0 and to.dot(_fwd()) < -0.35 * d)

func _people_tick(dt: float) -> void:
	_people_t -= dt
	if _people_t <= 0.0:
		_people_t = 1.5
		_seat_chatters()
		for c: Dictionary in _chatters:
			var ca: Actor3D = c["actor"]
			_people_awake(ca, Vector2(ca.position.x, ca.position.z))
	# one walker a tick is found a new place (a search along the pavements): several at once
	# when the car had driven on was a stutter
	var placed := false
	for w: Dictionary in _walkers:
		var a: Actor3D = w["actor"]
		var line: PackedVector2Array = w["line"]
		if line.size() < 2:   # found no place last time: look again now and then
			w["retry"] = float(w.get("retry", 0.0)) - dt
			if float(w["retry"]) <= 0.0 and not placed:
				w["retry"] = 2.0
				placed = true
				_place_walker(w, false)
			continue
		var cum: PackedFloat32Array = w["cum"]
		var total := cum[cum.size() - 1]
		var s: float = w["s"] + float(w["dir"]) * float(w["speed"]) * dt
		if s < 0.0 or s > total:   # the end of the block: turn back
			w["dir"] = -float(w["dir"])
			s = clampf(s, 0.0, total)
		w["s"] = s
		var p := _along(line, cum, s)
		var ahead := _along(line, cum, clampf(s + float(w["dir"]) * 0.5, 0.0, total)) - p
		# a car coming at them on the pavement: step aside, towards the buildings
		var to_car := _pos - p
		var dodge: float = w["dodge"]
		if to_car.length() < 6.0 and absf(_v) > 1.0:
			dodge = minf(dodge + dt * 1.4, 1.1)   # a step aside, not a leap
		else:
			dodge = maxf(dodge - dt * 0.5, 0.0)
		w["dodge"] = dodge
		if dodge > 0.0 and ahead != Vector2.ZERO:
			var side := Vector2(-ahead.y, ahead.x).normalized()
			if side.dot(to_car) > 0.0:
				side = -side
			p += side * dodge
		a.position = Vector3(p.x, _h(p) + _pave_top(), p.y)   # (their line is on the pavement)
		if ahead != Vector2.ZERO:
			# turning as people do, over a moment: at the end of a block they turned back on
			# the spot in one frame, and at every bend of the pavement line they snapped
			var want := atan2(ahead.y, ahead.x)
			var yaw: float = w.get("yaw", want)
			yaw = lerp_angle(yaw, want, 1.0 - exp(-dt * 5.0))
			w["yaw"] = yaw
			a.face(Vector3(cos(yaw), 0, sin(yaw)))
		_people_awake(a, p)
		if p.distance_to(_pos) > PEOPLE_RANGE and not placed:
			placed = true
			_place_walker(w, false)

## ---- what people look like ---------------------------------------------------------------------
## The kit's people (Quaternius, CC0) are cartoons: big heads and hands, one skin of dark
## grey with white cartoon eyes, the same clothes. Made more like people: a grown-up's
## proportions scaled on the skeleton (PART_SIZES), the face a deeper shade of the skin, and
## skin, hair, shirt and trousers each picked from a natural range mixed from the palette, so
## no two in a street are dressed alike.

## scales bones after the animation has posed them, every frame (the animation's pose puts
## every bone's scale back, so setting it once does not hold)
class PartSizes extends SkeletonModifier3D:
	var bones := {}   ## bone index -> scale

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for i: int in bones:
			sk.set_bone_pose_scale(i, bones[i])

func _people_looks() -> Dictionary:
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	var alt := Palette.col("bg_alt")
	var wn := Palette.col("warn")
	var pl := Palette.col("player")
	var hz := Palette.col("hazard")
	var fr := Palette.col("friend")
	var skin := _natural(ink.lerp(wn, 0.38).lerp(hz, 0.14), 0.7)
	return {
		"skin": [skin, skin.darkened(0.15), skin.darkened(0.32), skin.darkened(0.5), skin.darkened(0.64)],
		# mostly dark and brown, as in any street; a fair one, a red one, a grey one
		"hair": [bg.lerp(alt, 0.25), bg.lerp(alt, 0.45), _natural(wn.lerp(bg, 0.8), 0.5), _natural(wn.lerp(bg, 0.7), 0.5),
			_natural(wn.lerp(bg, 0.58), 0.5), _natural(wn.lerp(bg, 0.3), 0.45), _natural(hz.lerp(wn, 0.4).lerp(bg, 0.55), 0.55),
			_natural(ink.lerp(alt, 0.45), 0.15)],
		"shirt": [ink.lerp(alt, 0.08), _natural(pl.lerp(ink, 0.35), 0.5), _natural(hz.lerp(bg, 0.3), 0.5),
			_natural(fr.lerp(bg, 0.45), 0.5), _natural(wn.lerp(ink, 0.35), 0.45), ink.lerp(alt, 0.5),
			bg.lerp(alt, 0.5), _natural(pl.lerp(bg, 0.6), 0.6), _natural(Palette.col("accent").lerp(ink, 0.3), 0.45)],
		"pants": [_natural(pl.lerp(bg, 0.55), 0.45), bg.lerp(alt, 0.5), ink.lerp(alt, 0.55), _natural(wn.lerp(alt, 0.5), 0.4),
			_natural(pl.lerp(bg, 0.7), 0.5)],
		"belt": [bg.lerp(alt, 0.3), _natural(wn.lerp(bg, 0.65), 0.45)],
	}

## A grown-up's proportions on the kit's chunky figures: a smaller head, hands and feet,
## longer thighs and a longer middle. Scales on the bones, kept by PartSizes after the
## animation has posed them.
const PART_SIZES := {
	"Head": Vector3(0.64, 0.64, 0.64),
	"Fist.L": Vector3(0.7, 0.7, 0.7), "Fist.R": Vector3(0.7, 0.7, 0.7),
	"Foot.L": Vector3(0.85, 0.85, 0.85), "Foot.R": Vector3(0.85, 0.85, 0.85),
	"UpperLeg.L": Vector3(1.0, 1.16, 1.0), "UpperLeg.R": Vector3(1.0, 1.16, 1.0),
	"Abdomen": Vector3(1.0, 1.06, 1.0),
}

func _humanize(a: Actor3D, seed: int) -> void:
	if a == null or a.model == null:
		return
	var sks := a.model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		var sk: Skeleton3D = sks[0]
		var sizes := PartSizes.new()
		for bone: String in PART_SIZES:
			var i := sk.find_bone(bone)
			if i >= 0:
				sizes.bones[i] = PART_SIZES[bone]
		sk.add_child(sizes)
		a.model.scale *= 1.06   # back to the height asked for: the smaller head took some off
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var looks := _people_looks()
	var pick := {}
	for k: String in looks:
		pick[k] = looks[k][rng.randi() % (looks[k] as Array).size()]
	# the face (the big white eyes) in a deeper shade of the same skin: features, not a cartoon's eyes
	pick["face"] = (pick["skin"] as Color).darkened(0.42)
	for mi: MeshInstance3D in a.model.find_children("*", "MeshInstance3D", true, false):
		for si in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(si) as StandardMaterial3D
			var role := String(m.resource_name).to_lower() if m != null else ""
			if not pick.has(role):
				continue
			var nm := m.duplicate() as StandardMaterial3D
			nm.albedo_color = pick[role]
			nm.roughness = 0.85
			mi.set_surface_override_material(si, nm)

## ---- people crossing at the zebras -----------------------------------------------------------
## A few people at the zebra crossings near the car. They wait at the kerb, and cross once
## whatever is coming can still stop for them; traffic and autodrive stop for anyone on a
## crossing. Drive at someone crossing and they hurry back to the kerb -- and the game says
## so, the way it does a red light.
const CROSSERS := 5
const CROSS_NEAR := 110.0
var _crossers: Array = []            ## {actor, ni, a, b, s, state, t, speed}
var _zebras_on: Array = []           ## crossings with someone on them now: [middle, half width + 1, across]
var _zebra_t := 0.0
var _zebra_warned := -1              ## the crossing the player was last told off at

func _spawn_crossers() -> void:
	for i in range(CROSSERS):
		var a := Actor3D.new()
		world.add_child(a)
		a.set_character(PEOPLE[(i + 3) % PEOPLE.size()], _people_rng.randf_range(1.6, 1.86))
		_humanize(a, hash(a.get_instance_id()))
		_people_lod(a)
		a.visible = false
		_crossers.append({"actor": a, "ni": -1, "a": Vector2.ZERO, "b": Vector2.ZERO, "s": 0.0,
			"state": "off", "t": 0.0, "speed": _people_rng.randf_range(1.15, 1.5)})

## the zebra at node ni: [middle, across (unit, kerb to kerb), half the road's width, the
## road's way, the road]
func _zebra_geom(ni: int) -> Array:
	var c := _nodes[ni]
	for e: Vector2i in _node_roads[ni]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"] or HIGHWAYS.has(r["k"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var d := (pts[mini(e.y + 1, pts.size() - 1)] - pts[maxi(e.y - 1, 0)]).normalized()
		return [c, Vector2(-d.y, d.x), float(r["w"]) * 0.5, d, e.x]
	return []

## Where a crossing's people wait and walk to: [one kerb, the other], each a step back on the
## pavement. On a divided road the zebra is painted on each half, but people cross the lot,
## outer kerb to outer kerb (waiting on the median they stood in the other carriageway).
## [] when either end is on another road's asphalt or in a building.
func _zebra_span(z: Array) -> Array:
	var mid: Vector2 = z[0]
	var across: Vector2 = z[1]
	var hw: float = z[2]
	var r: Dictionary = _roads[int(z[4])]
	var a := mid - across * (hw + 1.1)
	var b := mid + across * (hw + 1.1)
	if r.has("median"):
		var pair := _partner(mid, z[3], int(z[4]), hw, int(r["o"]))
		if not pair.is_empty():
			var left: Vector2 = pair[3]
			var far := ((pair[1] as Vector2) - mid).dot(left) + float(_roads[int(pair[0])]["w"]) * 0.5
			a = mid - left * (hw + 1.1)
			b = mid + left * (far + 1.1)
	for q: Vector2 in [a, b]:
		if not _off_road(q, 0.2) or _push_out(q, 0.4, false) != Vector2.ZERO:
			return []
	return [a, b]

## At a crossing by a junction with lights, people go by the walk light (see _build_walk_lights):
## they step out on the green man only, with time enough left on it -- they walked out in front
## of cars that had just got their green, and every car through the junction stopped in the
## middle of it for them. Anywhere else: always.
func _walk_light(cr: Dictionary, need: float) -> bool:
	var n: int = cr.get("sig", -1)
	if n < 0 or not _sig_set.has(n):
		return true
	var grp := _light_group(n, cr["sig_dir"])
	var step: Array = SIGNAL_CYCLE[_sig_phase]
	if not (step[grp] == "r" and step[3 - grp] == "g"):
		return false   # the red man
	# the green man, with time enough left on it to be most of the way over
	return float(step[0]) - _sig_t >= minf(need, 8.0) + 1.0

## nothing coming that could not stop before the crossing (middle `mid`, `hw` from it to
## either kerb), and nothing standing on it
func _safe_to_cross(mid: Vector2, hw: float) -> bool:
	var movers: Array = [[_pos, _fwd() * signf(_v), absf(_v)]]
	for c in _traffic.cars:
		if c.alive:
			movers.append([c.pos, Vector2(sin(c.yaw), cos(c.yaw)), c.v])
	for m: Array in movers:
		var p: Vector2 = m[0]
		var to: Vector2 = mid - p
		var d := to.length()
		if d < hw + 2.5:
			return false   # on it, or right at it
		var v: float = m[2]
		if d < 45.0 and v > 0.8 and (m[1] as Vector2).dot(to / d) > 0.5 and v * v / (2.0 * 3.0) + 7.0 > d:
			return false   # coming, and too close to stop
	return true

func _crossers_tick(dt: float) -> void:
	if _crossers.is_empty() or _crossing_nodes.is_empty():
		return
	_zebra_t -= dt
	if _zebra_t <= 0.0:
		_zebra_t = 1.2
		_send_crossers()
	_zebras_on = []
	for cr: Dictionary in _crossers:
		var a: Actor3D = cr["actor"]
		var state: String = cr["state"]
		if state == "off":
			continue
		var z: Array = _zebra_geom(int(cr["ni"]))
		var from: Vector2 = cr["a"]
		var to: Vector2 = cr["b"]
		var p: Vector2 = from.lerp(to, float(cr["s"]))
		match state:
			"wait":
				cr["t"] = float(cr["t"]) - dt
				if float(cr["t"]) <= 0.0 and _walk_light(cr, from.distance_to(to) / float(cr["speed"])) \
						and _safe_to_cross((from + to) * 0.5, from.distance_to(to) * 0.5 - 1.1):
					cr["state"] = "cross"
					a.play("Walk", true, float(cr["speed"]) / 1.35)
			"cross", "back":
				var w := from.distance_to(to)
				var sp: float = cr["speed"] * (2.4 if state == "back" else 1.0)
				cr["s"] = clampf(float(cr["s"]) + (sp if state == "cross" else -sp) * dt / maxf(w, 0.1), 0.0, 1.0)
				p = from.lerp(to, float(cr["s"]))
				_zebras_on.append([(from + to) * 0.5, from.distance_to(to) * 0.5 - 0.1, (to - from).normalized()])
				# the player bearing down on them: back to the kerb they came from
				if state == "cross" and p.distance_to(_pos) < 5.5 and absf(_v) > 2.0 and (p - _pos).dot(_fwd() * signf(_v)) > 0.0:
					cr["state"] = "back"
					a.play("Run", true, 1.2)
					if _zebra_warned != int(cr["ni"]):
						_zebra_warned = int(cr["ni"])
						_show_banner("stop for people on the crossing", 1.8)
						Probe.event("zebra", {"street": _on_name, "kmh": int(absf(_v) * 3.6), "auto": _auto})
				if state == "cross" and float(cr["s"]) >= 1.0 or state == "back" and float(cr["s"]) <= 0.0:
					# over (or back): off along the pavement, gone once out of the way
					cr["state"] = "away"
					cr["t"] = 12.0
					a.play("Walk", true, float(cr["speed"]) / 1.35)
					_away_from(cr, z)
			"away":
				cr["t"] = float(cr["t"]) - dt
				var end: Vector2 = to if float(cr["s"]) >= 1.0 else from
				var dir: Vector2 = cr["away"]
				var far: float = cr["away_len"]
				var went := float(cr.get("a_off", 0.0))
				cr["a_off"] = went + float(cr["speed"]) * dt
				if went < far and float(cr["a_off"]) >= far:
					a.play("Idle", true, _people_rng.randf_range(0.8, 1.1))   # as far as the pavement goes
				var off := minf(float(cr["a_off"]), far)
				p = end + (cr["out"] as Vector2) * minf(off, 0.9) + dir * off
				if _unseen(p) and (float(cr["t"]) <= 0.0 or p.distance_to(_pos) > CROSS_NEAR):
					cr["state"] = "off"   # (gone only where nobody sees them go)
					cr["ni"] = -1
					a.visible = false
					continue
		# the kerb's step up or down over a moment, not in one frame
		var fy := _walk_y(p)
		if cr.has("y"):
			fy = lerpf(float(cr["y"]), fy, 1.0 - exp(-dt * 10.0))
		cr["y"] = fy
		a.position = Vector3(p.x, fy, p.y)
		var look: Vector2 = (to - from) if state in ["wait", "cross"] else ((from - to) if state == "back" else cr.get("away", to - from))
		if state == "away" and float(cr["a_off"]) >= float(cr["away_len"]):
			look = cr["out"]
		if look != Vector2.ZERO:
			a.face(Vector3(look.x, 0, look.y))
		_people_awake(a, p)

## Over the road: off along the pavement, a step back from the kerb, whichever way it runs
## further before meeting another road's asphalt or a building (up to 15 m), and there wait.
func _away_from(cr: Dictionary, z: Array) -> void:
	var from: Vector2 = cr["a"]
	var to: Vector2 = cr["b"]
	var end: Vector2 = to if float(cr["s"]) >= 1.0 else from
	var out := (end - (from + to) * 0.5).normalized()
	var way: Vector2 = z[3]
	var best := -1.0
	for sgn: float in ([1.0, -1.0] if _people_rng.randf() < 0.5 else [-1.0, 1.0]):
		var dir := way * sgn
		var go := 0.0
		while go < 15.0:
			var q := end + out * 0.9 + dir * (go + 1.5)
			if not _off_road(q, 0.3) or _push_out(q, 0.35, false) != Vector2.ZERO:
				break
			go += 1.5
		if go > best:
			best = go
			cr["away"] = dir
	cr["away_len"] = best
	cr["out"] = out
	cr["a_off"] = 0.0

## idle crossers to the zebras near the car (ahead of it rather than behind, and where
## there is life about), one each
func _send_crossers() -> void:
	var busy := {}
	for cr: Dictionary in _crossers:
		if cr["state"] != "off":
			busy[int(cr["ni"])] = true
	var look := _fwd()
	var near: Array = []
	for ni: int in _crossing_nodes:
		var to := _nodes[ni] - _pos
		var d := to.length()
		# only where they would not be seen to appear (beyond the distance people are drawn
		# at, or behind): popping up at the kerb in front of the car read as a teleport
		if d <= CROSS_NEAR + 40.0 and _unseen(_nodes[ni]) and not (d > 45.0 and to.dot(look) < 0.0):
			near.append(ni)
	for cr: Dictionary in _crossers:
		if cr["state"] != "off":
			continue
		var pick := -1
		for _try in range(8):
			if near.is_empty():
				break
			var ni: int = near[_people_rng.randi() % near.size()]
			if busy.has(ni) or _people_rng.randf() > _liveliness(_nodes[ni]) + 0.35 or _zebra_geom(ni).is_empty():
				continue
			pick = ni
			break
		if pick < 0:
			return
		busy[pick] = true
		var z := _zebra_geom(pick)
		var along: Vector2 = (z[3] as Vector2) * _people_rng.randf_range(-0.8, 0.8)
		var span := _zebra_span(z)
		if span.is_empty():
			continue   # (next time, another crossing)
		var flip := _people_rng.randf() < 0.5
		cr["ni"] = pick
		cr["a"] = (span[1] if flip else span[0]) + along
		cr["b"] = (span[0] if flip else span[1]) + along
		cr["s"] = 0.0
		cr["a_off"] = 0.0
		cr["state"] = "wait"
		cr["t"] = _people_rng.randf_range(1.0, 5.0)
		cr.erase("y")
		# a crossing at a junction with lights: they go with the lights
		cr["sig"] = -1
		var mid := ((cr["a"] as Vector2) + (cr["b"] as Vector2)) * 0.5
		var sd := 30.0
		for n: int in _near(_sig_hash, mid, 30.0, SEG_CELL):
			if _nodes[n].distance_to(mid) < sd:
				sd = _nodes[n].distance_to(mid)
				cr["sig"] = n
		cr["sig_dir"] = z[3]
		var a: Actor3D = cr["actor"]
		a.visible = true
		a.play("Idle", true, _people_rng.randf_range(0.8, 1.1))

## the people (walkers, those at crossings) within r of p
func _people_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	for w: Dictionary in _walkers:
		var a: Actor3D = w["actor"]
		if a.visible and Vector2(a.position.x, a.position.z).distance_to(p) < r:
			out.append(a.position)
	for cr: Dictionary in _crossers:
		var a: Actor3D = cr["actor"]
		if a.visible and Vector2(a.position.x, a.position.z).distance_to(p) < r:
			out.append(a.position)
	return out

## autodrive: anyone standing on the lane ahead -- crossing, hurrying back, stepping aside
## off a pavement -- stopped for, whatever the crossing rules say (the speed allowed, or INF)
func _ap_people_v() -> float:
	if _ap_pts.size() < 2:
		return INF
	var people: Array = []
	for cr: Dictionary in _crossers:
		if cr["state"] in ["cross", "back"]:
			people.append((cr["actor"] as Actor3D).position)
	for w: Dictionary in _walkers:
		var a: Actor3D = w["actor"]
		if a.visible:
			people.append(a.position)
	var fwd := _fwd()
	var best := INF
	for p3: Vector3 in people:
		var p := Vector2(p3.x, p3.z)
		if p.distance_squared_to(_pos) > 1100.0 or (p - _pos).dot(fwd) < 0.0:
			continue
		var base := -_ap_pts[0].distance_to(Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[0], _ap_pts[1]))
		for j in range(_ap_pts.size() - 1):
			if base > 32.0:
				break
			var a := _ap_pts[j]
			var b := _ap_pts[j + 1]
			var cp := Geometry2D.get_closest_point_to_segment(p, a, b)
			if cp.distance_to(p) < 1.7:
				var stop := base + a.distance_to(cp) - CAR_OFF - 2.8
				best = minf(best, sqrt(2.0 * 3.5 * maxf(stop - 0.3, 0.0)))
				break
			base += a.distance_to(b)
	return best

## autodrive: stop short of a crossing with someone on it (the speed allowed now, or INF)
func _ap_zebra_v() -> float:
	if _zebras_on.is_empty() or _ap_pts.size() < 2:
		return INF
	var best := INF
	for z: Array in _zebras_on:
		var mid: Vector2 = z[0]
		if mid.distance_to(_pos) > 70.0:
			continue
		var base := -_ap_pts[0].distance_to(Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[0], _ap_pts[1]))
		for j in range(_ap_pts.size() - 1):
			if base > 70.0:
				break
			var a := _ap_pts[j]
			var b := _ap_pts[j + 1]
			var cp := Geometry2D.get_closest_point_to_segment(mid, a, b)
			if cp.distance_to(mid) < float(z[1]):
				var stop := base + a.distance_to(cp) - 4.5 - CAR_OFF
				if stop > -1.5:
					best = minf(best, sqrt(2.0 * 2.6 * maxf(stop - 0.3, 0.0)))
				break
			base += a.distance_to(b)
	return best

## A lane point for centre-line point p (road direction d): `lane` to the right, or less,
## or the middle, or a little to the left, whichever first leaves the car room (nose, middle
## and tail). OSM rarely says how wide a street is; the guess is 8 m, and in the old narrow
## streets the "right-hand lane" of that guess ran into the buildings and the parked cars.
func _clear_lane(p: Vector2, d: Vector2, lane: float) -> Vector2:
	var right := Vector2(-d.y, d.x)
	for off: float in [lane, lane * 0.6, lane * 0.25, 0.0, -0.7, 0.7]:
		var q := p + right * off
		if _push_out(q, 1.2, true, false) == Vector2.ZERO and _push_out(q + d * 1.4, 1.15, true, false) == Vector2.ZERO \
				and _push_out(q - d * 1.4, 1.15, true, false) == Vector2.ZERO:
			return q
	return p + right * lane

## ---- collisions: the car's two circles against building outlines and posts -------------

func _collide() -> void:
	var fwd := _fwd()
	var total := Vector2.ZERO
	var at_front := Vector2.ZERO
	var at_back := Vector2.ZERO
	# a few passes: out of a wall can be into a tree, and one push each left the car
	# jittering between the two, stuck
	for _pass in range(3):
		var moved := false
		for off: float in [CAR_OFF, -CAR_OFF]:
			var p := _push_out(_pos + fwd * off, CAR_R, true)
			p += _steep_push(_pos + fwd * off + p, CAR_R)
			if p != Vector2.ZERO:
				total += p
				_pos += p
				moved = true
				if off > 0.0:
					at_front += p
				else:
					at_back += p
		if not moved:
			break
	if total == Vector2.ZERO:
		return
	_touch_t = 0.5
	var n := total.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var vel := fwd * _v + right * _v_lat
	var vn := vel.dot(n)
	if vn < 0.0:
		var impact := -vn
		# a real knock bounces a little; leaning on a wall at walking pace does not (the
		# bounce back and push in again was a judder that held the car there)
		vel -= n * vn * (1.0 + (BOUNCE if impact > 2.0 else 0.0))
		# a knock off one end turns the car about the other, as a real one does -- a little:
		# it used to spin it like a top and hop it off the ground, more pinball than crash
		if impact > 2.0:
			var lever := (at_front - at_back).dot(right) / maxf(at_front.length() + at_back.length(), 0.001)
			_spin = clampf(_spin + lever * impact * 0.07, -1.4, 1.4)
		# scraping along it: the harder it hit, the more speed the scrape takes, so a
		# glancing touch slides on and a head-on stops. (It used to lose 6% every tick in
		# contact, which glued the car to anything it touched.)
		var along := vel - n * vel.dot(n)
		vel -= along.limit_length(impact * WALL_GRIP)
		_crash(impact)
		if _last_hit.begins_with("car "):
			_traffic.bumped(int(_last_hit.substr(4)))
	_v = vel.dot(fwd)
	_v_lat = clampf(vel.dot(right), -7.0, 7.0)

func _crash(speed: float) -> void:
	if speed < 1.2 or _crash_cool > 0.0:
		return
	_crash_cool = 0.4
	if _auto and (_last_hit.begins_with("building") or _last_hit.begins_with("wall") or _last_hit.begins_with("post")):
		_ap_bonks += 1.0
	# a jolt of the camera, not a freeze-frame: the car stops dead and the view with it
	if speed > 9.0:
		shake3d(minf(4.0, speed * 0.25))
		Audio.play("impact_metal")
	elif speed > 4.0:
		shake3d(speed * 0.25)
		Audio.play("impact_punch")
	else:
		shake3d(1.0)
		Audio.play("impact_soft", 0.1, -6.0)
	Probe.event("crash", {"kmh": int(speed * 3.6), "hit": _last_hit, "at": Vector2i(_pos),
		"street": _on_name, "auto": _auto})

## Ground too steep to climb is a wall (STEEP): a circle whose uphill edge is on it is moved
## back downhill to where the ground is gentle enough. A road is always drivable, however
## steep. Nothing to do in a city without such ground.
func _steep_push(c: Vector2, r: float) -> Vector2:
	if not _steep:
		return Vector2.ZERO
	var g := _grade(c)
	if g == Vector2.ZERO:
		return Vector2.ZERO
	var up := g.normalized()
	var edge := c + up * r
	if _grade(edge).length() < STEEP:
		return Vector2.ZERO
	var on := _nearest_seg(edge, 14.0, true)
	if not on.is_empty() and float(on["edge"]) < 0.0:
		return Vector2.ZERO
	var s := 0.0
	while s < 4.0:
		s += 0.25
		if _grade(edge - up * s).length() < STEEP:
			break
	_last_hit = "steep ground"
	return -up * s

## which way and how steeply the ground rises at p (metres up per metre across)
func _grade(p: Vector2) -> Vector2:
	return Vector2(_h(p + Vector2(1, 0)) - _h(p - Vector2(1, 0)), _h(p + Vector2(0, 1)) - _h(p - Vector2(0, 1))) * 0.5

## true when some cell of the height grid is steeper than STEEP
func _any_steep() -> bool:
	var lim := STEEP * _hstep
	for j in range(_hnz - 1):
		for i in range(_hnx - 1):
			var r := j * _hnx + i
			if absf(_hgrid[r + 1] - _hgrid[r]) > lim or absf(_hgrid[r + _hnx] - _hgrid[r]) > lim:
				return true
	return false

## how far to move a circle so it overlaps nothing solid
func _push_out(c: Vector2, r: float, posts: bool, cars := true) -> Vector2:
	var push := Vector2.ZERO
	for i: int in _near(_bld_hash, c, r, BLD_CELL):
		if _bld_solid[i] == 0:
			continue
		var box: Rect2 = _bld_box[i]
		if not box.grow(r).has_point(c + push):
			continue
		var p := _poly_push(_blds[i], c + push, r)
		if p != Vector2.ZERO:
			push += p
			_last_hit = "building %d" % i
	if posts:
		# fences, railings, hedges, garden walls, a shelter's back: thin walls, as segments
		for i: int in _near(_wall_hash, c, r + 0.5, BLD_CELL):
			var q := c + push
			var cp := Geometry2D.get_closest_point_to_segment(q, _walls[i * 2], _walls[i * 2 + 1])
			var d := q - cp
			var need := r + _wall_r[i]
			if d.length_squared() < need * need:
				var nrm := d.normalized() if d.length() > 0.001 else (_walls[i * 2 + 1] - _walls[i * 2]).orthogonal().normalized()
				push += nrm * (need - d.length())
				_last_hit = "wall %d" % i
		for i: int in _near(_post_hash, c, r, BLD_CELL):
			var d := (c + push) - _posts[i]
			var need := r + _post_r[i]
			if d.length() < need:
				push += d.normalized() * (need - d.length()) if d.length() > 0.001 else Vector2(need, 0)
				_last_hit = "post %d" % i
		if _traffic != null and cars:
			var tp := _traffic.push(c + push, r)
			if tp != Vector2.ZERO:
				push += tp
				_last_hit = "car %d" % _traffic.hit_index
	return push

func _poly_push(poly: PackedVector2Array, c: Vector2, r: float) -> Vector2:
	var best := INF
	var q := c
	var n := poly.size()
	for i in range(n):
		var p := Geometry2D.get_closest_point_to_segment(c, poly[i], poly[(i + 1) % n])
		var d := c.distance_squared_to(p)
		if d < best:
			best = d
			q = p
	best = sqrt(best)
	if Geometry2D.is_point_in_polygon(c, poly):
		var out := q - c
		return out + out.normalized() * r if best > 0.001 else Vector2(r, 0)
	if best < r:
		return (c - q) / maxf(best, 0.001) * (r - best)
	return Vector2.ZERO

## ---- spatial hashes -------------------------------------------------------------------------

func _cell(p: Vector2, size: float) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.y / size))

func _hash_add(h: Dictionary, box: Rect2, size: float, item: int) -> void:
	var a := _cell(box.position, size)
	var b := _cell(box.end, size)
	for cx in range(a.x, b.x + 1):
		for cz in range(a.y, b.y + 1):
			var key := Vector2i(cx, cz)
			if h.has(key):
				(h[key] as Array).append(item)
			else:
				h[key] = [item]

## every item whose cells touch the square of radius r round p, once each
func _near(h: Dictionary, p: Vector2, r: float, size: float) -> Array:
	var a := _cell(p - Vector2(r, r), size)
	var b := _cell(p + Vector2(r, r), size)
	if a == b:
		return h.get(a, [])
	var seen := {}
	for cx in range(a.x, b.x + 1):
		for cz in range(a.y, b.y + 1):
			for i: int in h.get(Vector2i(cx, cz), []):
				seen[i] = true
	return seen.keys()

## the closest road segment to p within max_d: {road, seg, q (closest point), edge (metres
## past the asphalt's edge, negative when on it)}; {} when there is none
func _nearest_seg(p: Vector2, max_d: float, drivable: bool, public := false) -> Dictionary:
	var best := {}
	var bd := INF
	for code: int in _near(_seg_hash, p, max_d, SEG_CELL):
		var ri := code / 4096
		var sj := code % 4096
		var r: Dictionary = _roads[ri]
		if drivable and not r["drive"]:
			continue
		if public and r["pv"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var q := Geometry2D.get_closest_point_to_segment(p, pts[sj], pts[sj + 1])
		var edge := p.distance_to(q) - float(r["w"]) * 0.5
		if edge < bd:
			bd = edge
			best = {"road": ri, "seg": sj, "q": q, "edge": edge}
	return best

func _hash_i(v: Vector2) -> int:
	return absi((int(v.x * 7.0) * 73856093) ^ (int(v.y * 7.0) * 19349663))

func _in_city(p: Vector2) -> bool:
	if _boundary.is_empty():
		return true
	for ring: PackedVector2Array in _boundary:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false

## ---- camera: a chase cam that swings wide on turns and never sits inside a building -----

## `p` and `yaw`: where the car is drawn this frame
## A camera for looking at the city in screenshots (tools/shots.sh), never in play:
## STREETS_CAM="ahead,left,up,turn,tilt" stands it that many metres ahead of the car, to its
## left and above the ground, turned that many degrees left of the car's heading and tilted
## that many up; a sixth value of 1 makes it night. Unset (always, outside a test) it does
## nothing.
var _dev_cam := PackedFloat32Array()

func _camera(dt: float, p: Vector2, yaw: float) -> void:
	if _dev_cam.size() == 5:
		var fw := Vector2(cos(yaw), sin(yaw))
		var lf := Vector2(sin(yaw), -cos(yaw))
		var at2 := p + fw * _dev_cam[0] + lf * _dev_cam[1]
		var dy := yaw - deg_to_rad(_dev_cam[3])
		var tl := deg_to_rad(_dev_cam[4])
		var eye := Vector3(at2.x, _h(at2) + _dev_cam[2], at2.y)
		look_from(eye, eye + Vector3(cos(dy) * cos(tl), sin(tl), sin(dy) * cos(tl)))
		cam.fov = 70.0
		return
	if _cockpit:
		_seat_camera(dt, yaw)
		return
	_cam_yaw = lerp_angle(_cam_yaw, yaw, 1.0 - exp(-dt * 3.0))
	var back := Vector2(cos(_cam_yaw), sin(_cam_yaw))
	var spd := clampf(absf(_v) / 30.0, 0.0, 1.0)
	var want := lerpf(6.3, 7.8, spd)
	var clear := _clear_behind(p, -back, want)
	_cam_dist = clear if clear < _cam_dist else lerpf(_cam_dist, clear, 1.0 - exp(-dt * 1.5))
	var d := _cam_dist
	var gy := _h(p) + maxf(_view_y - _h(p), 0.0) * 0.8   # up with the car when it flies
	var eye2 := p - back * d
	var eye := Vector3(eye2.x, maxf(gy + 2.0 + d * 0.14, _h(eye2) + 1.4), eye2.y)
	var ahead := p + back * 4.0
	var at := Vector3(ahead.x, lerpf(gy, _h(ahead), 0.5) + 1.0, ahead.y)
	look_from(eye, at)
	cam.fov = lerpf(64.0, 74.0, spd)

## from the driver's seat: with the body as it pitches and leans, the head pushed back a
## little as the car pulls away, the eyes leading into a turn
func _seat_camera(dt: float, yaw: float) -> void:
	_cam_yaw = yaw
	_look_turn = lerpf(_look_turn, clampf(_steer * 0.55, -0.3, 0.3), 1.0 - exp(-dt * 3.0))
	var xf := _body.global_transform
	var head := SEAT + Vector3(0, 0, clampf(-_a_long * 0.004, -0.04, 0.04))
	var eye := xf * head
	var ahead := Vector3(-sin(_look_turn), -0.06, cos(_look_turn)) * 12.0   # +X is the car's left
	look_from(eye, xf * (head + ahead))
	cam.fov = lerpf(72.0, 78.0, clampf(absf(_v) / 30.0, 0.0, 1.0))
	if _wheel_node != null:
		_wheel_node.rotation.z = _steer * 15.0 * 0.5
	# the needles: 0-200 km/h and 0-7000 rpm round 4.4 radians, from the bottom left
	if _dial_speed != null:
		# (the dial's +X is the driver's left: from -2.2, bottom left as the driver sees it,
		# clockwise over the top)
		_dial_speed.basis = Basis(Vector3.RIGHT, 0.32) * Basis(Vector3.BACK, -2.2 + 4.4 * clampf(absf(_v) * 3.6 / 200.0, 0.0, 1.0))
		_dial_rpm.basis = Basis(Vector3.RIGHT, 0.32) * Basis(Vector3.BACK, -2.2 + 4.4 * clampf(_rpm / 7000.0, 0.0, 1.0))

func _clear_behind(from: Vector2, dir: Vector2, want: float) -> float:
	var s := 1.0
	while s <= want + 0.6:
		var p := from + dir * s
		for i: int in _near(_bld_hash, p, 0.1, BLD_CELL):
			var box: Rect2 = _bld_box[i]
			if box.has_point(p) and Geometry2D.is_point_in_polygon(p, _blds[i]):
				return maxf(2.2, s - 0.8)
		s += 0.5
	return want

## ---- autodrive: follow the road graph in the right-hand lane, preferring new streets ----

func _set_auto(on: bool) -> void:
	_auto = on
	_cross = {}
	_ap_queue = []
	_ap_pts = PackedVector2Array()
	_ap_v = PackedFloat32Array()
	_ap_lim = PackedFloat32Array()
	_ap_stuck = 0.0
	_ap_back = 0.0
	_ap_turn = 0.0
	if on:
		_gear = 1
	Probe.event("autodrive", {"on": on})
	_show_banner("autodrive" if on else "you drive", 1.2)

## the lower of two speeds, noting what the new one is for when it is the lower
func _held(cur: float, v: float, why: String) -> float:
	if v < cur:
		_ap_why = why
		return v
	return cur

func _autodrive(dt: float) -> Array:
	# into the walls again and again (a few in quick succession): lost, back to the street
	_ap_bonks = maxf(0.0, _ap_bonks - dt / 10.0)
	if _ap_bonks >= 3.0 and _ap_rescue():
		_ap_pts = PackedVector2Array()
	if _ap_back > 0.0:     # stuck against something: back off, then plan again
		_ap_back -= dt
		_gear = -1
		# looking over the shoulder: anything behind (a car, a post, a wall, someone) and
		# it stops backing -- it used to reverse its 1.4 s blind, into the car behind
		var tail := _pos - _fwd() * (CAR_OFF + 0.7 + absf(_v) * 0.4)
		var behind := _push_out(tail, CAR_R, true, true) != Vector2.ZERO
		behind = behind or not _people_near(tail, 2.5).is_empty()
		if behind or _ap_back <= 0.0:
			_ap_back = 0.0
			_gear = 1
			_ap_pts = PackedVector2Array()
			return [0.0, 1.0, 0.0]
		return [0.7, 0.0, -signf(_steer) * MAX_STEER * 0.6]
	if _ap_pts.size() < 2 or _ap_off_route() > 25.0:
		_ap_plan()
		if _ap_pts.size() < 2:
			return [0.0, 1.0, 0.0]
	# forget what is behind: we are on whichever of the next stretches is closest. Looking
	# at only the current one lost track after a sharp corner and sent the car back round
	# to a point it had already passed.
	var at := _ap_nearest_seg()
	for _k in range(at):
		_ap_pts.remove_at(0)
		_ap_v.remove_at(0)
		_ap_lim.remove_at(0)
	_cross_tick()
	var legs := 0
	while _ap_len() < 160.0:
		# one leg a tick while there is plenty ahead: planning one is a few milliseconds (more
		# in a browser), and several in the same tick showed as a stutter
		if legs > 0 and _ap_len() > 90.0:
			break
		legs += 1
		if not _ap_next():
			# nowhere further (and no crossing waiting on a choice): stop at the end of the
			# plan instead of running on past it, off the road and into whatever is there
			if _cross.is_empty() and _ap_v.size() > 0:
				_ap_v[_ap_v.size() - 1] = 0.0
			break
	# at a dead end's turning point, stopped: on to the lane back, which faces the other
	# way, so it turns round on the spot just below
	while _ap_pts.size() > 2 and _ap_v[1] == 0.0 and absf(_v) < 1.0 and _pos.distance_to(_ap_pts[1]) < 5.0:
		_ap_pts.remove_at(0)
		_ap_v.remove_at(0)
		_ap_lim.remove_at(0)
	# facing well away from the lane it must take (handed over pointing the wrong way up a
	# one-way street, or across it): turn round on the spot first. Steering full lock at
	# it from a standstill put the nose into the kerb and the wall behind it, again and again.
	var lane_dir := (_ap_pts[1] - _ap_pts[0]).normalized() if _ap_pts.size() > 1 else _fwd()
	if _ap_turn <= 0.0 and absf(_v) >= 2.0 and _fwd().dot(lane_dir) < -0.2:
		# the lane it must take is behind it and it is still rolling (it ran past a dead
		# end's turning point at 18 km/h): brake to a stop in a straight line, then turn.
		# Steering for a lane behind at speed swung it wide, off the end, onto the footpath.
		_ap_why = "turning"
		return [0.0, 1.0, 0.0]
	if _ap_turn <= 0.0 and absf(_v) < 2.0 and _fwd().dot(lane_dir) < -0.2:
		_ap_turn = 3.0
		_show_banner("turning round", 1.2)
	if _ap_turn > 0.0:
		_ap_turn -= dt
		var want := lane_dir.angle()
		var diff := angle_difference(_yaw, want)
		_yaw = wrapf(_yaw + clampf(diff, -1.7 * dt, 1.7 * dt), -PI, PI)
		_yaw_rate = 0.0
		_v = 0.0
		_v_lat = 0.0
		if absf(diff) < 0.12:
			_ap_turn = 0.0
		return [0.0, 1.0, 0.0]
	# pure pursuit on a point ahead of the rear axle
	var fwd := _fwd()
	var rear := _pos - fwd * WHEELBASE * 0.5
	var look := clampf(3.5 + absf(_v) * 0.5, 5.0, 16.0)
	var tgt := _ap_point_ahead(look)
	var to := tgt - rear
	var alpha := fwd.angle_to(to)
	var steer := clampf(atan(2.0 * WHEELBASE * sin(alpha) / maxf(to.length(), 1.0)), -MAX_STEER, MAX_STEER)
	# a safety net: anything solid near where the nose will be in a moment (a parked car's
	# corner, a building on a bend) steers it away, and slows it if it is dead ahead. The
	# planned lane is clear; this catches the car drifting off it.
	var nose := _pos + fwd * (CAR_OFF + 0.5 + absf(_v) * 0.3)
	var shove := _push_out(nose, 1.15, true, false)
	var ahead_blocked := false
	if shove != Vector2.ZERO:
		var side := Vector2(-fwd.y, fwd.x)
		steer = clampf(steer + clampf(shove.dot(side) * 0.45, -0.3, 0.3), -MAX_STEER, MAX_STEER)
		ahead_blocked = shove.normalized().dot(fwd) < -0.6
	# keep the limit, and slow for the corners ahead: at most the speed from which each
	# one can still be braked down to in time
	var vt: float = _ap_lim[1]
	_ap_why = "limit"
	var dist := 0.0
	var p := _pos
	for i in range(1, _ap_pts.size()):
		dist += p.distance_to(_ap_pts[i])
		p = _ap_pts[i]
		if dist > 90.0:
			break
		# (a stop -- a dead end's turning point -- a metre and a half short, so the car is
		# standing when it gets there rather than rolling past)
		var to_go := dist if _ap_v[i] > 0.0 else maxf(dist - 1.5, 0.0)
		vt = _held(vt, sqrt(_ap_v[i] * _ap_v[i] + 2.0 * 2.6 * to_go), "curve")
	vt = _held(vt, _ap_light_v(), "light")
	vt = _held(vt, _ap_sign_v(dt), "sign")
	vt = _held(vt, _ap_zebra_v(), "zebra")
	vt = _held(vt, _ap_people_v(), "people")
	if not _cross.is_empty() and not _cross["chosen"]:
		_ap_why = "choice" if vt >= CROSS_V else _ap_why
	if ahead_blocked:
		vt = _held(vt, 2.5, "blocked")
	# the car in front, kept a couple of metres and a second or so behind; after waiting
	# a while, ignore cars crossing the lane (a standoff in a junction) -- never one ahead
	var lead: Array = _traffic.lead_on(_ap_pts, _pos, clampf(12.0 + _v * 1.2 + _v * _v / 5.2, 18.0, 130.0), _ap_wait > 3.0)
	if float(lead[0]) < 30.0 and _ap_pass_bus(lead):
		lead = _traffic.lead_on(_ap_pts, _pos, clampf(12.0 + _v * 1.2 + _v * _v / 5.2, 18.0, 130.0), _ap_wait > 3.0)
	_ap_lead = float(lead[0]) if float(lead[0]) < INF else -1.0
	if float(lead[0]) < INF:
		var lv: float = lead[1]
		# from my nose to its back (a bus is two and a half cars long: kept a car's length
		# from its middle, autodrive drove into its back)
		var room := float(lead[0]) - CAR_LEN * 0.5 - float(lead[2]) - 2.2 - lv * 1.2
		var follow := 0.0 if room <= 0.0 else sqrt(lv * lv + 2.0 * 2.6 * room)
		if follow < vt:
			vt = follow
			_ap_why = "car"
			_ap_wait = _ap_wait + dt if _v < 0.3 else 0.0
		else:
			_ap_wait = 0.0
	else:
		_ap_wait = 0.0
	var err := vt - _v
	var throttle := clampf(err * 0.35, 0.0, 1.0)
	var brake := clampf(-err * 0.25, 0.0, 1.0) if err < -0.3 else 0.0
	if vt < 0.5 and _v < 1.5:
		brake = maxf(brake, 0.8)   # waiting at a light or behind a car: foot on the brake
	if throttle > 0.3 and absf(_v) < 0.4:
		_ap_stuck += dt
		if _ap_stuck > 2.0:
			_ap_stuck = 0.0
			_ap_back = 1.4
			# a push that went nowhere counts as a bump (too slow to be one): three in a row
			# and it is lost, back to the street. Forward into a post, back, forward into it
			# again went on for a minute and a half, foot on the gas -- not driving.
			_ap_bonks += 1.0
			Probe.event("autodrive_stuck")
	else:
		_ap_stuck = 0.0
	_ap_watch(dt, vt)
	return [throttle, brake, steer]

## The last resort: autodrive that has got nowhere for 40 s -- not waiting at a light,
## just stuck (a dead end at the edge of the map, a knot of buildings the plan runs into) --
## is lifted onto a street a little way toward the middle of town, and drives on from there.
var _ap_mark := Vector2.INF
var _ap_mark_t := 0.0
const AP_GIVE_UP := 40.0

func _ap_watch(dt: float, vt: float) -> void:
	if _ap_mark == Vector2.INF or _pos.distance_to(_ap_mark) > 12.0 or _ap_light_v() < 0.5 or not _cross.is_empty():
		_ap_mark = _pos
		_ap_mark_t = 0.0
		return
	_ap_mark_t += dt
	if _ap_mark_t < AP_GIVE_UP:
		return
	_ap_mark = Vector2.INF
	var mid := _bounds.get_center()
	var toward := (mid - _pos).normalized()
	for reach: float in [40.0, 80.0, 140.0]:
		if _land_on_road(_pos + toward * reach, 50.0, toward):
			_ap_pts = PackedVector2Array()
			_show_banner("autodrive: unstuck", 1.6)
			Probe.event("autodrive_unstuck")
			_log.event("unstuck")
			return

## the point `dist` metres along the planned lane from point k (negative = back)
func _ap_walk(k: int, dist: float) -> Vector2:
	var step := 1 if dist > 0.0 else -1
	var left := absf(dist)
	var p := _ap_pts[k]
	var j := k + step
	while j >= 0 and j < _ap_pts.size():
		var L := p.distance_to(_ap_pts[j])
		if L >= left:
			return p + (_ap_pts[j] - p) * (left / maxf(L, 0.0001))
		left -= L
		p = _ap_pts[j]
		j += step
	return p

## index of the planned stretch the car is on: the closest of the next three, or of any
## further one that starts within 60 m of the car (not "within 40 m of the point behind":
## a long first stretch then hid the next one, and the car never saw its stop coming)
func _ap_nearest_seg() -> int:
	var best_i := 0
	var best_d := INF
	for i in range(_ap_pts.size() - 1):
		if i >= 3 and _ap_pts[i].distance_to(_pos) > 60.0:
			break
		var d := Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[i], _ap_pts[i + 1]).distance_to(_pos)
		if d < best_d - 0.05:
			best_d = d
			best_i = i
	return best_i

func _ap_off_route() -> float:
	if _ap_pts.size() < 2:
		return INF
	var i := _ap_nearest_seg()
	return Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[i], _ap_pts[i + 1]).distance_to(_pos)

func _ap_len() -> float:
	var L := 0.0
	for i in range(1, _ap_pts.size()):
		L += _ap_pts[i - 1].distance_to(_ap_pts[i])
	return L

func _ap_point_ahead(look: float) -> Vector2:
	var p := Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[0], _ap_pts[1])
	var left := look
	for i in range(1, _ap_pts.size()):
		var nxt := _ap_pts[i]
		var L := p.distance_to(nxt)
		if L >= left:
			return p + (nxt - p) * (left / maxf(L, 0.001))
		left -= L
		p = nxt
	return p

const AP_OFFROAD_V := 4.0             ## m/s, finding its way back to the road
const WAY_CELL := 2.0
const WAY_REACH := 36                 ## cells each way from the car: 72 m

## The way from the car back onto a road it can drive, round whatever buildings are in
## between: a search outward over 2 m squares the car fits through, to the first one well on
## the asphalt, then pulled straight wherever a straight line is clear. [] when there is none
## within reach.
func _way_to_road() -> PackedVector2Array:
	var origin := _pos
	var came := {Vector2i.ZERO: Vector2i.ZERO}
	var wall := {}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head := 0
	var goal := Vector2i.ZERO
	var found := false
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c != Vector2i.ZERO:
			var on := _nearest_seg(origin + Vector2(c) * WAY_CELL, 8.0, true, true)
			if not on.is_empty() and float(on["edge"]) < -1.2:
				goal = c
				found = true
				break
		for st: Vector2i in steps:
			var n: Vector2i = c + st
			if came.has(n) or wall.has(n) or absi(n.x) > WAY_REACH or absi(n.y) > WAY_REACH:
				continue
			if _push_out(origin + Vector2(n) * WAY_CELL, 1.3, true, false) != Vector2.ZERO:
				wall[n] = true
				continue
			came[n] = c
			queue.append(n)
	if not found:
		return PackedVector2Array()
	var cells: Array[Vector2i] = []
	var at := goal
	while at != Vector2i.ZERO:
		cells.append(at)
		at = came[at]
	cells.reverse()
	var out := PackedVector2Array([origin])
	var i := 0
	while i < cells.size():
		var far := i
		for j in range(cells.size() - 1, i, -1):
			if _clear_line(out[out.size() - 1], origin + Vector2(cells[j]) * WAY_CELL):
				far = j
				break
		out.append(origin + Vector2(cells[far]) * WAY_CELL)
		i = far + 1
	return out

## a car's width clear all the way from a to b (from a little way out of a: the car may be
## up against a wall where it stands)
func _clear_line(a: Vector2, b: Vector2) -> bool:
	var L := a.distance_to(b)
	var s := minf(1.5, L)
	while s < L:
		if _push_out(a.lerp(b, s / L), 1.2, true, false) != Vector2.ZERO:
			return false
		s += 1.0
	return true

## Lost: no way back found, or into the walls again and again. Back onto the nearest street,
## the way the 40 s unstuck does.
func _ap_rescue() -> bool:
	_ap_bonks = 0.0
	if not _land_on_road(_pos, 80.0, _fwd()):
		return false
	_ap_back = 0.0
	_ap_turn = 0.0
	_show_banner("autodrive: back on the road", 1.6)
	Probe.event("autodrive_rescue")
	_log.event("rescue")
	return true

func _ap_plan() -> void:
	_cross = {}
	_ap_queue = []
	_ap_pts = PackedVector2Array()
	_ap_v = PackedFloat32Array()
	_ap_lim = PackedFloat32Array()
	if _dest_on:
		# off the road (on a footpath, in a yard): first the way back onto it, as below. The
		# trip planned from the nearest street as if the car were on it, and autodrive drove
		# along the footpath beside it into the bollards at its end, for a minute and a half.
		var from := _pos
		var heading := _fwd()
		var way := PackedVector2Array()
		var on := _nearest_seg(_pos, 60.0, true, true)
		if not on.is_empty() and float(on["edge"]) > 1.0:
			way = _way_to_road()
			if way.size() >= 2:
				from = way[way.size() - 1]
				heading = (way[way.size() - 1] - way[way.size() - 2]).normalized()
			elif _ap_rescue():
				from = _pos
				heading = _fwd()
		if not _route_to(_dest, from, heading):
			_show_banner("can't find a way there from here", 2.0)
			_clear_dest()
			return
		if way.size() >= 2:
			var off_v := PackedFloat32Array()
			off_v.resize(way.size() - 1)
			off_v.fill(AP_OFFROAD_V)
			way.resize(way.size() - 1)   # (the route starts where the way ends)
			way.append_array(_ap_pts)
			_ap_pts = way
			off_v.append_array(_ap_v)
			_ap_v = off_v
			var off_l := PackedFloat32Array()
			off_l.resize(_ap_pts.size() - _ap_lim.size())
			off_l.fill(AP_OFFROAD_V)
			off_l.append_array(_ap_lim)
			_ap_lim = off_l
		return
	var hit := _nearest_seg(_pos, 60.0, true, true)
	if hit.is_empty():
		return
	var heading := _fwd()
	if float(hit["edge"]) > 1.0:
		# off the road (a yard, a car park, between blocks): the way back to it round the
		# buildings. Straight at the nearest bit of road went into the wall in between, backed
		# off, planned the same again, and into the wall again.
		var way := _way_to_road()
		if way.size() < 2:
			if not _ap_rescue():
				return
			hit = _nearest_seg(_pos, 20.0, true, true)
			if hit.is_empty():
				return
			heading = _fwd()
		else:
			for q: Vector2 in way:
				_ap_pts.append(q)
				_ap_v.append(AP_OFFROAD_V)
				_ap_lim.append(AP_OFFROAD_V)
			heading = (way[way.size() - 1] - way[way.size() - 2]).normalized()
			hit = _nearest_seg(way[way.size() - 1], 12.0, true, true)
			if hit.is_empty():
				return
	var ri: int = hit["road"]
	var sj: int = hit["seg"]
	var r: Dictionary = _roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var dir := 1 if (pts[sj + 1] - pts[sj]).dot(heading) >= 0.0 else -1
	if r["o"] != 0:
		dir = r["o"]
	var d_first := (pts[sj + 1] - pts[sj]).normalized() * float(dir)
	_ap_pts.append((hit["q"] as Vector2) + Vector2(-d_first.y, d_first.x) * _lane_off(r))   # (its lane, see _route_to)
	_ap_v.append(float(r["speed"]))
	_ap_lim.append(float(r["speed"]))
	_ap_leg(ri, sj + 1 if dir > 0 else sj, dir)

## append a road from index `from` to its end in direction `dir`, offset into the lane
func _ap_leg(ri: int, from: int, dir: int) -> void:
	var r: Dictionary = _roads[ri]
	var pts: PackedVector2Array = r["pts"]
	# the right-hand lane: every two-way street has two, however narrow (with traffic
	# about, driving down the middle of one meant meeting cars head on)
	var lane := _lane_off(r)
	var last := pts.size() - 1 if dir > 0 else 0
	if r.get("ring", false):   # a roundabout: plan only to its next exit (see traffic.gd's _ring_stop)
		var ids: PackedInt32Array = r["ids"]
		var k := from
		while k != last:
			if k != from and _node_ways(ids[k]) >= 3:
				last = k
				break
			k += dir
	var i := from
	_ap_turn_lane(ri, from, dir)
	_ap_turn_into(ri, from, dir, lane)
	var start := maxi(_ap_pts.size() - 6, 0)
	while true:
		var prv := pts[i - dir] if (i - dir >= 0 and i - dir < pts.size()) else pts[i]
		var nxt := pts[i + dir] if (i + dir >= 0 and i + dir < pts.size()) else pts[i]
		var d := (nxt - prv).normalized()
		if d == Vector2.ZERO:
			d = _fwd()
		_ap_pts.append(_clear_lane(pts[i], d, lane))
		_ap_v.append(float(r["speed"]))
		_ap_lim.append(float(r["speed"]))
		if i == last:
			break
		i += dir
	_ap_end = Vector3i(ri, last, dir)
	# corners: the radius through the points 5 m either side of each one, and the speed
	# that keeps the sideways pull comfortable round it. A sharp junction corner and the
	# gentle-looking many-sided ring of a roundabout both come out as the tight turns
	# they are. (Points near the old end are redone now that there is road beyond them.)
	_ap_curves(start - 10)

## Round a bus at its stop: on a road of two lanes or more each way, a bus standing at the
## kerb ahead is passed in the next lane over when that lane is clear from 15 m behind to 25 m
## ahead -- moving out over 8 m before it, back in 12 m past it -- instead of queueing behind
## it for the whole stop (or, as it once did, driving into its back). True when it moved out.
var _ap_passed := -1                 ## the bus last passed (not again)

func _ap_pass_bus(lead: Array) -> bool:
	var bi: int = lead[3]
	if bi < 0 or bi == _ap_passed:
		return false
	var bus = _traffic.cars[bi]
	if bus.kind != "bus" or bus.v > 0.6 or bus.dwell <= 0.0 or _ap_pts.size() < 3:
		return false
	var hit := _nearest_seg(_pos, 12.0, true, true)
	if hit.is_empty():
		return false
	var r: Dictionary = _roads[hit["road"]]
	var n := _lanes_each_way(r)
	if n < 2:
		return false
	var w := float(r["w"])
	var lane_w := w / n if int(r["o"]) != 0 else (w * 0.5) / n
	if int(r["o"]) == 0:
		# a two-way road: over to the inner lane of its own side -- by a whole lane from where
		# autodrive drives (a little in from the right lane's middle) it crossed the centre
		var inner := (w * 0.5) / n * 0.5
		if inner < float(r.get("mid", 0.0)) + 1.15:
			return false
		lane_w = _lane_off(r) - inner
		if lane_w < 1.5:
			return false
	var fwd := _fwd()
	var left := Vector2(fwd.y, -fwd.x)
	var gap: float = lead[0]
	if _ap_turn_ahead() != 0:
		return false   # (a junction just after it: stay in lane)
	# the next lane over clear, by every car's middle
	for c in _traffic.cars:
		if not c.alive or c == bus:
			continue
		var rel: Vector2 = c.pos - _pos
		var ahead := rel.dot(fwd)
		var side := rel.dot(left)
		if ahead > -15.0 and ahead < gap + 25.0 and side > lane_w * 0.4 and side < lane_w * 1.6:
			return false
	# out, past, back in: the points of the plan from just ahead to past the bus
	var s := 0.0
	var half: float = bus.len * 0.5
	var start_s := maxf(gap - half - 10.0, 2.0)
	var end_s := gap + half + 12.0
	for k in range(1, _ap_pts.size()):
		s += _ap_pts[k - 1].distance_to(_ap_pts[k])
		if s > end_s + 8.0:
			break
		var t := clampf((s - start_s) / 8.0, 0.0, 1.0) * clampf((end_s + 8.0 - s) / 8.0, 0.0, 1.0)
		if t <= 0.0:
			continue
		var kd := (_ap_pts[mini(k + 1, _ap_pts.size() - 1)] - _ap_pts[k - 1]).normalized()
		_ap_pts[k] += Vector2(kd.y, -kd.x) * lane_w * t
	_ap_passed = bi
	Probe.event("pass_bus", {"lane_w": snappedf(lane_w, 0.1)})
	_log.event("pass bus")
	return true

## Into the turn lane: before a left turn, over the last 45 m, the lane on the left of its
## way -- the leftmost of a one-way road of several, the one beside the centre line of a
## two-way road of several, and toward the centre line on a road of one each way. People turn
## left from the left lane; autodrive turned across the lanes from the right-hand one.
func _ap_turn_lane(ri: int, from: int, dir: int) -> void:
	var m := _ap_pts.size()
	if _ap_end.x < 0 or m < 4:
		return
	var r_in: Dictionary = _roads[_ap_end.x]
	var pts: PackedVector2Array = _roads[ri]["pts"]
	var at := from - dir
	if at < 0 or at >= pts.size() or r_in.get("ring", false):
		return
	var c := pts[at]
	var in_dir := (_ap_pts[m - 1] - _ap_pts[m - 3]).normalized()
	var out_dir := (pts[from] - c).normalized()
	if in_dir == Vector2.ZERO or out_dir == Vector2.ZERO or in_dir.angle_to(out_dir) > -0.6:
		return   # (not a left turn: + is right)
	var n := _lanes_each_way(r_in)
	var w := float(r_in["w"])
	var target := 0.0
	if int(r_in["o"]) != 0:
		if n < 2:
			return
		target = -(w * 0.5 - w / n * 0.5)
	else:
		target = (w * 0.5) / n * 0.5 if n >= 2 else _lane_off(r_in) * 0.55
		target = maxf(target, float(r_in.get("mid", 0.0)) + 1.15)   # (clear of a median)
	var shift := target - _lane_off(r_in)
	if absf(shift) < 0.3:
		return
	var s := 0.0
	for k in range(m - 1, 1, -1):   # (not the points right by the car: no swerve)
		if k < m - 1:
			s += _ap_pts[k].distance_to(_ap_pts[k + 1])
		if s > 45.0:
			break
		var kd := (_ap_pts[mini(k + 1, m - 1)] - _ap_pts[k - 1]).normalized()
		var right := Vector2(-kd.y, kd.x)
		_ap_pts[k] += right * shift * clampf((45.0 - s) / 25.0, 0.0, 1.0)

## Into the next road at a junction: the last road ended on the junction's point, and the
## next road's first point can be 30-100 m down it -- the straight line between them ran
## down the wrong side of the new street (after a left turn the car sat in the oncoming
## lane for a while, after a right one it straddled the middle) and into the cars there.
## Now the turn starts just short of the junction in the lane it is in, curves round, and
## comes out just past it in the right lane of the new road.
func _ap_turn_into(ri: int, from: int, dir: int, lane: float) -> void:
	var r: Dictionary = _roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	var at := from - dir
	var n := _ap_pts.size()
	if at < 0 or at >= pts.size() or n < 2:
		return
	var node := ids[at]
	var c := _nodes[node]
	if _node_ways(node) < 3 or _ap_pts[n - 1].distance_to(c) > 6.0:
		return
	var before := _ap_pts[n - 2]
	var in_dir := (c - before).normalized()
	var out_dir := (pts[from] - c).normalized()
	if in_dir == Vector2.ZERO or out_dir == Vector2.ZERO or absf(in_dir.angle_to(out_dir)) < 0.35:
		return
	var rin := Vector2(-in_dir.y, in_dir.x)
	var rout := Vector2(-out_dir.y, out_dir.x)
	var lane_in := (_ap_pts[n - 1] - c).dot(rin)
	var back := minf(_node_r[node] + 1.0, before.distance_to(c) * 0.8)
	var ahead := minf(_node_r[node] + 1.0, c.distance_to(pts[from]) * 0.8)
	var E := c - in_dir * back + rin * lane_in
	var X := c + out_dir * ahead + rout * lane
	var K = Geometry2D.line_intersects_line(E, in_dir, X, -out_dir)
	var k2: Vector2 = K if K != null and (K as Vector2).distance_to(c) < back + ahead + 4.0 else (E + X) * 0.5
	var v := _ap_v[n - 1]
	var lim := _ap_lim[n - 1]
	_ap_pts[n - 1] = E
	for t: float in [0.25, 0.5, 0.75, 1.0]:
		_ap_pts.append(E * (1.0 - t) * (1.0 - t) + k2 * 2.0 * (1.0 - t) * t + X * t * t)
		_ap_v.append(v)
		_ap_lim.append(minf(lim, float(r["speed"])))

func _ap_curves(from_k: int) -> void:
	for k in range(maxi(1, from_k), _ap_pts.size() - 1):
		if _ap_v[k] == 0.0:
			continue   # a stop to turn round at (a dead end's U-turn): kept
		var a := _ap_walk(k, -5.0)
		var b := _ap_pts[k]
		var c := _ap_walk(k, 5.0)
		var cross := absf((b - a).cross(c - a))
		var radius := INF if cross < 0.001 else a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * cross)
		_ap_v[k] = minf(_ap_lim[k], maxf(sqrt(AP_LAT * radius), 2.5))

## at the end of the planned road pick the next one: ahead rather than a turn, a street
## not driven yet rather than an old one, never against a one-way, U-turn only at a dead end
## the legs still to drive across a junction already chosen at (see _cluster_exits)
var _ap_queue: Array = []
const CLUSTER_M := 35.0              ## legs this short between junction points: one junction

func _ap_next() -> bool:
	if _ap_end.x < 0:
		return false
	var r: Dictionary = _roads[_ap_end.x]
	var node: int = (r["ids"] as PackedInt32Array)[_ap_end.y]
	if not _ap_queue.is_empty():
		var q: Vector3i = _ap_queue.pop_front()
		var rq: Dictionary = _roads[q.x]
		if (rq["ids"] as PackedInt32Array)[q.y - q.z] == node:
			_ap_ring_n = 0
			_ap_leg(q.x, q.y, q.z)
			return true
		_ap_queue = []   # (somewhere else after all: choose afresh)
	var found := _ap_ways(_ap_end.x, _ap_end.y, _ap_end.z)
	var ways: Array = found[0]
	var back: Vector3i = found[1]
	if ways.is_empty():
		if back.x < 0:
			return false
		# a dead end: stop at its end and turn round there (see _autodrive). Planned as a
		# lane out and a lane back, the U-turn was a corner a few metres across taken at
		# 2.5 m/s -- autodrive swung wide past the end, onto the footpath beyond, and drove
		# on along it at 40 km/h while it worked its way round.
		var apex := _ap_pts.size() - 1
		_ap_leg(back.x, back.y, back.z)
		for k in [apex, apex + 1]:
			if k > 0 and k < _ap_v.size() - 1:
				_ap_v[k] = 0.0
		return true
	# a real crossing (two or more proper streets on): ask, and plan no further for now --
	# but not round a roundabout, where the exits come too fast to ask at each
	var main: Array = ways.filter(func(w): return not w["service"])
	if not _dest_on and main.size() >= 2 and not r.get("ring", false):
		if _cross.is_empty() or _cross["node"] != node:
			var pts: PackedVector2Array = r["pts"]
			var prev := clampi(_ap_end.y - _ap_end.z, 0, pts.size() - 1)
			var came := (pts[_ap_end.y] - pts[prev]).normalized()
			var exits := _cluster_exits(main, came, 0, {node: true})
			if exits.is_empty():
				exits = main
				for w: Dictionary in exits:
					w["legs"] = [w["leg"]]
			exits.sort_custom(func(a, b): return a["turn"] < b["turn"])
			var pick := 0
			for i in range(exits.size()):
				if exits[i]["score"] > exits[pick]["score"]:
					pick = i
			_cross = {"node": node, "at": _ap_pts[_ap_pts.size() - 1], "ways": exits, "pick": pick, "chosen": false}
			_ap_v[_ap_v.size() - 1] = minf(_ap_v[_ap_v.size() - 1], CROSS_V)
		return false
	var best_i := 0
	for i in range(ways.size()):
		if ways[i]["score"] > ways[best_i]["score"]:
			best_i = i
	var leg: Vector3i = ways[best_i]["leg"]
	_ap_ring_n = _ap_ring_n + 1 if (_roads[leg.x] as Dictionary).get("ring", false) else 0
	_ap_leg(leg.x, leg.y, leg.z)
	return true

## The ways on from point ei of road ri, arrived at going `dir`: [ways, back], ways each
## {leg: Vector3i(road, first index, direction), turn, name, en, service, score}, back the
## leg back the way it came (only from a dead end; Vector3i(-1, ...) when there is none).
func _ap_ways(ri: int, ei: int, dir: int) -> Array:
	var r: Dictionary = _roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var node: int = (r["ids"] as PackedInt32Array)[ei]
	var prev := ei - dir
	if prev < 0 or prev >= pts.size():
		prev = ei
	var came := (pts[ei] - pts[prev]).normalized()
	var ways: Array = []
	var back := Vector3i(-1, 0, 0)
	for e: Vector2i in _node_roads[node]:
		var r2: Dictionary = _roads[e.x]
		if not r2["drive"] or r2["pv"]:
			continue   # autodrive stays out of private driveways and car parks
		var p2: PackedVector2Array = r2["pts"]
		for d2: int in [1, -1]:
			var nxt := e.y + d2
			if nxt < 0 or nxt >= p2.size():
				continue
			if e.x == ri and nxt == prev:
				back = Vector3i(e.x, nxt, d2)   # back the way it came: only from a dead end
				continue
			if r2["o"] != 0 and r2["o"] != d2:
				continue
			var go := (p2[nxt] - p2[e.y]).normalized()
			var c := came.dot(go)
			if c < -0.7:
				continue
			var score := c * 1.2 + randf()
			if r2["name"] != "" and not _visited.has(r2["name"]):
				score += 1.4
			if r2["k"] == "service":
				score -= 6.0   # alleys and car-park lanes: only when there is nothing else
			if not _in_city(p2[nxt]):
				score -= 2.5   # back toward town rather than out past its edge
			if r.get("ring", false):
				# on a roundabout: off at one of the next exits, never round and round
				score += (-0.8 - 1.2 * _ap_ring_n) if r2.get("ring", false) else 1.2
			ways.append({"leg": Vector3i(e.x, nxt, d2), "turn": came.angle_to(go), "name": r2["name"],
				"en": r2["en"], "service": r2["k"] == "service", "score": score})
	return [ways, back]

## One big junction drawn as several. Where a divided road meets a street, each of its halves
## meets it at a point of its own, 10-30 m apart (four points where two divided roads cross),
## and every one of them asked again which way: right-or-on, then left-or-on, for one left
## turn. The choices are now the ways out of the whole knot -- each with the short legs
## across it that get there, driven without asking -- and how far each turns from the way in.
func _cluster_exits(ways: Array, came: Vector2, depth: int, seen: Dictionary) -> Array:
	var out: Array = []
	for w: Dictionary in ways:
		if w["service"]:
			continue
		var leg: Vector3i = w["leg"]
		var r2: Dictionary = _roads[leg.x]
		var p2: PackedVector2Array = r2["pts"]
		var last := p2.size() - 1 if leg.z > 0 else 0
		var length := 0.0
		var k := leg.y - leg.z
		while k != last:
			length += p2[k].distance_to(p2[k + leg.z])
			k += leg.z
		var end_node: int = (r2["ids"] as PackedInt32Array)[last]
		if depth < 3 and length <= CLUSTER_M and not r2.get("ring", false) and not seen.has(end_node):
			var main2: Array = (_ap_ways(leg.x, last, leg.z)[0] as Array).filter(func(x): return not x["service"])
			if main2.size() >= 2:   # another point of the same junction: on across it
				seen[end_node] = true
				for sub: Dictionary in _cluster_exits(main2, came, depth + 1, seen):
					sub["legs"] = [leg] + (sub["legs"] as Array)
					out.append(sub)
				continue
		# (not one that runs back into the knot: round three sides of it to leave by a road
		# the first point already offered)
		var ids2: PackedInt32Array = r2["ids"]
		var back_in := false
		var run := 0.0
		var j := leg.y
		while run < CLUSTER_M * 1.5:
			run += p2[j - leg.z].distance_to(p2[j])
			if seen.has(ids2[j]):
				back_in = true
				break
			if j == last:
				break
			j += leg.z
		if back_in:
			continue
		# a way out: where it heads 15 m on (a slip road curves), against the way in
		var a := p2[leg.y - leg.z]
		var b := a
		var i := leg.y - leg.z
		while i != last and b.distance_to(a) < 15.0:
			i += leg.z
			b = p2[i]
		var go := (b - a).normalized()
		if go == Vector2.ZERO or came.dot(go) < -0.7:
			continue   # round the knot and back the way it came
		out.append({"leg": leg, "legs": [leg], "turn": came.angle_to(go), "name": w["name"], "en": w["en"],
			"service": false, "score": w["score"]})
	if depth > 0:
		return out
	# the same way out reached two ways round (or the same street, the same way, from two
	# of its points): the one across fewer of them
	var keep: Array = []
	for x: Dictionary in out:
		var dup := -1
		for i in range(keep.size()):
			var k2: Dictionary = keep[i]
			if (k2["legs"] as Array).back() == (x["legs"] as Array).back() \
					or (x["name"] != "" and k2["name"] == x["name"] and absf(angle_difference(k2["turn"], x["turn"])) < 0.5):
				dup = i
				break
		if dup < 0:
			keep.append(x)
		elif (x["legs"] as Array).size() < (keep[dup]["legs"] as Array).size():
			keep[dup] = x
	return keep

## the crossing ahead: take your pick (or ours, once it is too late to wait for yours)
func _cross_tick() -> void:
	if _cross.is_empty():
		return
	var ways: Array = _cross["ways"]
	if not _cross["chosen"] and _cross_showing():
		var pick := -1
		if PInput.just_pressed("move_left"):
			pick = 0
		elif PInput.just_pressed("move_right"):
			pick = ways.size() - 1
		elif PInput.just_pressed("move_up"):
			pick = 0
			for i in range(ways.size()):
				if absf(ways[i]["turn"]) < absf(ways[pick]["turn"]):
					pick = i
		if pick >= 0:
			_cross_pick(pick)
	var d := _pos.distance_to(_cross["at"])
	# go on: chosen, or too close to wait -- or crawling with the plan nearly used up (a car
	# handed over beside a crossing, that could not get within 10 m of its point, waited
	# there for ever and drifted into the parked cars)
	if _cross["chosen"] or d < maxf(10.0, _v * 1.3) or (absf(_v) < 1.5 and d < 26.0):
		var w: Dictionary = ways[_cross["pick"]]
		var legs: Array = w["legs"]
		var leg: Vector3i = legs[0]
		Probe.event("crossing", {"turn": int(rad_to_deg(w["turn"])), "chosen": _cross["chosen"], "legs": legs.size()})
		_log.event("junction", "%+d deg%s" % [int(rad_to_deg(w["turn"])), " (chosen)" if _cross["chosen"] else ""])
		_cross = {}
		_ap_queue = legs.slice(1)
		_ap_leg(leg.x, leg.y, leg.z)

func _cross_pick(i: int) -> void:
	_cross["pick"] = i
	_cross["chosen"] = true
	Audio.play("click", 0.05, -6.0)

## the choices are up from CROSS_SHOW_S seconds (and at least 45 m) out
func _cross_showing() -> bool:
	return not _cross.is_empty() and _pos.distance_to(_cross["at"]) < maxf(45.0, _v * CROSS_SHOW_S)

func _cross_rect(i: int, n: int) -> Rect2:
	var w := 78.0
	return Rect2(320.0 - n * (w + 6.0) * 0.5 + i * (w + 6.0) + 3.0, 44.0, w, 46.0)

## ---- going to an address ------------------------------------------------------------------

## plan the shortest legal way from the car to the kerb nearest `goal` into the autodrive lane
func _route_to(goal: Vector2, from := Vector2.INF, heading := Vector2.ZERO) -> bool:
	if from == Vector2.INF:
		from = _pos
	if heading == Vector2.ZERO:
		heading = _fwd()
	var s := _nearest_seg(from, 40.0, true, true)
	var g := _nearest_seg(goal, 150.0, true, true)
	if s.is_empty() or g.is_empty():
		return false
	var r: Dictionary = _roads[s["road"]]
	var ids: PackedInt32Array = r["ids"]
	var pts: PackedVector2Array = r["pts"]
	var sj: int = s["seg"]
	var ahead := (pts[sj + 1] - pts[sj]).dot(heading) >= 0.0
	# Either way along the street it stands in (a two-way one), whichever makes the shorter
	# trip -- the way it faces only breaks a near tie (turning round costs ~15 m). It took the
	# way the car faced, and leaving a house facing away from the route it swerved across a
	# narrow street into the wall, then crept to a junction to turn round in it.
	var dirs: Array = [int(r["o"])] if int(r["o"]) != 0 else [1, -1]
	var dir := 0
	var first := -1
	# arrive at either end of the goal's segment, whichever is legal and shorter
	var gr: Dictionary = _roads[g["road"]]
	var gids: PackedInt32Array = gr["ids"]
	var gj: int = g["seg"]
	var best := PackedInt64Array()
	var best_len := INF
	var best_dir := 0
	for d0: int in dirs:
		var f0 := ids[sj + 1] if d0 > 0 else ids[sj]
		var lead_in := (s["q"] as Vector2).distance_to(_nodes[f0]) + (0.0 if (d0 > 0) == ahead else 15.0)
		for end: Array in [[gids[gj], 1], [gids[gj + 1], -1]]:
			if gr["o"] != 0 and gr["o"] != end[1]:
				continue   # would mean driving the last bit against a one-way
			if not _astar.has_point(f0) or not _astar.has_point(end[0]):
				continue
			var path := _astar.get_id_path(f0, end[0])
			if path.is_empty():
				continue
			if path.size() >= 2 and path[1] == (ids[sj] if d0 > 0 else ids[sj + 1]):
				continue   # on to the end of its street and straight back (a dead end): the
				           # other way round is the same trip without the U-turn. It took this
				           # one from a house at a dead end, swung round in the closed end and
				           # into the fence there.
			var other := gids[gj + 1] if end[1] == 1 else gids[gj]
			if path.size() >= 2 and path[path.size() - 2] == other:
				continue   # it drives past the address to the far end, then U-turns back: no
			var L := lead_in
			for i in range(1, path.size()):
				L += _nodes[path[i - 1]].distance_to(_nodes[path[i]])
			if L < best_len:
				best_len = L
				best = path
				best_dir = end[1]
				dir = d0
				first = f0
	if best.is_empty():
		return false
	# from its own lane, not the middle of the street: from the middle, the line to the next
	# point down the street ran diagonally across it, and the car drove left of the centre
	# line for the length of the street (turned round out of a dead end, all of it)
	var d_first := (pts[sj + 1] - pts[sj]).normalized() * float(dir)
	_ap_pts = PackedVector2Array([(s["q"] as Vector2) + Vector2(-d_first.y, d_first.x) * _lane_off(r)])
	_ap_lim = PackedFloat32Array([float(r["speed"])])
	for i in range(best.size()):
		var n := int(best[i])
		var prv := _ap_pts[_ap_pts.size() - 1]
		var nxt: Vector2 = _nodes[best[i + 1]] if i + 1 < best.size() else g["q"]
		var e: Vector3i = _edge_of.get(Vector2i(int(best[i - 1]), n), Vector3i(s["road"], 0, 1)) if i > 0 else Vector3i(s["road"], 0, dir)
		var road: Dictionary = _roads[e.x]
		var d := (nxt - prv).normalized()
		var lane := _lane_off(road)
		_ap_pts.append(_nodes[n] + Vector2(-d.y, d.x) * lane)
		_ap_lim.append(float(road["speed"]))
	# the last stretch along the goal's segment, to the kerb in front of the address
	var last_dir := (gr["pts"] as PackedVector2Array)[gj + 1] - (gr["pts"] as PackedVector2Array)[gj]
	last_dir = last_dir.normalized() * float(best_dir)
	var glane := _lane_off(gr)
	_dest_stop = (g["q"] as Vector2) + Vector2(-last_dir.y, last_dir.x) * glane
	_ap_pts.append(_dest_stop)
	_ap_lim.append(float(gr["speed"]))
	_ap_v = _ap_lim.duplicate()
	_ap_curves(1)
	_ap_v[_ap_v.size() - 1] = 0.0   # and stop there
	_ap_end = Vector3i(-1, 0, 0)    # nothing after the destination
	Probe.event("route", {"to": _dest_name, "m": int(best_len), "points": _ap_pts.size()})
	return true

func _set_dest(at: Vector2, label: String) -> void:
	_dest_on = true
	_dest = at
	_dest_stop = at
	_dest_name = label
	_dest_t = 0.0
	if _beacon == null:
		_beacon = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.4
		cm.bottom_radius = 1.4
		cm.height = 70.0
		cm.radial_segments = 16
		cm.cap_top = false
		var m := _surface("beacon")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		cm.material = m
		_beacon.mesh = cm
		_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_beacon)
	_beacon.position = Vector3(at.x, _h(at) + 35.0, at.y)
	_beacon.visible = true
	Probe.event("destination", {"to": label})
	_set_auto(true)
	_show_banner("→ " + label, 2.0)

func _clear_dest() -> void:
	_dest_on = false
	if _beacon != null:
		_beacon.visible = false

func _check_arrival(dt: float) -> void:
	if not _dest_on:
		return
	_dest_t += dt
	var near_stop := _pos.distance_to(_dest_stop)
	var last_leg := _auto and _ap_pts.size() <= 3
	if near_stop < 9.0 and absf(_v) < 1.5 or last_leg and near_stop < 15.0 and absf(_v) < 3.0 \
			or (not _auto and _pos.distance_to(_dest) < 16.0 and absf(_v) < 2.5):
		_auto = false
		_ap_pts = PackedVector2Array()
		_clear_dest()
		Audio.play("coin", 0.05, -2.0)
		_show_banner("arrived: " + _dest_name, 3.0)
		Probe.event("arrived", {"to": _dest_name, "secs": int(_dest_t)})

## ---- the address picker: streets, then house numbers ---------------------------------------
## Built for thumbs: no scrolling list (a phone's finger lands on a button, not the list)
## and no typing box (web builds get no reliable on-screen keyboard). Letter chips narrow
## the streets to an initial, pages flip with big arrows. The buttons are only drawn: the
## shell's UI layer sits over every game and would swallow real clicks, so _input() hit-
## tests them and calls the Callable each one carries in its "cb" meta (see _pick_tap).

const PICK_COLS := 2
const PICK_ROWS := 7
const NUM_COLS := 6

func _open_picker() -> void:
	if _picker != null:
		return
	if _walking:
		_show_banner("get back in the car first", 1.2)
		return
	if _streets_list.is_empty():
		_build_street_list()
	_picker = Control.new()
	_picker.size = Vector2(640, 360)
	_picker.z_index = 90
	add_child(_picker)
	var dim := ColorRect.new()
	dim.color = Color(Palette.col("bg"), 0.93)
	dim.size = Vector2(640, 360)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker.add_child(dim)
	var title := UIKit.label("", 16, "player")
	title.position = Vector2(170, 2)
	title.size = Vector2(300, 22)
	_picker.add_child(title)
	_pick_title = title
	# drive there (autodrive takes you) or jump there (you are put down on that street)
	_pick_jump_btn = _bar_button("", Vector2(10, 4), 124, func():
		_pick_jump = not _pick_jump
		_show_pick_mode())
	_show_pick_mode()
	_pick_letters = Control.new()
	_pick_letters.position = Vector2(0, 34)   # clear of the shell's sound/menu buttons
	_picker.add_child(_pick_letters)
	_pick_body = Control.new()
	_pick_body.position = Vector2(20, 90)
	_picker.add_child(_pick_body)
	_pick_prev = _bar_button("◀", Vector2(20, 331), 90, func(): _turn(-1))
	_pick_next = _bar_button("▶", Vector2(410, 331), 90, func(): _turn(1))
	_bar_button("close", Vector2(530, 331), 90, _close_picker)
	_pick_page_lbl = UIKit.label("", 12, "ink")
	_pick_page_lbl.add_theme_font_override("font", _font)
	_pick_page_lbl.text_direction = Control.TEXT_DIRECTION_LTR
	_pick_page_lbl.position = Vector2(110, 334)
	_pick_page_lbl.size = Vector2(300, 18)
	_picker.add_child(_pick_page_lbl)
	_pick_mode = "streets"
	_pick_page = 0
	_build_letters()
	_refresh_pick()
	Probe.event("picker")

func _show_pick_mode() -> void:
	_pick_jump_btn.text = "⇄ jump there" if _pick_jump else "⇄ drive there"
	_pick_title.text = "jump to where?" if _pick_jump else "where to?"

func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null

## a drawn button that _pick_tap() can press
func _tap_button(text: String, cb: Callable) -> Button:
	var b := UIKit.button(text, func(): pass)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("cb", cb)
	return b

## a click or tap while the picker is open: whichever of its buttons is under it
func _pick_tap(at: Vector2) -> void:
	for b: Button in _picker.find_children("*", "Button", true, false):
		if b.is_queued_for_deletion() or b.disabled or not b.is_visible_in_tree():
			continue
		if b.get_global_rect().has_point(at):
			Audio.play("click", 0.05, -8.0)
			(b.get_meta("cb") as Callable).call()
			return

func _bar_button(text: String, at: Vector2, w: float, cb: Callable) -> Button:
	var b := _tap_button(text, cb)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 13)
	_picker.add_child(b)
	_put(b, at, Vector2(w, 26))
	return b

## size a button once it is in the tree: set before, Godot keeps the kit's 180x34 minimum
## on record and the "small" buttons came out 180 wide, overlapping their neighbours
func _put(b: Control, at: Vector2, sz: Vector2) -> void:
	b.custom_minimum_size = sz
	b.position = at
	b.size = sz

## every named street, as the roads and the addresses spell it
func _build_street_list() -> void:
	var en := {}
	for r: Dictionary in _roads:
		if r["drive"] and not r["pv"] and r["name"] != "" and not String(r["name"]).is_valid_int():
			en[r["name"]] = r["en"]
	for st: String in _addr:
		if not en.has(st) and not st.is_valid_int():
			en[st] = ""
	for nm: String in en:
		var e: String = en[nm]
		var count := (_addr.get(nm, []) as Array).size()
		var label: String = nm if e == "" or e == nm else "%s · %s" % [e, nm]
		# U+200E (left-to-right mark) after the Hebrew keeps the count at the end, not in it
		_streets_list.append({"name": nm, "en": e, "label": label + ("\u200e  (%d)" % count if count > 0 else "")})
	_streets_list.sort_custom(func(a, b): return _sort_key(a).naturalnocasecmp_to(_sort_key(b)) < 0)

func _sort_key(st: Dictionary) -> String:
	return String(st["en"]) if st["en"] != "" else String(st["name"])

## the initials a street can be found under: of its English name and of its own name
func _initials(st: Dictionary) -> Array:
	var out: Array = []
	for nm: String in [st["en"], st["name"]]:
		if nm != "":
			var c := nm.substr(0, 1).to_upper()
			if not out.has(c):
				out.append(c)
	return out

func _build_letters() -> void:
	for c in _pick_letters.get_children():
		c.queue_free()
	var latin: Array = []
	var other: Array = []
	for st: Dictionary in _streets_list:
		for c: String in _initials(st):
			var bucket: Array = latin if c.unicode_at(0) < 0x0250 else other
			if not bucket.has(c):
				bucket.append(c)
	latin.sort()
	other.sort()
	var rows: Array = [["all"] + latin, other] if not other.is_empty() else [["all"] + latin]
	for r in range(rows.size()):
		var row: Array = rows[r]
		var w := minf(24.0, 560.0 / maxf(1.0, row.size()))
		var total := 0.0
		for c: String in row:
			total += 42.0 if c == "all" else w
		var x := 320.0 - total * 0.5
		for i in range(row.size()):
			var c: String = row[i]
			var key := "" if c == "all" else c
			var b := _tap_button(c, func(): _pick_letter = key; _pick_page = 0; _pick_mode = "streets"; _refresh_pick())
			b.add_theme_font_override("font", _font)
			b.add_theme_font_size_override("font_size", 11)
			b.set_meta("key", key)
			_pick_letters.add_child(b)
			var cw := 42.0 if c == "all" else w
			_put(b, Vector2(x, r * 25), Vector2(cw - 2.0, 22))
			x += cw

func _turn(by: int) -> void:
	_pick_page += by
	_refresh_pick()

## lay out the current page: streets (two columns) or one street's numbers (six columns)
func _refresh_pick() -> void:
	for c in _pick_body.get_children():
		c.queue_free()
	for b in _pick_letters.get_children():
		(b as Control).modulate = Color(1, 1, 1, 1.0 if b.get_meta("key") == _pick_letter else 0.55)
	var items: Array = []   ## [text, callable]
	var cols := PICK_COLS
	if _pick_mode == "streets":
		for st: Dictionary in _streets_list:
			if _pick_letter == "" or _initials(st).has(_pick_letter):
				items.append([st["label"], _pick_numbers.bind(st["name"])])
	else:
		cols = NUM_COLS
		items.append(["← streets", func(): _pick_mode = "streets"; _pick_page = _pick_back_page; _refresh_pick()])
		items.append(["anywhere", _go.bind(_pick_street, -1)])
		var nums: Array = _addr.get(_pick_street, []).duplicate()
		nums.sort_custom(func(a, b): return String(a[0]).naturalnocasecmp_to(String(b[0])) < 0)
		for n: Array in nums:
			items.append([String(n[0]), _go_to.bind(_pick_street + " " + String(n[0]), n[1])])
	var per := cols * PICK_ROWS
	var pages := maxi(1, ceili(float(items.size()) / per))
	_pick_page = clampi(_pick_page, 0, pages - 1)
	var w := 600.0 / cols
	for i in range(_pick_page * per, mini(items.size(), (_pick_page + 1) * per)):
		var k := i - _pick_page * per
		var b := _tap_button(items[i][0], items[i][1])
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 13)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		_pick_body.add_child(b)
		_put(b, Vector2((k % cols) * w, (k / cols) * 33), Vector2(w - 8.0, 28))
	_pick_prev.disabled = _pick_page == 0
	_pick_next.disabled = _pick_page >= pages - 1
	var what := _pick_street if _pick_mode == "numbers" else ("streets" if _pick_letter == "" else "streets · " + _pick_letter)
	_pick_page_lbl.text = "%s\u200e   %d / %d" % [what, _pick_page + 1, pages]

var _pick_back_page := 0

func _pick_numbers(street: String) -> void:
	_pick_back_page = _pick_page
	_pick_street = street
	_pick_mode = "numbers"
	_pick_page = 0
	_refresh_pick()

## a street with no particular number: its nearest point to the car
func _go(street: String, _i: int) -> void:
	var best := INF
	var at := _pos
	for r: Dictionary in _roads:
		if r["name"] != street or not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(_pos, pts[j], pts[j + 1])
			if q.distance_to(_pos) < best:
				best = q.distance_to(_pos)
				at = q
	if best == INF and _addr.has(street):
		at = (_addr[street] as Array)[0][1]
	_go_to(street, at)

func _go_to(label: String, at: Vector2) -> void:
	_close_picker()
	if _pick_jump:
		_jump_to(at, label)
	else:
		_set_dest(at, label)

## "jump there": the car is put down on the street at `at`, in its lane, stopped, facing
## the way that has the address on the kerb side
func _jump_to(at: Vector2, label: String) -> void:
	_clear_dest()
	if _auto:
		_set_auto(false)
	if not _land_on_road(at, 120.0, Vector2.ZERO):
		_show_banner("no street to land on there", 2.0)
		return
	_pin_at = _pos
	_show_banner(label, 2.5)
	Probe.event("jump", {"to": label, "at": Vector2i(_pos)})

## ---- exploring: a point for every street of the city you drive down -----------------------

func _explore(dt: float) -> void:
	_on_m += absf(_v) * dt
	_scan_t -= dt
	if _scan_t > 0.0:
		return
	_scan_t = 0.15
	var hit := _nearest_seg(_pos, 14.0, true)
	var nm := ""
	var en := ""
	if not hit.is_empty() and float(hit["edge"]) < 1.5:
		var r: Dictionary = _roads[hit["road"]]
		nm = r["name"]
		en = r["en"]
	if nm != _on_name:
		_on_name = nm
		_on_m = 0.0
		_street_lbl.text = nm
		_street_en_lbl.text = en if en != nm else ""
	if nm != "" and _on_m >= NEW_STREET_M and _streets.has(nm) and not _visited.has(nm):
		_visited[nm] = true
		add_score(1)
		Audio.play("coin", 0.05, -4.0)
		Probe.event("new_street", {"n": _visited.size()})
		_show_banner("+ " + nm, 1.6)
		_count_lbl.text = "streets %d / %d" % [_visited.size(), _streets.size()]
	_inside_t -= 0.15
	if _inside_t <= 0.0 and not _boundary.is_empty():
		_inside_t = 0.6
		var now := _in_city(_pos)
		if now != _inside:
			_inside = now
			_show_banner(("welcome to " if now else "leaving ") + _city_name, 2.2)
			Probe.event("city_limits", {"inside": now})

## ---- HUD ---------------------------------------------------------------------------------

func _make_font() -> void:
	var base: Font = ThemeDB.fallback_font
	var he: Font = load(get_script().resource_path.get_base_dir() + "/fonts/NotoSansHebrew-SemiBold.woff2")
	if he == null:
		_font = base
		return
	var f := FontVariation.new()
	f.base_font = base
	var fb: Array[Font] = [he]
	f.fallbacks = fb
	_font = f

func _label(size: int, role: String) -> Label:
	var l := UIKit.label("", size, role)
	l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_outline_color", Palette.col("bg"))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("role", role)
	_hud.add_child(l)
	return l

func _build_hud() -> void:
	_hud = Node2D.new()
	_hud.z_index = 50
	add_child(_hud)
	_hud.draw.connect(_draw_hud)
	_street_lbl = _label(17, "ink")
	_street_lbl.position = Vector2(170, 2)
	_street_lbl.size = Vector2(300, 26)
	_street_en_lbl = _label(10, "ink")
	_street_en_lbl.position = Vector2(170, 26)
	_street_en_lbl.size = Vector2(300, 14)
	_count_lbl = _label(11, "ink")
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_count_lbl.position = Vector2(10, 32)
	_count_lbl.text = "streets 0 / %d" % _streets.size()
	_build_lbl = _label(9, "ink")   # how much of the city is up yet (the rest goes on while you drive)
	_build_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_build_lbl.position = Vector2(10, 46)
	_build_lbl.modulate.a = 0.7
	_speed_lbl = _label(30, "ink")
	_speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_lbl.position = Vector2(496, 30)
	_speed_lbl.size = Vector2(100, 40)
	_gear_lbl = _label(16, "warn")
	_gear_lbl.position = Vector2(600, 42)
	_gear_lbl.size = Vector2(24, 22)
	var unit := _label(9, "ink")
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unit.position = Vector2(496, 66)
	unit.size = Vector2(100, 14)
	unit.text = "km/h"
	# frames a second and the quality level, small: "it's laggy" comes with a number
	_fps_lbl = _label(8, "ink")
	_fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_lbl.position = Vector2(496, 79)
	_fps_lbl.size = Vector2(130, 12)
	_fps_lbl.modulate.a = 0.55
	_perf_lbl = _label(7, "ink")
	_perf_lbl.position = Vector2(8, 128)
	_perf_lbl.size = Vector2(330, 60)
	_perf_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_perf_lbl.visible = false
	_dest_lbl = _label(12, "accent")
	_dest_lbl.text_direction = Control.TEXT_DIRECTION_LTR   # "→ <Hebrew street> 47 · 930 m" reads left to right
	_dest_lbl.position = Vector2(150, 314)
	_dest_lbl.size = Vector2(340, 18)
	_banner = _label(20, "warn")
	_banner.position = Vector2(120, 98)
	_banner.size = Vector2(400, 30)
	_banner.modulate.a = 0.0
	_osm_lbl = _label(8, "ink")
	_osm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_osm_lbl.position = Vector2(8, 347)
	_osm_lbl.text = "a made-up town: not a real place" if _made_up else "map data © OpenStreetMap contributors"
	_osm_lbl.modulate.a = 0.7
	_map = Control.new()
	_map.position = Vector2(8, 224)
	_map.size = Vector2(118, 118)
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	_hud.add_child(_map)

func _retint_hud() -> void:
	if _hud == null:
		return
	for c in _hud.get_children():
		if c is Label and c.has_meta("role"):
			(c as Label).add_theme_color_override("font_color", Palette.col(c.get_meta("role")))
			(c as Label).add_theme_color_override("font_outline_color", Palette.col("bg"))

func _show_banner(msg: String, secs: float) -> void:
	if _banner == null:
		return
	_banner.text = msg
	if _banner_tw != null:
		_banner_tw.kill()
	_banner.modulate.a = 1.0
	_banner_tw = create_tween()
	_banner_tw.tween_interval(secs)
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.5)

func _tick_hud() -> void:
	_speed_lbl.text = str(int(round(absf(_v) * 3.6)))
	_fps_lbl.text = "%d fps · worst %d ms · quality %d" % [Engine.get_frames_per_second(), int(_worst_ms()), _quality]
	if _perf_view:
		_perf_lbl.text = "frame time, last %d frames (lines: 16 and 33 ms)\n%s\nhitches (slowest parts, ms):\n%s" % [
			_frame_ms.size(), _prof_avg, "\n".join(_hitches) if not _hitches.is_empty() else "none yet"]
	if _dest_on:
		var left := _pos.distance_to(_dest)
		if _auto and _ap_pts.size() > 1:
			left = _pos.distance_to(_ap_pts[0]) + _ap_len()
		_dest_lbl.text = "→ %s · %s" % [_dest_name, ("%.1f km" % (left / 1000.0)) if left >= 1000.0 else ("%d m" % int(left))]
	else:
		_dest_lbl.text = ""
	_gear_lbl.text = "" if _walking else ("D" if _gear > 0 else "R")
	_hud.queue_redraw()
	_map.queue_redraw()

## P (or a tap on the fps text): the frame times, then the drive map, then off
func _toggle_perf() -> void:
	if not _perf_view and not _trace_view:
		_perf_view = true
	elif _perf_view:
		_perf_view = false
		_trace_view = true
		_trace_roads = PackedVector2Array()
	else:
		_trace_view = false
	_perf_lbl.visible = _perf_view

## ---- the drive map: the last two minutes from the recorder (drivelog.gd), drawn north up --
## Your track coloured by speed (red standing, green at the limit), autodrive's lane ahead,
## the other cars' tracks faint, a cross where something was hit, a ring where it was put
## back on the road, a dot and the seconds where it stood still (not at a light) 3 s or more.
## "save log" downloads the two minutes as JSON (tests/drive_log_map.py draws one).
const TRACE_RECT := Rect2(96, 36, 448, 252)
const TRACE_SAVE := Rect2(452, 262, 84, 20)
var _trace_view := false
var _trace_roads := PackedVector2Array()   ## the streets in view, world metres, gathered on opening
var _trace_box := Rect2()

func _trace_frame() -> Rect2:
	var box := Rect2(_pos, Vector2.ZERO)
	for sm: Dictionary in _log.samples:
		box = box.expand(Vector2(float(sm["x"]), float(sm["z"])))
	box = box.grow(25.0)
	var want := TRACE_RECT.size.x / TRACE_RECT.size.y
	if box.size.x / maxf(box.size.y, 1.0) < want:
		box = box.grow_individual((box.size.y * want - box.size.x) * 0.5, 0, (box.size.y * want - box.size.x) * 0.5, 0)
	else:
		box = box.grow_individual(0, (box.size.x / want - box.size.y) * 0.5, 0, (box.size.x / want - box.size.y) * 0.5)
	if box.size.x < 150.0:
		box = box.grow((150.0 - box.size.x) * 0.5)
	return box

func _draw_trace() -> void:
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	_hud.draw_rect(TRACE_RECT, Color(bg, 0.9))
	if _trace_roads.is_empty():
		_trace_box = _trace_frame()
		var seen := {}
		for code: int in _near(_seg_hash, _trace_box.get_center(), maxf(_trace_box.size.x, _trace_box.size.y) * 0.5, SEG_CELL):
			if seen.has(code):
				continue
			seen[code] = true
			var r: Dictionary = _roads[code / 4096]
			if not r["drive"]:
				continue
			var pts: PackedVector2Array = r["pts"]
			_trace_roads.append(pts[code % 4096])
			_trace_roads.append(pts[code % 4096 + 1])
	var box := _trace_box
	var sc := TRACE_RECT.size.x / box.size.x
	var to := func(p: Vector2) -> Vector2: return TRACE_RECT.position + (p - box.position) * sc
	var roads := PackedVector2Array()
	for p: Vector2 in _trace_roads:
		roads.append(to.call(p))
	if not roads.is_empty():
		_hud.draw_multiline(roads, Color(ink, 0.25), maxf(1.0, 7.0 * sc))
	# the other cars, faint
	var tracks := {}
	for sm: Dictionary in _log.samples:
		for c: Array in sm["cars"]:
			if not tracks.has(c[0]):
				tracks[c[0]] = PackedVector2Array()
			(tracks[c[0]] as PackedVector2Array).append(to.call(Vector2(float(c[2]), float(c[3]))))
	for id in tracks:
		var tr: PackedVector2Array = tracks[id]
		for k in range(1, tr.size()):
			if tr[k - 1].distance_to(tr[k]) < 25.0 * sc:   # (sent elsewhere: no line across)
				_hud.draw_line(tr[k - 1], tr[k], Color(ink, 0.3), 1.0)
	# mine, by speed; and the standstills
	var prev := Vector2.INF
	var still := 0.0
	var still_at := Vector2.ZERO
	for sm: Dictionary in _log.samples:
		var q: Vector2 = to.call(Vector2(float(sm["x"]), float(sm["z"])))
		var v := absf(float(sm["v"]))
		if prev != Vector2.INF and prev.distance_to(q) < 40.0:
			var k := clampf(v / 14.0, 0.0, 1.0)
			_hud.draw_line(prev, q, Palette.col("hazard").lerp(Palette.col("friend"), k), 2.0)
		prev = q
		if v < 0.3 and sm["why"] != "light":
			if still == 0.0:
				still_at = q
			still += 1.0 / DriveLog.HZ
		else:
			if still >= 3.0:
				_hud.draw_circle(still_at, 2.5, Palette.col("warn"))
				_hud.draw_string(_font, still_at + Vector2(3, -3), "%ds" % int(still), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.col("warn"))
			still = 0.0
	# what happened
	for ev: Array in _log.events:
		var at := Vector2.INF
		for sm: Dictionary in _log.samples:
			if float(sm["t"]) >= float(ev[0]):
				at = to.call(Vector2(float(sm["x"]), float(sm["z"])))
				break
		if at == Vector2.INF:
			continue
		match String(ev[1]):
			"hit":
				_hud.draw_line(at - Vector2(4, 4), at + Vector2(4, 4), Palette.col("hazard"), 2.0)
				_hud.draw_line(at - Vector2(4, -4), at + Vector2(4, -4), Palette.col("hazard"), 2.0)
			"rescue", "unstuck":
				_hud.draw_arc(at, 6.0, 0.0, TAU, 16, Palette.col("warn"), 1.5)
			"junction", "pass bus":
				_hud.draw_circle(at, 2.0, Palette.col("accent"))
	# autodrive's lane ahead, and the car
	if _auto and _ap_pts.size() > 1:
		var lane := PackedVector2Array()
		var s := 0.0
		for k in range(_ap_pts.size()):
			if k > 0:
				s += _ap_pts[k - 1].distance_to(_ap_pts[k])
			if s > 80.0:
				break
			lane.append(to.call(_ap_pts[k]))
		_hud.draw_polyline(lane, Color(Palette.col("accent"), 0.9), 1.5)
	var c: Vector2 = to.call(_pos)
	var f := _fwd()
	var sd := Vector2(-f.y, f.x)
	_hud.draw_colored_polygon(PackedVector2Array([c + f * 7.0, c - f * 4.0 + sd * 4.0, c - f * 4.0 - sd * 4.0]), Palette.col("player"))
	var metres := 0.0
	for k in range(1, _log.samples.size()):
		var a: Dictionary = _log.samples[k - 1]
		var b: Dictionary = _log.samples[k]
		metres += Vector2(float(a["x"]), float(a["z"])).distance_to(Vector2(float(b["x"]), float(b["z"])))
	var why: String = _ap_why if _auto else "(you drive)"
	_hud.draw_string(_font, TRACE_RECT.position + Vector2(6, 13), "the last %d s, %d m · held by: %s · tap the fps text to close" % [
		int(_log.samples.size() / DriveLog.HZ), int(metres), why], HORIZONTAL_ALIGNMENT_LEFT, TRACE_RECT.size.x - 12, 9, ink)
	_hud.draw_rect(TRACE_SAVE, Color(bg, 0.9))
	_hud.draw_rect(TRACE_SAVE, Color(Palette.col("accent"), 0.9), false, 1.5)
	_hud.draw_string(_font, TRACE_SAVE.position + Vector2(0, 14), "save log", HORIZONTAL_ALIGNMENT_CENTER, TRACE_SAVE.size.x, 10, Palette.col("accent"))

func _save_log() -> void:
	var where := _log.save(self)
	_show_banner(("drive log saved: " + where.get_file()) if where != "" else "could not save the log", 2.5)
	Probe.event("drive_log", {"file": where})

func _draw_hud() -> void:
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	if _trace_view:
		_draw_trace()
	if _perf_view and not _frame_ms.is_empty():
		# the last frames' times as bars, oldest on the left; 16 and 33 ms marked
		var box := Rect2(8, 96, 150, 30)
		_hud.draw_rect(box, Color(bg, 0.7))
		var n := _frame_ms.size()
		var w := box.size.x / PERF_FRAMES
		for i in range(n):
			var v: float = _frame_ms[(_frame_i + i) % n] if n == PERF_FRAMES else _frame_ms[i]
			var h := minf(v / 50.0, 1.0) * box.size.y
			var c := Palette.col("friend") if v < 20.0 else (Palette.col("warn") if v < 40.0 else Palette.col("hazard"))
			_hud.draw_rect(Rect2(box.position.x + i * w, box.end.y - h, maxf(w, 1.0), h), c)
		for ms: float in [16.7, 33.3]:
			var y := box.end.y - ms / 50.0 * box.size.y
			_hud.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), Color(ink, 0.35), 1.0)
	var on := Palette.col("friend") if _auto else ink
	_hud.draw_rect(AUTO_BTN, Color(bg, 0.65))
	_hud.draw_rect(AUTO_BTN, Color(on, 0.9), false, 1.5)
	var txt := "AUTODRIVE ON" if _auto else "autodrive"
	_hud.draw_string(_font, AUTO_BTN.position + Vector2(0, 15), txt, HORIZONTAL_ALIGNMENT_CENTER, AUTO_BTN.size.x, 11, on)
	if _auto and _cross_showing():
		var ways: Array = _cross["ways"]
		var commit := maxf(10.0, _v * 1.3)
		var show := maxf(45.0, _v * CROSS_SHOW_S)
		var left := clampf((_pos.distance_to(_cross["at"]) - commit) / maxf(show - commit, 1.0), 0.0, 1.0)
		for i in range(ways.size()):
			var rc := _cross_rect(i, ways.size())
			var mine: bool = i == _cross["pick"]
			var col := (Palette.col("friend") if _cross["chosen"] else Palette.col("accent")) if mine else ink
			_hud.draw_rect(rc, Color(bg, 0.9))
			_hud.draw_rect(rc, Color(col, 0.95 if mine else 0.5), false, 2.0 if mine else 1.0)
			var c := rc.position + Vector2(rc.size.x * 0.5, 17.0)
			var v := Vector2(sin(ways[i]["turn"]), -cos(ways[i]["turn"]))
			_hud.draw_line(c - v * 9.0, c + v * 7.0, col, 3.0)
			var side := Vector2(-v.y, v.x)
			_hud.draw_colored_polygon(PackedVector2Array([c + v * 13.0, c + v * 5.0 + side * 5.5, c + v * 5.0 - side * 5.5]), col)
			var nm: String = ways[i]["en"] if ways[i]["en"] != "" else ways[i]["name"]
			_hud.draw_string(_font, rc.position + Vector2(2, 41), nm, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x - 4, 9, Color(ink, 0.9))
		if not _cross["chosen"]:
			var bar := Rect2(_cross_rect(0, ways.size()).position + Vector2(0, 50), Vector2(ways.size() * 84.0 - 6.0, 3))
			_hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, 3)), Color(Palette.col("accent"), 0.8))
	var go := Palette.col("accent")
	_hud.draw_rect(GOTO_BTN, Color(bg, 0.65))
	_hud.draw_rect(GOTO_BTN, Color(go, 0.9), false, 1.5)
	_hud.draw_string(_font, GOTO_BTN.position + Vector2(0, 15), "go to…", HORIZONTAL_ALIGNMENT_CENTER, GOTO_BTN.size.x, 11, go)
	var asc := Palette.col("friend") if _assist else Color(ink, 0.6)
	_hud.draw_rect(ASSIST_BTN, Color(bg, 0.65))
	_hud.draw_rect(ASSIST_BTN, Color(asc, 0.9), false, 1.5)
	_hud.draw_string(_font, ASSIST_BTN.position + Vector2(0, 15), "assist on" if _assist else "assist off", HORIZONTAL_ALIGNMENT_CENTER, ASSIST_BTN.size.x, 11, asc)
	var nc := Palette.col("warn") if _night else Color(ink, 0.8)
	_hud.draw_rect(NIGHT_BTN, Color(bg, 0.65))
	_hud.draw_rect(NIGHT_BTN, Color(nc, 0.9), false, 1.5)
	_hud.draw_string(_font, NIGHT_BTN.position + Vector2(0, 15), "day" if _night else "night", HORIZONTAL_ALIGNMENT_CENTER, NIGHT_BTN.size.x, 11, nc)
	var lc := Palette.col("warn") if _lights_on else Color(ink, 0.8)
	_hud.draw_rect(LIGHTS_BTN, Color(bg, 0.65))
	_hud.draw_rect(LIGHTS_BTN, Color(lc, 0.9), false, 1.5)
	_hud.draw_string(_font, LIGHTS_BTN.position + Vector2(0, 15), "lights", HORIZONTAL_ALIGNMENT_CENTER, LIGHTS_BTN.size.x, 11, lc)
	# the indicator blinking by the speed, as on a dashboard
	if _blink != 0 and _blink_lit:
		var s := float(_blink)
		var at := Vector2(500.0 if _blink < 0 else 633.0, 50.0)
		_hud.draw_colored_polygon(PackedVector2Array([at + Vector2(s * 7, 0), at + Vector2(-s * 5, -7), at + Vector2(-s * 5, 7)]), Palette.col("friend"))
	var near_car := _walking and _pos.distance_to(_car_at) < 3.6
	var wc := Palette.col("accent") if near_car or not _walking else Color(ink, 0.7)
	_hud.draw_rect(WALK_BTN, Color(bg, 0.65))
	_hud.draw_rect(WALK_BTN, Color(wc, 0.9), false, 1.5)
	_hud.draw_string(_font, WALK_BTN.position + Vector2(0, 15), "drive" if _walking else "walk", HORIZONTAL_ALIGNMENT_CENTER, WALK_BTN.size.x, 11, wc)
	var vc := Palette.col("player") if _cockpit else Color(ink, 0.8)
	_hud.draw_rect(VIEW_BTN, Color(bg, 0.65))
	_hud.draw_rect(VIEW_BTN, Color(vc, 0.9), false, 1.5)
	_hud.draw_string(_font, VIEW_BTN.position + Vector2(0, 15), "chase" if _cockpit else "seat", HORIZONTAL_ALIGNMENT_CENTER, VIEW_BTN.size.x, 11, vc)
	if _touch_seen:
		var held := _stick_id >= 0
		var c := STICK_C
		var a := 0.85 if held else 0.45
		_hud.draw_circle(c, STICK_R, Color(bg, 0.35 if held else 0.2))
		_hud.draw_arc(c, STICK_R, 0.0, TAU, 48, Color(ink, a * 0.6), 2.0)
		# the top of the ring is gas, the bottom brake / reverse
		_hud.draw_arc(c, STICK_R + 4.0, PI * 1.2, PI * 1.8, 16, Color(Palette.col("friend"), a), 3.0)
		_hud.draw_arc(c, STICK_R + 4.0, PI * 0.2, PI * 0.8, 16, Color(Palette.col("hazard"), a), 3.0)
		_hud.draw_circle(c + _stick * STICK_R, 17.0, Color(Palette.col("player"), 0.75 if held else 0.35))
		if not held:
			_hud.draw_string(_font, c + Vector2(-60, STICK_R + 18), "hold & drag to drive", HORIZONTAL_ALIGNMENT_CENTER, 120, 9, Color(ink, 0.6))

## The minimap's lines round a point, in metres from it: outlines, paths, minor and major
## streets, the city limits, places. Gathered again only once the car is MAP_MOVE away,
## not every frame (that was a few thousand points a frame, in script).
const MAP_MOVE := 60.0
var _map_lines := {}

## The minimap's lines, sorted once (while the city loads) into squares of the map, in the
## city's own coordinates: building outlines, paths, minor and major streets. Gathering the
## ones round the car is then joining the squares' arrays, not walking every outline and
## street in 360 m: that walk, every 60 m driven, was a stutter every few seconds.
const MAP_CELL := 120.0
var _map_cells := {}                 ## Vector2i -> {"blds", "paths", "minor", "major"}

func _map_build_cells() -> void:
	_map_cells = {}
	var cell_of := func(p: Vector2) -> Dictionary:
		var key := Vector2i(floori(p.x / MAP_CELL), floori(p.y / MAP_CELL))
		if not _map_cells.has(key):
			_map_cells[key] = {"blds": PackedVector2Array(), "paths": PackedVector2Array(),
				"minor": PackedVector2Array(), "major": PackedVector2Array()}
		return _map_cells[key]
	for poly: PackedVector2Array in _blds:
		if poly.is_empty():
			continue
		var out: PackedVector2Array = cell_of.call(poly[0])["blds"]
		for j in range(poly.size()):
			out.append(poly[j])
			out.append(poly[(j + 1) % poly.size()])
	for r: Dictionary in _roads:
		var pts: PackedVector2Array = r["pts"]
		var kind := "paths" if (not r["drive"] or r["pv"]) else ("major" if float(r["w"]) >= 9.0 else "minor")
		for j in range(pts.size() - 1):
			var out: PackedVector2Array = cell_of.call((pts[j] + pts[j + 1]) * 0.5)[kind]
			out.append(pts[j])
			out.append(pts[j + 1])

## the lines round `at` (in the city's coordinates: "at" in the result is where they were
## gathered, for knowing when to gather again)
func _map_gather() -> Dictionary:
	if _map_cells.is_empty():
		_map_build_cells()
	var at := _view_pos
	var reach := MAP_R * 1.45 + MAP_MOVE   # the map's corners, wherever the car turns
	# (plain local arrays: appending through `dict[k] as PackedVector2Array` goes to a copy)
	var blds := PackedVector2Array()
	var paths := PackedVector2Array()
	var minor := PackedVector2Array()
	var major := PackedVector2Array()
	var c0 := Vector2i(floori((at.x - reach) / MAP_CELL), floori((at.y - reach) / MAP_CELL))
	var c1 := Vector2i(floori((at.x + reach) / MAP_CELL), floori((at.y + reach) / MAP_CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell: Dictionary = _map_cells.get(Vector2i(cx, cz), {})
			if cell.is_empty():
				continue
			blds.append_array(cell["blds"])
			paths.append_array(cell["paths"])
			minor.append_array(cell["minor"])
			major.append_array(cell["major"])
	var limits: Array = []
	for ring: PackedVector2Array in _boundary:
		var pts := ring.duplicate()
		pts.append(ring[0])
		limits.append(pts)
	var places: Array = []
	for poi: Array in _pois:
		var d: Vector2 = (poi[0] as Vector2) - at
		if absf(d.x) < reach and absf(d.y) < reach:
			places.append([poi[0], poi[1]])
	return {"at": at, "blds": blds, "paths": paths, "minor": minor, "major": major,
		"limits": limits, "places": places}

## the minimap: streets and building outlines round the car, heading up
func _draw_map() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_map_inner()
	_prof["minimap"] = int(_prof.get("minimap", 0)) + Time.get_ticks_usec() - t0

func _draw_map_inner() -> void:
	var sz := _map.size
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color(bg, 0.72))
	if _map_lines.is_empty() or (_map_lines["at"] as Vector2).distance_to(_view_pos) > MAP_MOVE:
		_map_lines = _map_gather()
	var at := Vector2.ZERO   # the lines are in the city's own coordinates
	var s := sz.x * 0.5 / MAP_R
	# heading up round the middle of the map, the car in the middle
	_map.draw_set_transform_matrix(Transform2D(-PI * 0.5 - _view_yaw, Vector2(s, s), 0.0, sz * 0.5)
		* Transform2D(0.0, -_view_pos))
	if not (_map_lines["blds"] as PackedVector2Array).is_empty():
		# plain one-pixel lines: wide ones are rebuilt as strips every frame, and the outlines
		# are most of the map's lines
		_map.draw_multiline(_map_lines["blds"], Color(ink, 0.3), -1.0)
	if not (_map_lines["paths"] as PackedVector2Array).is_empty():
		_map.draw_multiline(_map_lines["paths"], Color(ink, 0.3), 1.0 / s)
	if not (_map_lines["minor"] as PackedVector2Array).is_empty():
		_map.draw_multiline(_map_lines["minor"], Color(ink, 0.75), 2.0 / s)
	if not (_map_lines["major"] as PackedVector2Array).is_empty():
		_map.draw_multiline(_map_lines["major"], Palette.col("warn"), 3.0 / s)
	for pts: PackedVector2Array in _map_lines["limits"]:
		_map.draw_polyline(pts, Color(Palette.col("accent"), 0.8), 1.5 / s)
	var rim := _bounds.grow(-EDGE)
	if not rim.grow(-MAP_R * 1.5).has_point(_view_pos):   # the map's edge, when it is in view
		_map.draw_polyline(PackedVector2Array([rim.position - at, Vector2(rim.end.x, rim.position.y) - at, rim.end - at,
			Vector2(rim.position.x, rim.end.y) - at, rim.position - at]), Palette.col("hazard"), 3.0 / s)
	if _auto and _ap_pts.size() > 1:
		var route := PackedVector2Array()
		for p in _ap_pts:
			route.append(p - at)
		_map.draw_polyline(route, Color(Palette.col("friend"), 0.8), 1.5 / s)
	for pl: Array in _map_lines["places"]:
		_map.draw_circle(pl[0], 1.8 / s, Palette.col(pl[1]))
	if _traffic != null:
		for c in _traffic.cars:
			if c.alive:
				_map.draw_circle(c.pos - at, 1.9 / s, Color(ink, 0.8))
	if _walking:
		_map.draw_rect(Rect2(_car_at - at - Vector2(3, 3) / s, Vector2(6, 6) / s), Palette.col("warn"))
	if _dest_on:
		_map.draw_circle(_dest - at, 6.0 / s, Palette.col("accent"))
		_map.draw_arc(_dest - at, 11.0 / s, 0.0, TAU, 24, Color(Palette.col("accent"), 0.6), 1.5 / s)
	_map.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var c := sz * 0.5
	_map.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 5), c + Vector2(-5, 5)]), Palette.col("player"))
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color(ink, 0.5), false, 1.0)

## ---- touch: one stick that stays put on the right -- thumb on it, drag up for gas, down
## to brake (and reverse once stopped), sideways to steer; let go and it centres. Grabbing
## it takes the wheel back from autodrive. ----------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _loaded or not _film.is_empty():
		return
	if _picker != null:   # everything goes to the picker while it is open
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and not Flow.pointer_over_hud():
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_pick_tap(mb.position)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_turn(1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_turn(-1)
		return
	var key := event as InputEventKey
	if key != null and not key.echo:
		# the view and the car's switches, straight off the keyboard: none of them drives the
		# car, so the bots (which play through PInput) have no use for them
		if key.keycode == KEY_H:
			_horn_held = key.pressed
			return
		if key.pressed:
			match key.keycode:
				KEY_C:
					_set_cockpit(not _cockpit)
					return
				KEY_Q:
					_set_blink(0 if _blink == -1 else -1)
					return
				KEY_E:
					_set_blink(0 if _blink == 1 else 1)
					return
				KEY_L:
					_set_lights(not _lights_on)
					return
				KEY_F:
					_toggle_walk()
					return
				KEY_P:
					_toggle_perf()
					return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not Flow.pointer_over_hud():
			if _auto and _cross_showing() and not _cross["chosen"]:
				for i in range((_cross["ways"] as Array).size()):
					if _cross_rect(i, (_cross["ways"] as Array).size()).grow(3).has_point(mb.position):
						_cross_pick(i)
						return
			if PERF_RECT.has_point(mb.position):
				_toggle_perf()
			elif _trace_view and TRACE_SAVE.grow(3).has_point(mb.position):
				_save_log()
			elif _trace_view and TRACE_RECT.has_point(mb.position):
				pass   # (a tap on the map is not a tap on the road under it)
			elif AUTO_BTN.grow(4).has_point(mb.position):
				if not _walking:
					_set_auto(not _auto)
			elif GOTO_BTN.grow(4).has_point(mb.position):
				_open_picker.call_deferred()   # after this click, so it does not hit the list
			elif NIGHT_BTN.grow(4).has_point(mb.position):
				_set_night(not _night)
			elif VIEW_BTN.grow(4).has_point(mb.position):
				_set_cockpit(not _cockpit)
			elif LIGHTS_BTN.grow(2).has_point(mb.position):
				_set_lights(not _lights_on)
			elif WALK_BTN.grow(2).has_point(mb.position):
				_toggle_walk()
			elif ASSIST_BTN.grow(4).has_point(mb.position):
				_assist = not _assist
				_show_banner("driving assist " + ("on" if _assist else "off"), 1.2)
				Probe.event("assist", {"on": _assist})
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _woke:   # some browsers grant the wake lock only after a tap
			_woke = true
			_keep_screen_on(true)
		_touch_seen = true
		if t.pressed:
			if AUTO_BTN.grow(4).has_point(t.position) or GOTO_BTN.grow(4).has_point(t.position) \
					or ASSIST_BTN.grow(4).has_point(t.position) or NIGHT_BTN.grow(4).has_point(t.position) \
					or VIEW_BTN.grow(4).has_point(t.position) or LIGHTS_BTN.grow(2).has_point(t.position) \
					or WALK_BTN.grow(2).has_point(t.position) \
					or (_trace_view and TRACE_RECT.has_point(t.position)) \
					or t.position.y < 36.0:
				return   # the button (via its emulated click) and the shell's menu/sound row
			if _stick_id < 0 and t.position.distance_to(STICK_C) <= STICK_GRAB:
				_stick_id = t.index
				_stick = ((t.position - STICK_C) / STICK_R).limit_length(1.0)
				if _auto:
					_set_auto(false)
		elif t.index == _stick_id:
			_stick_id = -1
			_stick = Vector2.ZERO
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if dr.index == _stick_id:
			_stick = ((dr.position - STICK_C) / STICK_R).limit_length(1.0)
