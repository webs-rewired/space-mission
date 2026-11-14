# Makes the three "places" of the game as Godot scenes you can open and edit:
#   scenes/places/clean_room.tscn                  where the probe is built (like JPL's Spacecraft Assembly Facility, High Bay 1)
#   scenes/places/vehicle_assembly_building.tscn   where the rocket is stacked (like the VAB at Kennedy Space Center)
#   scenes/places/launch_complex.tscn              where it launches (like Launch Complex 39B)
# and the pictures they use (assets/places/*.png).
# Run from the project folder:  python3 tools/make_places.py
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np

os.makedirs("scenes/places", exist_ok=True)
os.makedirs("assets/places", exist_ok=True)
rng = np.random.default_rng(3)

# ---------------------------------------------------------------------------
# Pictures
# ---------------------------------------------------------------------------
def noise(size, strength, blur=0.0):
    grain = rng.normal(0, strength, (size, size)).astype(np.float32)
    image = Image.fromarray(np.clip(grain + 128, 0, 255).astype(np.uint8))
    if blur:
        image = image.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(image).astype(np.float32) - 128

def save(name, array):
    Image.fromarray(np.clip(array, 0, 255).astype(np.uint8)).save("assets/places/%s.png" % name)

def heading_font(size):
    for path in ["assets/fonts/BarlowCondensed-SemiBold.ttf"]:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()

def make_pictures():
    size = 512
    # The wall of air filters in a clean room: square filter panels in metal frames (one picture = 2 x 2 panels)
    filters = np.full((size, size, 3), 236.0)
    filters += noise(size, 3)[..., None]
    for edge in range(0, size, size // 2):
        filters[edge:edge + 7, :, :] = 168
        filters[:, edge:edge + 7, :] = 168
        filters[edge + 7:edge + 10, :, :] = 250
    for line in range(14, size, 9):   # the pleats of the filter paper
        filters[:, line:line + 1, :] -= 7
    save("filter_wall", filters)

    # Plain clean-room wall panels: big white sheets with thin seams
    panels = np.full((size, size, 3), 238.0) + noise(size, 2)[..., None]
    panels[:3, :, :] = 205
    panels[:, :3, :] = 205
    save("wall_panels", panels)

    # Glossy poured floor: nearly even, with faint scuffs
    floor = np.full((size, size, 3), 196.0) + noise(size, 2)[..., None] + noise(size, 18, 30)[..., None] * 0.5
    save("clean_floor", floor)

    # Yellow and black warning tape
    tape = np.zeros((64, 64, 3))
    for y in range(64):
        for x in range(64):
            tape[y, x] = (242, 196, 30) if ((x + y) // 16) % 2 == 0 else (22, 22, 22)
    save("warning_tape", tape)

    # Ribbed steel sheet for the walls of the assembly building
    ribs = np.zeros((size, size, 3))
    wave = (np.sin(np.arange(size) / size * math.tau * 16) * 0.5 + 0.5)[None, :, None]
    ribs[:] = 150 + wave * 38
    ribs += noise(size, 4)[..., None] + noise(size, 20, 40)[..., None] * 0.6
    ribs[:4, :, :] -= 40
    save("steel_sheet", ribs)

    # Concrete: for floors, the pad and roads
    concrete = np.full((size, size, 3), 128.0) + noise(size, 9)[..., None] + noise(size, 30, 24)[..., None] * 0.7
    concrete[:3, :, :] -= 30   # the joints between slabs
    concrete[:, :3, :] -= 30
    save("concrete", concrete)

    # River gravel on the crawlerway (the real one is Alabama river rock)
    gravel = np.zeros((size, size, 3))
    base = noise(size, 26) + noise(size, 30, 2) * 2.0
    gravel[..., 0] = 170 + base
    gravel[..., 1] = 158 + base
    gravel[..., 2] = 138 + base
    save("gravel", gravel)

    # The United States flag (the VAB has one of the largest ever painted: 64 m tall)
    flag = Image.new("RGB", (760, 400), (255, 255, 255))
    draw = ImageDraw.Draw(flag)
    stripe = 400 / 13
    for index in range(13):
        if index % 2 == 0:
            draw.rectangle([0, index * stripe, 760, (index + 1) * stripe], fill=(178, 34, 52))
    draw.rectangle([0, 0, 304, stripe * 7], fill=(60, 59, 110))
    for row in range(9):
        count = 6 if row % 2 == 0 else 5
        for column in range(count):
            x = 25 + column * 50.6 + (0 if row % 2 == 0 else 25.3)
            y = 21 + row * 21.5
            points = []
            for corner in range(10):
                radius = 9 if corner % 2 == 0 else 3.6
                angle = -math.pi / 2 + corner * math.pi / 5
                points.append((x + math.cos(angle) * radius, y + math.sin(angle) * radius))
            draw.polygon(points, fill=(255, 255, 255))
    flag.save("assets/places/flag.png")

    # Signs
    def sign(name, lines, width=1024, height=256, back=(16, 34, 66), ink=(240, 244, 250)):
        image = Image.new("RGB", (width, height), back)
        draw = ImageDraw.Draw(image)
        draw.rectangle([6, 6, width - 7, height - 7], outline=ink, width=4)
        y = 26 if len(lines) > 1 else 70
        for text, size in lines:
            font = heading_font(size)
            draw.text(((width - draw.textlength(text, font=font)) / 2, y), text, font=font, fill=ink)
            y += size + 12
        image.save("assets/places/%s.png" % name)
    sign("sign_clean_room", [("SPACECRAFT ASSEMBLY FACILITY", 84), ("HIGH BAY 1   |   CLEAN ROOM, CLASS 10,000", 46)])
    sign("sign_vab", [("VEHICLE ASSEMBLY BUILDING", 92), ("HIGH BAY 3", 60)])
    sign("sign_pad", [("LAUNCH COMPLEX 39B", 110)], back=(232, 232, 228), ink=(24, 30, 44))

# ---------------------------------------------------------------------------
# A tiny scene writer
# ---------------------------------------------------------------------------
def number(value):
    text = "%.5f" % value
    text = text.rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text

def vector(values):
    return "Vector3(%s)" % ", ".join(number(v) for v in values)

def color(values):
    values = list(values) + [1.0] * (4 - len(values))
    return "Color(%s)" % ", ".join(number(v) for v in values)

class Scene:
    def __init__(self, root_name, root_type="Node3D"):
        self.externals, self.subs, self.nodes, self.cache = [], [], [], {}
        self.root_name, self.root_type, self.names = root_name, root_type, {}

    def external(self, kind, path):
        key = (kind, path)
        if key not in self.cache:
            identity = "ext_%d" % (len(self.externals) + 1)
            self.externals.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, identity))
            self.cache[key] = 'ExtResource("%s")' % identity
        return self.cache[key]

    def sub(self, kind, **properties):
        key = (kind, tuple(sorted(properties.items())))
        if key not in self.cache:
            identity = "%s_%d" % (kind.lower(), len(self.subs) + 1)
            lines = ['[sub_resource type="%s" id="%s"]' % (kind, identity)]
            lines += ["%s = %s" % (name, value) for name, value in properties.items()]
            self.subs.append("\n".join(lines))
            self.cache[key] = 'SubResource("%s")' % identity
        return self.cache[key]

    def material(self, tint, rough=0.8, metal=0.0, picture=None, tile=None, glow=None, glow_strength=1.0, clear=False, unlit=False, both_sides=False):
        properties = {"albedo_color": color(tint), "roughness": number(rough), "metallic": number(metal)}
        if picture:
            properties["albedo_texture"] = self.external("Texture2D", "res://assets/places/%s.png" % picture)
            if tile:   # the picture repeats every "tile" meters, whatever the size of the thing it's on
                properties["uv1_scale"] = vector([1.0 / tile] * 3)
                properties["uv1_triplanar"] = "true"
                properties["uv1_world_triplanar"] = "true"
        if glow:
            properties["emission_enabled"] = "true"
            properties["emission"] = color(glow)
            properties["emission_energy_multiplier"] = number(glow_strength)
        if clear:
            properties["transparency"] = "1"
        if unlit:
            properties["shading_mode"] = "0"
        if both_sides:
            properties["cull_mode"] = "2"
        return self.sub("StandardMaterial3D", **properties)

    def node(self, name, kind, parent=".", **properties):
        count = self.names.get((parent, name), 0) + 1
        self.names[(parent, name)] = count
        if count > 1:
            name = "%s%d" % (name, count)
        lines = ['[node name="%s" type="%s" parent="%s"]' % (name, kind, parent)]
        lines += ["%s = %s" % (key, value) for key, value in properties.items()]
        self.nodes.append("\n".join(lines))
        return name if parent == "." else parent + "/" + name

    def transform(self, place, yaw=0.0, pitch=0.0, roll=0.0, size=(1, 1, 1)):
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        cx, sx = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
        cz, sz = math.cos(math.radians(roll)), math.sin(math.radians(roll))
        turn_y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
        turn_x = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
        turn_z = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
        basis = turn_y @ turn_x @ turn_z @ np.diag(size)
        return "Transform3D(%s)" % ", ".join(number(v) for v in list(basis.flatten()) + list(place))

    def group(self, name, parent=".", place=(0, 0, 0), yaw=0.0):
        return self.node(name, "Node3D", parent, transform=self.transform(place, yaw))

    def shape(self, name, mesh, material, place, parent=".", yaw=0.0, pitch=0.0, roll=0.0, shadow=True):
        properties = {"transform": self.transform(place, yaw, pitch, roll), "mesh": mesh, "surface_material_override/0": material}
        if not shadow:
            properties["cast_shadow"] = "0"
        return self.node(name, "MeshInstance3D", parent, **properties)

    def box(self, name, size, place, material, parent=".", yaw=0.0, pitch=0.0, roll=0.0, shadow=True):
        return self.shape(name, self.sub("BoxMesh", size=vector(size)), material, place, parent, yaw, pitch, roll, shadow)

    def tube(self, name, radius, height, place, material, parent=".", top_radius=None, pitch=0.0, roll=0.0, yaw=0.0, sides=16):
        mesh = self.sub("CylinderMesh", top_radius=number(radius if top_radius is None else top_radius), bottom_radius=number(radius), height=number(height), radial_segments=str(sides), rings="1")
        return self.shape(name, mesh, material, place, parent, yaw, pitch, roll)

    def ball(self, name, radius, place, material, parent="."):
        mesh = self.sub("SphereMesh", radius=number(radius), height=number(radius * 2), radial_segments="24", rings="12")
        return self.shape(name, mesh, material, place, parent)

    # A flat sheet that only shows from the side it faces, so the camera can look in through the walls from outside
    def sheet(self, name, size, place, material, parent=".", yaw=0.0, pitch=0.0):
        return self.shape(name, self.sub("QuadMesh", size="Vector2(%s, %s)" % (number(size[0]), number(size[1]))), material, place, parent, yaw, pitch, shadow=False)

    def beam_between(self, name, start, end, thickness, material, parent="."):
        start, end = np.array(start, float), np.array(end, float)
        along = end - start
        length = float(np.linalg.norm(along))
        yaw = math.degrees(math.atan2(along[0], along[2]))
        pitch = -math.degrees(math.asin(along[1] / length))
        return self.box(name, (thickness, thickness, length), tuple((start + end) / 2), material, parent, yaw, pitch, shadow=False)

    def write(self, path, comment):
        text = "[gd_scene load_steps=%d format=3]\n\n" % (len(self.externals) + len(self.subs) + 1)
        text += "\n".join(self.externals) + "\n\n" + "\n\n".join(self.subs) + "\n\n"
        text += '[node name="%s" type="%s"]\n' % (self.root_name, self.root_type)
        text += 'editor_description = "%s"\n\n' % comment
        text += "\n\n".join(self.nodes) + "\n"
        open(path, "w").write(text)
        print(path, len(self.nodes), "nodes")

# A worker in a clean-room "bunny suit" (or a hard hat and vest): simple, but it shows how big everything is
def worker(scene, parent, place, yaw, suit, head, extra=None):
    person = scene.group("Worker", parent, place, yaw)
    scene.shape("Body", scene.sub("CapsuleMesh", radius="0.24", height="1.25"), suit, (0, 1.0, 0), person)
    scene.shape("Legs", scene.sub("CapsuleMesh", radius="0.2", height="0.9"), suit, (0, 0.45, 0), person)
    scene.ball("Head", 0.15, (0, 1.72, 0), head, person)
    scene.shape("ArmLeft", scene.sub("CapsuleMesh", radius="0.075", height="0.72"), suit, (-0.31, 1.12, 0.08), person, pitch=-18)
    scene.shape("ArmRight", scene.sub("CapsuleMesh", radius="0.075", height="0.72"), suit, (0.31, 1.12, 0.08), person, pitch=-30)
    if extra:
        scene.tube("Helmet", 0.17, 0.12, (0, 1.84, 0), extra, person, top_radius=0.12)

# ---------------------------------------------------------------------------
# 1. The clean room
# ---------------------------------------------------------------------------
def clean_room():
    scene = Scene("CleanRoom")
    half, floor_y, top = 80.0, -3.0, 37.0
    height = top - floor_y
    middle = (top + floor_y) / 2

    environment = scene.sub("Environment", background_mode="1", background_color=color((0.5, 0.53, 0.57)), ambient_light_source="2",
        ambient_light_color=color((0.93, 0.95, 1.0)), ambient_light_energy="0.2", tonemap_mode="2", tonemap_white="4.0",
        ssao_enabled="true", glow_enabled="true", glow_hdr_threshold="1.2", glow_intensity="0.5")
    scene.node("WorldEnvironment", "WorldEnvironment", environment=environment)
    scene.node("CeilingLight", "DirectionalLight3D", transform=scene.transform((0, 30, 0), 25, -62), light_energy="0.5", shadow_enabled="true", directional_shadow_max_distance="120.0", shadow_blur="2.0")
    scene.node("FillLight", "DirectionalLight3D", transform=scene.transform((0, 30, 0), -150, -35), light_energy="0.15")

    floor = scene.material((0.62, 0.64, 0.67), 0.22, 0.05, "clean_floor", 6.0)
    scene.shape("Floor", scene.sub("PlaneMesh", size="Vector2(%s, %s)" % (half * 2, half * 2)), floor, (0, floor_y, 0), shadow=False)
    walls = scene.group("Walls")
    plain = scene.material((0.7, 0.72, 0.75), 0.7, 0.0, "wall_panels", 4.0)
    filters = scene.material((0.72, 0.74, 0.78), 0.6, 0.0, "filter_wall", 2.4, glow=(0.9, 0.95, 1.0), glow_strength=0.05)
    scene.sheet("FilterWall", (half * 2, height), (0, middle, -half), filters, walls, 0)       # the whole wall blows filtered air across the room
    scene.sheet("DoorWall", (half * 2, height), (0, middle, half), plain, walls, 180)
    scene.sheet("GalleryWall", (half * 2, height), (-half, middle, 0), plain, walls, 90)
    scene.sheet("SignWall", (half * 2, height), (half, middle, 0), plain, walls, -90)
    ceiling = scene.material((0.86, 0.87, 0.9), 0.9)
    scene.sheet("Ceiling", (half * 2, half * 2), (0, top, 0), ceiling, walls, 0, 90)

    # Rows of light panels in the ceiling
    lamp = scene.material((1, 1, 1), 0.5, glow=(1.0, 0.98, 0.95), glow_strength=2.2)
    lights = scene.group("CeilingLights")
    for row in range(-3, 4):
        for column in range(-3, 4):
            scene.box("LightPanel", (9.0, 0.2, 2.2), (column * 21.0, top - 0.15, row * 21.0), lamp, lights, shadow=False)

    # The visitors' gallery: a long window high on one wall, where people watch spacecraft being built
    gallery = scene.group("VisitorGallery", ".", (-half + 0.2, 9.0, 0), 90)
    scene.box("Frame", (46.0, 4.6, 0.3), (0, 0, 0), scene.material((0.55, 0.58, 0.62), 0.4, 0.6), gallery, shadow=False)
    scene.box("Glass", (45.0, 3.8, 0.34), (0, 0, 0), scene.material((0.1, 0.16, 0.22), 0.08, 0.2, glow=(0.25, 0.3, 0.36), glow_strength=0.5), gallery, shadow=False)

    # The big door spacecraft leave through, and the sign
    door = scene.group("RollUpDoor", ".", (18.0, floor_y + 9.0, half - 0.2), 180)
    scene.box("Door", (16.0, 18.0, 0.3), (0, 0, 0), scene.material((0.8, 0.82, 0.85), 0.5, 0.3, "steel_sheet", 2.0), door, pitch=0, shadow=False)
    scene.box("DoorFrame", (17.2, 19.0, 0.2), (0, 0.3, -0.1), scene.material((0.95, 0.75, 0.1), 0.6), door, shadow=False)
    scene.sheet("Sign", (30.0, 7.5), (half - 0.15, 22.0, 0), scene.material((1, 1, 1), 0.7, picture="sign_clean_room"), ".", -90)
    scene.sheet("Flag", (15.2, 8.0), (half - 0.15, 22.0, -34.0), scene.material((1, 1, 1), 0.8, picture="flag"), ".", -90)

    # The overhead crane that lifts spacecraft: two rails, a yellow bridge, a trolley and a hook
    crane = scene.group("OverheadCrane")
    yellow = scene.material((0.95, 0.72, 0.08), 0.5, 0.3)
    steel = scene.material((0.45, 0.47, 0.5), 0.45, 0.7)
    for side in (-1, 1):
        scene.box("Rail", (1.2, 1.4, half * 2), (side * (half - 2.0), top - 5.0, 0), steel, crane, shadow=False)
    scene.box("Bridge", (half * 2 - 4.0, 2.2, 2.6), (0, top - 4.2, -24.0), yellow, crane)
    scene.box("Trolley", (4.0, 1.6, 3.4), (14.0, top - 6.0, -24.0), steel, crane)
    scene.tube("Cable", 0.06, 9.0, (14.0, top - 11.2, -24.0), steel, crane, sides=6)
    scene.box("HookBlock", (1.0, 1.4, 0.6), (14.0, top - 16.2, -24.0), yellow, crane)

    # Warning tape around the work area, and the test stand's turntable is added by the builder script
    tape = scene.material((1, 1, 1), 0.5, picture="warning_tape", tile=1.0)
    work_area = scene.group("WorkArea")
    for side in (-1, 1):
        scene.box("Tape", (24.0, 0.02, 0.3), (0, floor_y + 0.011, side * 12.0), tape, work_area, shadow=False)
        scene.box("Tape", (0.3, 0.02, 24.0), (side * 12.0, floor_y + 0.011, 0), tape, work_area, shadow=False)

    # Rolling work platforms, tool carts and test equipment racks
    blue = scene.material((0.16, 0.3, 0.55), 0.5, 0.4)
    white = scene.material((0.9, 0.91, 0.93), 0.4, 0.1)
    for index, (x, z, yaw) in enumerate([(-17.0, -13.0, 30), (16.0, -17.0, -40)]):
        stand = scene.group("WorkPlatform", ".", (x, floor_y, z), yaw)
        scene.box("Deck", (4.0, 0.15, 2.4), (0, 3.0, 0), steel, stand)
        for corner_x in (-1.9, 1.9):
            for corner_z in (-1.1, 1.1):
                scene.tube("Leg", 0.06, 4.1, (corner_x, 2.05, corner_z), yellow, stand, sides=6)
        scene.box("Rail", (4.0, 0.06, 0.06), (0, 4.1, 1.1), yellow, stand, shadow=False)
        scene.box("Rail", (4.0, 0.06, 0.06), (0, 4.1, -1.1), yellow, stand, shadow=False)
        scene.box("Stairs", (1.0, 0.12, 4.4), (2.6, 1.5, 0), steel, stand, pitch=43)
    for x, z, yaw in [(-14.0, 15.0, 20), (19.0, 11.0, -70), (-22.0, 2.0, 95)]:
        cart = scene.group("ToolCart", ".", (x, floor_y, z), yaw)
        scene.box("Cabinet", (1.6, 1.0, 0.8), (0, 0.65, 0), blue, cart)
        scene.box("Top", (1.7, 0.06, 0.9), (0, 1.18, 0), steel, cart)
    for index in range(5):
        rack = scene.group("TestRack", ".", (-36.0 + index * 1.3, floor_y, -half + 3.0))
        scene.box("Cabinet", (1.2, 2.2, 1.0), (0, 1.1, 0), white, rack)
        scene.box("Screen", (0.9, 0.5, 0.04), (0, 1.6, 0.51), scene.material((0.05, 0.1, 0.12), 0.2, glow=(0.2, 0.9, 0.7), glow_strength=0.8), rack, shadow=False)

    # The team, in "bunny suits" so no dust or hair reaches the spacecraft
    suit = scene.material((0.95, 0.96, 0.98), 0.85)
    hood = scene.material((0.93, 0.95, 0.98), 0.8)
    team = scene.group("Team")
    for x, z, yaw in [(-15.5, -11.0, 120), (-13.0, 14.0, 200), (17.5, -15.0, -60), (20.5, 12.0, -100), (-21.0, 3.5, 60), (14.0, 16.0, 215), (-34.0, -74.0, 180)]:
        worker(scene, team, (x, floor_y, z), yaw, suit, hood)
    scene.write("scenes/places/clean_room.tscn", "The clean room where the probe is built, like the Spacecraft Assembly Facility at NASA's Jet Propulsion Laboratory, where Voyager, Cassini and the Mars rovers were put together. Made by tools/make_places.py.")

# ---------------------------------------------------------------------------
# 2. The Vehicle Assembly Building
# ---------------------------------------------------------------------------
def assembly_building():
    scene = Scene("VehicleAssemblyBuilding")
    half, floor_y, top = 190.0, 1.0, 215.0
    height = top - floor_y
    middle = (top + floor_y) / 2
    door_width, door_height = 60.0, 180.0

    environment = scene.sub("Environment", background_mode="1", background_color=color((0.09, 0.1, 0.12)), ambient_light_source="2",
        ambient_light_color=color((0.75, 0.78, 0.86)), ambient_light_energy="0.5", tonemap_mode="3", glow_enabled="true",
        glow_hdr_threshold="1.1", glow_intensity="0.7", fog_enabled="true", fog_light_color=color((0.55, 0.58, 0.62)), fog_density="0.0009")
    scene.node("WorldEnvironment", "WorldEnvironment", environment=environment)
    scene.node("HighBayLights", "DirectionalLight3D", transform=scene.transform((0, 200, 0), 20, -70), light_color=color((1.0, 0.93, 0.82)), light_energy="0.9", shadow_enabled="true", directional_shadow_max_distance="500.0")
    scene.node("Daylight", "DirectionalLight3D", transform=scene.transform((0, 100, 0), 180, -22), light_color=color((0.8, 0.9, 1.0)), light_energy="0.55")   # in through the open door

    floor = scene.material((0.62, 0.62, 0.6), 0.85, 0.0, "concrete", 12.0)
    scene.shape("Floor", scene.sub("PlaneMesh", size="Vector2(%s, %s)" % (half * 2, half * 2)), floor, (0, floor_y, 0), shadow=False)
    sheet = scene.material((0.62, 0.66, 0.7), 0.6, 0.35, "steel_sheet", 14.0)
    walls = scene.group("Walls")
    scene.sheet("BackWall", (half * 2, height), (0, middle, -half), sheet, walls, 0)
    scene.sheet("LeftWall", (half * 2, height), (-half, middle, 0), sheet, walls, 90)
    scene.sheet("RightWall", (half * 2, height), (half, middle, 0), sheet, walls, -90)
    side_width = half - door_width / 2
    for side in (-1, 1):
        scene.sheet("DoorWall", (side_width, height), (side * (door_width / 2 + side_width / 2), middle, half), sheet, walls, 180)
    scene.sheet("AboveDoor", (door_width, top - floor_y - door_height), (0, floor_y + door_height + (top - floor_y - door_height) / 2, half), sheet, walls, 180)
    scene.sheet("Roof", (half * 2, half * 2), (0, top, 0), scene.material((0.2, 0.22, 0.25), 0.9), walls, 0, 90)
    # The open door: 139 m tall on the real building, the tallest doors in the world. Daylight pours in.
    scene.sheet("Sky", (door_width, door_height), (0, floor_y + door_height / 2, half + 2.0), scene.material((0.75, 0.87, 1.0), 1.0, glow=(0.75, 0.88, 1.0), glow_strength=2.4, unlit=True), walls, 180)
    scene.sheet("LightOnFloor", (door_width * 1.1, 150.0), (0, floor_y + 0.06, half - 78.0), scene.material((1.0, 1.0, 1.0, 0.16), 1.0, clear=True, unlit=True), walls, 0, -90)

    # The steel skeleton: columns up the walls and girders around them
    girder = scene.material((0.34, 0.37, 0.42), 0.5, 0.6)
    frame = scene.group("SteelFrame")
    for step in range(-4, 5):
        offset = step * 42.0
        scene.box("Column", (3.0, height, 3.0), (offset, middle, -half + 1.5), girder, frame, shadow=False)
        scene.box("Column", (3.0, height, 3.0), (-half + 1.5, middle, offset), girder, frame, shadow=False)
        scene.box("Column", (3.0, height, 3.0), (half - 1.5, middle, offset), girder, frame, shadow=False)
    for level in range(1, 8):
        y = floor_y + level * 27.0
        scene.box("Girder", (half * 2, 2.0, 2.4), (0, y, -half + 1.5), girder, frame, shadow=False)
        scene.box("Girder", (2.4, 2.0, half * 2), (-half + 1.5, y, 0), girder, frame, shadow=False)
        scene.box("Girder", (2.4, 2.0, half * 2), (half - 1.5, y, 0), girder, frame, shadow=False)
    for step in range(-3, 4):   # roof trusses
        scene.box("RoofTruss", (half * 2, 5.0, 1.6), (0, top - 3.0, step * 55.0), girder, frame, shadow=False)

    # High-bay lamps
    lamp = scene.material((1, 1, 1), 0.5, glow=(1.0, 0.9, 0.7), glow_strength=4.0)
    lamps = scene.group("Lamps")
    for row in range(-3, 4):
        for column in range(-3, 4):
            scene.box("Lamp", (3.0, 0.6, 3.0), (column * 50.0, top - 6.5, row * 50.0 + 25.0), lamp, lamps, shadow=False)

    # The work platforms that fold out around the rocket at every level
    yellow = scene.material((0.92, 0.7, 0.1), 0.55, 0.3)
    deck = scene.material((0.5, 0.52, 0.55), 0.6, 0.5)
    tower = scene.group("PlatformTower", ".", (0, floor_y, -62.0))
    for corner_x in (-26.0, 26.0):
        for corner_z in (-12.0, 12.0):
            scene.box("Post", (2.2, 150.0, 2.2), (corner_x, 75.0, corner_z), girder, tower)
    for level in range(1, 7):
        y = level * 23.0
        scene.box("Deck", (56.0, 1.0, 26.0), (0, y, 0), deck, tower)
        scene.box("Arm", (30.0, 0.8, 22.0), (0, y, 23.0), yellow, tower)          # the part that reaches out to the rocket
        scene.box("Railing", (56.0, 0.25, 0.25), (0, y + 2.2, 13.0), yellow, tower, shadow=False)
        scene.beam_between("Brace", (-26.0, y - 23.0, 12.0), (26.0, y, 12.0), 0.8, girder, tower)

    # Two bridge cranes under the roof (the real ones lift 295 tonnes each)
    crane = scene.group("BridgeCranes")
    for index, z in enumerate((-40.0, 70.0)):
        scene.box("Bridge", (half * 2 - 8.0, 6.0, 7.0), (0, top - 14.0, z), yellow, crane)
        scene.box("Trolley", (12.0, 4.0, 9.0), (-70.0 + index * 150.0, top - 18.5, z), girder, crane)
        scene.tube("Cable", 0.3, 40.0, (-70.0 + index * 150.0, top - 40.0, z), girder, crane, sides=6)
        scene.box("Hook", (4.0, 5.0, 2.0), (-70.0 + index * 150.0, top - 62.0, z), yellow, crane)

    # The flag and the sign, and yellow lines on the floor out to the door
    scene.sheet("Flag", (121.6, 64.0), (-78.0, 150.0, -half + 3.4), scene.material((1, 1, 1), 0.8, picture="flag"), ".", 0)
    scene.sheet("Sign", (88.0, 22.0), (86.0, 176.0, -half + 3.4), scene.material((1, 1, 1), 0.7, picture="sign_vab"), ".", 0)
    paint = scene.material((0.95, 0.78, 0.12), 0.7)
    lines = scene.group("FloorLines")
    for side in (-1, 1):
        scene.box("CrawlerLine", (1.0, 0.04, half + 20.0), (side * 22.0, floor_y + 0.03, half / 2 - 10.0), paint, lines, shadow=False)
    gravel = scene.material((1, 1, 1), 1.0, picture="gravel", tile=5.0)
    for side in (-1, 1):
        scene.box("CrawlerTrack", (12.0, 0.04, half), (side * 14.0, floor_y + 0.02, half / 2), gravel, lines, shadow=False)

    # People and trucks, to show the size of the place (the building is 160 m tall)
    vest = scene.material((0.95, 0.5, 0.1), 0.8)
    skin = scene.material((0.8, 0.62, 0.5), 0.8)
    helmet = scene.material((0.96, 0.96, 0.96), 0.4)
    crew = scene.group("Crew")
    for x, z, yaw in [(34.0, 30.0, -120), (36.0, 31.5, 60), (-40.0, 44.0, 140), (-28.0, 60.0, 20), (48.0, -20.0, -80), (-52.0, -6.0, 100), (8.0, 96.0, 180), (10.5, 97.0, 150)]:
        worker(scene, crew, (x, floor_y, z), yaw, vest, skin, helmet)
    white = scene.material((0.92, 0.93, 0.95), 0.4, 0.2)
    tyre = scene.material((0.08, 0.08, 0.09), 0.9)
    for x, z, yaw in [(60.0, 40.0, 25), (-66.0, 20.0, -70)]:
        truck = scene.group("Truck", ".", (x, floor_y, z), yaw)
        scene.box("Cab", (2.4, 2.2, 2.4), (0, 1.9, 3.2), white, truck)
        scene.box("Bed", (2.5, 1.9, 6.0), (0, 2.0, -1.2), scene.material((0.2, 0.35, 0.6), 0.5, 0.3), truck)
        for wheel_x in (-1.2, 1.2):
            for wheel_z in (-3.0, 0.0, 3.0):
                scene.tube("Wheel", 0.55, 0.4, (wheel_x, 0.55, wheel_z), tyre, truck, roll=90, sides=12)
    scene.write("scenes/places/vehicle_assembly_building.tscn", "Inside the Vehicle Assembly Building at Kennedy Space Center, where the Saturn V, the Space Shuttle and SLS were stacked on their mobile launchers. Made by tools/make_places.py.")

# ---------------------------------------------------------------------------
# 3. The launch complex
# ---------------------------------------------------------------------------
def launch_complex():
    scene = Scene("LaunchComplex")
    concrete = scene.material((0.7, 0.7, 0.68), 0.9, 0.0, "concrete", 14.0)
    dark = scene.material((0.16, 0.15, 0.15), 0.9)
    steel = scene.material((0.62, 0.64, 0.67), 0.45, 0.7)
    white = scene.material((0.93, 0.94, 0.95), 0.4, 0.1)
    red = scene.material((0.75, 0.16, 0.12), 0.5, 0.3)
    gravel = scene.material((1, 1, 1), 1.0, picture="gravel", tile=6.0)

    # The pad: a concrete hill with a flame trench through it that steers the fire out both sides
    pad = scene.group("Pad")
    scene.tube("Hardstand", 150.0, 0.5, (0, 0.25, 0), concrete, pad, top_radius=140.0, sides=8, yaw=22.5)
    scene.box("FlameTrench", (18.0, 0.1, 290.0), (0, 0.56, 0), dark, pad, shadow=False)
    scene.box("FlameDeflector", (17.0, 5.0, 12.0), (0, 2.0, 0), scene.material((0.3, 0.27, 0.25), 0.8, 0.3), pad, pitch=0)
    scene.sheet("PadSign", (26.0, 6.5), (-40.0, 5.0, 205.0), scene.material((1, 1, 1), 0.7, picture="sign_pad", both_sides=True), pad, -50)
    for post in (-10.0, 10.0):
        scene.tube("SignPost", 0.25, 5.0, (-40.0 + post * 0.64, 2.5, 205.0 + post * 0.77), steel, pad, sides=6)

    # Three lightning towers, 181 m tall, with wires strung between them to catch strikes before they reach the rocket
    towers = scene.group("LightningTowers")
    tops = []
    for x, z in [(150.0, 50.0), (20.0, -170.0), (-160.0, -70.0)]:
        tower = scene.group("Tower", towers, (x, 0, z))
        for corner in range(3):
            angle = corner * math.tau / 3
            scene.beam_between("Leg", (math.cos(angle) * 9.0, 0, math.sin(angle) * 9.0), (math.cos(angle) * 1.5, 150.0, math.sin(angle) * 1.5), 0.9, steel, tower)
        for level in range(1, 6):
            radius = 9.0 - level * 1.25
            scene.tube("Ring", radius, 0.5, (0, level * 25.0, 0), steel, tower, sides=3)
        scene.tube("Mast", 0.7, 31.0, (0, 165.5, 0), white, tower, top_radius=0.2, sides=8)
        tops.append((x, 181.0, z))
    wire = scene.material((0.3, 0.3, 0.32), 0.5, 0.8)
    for index in range(3):
        start, end = np.array(tops[index]), np.array(tops[(index + 1) % 3])
        sag = (start + end) / 2 - np.array([0, 16.0, 0])
        scene.beam_between("Wire", start, sag, 0.18, wire, towers)
        scene.beam_between("Wire", sag, end, 0.18, wire, towers)

    # The water tower: 1.1 million liters dumped on the pad in 41 seconds to soften the roar
    water = scene.group("WaterTower", ".", (210.0, 0, -150.0))
    scene.ball("Tank", 13.0, (0, 78.0, 0), white, water)
    scene.tube("Column", 2.6, 70.0, (0, 35.0, 0), white, water, top_radius=1.8)
    for corner in range(4):
        angle = corner * math.tau / 4 + 0.4
        scene.beam_between("Leg", (math.cos(angle) * 14.0, 0, math.sin(angle) * 14.0), (math.cos(angle) * 6.0, 70.0, math.sin(angle) * 6.0), 0.9, white, water)

    # Fuel farms: liquid hydrogen (the biggest ball) and liquid oxygen, kept well away from each other
    for name, x, z, radius in [("LiquidHydrogenTank", 420.0, -330.0, 13.0), ("LiquidOxygenTank", -380.0, -360.0, 10.0)]:
        farm = scene.group(name, ".", (x, 0, z))
        scene.ball("Sphere", radius, (0, radius + 4.0, 0), white, farm)
        for corner in range(6):
            angle = corner * math.tau / 6
            scene.tube("Leg", 0.5, radius + 5.0, (math.cos(angle) * radius * 0.8, (radius + 5.0) / 2, math.sin(angle) * radius * 0.8), steel, farm, sides=6)
        scene.box("Pipe", (0.8, 0.8, 380.0), (-x * 0.42, 1.2, -z * 0.42), steel, farm, yaw=math.degrees(math.atan2(-x, -z)), shadow=False)
    flare = scene.group("HydrogenFlareStack", ".", (520.0, 0, -180.0))
    scene.tube("Stack", 0.6, 30.0, (0, 15.0, 0), red, flare, sides=8)

    # Floodlight towers
    lamp = scene.material((1, 1, 1), 0.4, glow=(1.0, 0.97, 0.9), glow_strength=3.0)
    for x, z in [(230.0, 190.0), (-250.0, 150.0), (120.0, -260.0), (-230.0, -220.0)]:
        light = scene.group("Floodlights", ".", (x, 0, z), math.degrees(math.atan2(-x, -z)))
        scene.tube("Pole", 0.7, 50.0, (0, 25.0, 0), steel, light, top_radius=0.4, sides=8)
        scene.box("Rack", (9.0, 4.0, 0.8), (0, 51.0, 0), steel, light)
        scene.box("Lamps", (8.2, 3.2, 0.2), (0, 51.0, 0.5), lamp, light, shadow=False)

    # The crawlerway: two gravel lanes, each as wide as a road, that the crawler carries the rocket along from the
    # Vehicle Assembly Building. Then the building itself on the horizon, and the Atlantic beyond.
    building = np.array([3200.0, 0.0, -3000.0])
    direction = building / np.linalg.norm(building)
    yaw = math.degrees(math.atan2(direction[0], direction[2]))
    side = np.array([direction[2], 0, -direction[0]])
    length = float(np.linalg.norm(building)) - 260.0
    road = scene.group("Crawlerway")
    for lane in (-1, 1):
        place = direction * (150.0 + length / 2) + side * lane * 14.0
        scene.box("Lane", (12.0, 0.06, length), (place[0], 0.03, place[2]), gravel, road, yaw=yaw, shadow=False)
    ramp_place = direction * 150.0
    scene.box("Ramp", (46.0, 0.3, 120.0), (ramp_place[0] * 0.75, 0.3, ramp_place[2] * 0.75), concrete, road, yaw=yaw, shadow=False)
    ring = scene.material((0.2, 0.2, 0.21), 0.9)
    scene.tube("PerimeterRoad", 330.0, 0.05, (0, 0.02, 0), ring, ".", sides=48)
    scene.tube("Grass", 322.0, 0.06, (0, 0.025, 0), scene.material((0.2, 0.26, 0.12), 1.0), ".", sides=48)

    vab = scene.group("VehicleAssemblyBuilding", ".", tuple(building), yaw + 180.0)
    scene.box("HighBay", (218.0, 160.0, 158.0), (0, 80.0, 0), scene.material((0.88, 0.89, 0.9), 0.8), vab)
    scene.box("LowBay", (135.0, 64.0, 84.0), (0, 32.0, 121.0), scene.material((0.84, 0.85, 0.86), 0.8), vab)
    for door in (-54.0, 54.0):
        scene.box("Door", (22.0, 139.0, 1.0), (door, 69.5, -79.2), scene.material((0.45, 0.47, 0.5), 0.7), vab, shadow=False)
    scene.sheet("Flag", (64.0 * 1.9, 64.0), (-109.2, 105.0, 30.0), scene.material((1, 1, 1), 0.8, picture="flag"), vab, -90)
    scene.box("LaunchControlCenter", (115.0, 23.0, 55.0), (190.0, 11.5, -40.0), white, vab)

    ocean = scene.material((0.05, 0.2, 0.32), 0.12, 0.2)
    scene.shape("AtlanticOcean", scene.sub("PlaneMesh", size="Vector2(24000, 30000)"), ocean, (16500.0, 0.04, 0), shadow=False)
    scene.box("Beach", (90.0, 0.08, 30000.0), (4470.0, 0.03, 0), scene.material((0.82, 0.76, 0.6), 1.0), shadow=False)
    scene.write("scenes/places/launch_complex.tscn", "The launch site, laid out like Launch Complex 39B at Kennedy Space Center: flame trench, three lightning towers, the water tower, fuel spheres, the crawlerway to the Vehicle Assembly Building and the Atlantic. The script adds the rocket and its mobile launcher. Made by tools/make_places.py.")

make_pictures()
clean_room()
assembly_building()
launch_complex()
