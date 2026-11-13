# Writes one landing-site scene per rocky world: res://scenes/worlds/<world>_site.tscn
# Each scene holds that world's sky, sunlight, ground, rocks and its own sights (dust devils, plumes, lakes...).
# The numbers come from real measurements: sizes, sunlight, colors and features from spacecraft data.
# Run:  python3 tools/make_sites.py   (from the project folder). After that, the scenes can be edited in Godot.
import math, os

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "worlds")
SUN_ANGLE_FROM_EARTH = 0.533   # degrees

ROCK_SETS = {   # tiny (pebbles), small (far rocks), medium (near rocks), large (boulders)
    "angular": (["rock_angular_1_tiny", "rock_angular_2_tiny", "rock_angular_3_tiny"],
                ["rock_angular_1_small", "rock_angular_2_small", "rock_angular_3_small"],
                ["rock_angular_1_medium", "rock_angular_2_medium", "rock_angular_3_medium"],
                ["rock_angular_1", "rock_angular_2", "rock_angular_3"]),
    "mars": (["rock_angular_1_tiny", "rock_angular_2_tiny", "rock_slab_tiny"],
             ["rock_angular_1_small", "rock_angular_2_small", "rock_slab_small"],
             ["rock_angular_1_medium", "rock_angular_3_medium", "rock_slab_medium"],
             ["rock_angular_2", "rock_angular_3", "rock_slab"]),
    "slab": (["rock_slab_tiny", "rock_angular_1_tiny"], ["rock_slab_small", "rock_angular_1_small"], ["rock_slab_medium", "rock_angular_2_medium"], ["rock_slab", "rock_angular_1"]),
    "cobble": (["rock_cobble_tiny", "rock_angular_3_tiny"], ["rock_cobble_small"], ["rock_cobble_medium"], ["rock_cobble"]),
    "ice": (["rock_angular_1_tiny", "rock_angular_3_tiny"], ["rock_angular_1_small", "rock_angular_2_small"], ["ice_block", "rock_angular_2_medium"], ["ice_block", "rock_angular_3"]),
}

def base():
    return dict(
        light=(0.55, 0.54, 0.52), dark=(0.26, 0.26, 0.25), rock=(0.3, 0.3, 0.3),
        patch=(0.2, 0.2, 0.2), patch_amount=0.0, patch_scale=0.012, second=(1, 1, 1), second_amount=0.0,
        grain=1.0, roughness=0.95, ice=0.0,
        hill=12.0, flat=30.0, radius=1e6, mountain=0.0, mountain_start=1500.0, sharp=0.0, terrace=0.0, landmark=None,
        craters=20, crater_max=30.0, crater_depth=0.2, fresh=0.5,
        grooves=0.0, groove_spacing=40.0, groove_dir=(1, 0.3), cracks=0.0, crack_color=(0.45, 0.25, 0.15), crack_scale=90.0,
        cells=0.0, cell_size=60.0, ripples=0.0, ripple_dir=(0.8, 0.6),
        zenith=(0, 0, 0), horizon=(0, 0, 0), ground_color=(0.03, 0.03, 0.03), softness=0.35, sky_energy=1.0,
        halo=(0, 0, 0), halo_size=0.1, glow=0.4, disk=1.0, band=0.0, band_color=(0.3, 0.5, 1.0), stars=0.0,
        ambient_sky=False, ambient=(0.55, 0.58, 0.65), ambient_energy=0.06, fog=None, volumetric=None,
        exposure=1.0, glow_intensity=0.8, reflections=False,
        sun_elevation=25.0, sun_azimuth=40.0, sun_color=(1, 0.98, 0.95), sun_energy=1.6, au=1.0, soft_light=None,
        rock_set="angular", pebbles=16000, rocks=1300, boulders=30, rock_color=(0.3, 0.3, 0.3), dust=(0.5, 0.5, 0.5),
        dust_amount=0.35, rock_ice=0.0, special=None, features=[], sky_bodies=[], sights=[], dust_kick=(0.6, 0.6, 0.6),
    )

def world(**changes):
    settings = base()
    settings.update(changes)
    return settings

WORLDS = {
    "Mars": world(
        light=(0.62, 0.36, 0.2), dark=(0.36, 0.19, 0.1), rock=(0.3, 0.18, 0.11), patch=(0.2, 0.14, 0.11), patch_amount=0.16, patch_scale=0.008,
        radius=3389500.0, hill=14.0, mountain=380.0, mountain_start=1400.0, sharp=0.2, terrace=0.7,
        landmark=(1, (0.3, -1.0), 6800.0, 1100.0, 4200.0), craters=22, crater_max=25.0, crater_depth=0.18, fresh=0.25, ripples=0.6,
        zenith=(0.46, 0.34, 0.25), horizon=(0.86, 0.67, 0.49), ground_color=(0.4, 0.25, 0.15), softness=0.45,
        halo=(0.32, 0.42, 0.55), halo_size=0.07, glow=0.2,
        ambient_sky=True, ambient_energy=0.65, fog=((0.82, 0.63, 0.46), 0.00035, 0.4),
        sun_elevation=32.0, sun_azimuth=40.0, sun_color=(1.0, 0.93, 0.83), sun_energy=1.5, au=1.524,
        rock_set="mars", pebbles=18000, rocks=1300, boulders=32, rock_color=(0.32, 0.2, 0.13), dust=(0.64, 0.38, 0.22), dust_amount=0.55,
        special=dict(shape="rock_slab", count=70, size=(1.2, 3.2), spread=(15.0, 200.0), clusters=6, cluster_radius=10.0, sink=0.35),
        features=[
            dict(type="dust_devil", position=(-180, -260), speed=5.0, radius=140.0, size=1.0),
            dict(type="dust_devil", position=(330, -430), speed=4.0, radius=200.0, size=1.4),
            dict(type="drift", color=(0.8, 0.6, 0.45, 0.5), amount=500, velocity=(0.6, 2.2), direction=(1, 0.05, 0.3), gravity=-0.03, size=(0.03, 0.08)),
        ],
        sights=["The sky is butterscotch: fine red dust hangs in the thin air. Around the Sun it turns bluish, because the dust scatters blue light forward.",
                "The big layered mountain on the horizon is like Mount Sharp, which Curiosity has been climbing since 2014: each layer is a chapter of Mars's watery past.",
                "Dust devils like these were caught on camera by Spirit, Opportunity and Perseverance. They even cleaned dust off the rovers' solar panels."],
        dust_kick=(0.7, 0.48, 0.32)),
    "Venus": world(
        light=(0.4, 0.31, 0.19), dark=(0.21, 0.16, 0.1), rock=(0.2, 0.16, 0.11), radius=6051800.0, hill=8.0,
        mountain=200.0, mountain_start=1500.0, landmark=(2, (-0.6, -1.0), 7000.0, 1400.0, 6000.0), craters=0, grain=0.8,
        zenith=(0.52, 0.38, 0.17), horizon=(0.86, 0.63, 0.31), ground_color=(0.3, 0.2, 0.1), softness=0.6, sky_energy=0.9,
        halo=(0.55, 0.38, 0.16), halo_size=0.7, glow=0.0, disk=0.0,
        ambient_sky=True, ambient_energy=0.9, fog=((0.78, 0.55, 0.27), 0.0006, 0.7), volumetric=(0.003, (0.95, 0.7, 0.4), 140.0),
        sun_elevation=50.0, sun_azimuth=20.0, sun_color=(1.0, 0.76, 0.46), sun_energy=0.5, au=0.723, soft_light=10.0,
        rock_set="slab", pebbles=14400, rocks=1000, boulders=20, rock_color=(0.22, 0.18, 0.13), dust=(0.36, 0.27, 0.17), dust_amount=0.15,
        special=dict(shape="rock_slab", count=260, size=(0.8, 3.0), spread=(8.0, 160.0), clusters=0, cluster_radius=10.0, sink=0.4),
        features=[
            dict(type="virga", height=450.0, extents=1200.0, amount=2400),
            dict(type="drift", color=(0.9, 0.7, 0.4, 0.25), amount=300, velocity=(0.2, 0.8), direction=(1, 0, 0.2), gravity=0.0, size=(0.05, 0.12)),
        ],
        sights=["Venus: 465 °C and 92 times Earth's air pressure, like being 900 m under the ocean. The flat slabs of lava rock are just like the ones in Venera 13's photos (1982).",
                "Those streaks high in the murk are sulfuric acid rain. It falls from clouds about 48 km up and boils away around 30 km up, so it never reaches the ground. (Here it's drawn much closer so you can see it.)",
                "There are no small craters here: the thick air burns up small space rocks before they can hit the ground."],
        dust_kick=(0.45, 0.34, 0.2)),
    "Moon": world(
        light=(0.5, 0.49, 0.47), dark=(0.24, 0.24, 0.23), rock=(0.27, 0.27, 0.27), radius=1737400.0, hill=10.0,
        mountain=1300.0, mountain_start=1500.0, sharp=0.25, craters=40, crater_max=45.0, crater_depth=0.22, fresh=0.75,
        glow=0.6, ambient=(0.55, 0.6, 0.7), ambient_energy=0.05,
        sun_elevation=16.0, sun_azimuth=60.0, sun_energy=2.2, au=1.0,
        pebbles=21600, rocks=1500, boulders=44, rock_color=(0.3, 0.3, 0.29), dust=(0.5, 0.49, 0.47), dust_amount=0.35,
        sky_bodies=[dict(name="Earth", width=1.9, direction=(-0.45, 0.35, -0.82))],
        sights=["No stars? The sunlit ground is so bright that cameras (and eyes) can't see them. It's the same in every Apollo photo.",
                "With no air to soften it, sunlight is harsh and shadows are pitch black. The low Sun makes long shadows, which is why Apollo landed in the lunar morning.",
                "The mountains around you are like the 2 km high massifs of the Taurus-Littrow valley, where Apollo 17 landed in 1972."],
        dust_kick=(0.55, 0.54, 0.52)),
    "Mercury": world(
        light=(0.42, 0.4, 0.38), dark=(0.2, 0.19, 0.18), rock=(0.24, 0.23, 0.22), second=(0.62, 0.67, 0.74), second_amount=0.06,
        radius=2439700.0, mountain=450.0, mountain_start=1500.0, sharp=0.3, landmark=(3, (1.0, -0.4), 2600.0, 650.0, 4000.0),
        craters=40, crater_max=50.0, fresh=0.6, glow=1.0, ambient_energy=0.04,
        sun_elevation=25.0, sun_azimuth=120.0, sun_color=(1, 1, 0.98), sun_energy=3.2, au=0.387, exposure=0.85,
        rock_color=(0.26, 0.25, 0.24), dust=(0.42, 0.4, 0.38),
        sights=["The Sun looks almost 3 times as wide as it does from Earth, and its light is 7 times as strong.",
                "The long cliff is a lobate scarp: as Mercury's iron core cooled, the whole planet shrank by up to 7 km and its crust buckled.",
                "The bright bluish patches are 'hollows', where some rock is slowly vanishing into space. MESSENGER found them in 2011."],
        dust_kick=(0.45, 0.43, 0.41)),
    "Io": world(
        light=(0.86, 0.77, 0.4), dark=(0.56, 0.42, 0.18), rock=(0.26, 0.21, 0.13), patch=(0.93, 0.91, 0.83), patch_amount=0.2,
        second=(0.72, 0.33, 0.12), second_amount=0.12, radius=1821600.0, hill=10.0, mountain=300.0, mountain_start=1500.0,
        landmark=(6, (-0.3, -1.0), 6500.0, 1800.0, 2400.0), craters=0, glow=0.2, ambient=(0.65, 0.55, 0.42), ambient_energy=0.08,
        sun_elevation=30.0, sun_azimuth=-30.0, sun_color=(1, 0.97, 0.92), sun_energy=1.1, au=5.2,
        rock_set="angular", pebbles=10800, rocks=750, boulders=16, rock_color=(0.28, 0.22, 0.14), dust=(0.82, 0.72, 0.36), dust_amount=0.5,
        sky_bodies=[dict(name="Jupiter", width=19.5, direction=(0.55, 0.38, -0.75))],
        features=[
            dict(type="plume", position=(-2600, -5200), velocity=(420, 480), gravity=-38.0, spread=24.0, damping=0.0, lifetime=24.0,
                 amount=1400, size=(320, 650), color=(0.76, 0.82, 0.96, 0.6)),
            dict(type="lava_lake", position=(950, -1350), radius=300.0),
        ],
        sights=["Jupiter fills 20 degrees of the sky: about 40 times as wide as the full Moon looks from Earth.",
                "That umbrella of gas is a volcanic plume, like Pele's or Prometheus's. Io's real plumes shoot sulfur up to 400 km high. (Here it's shrunk to fit the view.)",
                "Io has no craters at all: its 400 volcanoes repave the surface faster than space rocks can scar it. The glowing lake is lava, like Loki Patera."],
        dust_kick=(0.85, 0.76, 0.42)),
    "Europa": world(
        light=(0.87, 0.85, 0.81), dark=(0.63, 0.53, 0.43), rock=(0.72, 0.74, 0.77), radius=1560800.0, hill=6.0,
        mountain=150.0, mountain_start=1200.0, sharp=1.0, craters=4, crater_max=20.0, fresh=0.4, cracks=0.8,
        crack_color=(0.5, 0.28, 0.16), crack_scale=80.0, ice=0.5, roughness=0.6, glow=0.3, ambient=(0.6, 0.62, 0.68), ambient_energy=0.1,
        sun_elevation=22.0, sun_azimuth=50.0, sun_energy=1.1, au=5.2, exposure=0.9,
        rock_set="ice", pebbles=10800, rocks=900, boulders=20, rock_color=(0.8, 0.82, 0.86), dust=(0.9, 0.9, 0.92), dust_amount=0.4, rock_ice=0.5,
        special=dict(shape="ice_blade", count=170, size=(1.5, 5.0), spread=(20.0, 220.0), clusters=5, cluster_radius=16.0, sink=0.1, stand_up=True,
                     color=(0.86, 0.88, 0.92), ice=0.6),
        sky_bodies=[dict(name="Jupiter", width=12.0, direction=(-0.6, 0.3, -0.75))],
        features=[dict(type="plume", position=(-4200, 3000), velocity=(120, 160), gravity=-1.3, spread=5.0, damping=2.0, lifetime=18.0,
                       amount=120, size=(60, 120), color=(0.85, 0.9, 1.0, 0.35))],
        sights=["Under this ice shell (15 to 25 km thick) is a salty ocean with twice as much water as all of Earth's oceans.",
                "The reddish-brown cracks are 'lineae': salts and maybe sulfur from the ocean below, stained by Jupiter's radiation.",
                "The tall ice blades are 'penitentes'. Scientists expect sunlight to carve them on Europa, up to 15 m tall. The faint plume far away is the kind of water plume Hubble may have spotted."],
        dust_kick=(0.9, 0.9, 0.92)),
    "Ganymede": world(
        light=(0.55, 0.52, 0.48), dark=(0.3, 0.28, 0.25), rock=(0.32, 0.3, 0.28), second=(0.86, 0.88, 0.92), second_amount=0.1,
        grooves=0.8, groove_spacing=35.0, groove_dir=(1.0, 0.35), radius=2634100.0, mountain=250.0, mountain_start=1400.0, sharp=0.6,
        craters=25, fresh=0.6, glow=0.3, ambient_energy=0.06, sun_elevation=25.0, sun_azimuth=-60.0, sun_energy=1.1, au=5.2,
        rock_color=(0.34, 0.32, 0.3), dust=(0.86, 0.87, 0.9), dust_amount=0.5,
        sky_bodies=[dict(name="Jupiter", width=7.6, direction=(0.4, 0.25, -0.88))],
        sights=["Ganymede is the biggest moon in the solar system, bigger than the planet Mercury, and the only moon with its own magnetic field.",
                "The long parallel grooves formed when the icy crust was pulled apart, billions of years ago.",
                "The bright patches are fresh frost. ESA's JUICE spacecraft arrives here in 2034."],
        dust_kick=(0.6, 0.58, 0.55)),
    "Callisto": world(
        light=(0.42, 0.39, 0.35), dark=(0.18, 0.17, 0.15), rock=(0.3, 0.28, 0.26), craters=45, crater_max=50.0, fresh=0.35,
        radius=2410300.0, mountain=200.0, mountain_start=1400.0, glow=0.3, ambient_energy=0.05,
        sun_elevation=20.0, sun_azimuth=70.0, sun_energy=1.1, au=5.2,
        rock_color=(0.3, 0.28, 0.26), dust=(0.4, 0.37, 0.33),
        special=dict(shape="ice_knob", count=90, size=(12.0, 60.0), spread=(110.0, 900.0), clusters=0, cluster_radius=10.0, sink=0.15,
                     stand_up=True, color=(0.4, 0.37, 0.33), dust=(0.92, 0.92, 0.94), dust_amount=0.9, blocks=False),
        sky_bodies=[dict(name="Jupiter", width=4.3, direction=(-0.5, 0.32, -0.8))],
        sights=["Callisto is the most heavily cratered world in the solar system: its surface is about 4 billion years old.",
                "The tall knobs with bright tops are real: Galileo photographed spires of ice up to 100 m tall, wearing away as their ice slowly turns to gas."],
        dust_kick=(0.45, 0.42, 0.38)),
    "Enceladus": world(
        light=(0.95, 0.96, 0.98), dark=(0.76, 0.81, 0.87), rock=(0.72, 0.77, 0.82), cracks=0.5, crack_color=(0.42, 0.58, 0.74), crack_scale=200.0,
        radius=252100.0, hill=8.0, mountain=180.0, mountain_start=1200.0, sharp=1.0, craters=8, fresh=0.3, ice=0.6, roughness=0.55,
        glow=0.3, ambient=(0.7, 0.72, 0.75), ambient_energy=0.1, sun_elevation=20.0, sun_azimuth=30.0, sun_energy=1.0, au=9.58, exposure=0.8,
        rock_set="ice", pebbles=8400, rocks=800, boulders=20, rock_color=(0.82, 0.86, 0.9), dust=(0.96, 0.97, 0.99), dust_amount=0.8, rock_ice=0.5,
        sky_bodies=[dict(name="Saturn", width=27.5, direction=(0.25, 0.32, -0.91), rings="saturn", opening=0.0)],
        features=[
            dict(type="plume", position=(-1500, -2600), velocity=(240, 280), gravity=-0.11, spread=4.0, damping=6.0, lifetime=15.0,
                 amount=900, size=(150, 330), color=(0.95, 0.97, 1.0, 0.55)),
            dict(type="plume", position=(-900, -3000), velocity=(220, 260), gravity=-0.11, spread=5.0, damping=6.0, lifetime=15.0,
                 amount=800, size=(150, 330), color=(0.95, 0.97, 1.0, 0.55)),
            dict(type="plume", position=(-2200, -2200), velocity=(200, 250), gravity=-0.11, spread=4.0, damping=6.0, lifetime=15.0,
                 amount=700, size=(150, 330), color=(0.95, 0.97, 1.0, 0.55)),
            dict(type="drift", color=(1, 1, 1, 0.9), amount=500, velocity=(0.1, 0.4), direction=(0, -1, 0), gravity=-0.11, size=(0.02, 0.05), unshaded=True),
        ],
        sights=["Saturn hangs huge in the sky, with its rings seen exactly edge-on as a thin line, because Enceladus orbits in the ring plane.",
                "The jets come from the 'tiger stripe' cracks: water from an ocean under the ice, sprayed into space. Some of it falls back as snow, and the rest makes Saturn's E ring.",
                "Enceladus is the most reflective world in the solar system: its fresh snow bounces back 99 % of the sunlight."],
        dust_kick=(0.95, 0.96, 0.98)),
    "Titan": world(
        light=(0.45, 0.33, 0.2), dark=(0.25, 0.17, 0.1), rock=(0.5, 0.45, 0.38), patch=(0.19, 0.13, 0.08), patch_amount=0.15,
        radius=2574700.0, hill=6.0, mountain=160.0, mountain_start=1400.0, landmark=(5, (0.5, -1.0), 850.0, 12.0, 700.0), craters=0, ripples=0.4,
        zenith=(0.42, 0.28, 0.12), horizon=(0.79, 0.53, 0.25), ground_color=(0.3, 0.2, 0.1), softness=0.7, sky_energy=0.8,
        halo=(0.45, 0.3, 0.12), halo_size=0.8, glow=0.0, disk=0.0,
        ambient_sky=True, ambient_energy=0.9, fog=((0.66, 0.43, 0.21), 0.0006, 0.7), volumetric=(0.002, (0.85, 0.6, 0.35), 150.0), reflections=True,
        sun_elevation=40.0, sun_azimuth=-20.0, sun_color=(1.0, 0.75, 0.45), sun_energy=0.45, au=9.58, soft_light=8.0,
        rock_set="cobble", pebbles=22800, rocks=650, boulders=8, rock_color=(0.64, 0.6, 0.54), dust=(0.45, 0.33, 0.2), dust_amount=0.3,
        features=[
            dict(type="methane_lake", position=(380, -760), level=-3.0, size=1500.0),
            dict(type="rain", color=(0.75, 0.62, 0.45, 0.45), amount=900, fall=1.6),
        ],
        sights=["The rounded pebbles are just like the ones ESA's Huygens probe saw when it landed in 2005: water ice, rounded by flowing liquid.",
                "The dark lake is liquid methane and ethane. Titan is the only world besides Earth with rain, rivers and seas on its surface.",
                "Raindrops here are bigger than Earth's and fall about 6 times slower, drifting down through the thick air."],
        dust_kick=(0.5, 0.38, 0.24)),
    "Titania": world(
        light=(0.55, 0.53, 0.5), dark=(0.3, 0.29, 0.27), rock=(0.35, 0.34, 0.33), radius=788400.0, mountain=300.0, mountain_start=1300.0,
        sharp=0.5, landmark=(3, (-1.0, -0.3), 2200.0, 900.0, 3000.0), craters=30, fresh=0.4, ice=0.2, glow=0.3, ambient_energy=0.05,
        sun_elevation=15.0, sun_azimuth=45.0, sun_energy=1.0, au=19.2,
        rock_set="ice", rock_color=(0.4, 0.39, 0.38), dust=(0.55, 0.53, 0.5),
        sky_bodies=[dict(name="Uranus", width=6.7, direction=(0.45, 0.4, -0.8), rings="uranus", opening=0.0)],
        sights=["Uranus is tipped on its side, so its rings and moons circle it from top to bottom. Its rings look edge-on from here.",
                "The cliff is the wall of a canyon like Messina Chasma, 1,500 km long, cracked open as Titania's insides froze and swelled.",
                "Sunlight here is 370 times weaker than on Earth. Only Voyager 2 has ever visited, in 1986."],
        dust_kick=(0.55, 0.53, 0.5)),
    "Triton": world(
        light=(0.83, 0.75, 0.71), dark=(0.56, 0.46, 0.43), rock=(0.6, 0.55, 0.52), cells=0.5, cell_size=20.0, patch=(0.33, 0.28, 0.28),
        patch_amount=0.08, patch_scale=0.02, radius=1353400.0, mountain=120.0, mountain_start=1300.0, craters=5, fresh=0.3, ice=0.4,
        glow=0.3, ambient_energy=0.05, sun_elevation=18.0, sun_azimuth=-40.0, sun_energy=0.95, au=30.1,
        rock_set="ice", rock_color=(0.68, 0.62, 0.6), dust=(0.83, 0.75, 0.71), dust_amount=0.5, rock_ice=0.3,
        sky_bodies=[dict(name="Neptune", width=8.0, direction=(-0.4, 0.3, -0.87))],
        features=[
            dict(type="geyser", position=(-400, -3600)), dict(type="geyser", position=(900, -3200)),
        ],
        sights=["The dark plumes are nitrogen geysers: Voyager 2 saw them shoot 8 km up, then get blown sideways by thin winds for 150 km.",
                "The bumpy 'cantaloupe' ground is found nowhere else in the solar system.",
                "Triton orbits Neptune backwards. It was probably captured from the Kuiper Belt, and it's slowly spiraling in."],
        dust_kick=(0.8, 0.73, 0.7)),
    "Charon": world(
        light=(0.55, 0.53, 0.52), dark=(0.32, 0.29, 0.28), rock=(0.38, 0.36, 0.35), radius=606000.0, mountain=350.0, mountain_start=1300.0,
        sharp=0.4, landmark=(3, (0.7, -1.0), 2400.0, 1200.0, 3500.0), craters=25, fresh=0.4, glow=0.3, ambient_energy=0.04,
        sun_elevation=15.0, sun_azimuth=30.0, sun_energy=0.9, au=39.5,
        rock_set="ice", rock_color=(0.42, 0.4, 0.39), dust=(0.55, 0.53, 0.52),
        sky_bodies=[dict(name="Pluto", width=6.9, direction=(-0.35, 0.35, -0.87))],
        sights=["Pluto and Charon always show each other the same face, so Pluto never moves in Charon's sky.",
                "The cliff is part of a canyon system longer than the Grand Canyon, torn open when an ocean inside Charon froze and expanded."],
        dust_kick=(0.55, 0.53, 0.52)),
    "Ceres": world(
        light=(0.38, 0.36, 0.34), dark=(0.19, 0.18, 0.17), rock=(0.25, 0.24, 0.23), second=(0.92, 0.92, 0.9), second_amount=0.07,
        radius=469700.0, mountain=200.0, mountain_start=1400.0, landmark=(1, (-0.8, -1.0), 6500.0, 1500.0, 2600.0), craters=35, fresh=0.4,
        glow=0.5, ambient_energy=0.04, sun_elevation=25.0, sun_azimuth=80.0, sun_energy=1.3, au=2.77,
        rock_color=(0.26, 0.25, 0.24), dust=(0.38, 0.36, 0.34),
        sights=["The bright white patches are salt (sodium carbonate) left behind when salty water reached the surface, like the bright spots Dawn found in Occator crater.",
                "The lone mountain is like Ahuna Mons: an ice volcano 4 km tall that oozed up slushy mud instead of lava."],
        dust_kick=(0.38, 0.36, 0.34)),
    "Pluto": world(
        light=(0.9, 0.82, 0.72), dark=(0.56, 0.41, 0.31), rock=(0.76, 0.73, 0.71), patch=(0.5, 0.3, 0.2), patch_amount=0.15,
        cells=0.8, cell_size=70.0, radius=1188300.0, hill=4.0, landmark=(4, (-0.8, -1.0), 5500.0, 2600.0, 3000.0), craters=0, ice=0.4,
        band=0.25, band_color=(0.25, 0.45, 0.9), stars=0.15, glow=0.3, ambient_energy=0.04,
        sun_elevation=18.0, sun_azimuth=-50.0, sun_energy=1.0, au=39.5,
        rock_set="ice", rock_color=(0.82, 0.8, 0.78), dust=(0.9, 0.82, 0.72), rock_ice=0.4,
        sky_bodies=[dict(name="Charon", width=3.5, direction=(0.5, 0.3, -0.8))],
        sights=["You're on the edge of Sputnik Planitia: a 1,000 km plain of frozen nitrogen, slowly churning in cells like a lava lamp.",
                "The jagged peaks are mountains of solid water ice, like the Tenzing Montes, up to 6 km tall.",
                "The thin blue layers above the horizon are real: New Horizons photographed Pluto's blue haze in 2015. The reddish patches are tholins, made when sunlight breaks up methane."],
        dust_kick=(0.88, 0.8, 0.7)),
    "Phobos": world(
        light=(0.34, 0.3, 0.27), dark=(0.17, 0.15, 0.13), rock=(0.22, 0.2, 0.18), grooves=0.7, groove_spacing=60.0, groove_dir=(1.0, 0.2),
        radius=11267.0, hill=6.0, craters=25, crater_max=25.0, fresh=0.3, glow=0.5, ambient=(0.8, 0.5, 0.35), ambient_energy=0.12,
        sun_elevation=30.0, sun_azimuth=100.0, sun_energy=1.5, au=1.524,
        pebbles=12000, rocks=800, boulders=16, rock_color=(0.24, 0.22, 0.2), dust=(0.34, 0.3, 0.27),
        sky_bodies=[dict(name="Mars", width=42.0, direction=(0.0, 0.42, -0.9))],
        sights=["Mars fills 42 degrees of the sky: about 80 times as wide as the full Moon looks from Earth. Its reddish light falls on the ground.",
                "Phobos is so small (22 km across) that the horizon is only a few hundred meters away: you can see the ground curving.",
                "The long grooves may have been scratched by boulders from a giant impact. Phobos is spiraling in and will break up in about 50 million years."],
        dust_kick=(0.34, 0.3, 0.27)),
    "Deimos": world(
        light=(0.4, 0.36, 0.31), dark=(0.22, 0.19, 0.16), rock=(0.26, 0.23, 0.2), radius=6200.0, hill=5.0, craters=10, fresh=0.1, grain=0.6,
        glow=0.5, ambient=(0.8, 0.5, 0.35), ambient_energy=0.05, sun_elevation=28.0, sun_azimuth=-70.0, sun_energy=1.5, au=1.524,
        pebbles=7200, rocks=300, boulders=12, rock_color=(0.28, 0.25, 0.22), dust=(0.4, 0.36, 0.31),
        sky_bodies=[dict(name="Mars", width=16.0, direction=(0.3, 0.35, -0.88))],
        sights=["Deimos is only 12 km across: its horizon is so close that the ground visibly curves away.",
                "Its surface is smooth because loose dust has filled in most of its craters."],
        dust_kick=(0.4, 0.36, 0.31)),
    "Haumea": world(
        light=(0.92, 0.92, 0.94), dark=(0.68, 0.7, 0.74), rock=(0.8, 0.82, 0.85), radius=800000.0, mountain=120.0, craters=15, ice=0.8,
        roughness=0.4, stars=0.25, glow=0.3, ambient_energy=0.04, sun_elevation=20.0, sun_azimuth=0.0, sun_energy=0.9, au=43.0,
        rock_set="ice", rock_color=(0.85, 0.87, 0.9), dust=(0.92, 0.92, 0.94), rock_ice=0.6,
        sights=["Haumea spins once every 3.9 hours, so fast that it's stretched into an egg shape twice as long as it is wide.",
                "Its ground is crystalline water ice, and it has a thin ring, found in 2017."],
        dust_kick=(0.9, 0.9, 0.92)),
    "Makemake": world(
        light=(0.85, 0.7, 0.58), dark=(0.55, 0.38, 0.28), rock=(0.7, 0.6, 0.5), patch=(0.93, 0.91, 0.88), patch_amount=0.15,
        radius=715000.0, craters=15, ice=0.4, stars=0.25, glow=0.3, ambient_energy=0.04, sun_elevation=18.0, sun_azimuth=40.0,
        sun_energy=0.9, au=45.8, rock_set="ice", rock_color=(0.72, 0.62, 0.52), dust=(0.85, 0.72, 0.6),
        sights=["Makemake's reddish-brown color comes from methane ice changed by sunlight over billions of years.",
                "From here the Sun is just a dazzling star, 2,000 times dimmer than from Earth."],
        dust_kick=(0.82, 0.7, 0.58)),
    "Eris": world(
        light=(0.94, 0.93, 0.92), dark=(0.7, 0.7, 0.7), rock=(0.8, 0.8, 0.8), radius=1163000.0, craters=8, ice=0.5, stars=0.35, glow=0.3,
        ambient_energy=0.04, sun_elevation=18.0, sun_azimuth=-20.0, sun_energy=0.8, au=95.8,
        rock_set="ice", rock_color=(0.85, 0.85, 0.85), dust=(0.94, 0.93, 0.92), rock_ice=0.5,
        sky_bodies=[dict(name="Dysnomia", width=0.95, direction=(-0.4, 0.45, -0.8))],
        sights=["Eris is almost exactly Pluto's size but 27 % heavier. Finding it in 2005 is why Pluto was renamed a dwarf planet.",
                "It's about 96 times as far from the Sun as Earth: from here the Sun is just a very bright star."],
        dust_kick=(0.92, 0.91, 0.9)),
}

# --- Writing the scene -------------------------------------------------------------------------------
def color(value):
    if len(value) == 3:
        value = tuple(value) + (1.0,)
    return "Color(%s)" % ", ".join("%.4g" % component for component in value)

def vector2(value):
    return "Vector2(%s)" % ", ".join("%.4g" % component for component in value)

def vector3(value):
    return "Vector3(%s)" % ", ".join("%.4g" % component for component in value)

def sun_transform(elevation, azimuth):
    # The light shines along its -Z axis: turn it around (azimuth), then tip it down (elevation)
    elevation, azimuth = math.radians(elevation), math.radians(azimuth)
    yaw = [[math.cos(azimuth), 0, math.sin(azimuth)], [0, 1, 0], [-math.sin(azimuth), 0, math.cos(azimuth)]]
    pitch = [[1, 0, 0], [0, math.cos(-elevation), -math.sin(-elevation)], [0, math.sin(-elevation), math.cos(-elevation)]]
    matrix = [[sum(yaw[row][k] * pitch[k][column] for k in range(3)) for column in range(3)] for row in range(3)]
    rows = [matrix[row][column] for row in range(3) for column in range(3)]
    return "Transform3D(%s, 0, 300, 0)" % ", ".join("%.6g" % value for value in rows)

class Scene:
    def __init__(self):
        self.external = []
        self.sub = []
        self.nodes = []
        self.ids = {}

    def ext(self, kind, path):
        if path not in self.ids:
            identifier = "%d_%s" % (len(self.external) + 1, os.path.splitext(os.path.basename(path))[0][:24])
            self.ids[path] = identifier
            self.external.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, identifier))
        return 'ExtResource("%s")' % self.ids[path]

    def resource(self, kind, identifier, properties):
        lines = ['[sub_resource type="%s" id="%s"]' % (kind, identifier)]
        lines += ["%s = %s" % (key, value) for key, value in properties]
        self.sub.append("\n".join(lines))
        return 'SubResource("%s")' % identifier

    def node(self, header, properties=()):
        lines = [header] + ["%s = %s" % (key, value) for key, value in properties]
        self.nodes.append("\n".join(lines))

    def text(self):
        return "\n\n".join(["[gd_scene format=3]"] + ["\n".join(self.external)] + self.sub + self.nodes) + "\n"

def fade_ramp(scene, identifier, stops):
    gradient = scene.resource("Gradient", identifier + "_gradient", [
        ("offsets", "PackedFloat32Array(%s)" % ", ".join("%.3g" % stop[0] for stop in stops)),
        ("colors", "PackedColorArray(%s)" % ", ".join("1, 1, 1, %.3g" % stop[1] for stop in stops))])
    return scene.resource("GradientTexture1D", identifier, [("gradient", gradient)])

def grow_curve(scene, identifier, start):
    curve = scene.resource("Curve", identifier + "_curve", [
        ("_data", "[Vector2(0, %.3g), 0.0, 1.0, 0, 0, Vector2(1, 1), 0.0, 0.0, 0, 0]" % start), ("point_count", "2")])
    return scene.resource("CurveTexture", identifier, [("curve", curve)])

def puff_mesh(scene, identifier, unshaded=False, fixed_y=False, size=(1, 1), no_fog=False):
    puff = scene.ext("Texture2D", "res://assets/surface/textures/soft_puff.png")
    properties = [("transparency", "1"), ("vertex_color_use_as_albedo", "true"), ("albedo_texture", puff), ("roughness", "1.0"),
                  ("billboard_mode", "2" if fixed_y else "3"), ("billboard_keep_scale", "true")]
    if unshaded:
        properties.append(("shading_mode", "0"))
    if no_fog:
        properties.append(("disable_fog", "true"))
    material = scene.resource("StandardMaterial3D", identifier + "_material", properties)
    return scene.resource("QuadMesh", identifier, [("material", material), ("size", vector2(size))])

def write_world(name, settings):
    scene = Scene()
    terrain = scene.ext("Shader", "res://shaders/terrain.gdshader")
    sky_shader = scene.ext("Shader", "res://shaders/surface_sky.gdshader")
    rock_shader = scene.ext("Shader", "res://shaders/surface_rock.gdshader")
    regolith = scene.ext("Texture2D", "res://assets/surface/textures/regolith_detail.png")
    regolith_normal = scene.ext("Texture2D", "res://assets/surface/textures/regolith_normal.png")
    rock_texture = scene.ext("Texture2D", "res://assets/surface/textures/rock_detail.png")
    rock_normal = scene.ext("Texture2D", "res://assets/surface/textures/rock_normal.png")
    rock_field = scene.ext("PackedScene", "res://scenes/worlds/rock_field.tscn")

    # Ground
    seed = sum(ord(letter) for letter in name)
    hills = scene.resource("FastNoiseLite", "hills", [("seed", str(seed)), ("frequency", "0.008"), ("fractal_octaves", "5")])
    hills_texture = scene.resource("NoiseTexture2D", "hills_texture", [("width", "512"), ("height", "512"), ("seamless", "true"), ("noise", hills)])
    patches = scene.resource("FastNoiseLite", "patches", [("seed", str(seed + 1)), ("frequency", "0.03"), ("fractal_octaves", "4")])
    patches_texture = scene.resource("NoiseTexture2D", "patches_texture", [("width", "512"), ("height", "512"), ("seamless", "true"), ("noise", patches)])
    s = settings
    landmark = s["landmark"] or (0, (0, -1), 5000.0, 0.0, 1500.0)
    ground_properties = [
        ("shader", terrain), ("shader_parameter/height_noise", hills_texture), ("shader_parameter/detail_noise", patches_texture),
        ("shader_parameter/regolith_detail", regolith), ("shader_parameter/regolith_normal", regolith_normal),
        ("shader_parameter/rock_detail", rock_texture), ("shader_parameter/rock_normal", rock_normal),
        ("shader_parameter/light_ground", color(s["light"])), ("shader_parameter/dark_ground", color(s["dark"])),
        ("shader_parameter/rock_color", color(s["rock"])), ("shader_parameter/patch_color", color(s["patch"])),
        ("shader_parameter/patch_amount", s["patch_amount"]), ("shader_parameter/patch_scale", s["patch_scale"]),
        ("shader_parameter/second_patch_color", color(s["second"])), ("shader_parameter/second_patch_amount", s["second_amount"]),
        ("shader_parameter/grain_strength", s["grain"]), ("shader_parameter/ground_roughness", s["roughness"]), ("shader_parameter/ice_sheen", s["ice"]),
        ("shader_parameter/hill_height", s["hill"]), ("shader_parameter/flat_radius", s["flat"]), ("shader_parameter/world_radius", s["radius"]),
        ("shader_parameter/mountain_height", s["mountain"]), ("shader_parameter/mountain_start", s["mountain_start"]),
        ("shader_parameter/mountain_sharpness", s["sharp"]), ("shader_parameter/terrace", s["terrace"]),
        ("shader_parameter/landmark_kind", landmark[0]), ("shader_parameter/landmark_direction", vector2(landmark[1])),
        ("shader_parameter/landmark_distance", landmark[2]), ("shader_parameter/landmark_height", landmark[3]),
        ("shader_parameter/landmark_width", landmark[4]), ("shader_parameter/crater_freshness", s["fresh"]),
        ("shader_parameter/groove_strength", s["grooves"]), ("shader_parameter/groove_spacing", s["groove_spacing"]),
        ("shader_parameter/groove_direction", vector2(s["groove_dir"])), ("shader_parameter/crack_strength", s["cracks"]),
        ("shader_parameter/crack_color", color(s["crack_color"])), ("shader_parameter/crack_scale", s["crack_scale"]),
        ("shader_parameter/cell_strength", s["cells"]), ("shader_parameter/cell_size", s["cell_size"]),
        ("shader_parameter/ripple_strength", s["ripples"]), ("shader_parameter/ripple_direction", vector2(s["ripple_dir"])),
    ]
    ground_material = scene.resource("ShaderMaterial", "ground_material", [(key, value if isinstance(value, str) else repr(float(value)) if isinstance(value, float) else str(value)) for key, value in ground_properties])
    near_mesh = scene.resource("PlaneMesh", "near_mesh", [("material", ground_material), ("size", "Vector2(480, 480)"), ("subdivide_width", "319"), ("subdivide_depth", "319")])
    far_mesh = scene.resource("PlaneMesh", "far_mesh", [("material", ground_material), ("size", "Vector2(16000, 16000)"), ("subdivide_width", "399"), ("subdivide_depth", "399")])

    # Sky and air
    sky_properties = [("shader", sky_shader), ("shader_parameter/zenith_color", color(s["zenith"])), ("shader_parameter/horizon_color", color(s["horizon"])),
                      ("shader_parameter/ground_color", color(s["ground_color"])), ("shader_parameter/horizon_softness", "%.3g" % s["softness"]),
                      ("shader_parameter/sky_energy", "%.3g" % s["sky_energy"]), ("shader_parameter/sun_halo_color", color(s["halo"])),
                      ("shader_parameter/sun_halo_size", "%.3g" % s["halo_size"]), ("shader_parameter/sun_glow_strength", "%.3g" % s["glow"]),
                      ("shader_parameter/sun_disk_strength", "%.3g" % s["disk"]), ("shader_parameter/band_color", color(s["band_color"])),
                      ("shader_parameter/band_strength", "%.3g" % s["band"]), ("shader_parameter/star_brightness", "%.3g" % s["stars"])]
    if s["stars"] > 0:
        sky_properties.append(("shader_parameter/star_map", scene.ext("Texture2D", "res://assets/textures/2k_stars_milky_way.jpg")))
    sky_material = scene.resource("ShaderMaterial", "sky_material", sky_properties)
    sky = scene.resource("Sky", "sky", [("sky_material", sky_material)])
    environment = [("background_mode", "2"), ("sky", sky), ("tonemap_mode", "3"), ("tonemap_exposure", "%.3g" % s["exposure"]),
                   ("ssao_enabled", "true"), ("ssao_radius", "1.5"), ("ssao_intensity", "2.5"),
                   ("glow_enabled", "true"), ("glow_intensity", "%.3g" % s["glow_intensity"]), ("glow_hdr_threshold", "1.5")]
    if s["ambient_sky"]:
        environment += [("ambient_light_source", "3"), ("ambient_light_energy", "%.3g" % s["ambient_energy"])]
    else:
        environment += [("ambient_light_source", "2"), ("ambient_light_color", color(s["ambient"])), ("ambient_light_energy", "%.3g" % s["ambient_energy"]),
                        ("reflected_light_source", "1")]
    if s["fog"]:
        fog_color, density, sky_affect = s["fog"]
        environment += [("fog_enabled", "true"), ("fog_light_color", color(fog_color)), ("fog_density", "%.4g" % density), ("fog_sky_affect", "%.3g" % sky_affect)]
    if s["volumetric"]:
        density, albedo, length = s["volumetric"]
        environment += [("volumetric_fog_enabled", "true"), ("volumetric_fog_density", "%.4g" % density), ("volumetric_fog_albedo", color(albedo)),
                        ("volumetric_fog_length", "%.4g" % length)]
    if s["reflections"]:
        environment += [("ssr_enabled", "true"), ("ssr_max_steps", "96")]
    environment_resource = scene.resource("Environment", "environment", environment)

    # Rocks
    tiny, small, medium, large = ROCK_SETS[s["rock_set"]]
    rock_material = scene.resource("ShaderMaterial", "rock_material", [
        ("shader", rock_shader), ("shader_parameter/rock_detail", rock_texture), ("shader_parameter/rock_normal", rock_normal),
        ("shader_parameter/regolith_detail", regolith), ("shader_parameter/rock_color", color(s["rock_color"])),
        ("shader_parameter/dust_color", color(s["dust"])), ("shader_parameter/dust_amount", "%.3g" % s["dust_amount"]),
        ("shader_parameter/ice_sheen", "%.3g" % s["rock_ice"])])
    def shapes(names):
        return "Array[PackedScene]([%s])" % ", ".join(scene.ext("PackedScene", "res://assets/surface/rocks/%s.glb" % shape) for shape in names)

    angular_light = 0.533 / s["au"]
    scene.node('[node name="%sSite" type="Node3D"]' % name.replace(" ", ""), [
        ("metadata/crater_count", str(s["craters"])), ("metadata/crater_max_radius", "%.1f" % s["crater_max"]),
        ("metadata/crater_depth", "%.3g" % s["crater_depth"]), ("metadata/dust_color", color(s["dust_kick"])),
        ("metadata/sights", "PackedStringArray(%s)" % ", ".join('"%s"' % sight.replace('"', '\\"') for sight in s["sights"]))])
    scene.node('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]', [("environment", environment_resource)])
    scene.node('[node name="Sun" type="DirectionalLight3D" parent="."]', [
        ("transform", sun_transform(s["sun_elevation"], s["sun_azimuth"])), ("light_color", color(s["sun_color"])),
        ("light_energy", "%.3g" % s["sun_energy"]),
        ("light_angular_distance", "%.4g" % (s["soft_light"] if s["soft_light"] else angular_light)),
        ("shadow_enabled", "true"), ("directional_shadow_max_distance", "350.0")])
    scene.node('[node name="NearGround" type="MeshInstance3D" parent="."]', [("custom_aabb", "AABB(-240, -200, -240, 480, 400, 480)"), ("mesh", near_mesh)])
    scene.node('[node name="FarGround" type="MeshInstance3D" parent="."]', [
        ("custom_aabb", "AABB(-8000, -4000, -8000, 16000, 8000, 16000)"), ("mesh", far_mesh), ("instance_shader_parameters/sink_inside", "1.0")])

    field = [("tiny_shapes", shapes(tiny)), ("small_shapes", shapes(small)), ("medium_shapes", shapes(medium)), ("large_shapes", shapes(large)), ("rock_material", rock_material),
             ("pebble_count", str(s["pebbles"])), ("rock_count", str(s["rocks"])), ("boulder_count", str(s["boulders"]))]
    special = s["special"]
    if special:
        special_material = rock_material
        if "color" in special:
            special_material = scene.resource("ShaderMaterial", "special_material", [
                ("shader", rock_shader), ("shader_parameter/rock_detail", rock_texture), ("shader_parameter/rock_normal", rock_normal),
                ("shader_parameter/regolith_detail", regolith), ("shader_parameter/rock_color", color(special["color"])),
                ("shader_parameter/dust_color", color(special.get("dust", s["dust"]))),
                ("shader_parameter/dust_amount", "%.3g" % special.get("dust_amount", s["dust_amount"])),
                ("shader_parameter/ice_sheen", "%.3g" % special.get("ice", 0.0)), ("shader_parameter/texture_scale", "0.25")])
        field += [("special_shape", scene.ext("PackedScene", "res://assets/surface/rocks/%s.glb" % special["shape"])),
                  ("special_material", special_material), ("special_count", str(special["count"])), ("special_size", vector2(special["size"])),
                  ("special_spread", vector2(special["spread"])), ("special_clusters", str(special["clusters"])),
                  ("special_cluster_radius", "%.1f" % special["cluster_radius"]), ("special_sink", "%.2f" % special["sink"]),
                  ("special_stand_up", "true" if special.get("stand_up") else "false"),
                  ("special_blocks_rover", "false" if special.get("blocks") is False else "true")]
    scene.node('[node name="RockField" parent="." instance=%s]' % rock_field.replace("ExtResource(", "ExtResource(") , field)

    for index, body in enumerate(s["sky_bodies"]):
        planet_scene = scene.ext("PackedScene", "res://scenes/worlds/sky_planet.tscn")
        properties = [("body_name", '"%s"' % body["name"]), ("width_degrees", "%.3g" % body["width"]), ("direction", vector3(body["direction"]))]
        if body.get("rings"):
            properties += [("rings", '"%s"' % body["rings"]), ("ring_opening_degrees", "%.3g" % body.get("opening", 0.0))]
        scene.node('[node name="%sInTheSky" parent="." instance=%s]' % (body["name"], planet_scene), properties)

    for index, feature in enumerate(s["features"]):
        kind = feature["type"]
        label = "%s%d" % (kind.title().replace("_", ""), index + 1)
        if kind == "dust_devil":
            devil = scene.ext("PackedScene", "res://scenes/effects/dust_devil.tscn")
            x, z = feature["position"]
            size = feature["size"]
            scene.node('[node name="DustDevil%d" parent="." instance=%s]' % (index + 1, devil), [
                ("transform", "Transform3D(%g, 0, 0, 0, %g, 0, 0, 0, %g, %g, 0, %g)" % (size, size, size, x, z)),
                ("speed", "%.3g" % feature["speed"]), ("wander_radius", "%.4g" % feature["radius"])])
        elif kind in ("plume", "geyser"):
            plume = scene.ext("PackedScene", "res://scenes/effects/plume.tscn")
            x, z = feature["position"]
            fade = fade_ramp(scene, label + "_fade", [(0, 0), (0.08, 0.7), (0.6, 0.45), (1, 0)])
            grow = grow_curve(scene, label + "_grow", 0.25)
            if kind == "geyser":
                # Triton: a dark column that rises 8 km and then gets blown sideways by the thin wind
                process = scene.resource("ParticleProcessMaterial", label + "_process", [
                    ("emission_shape", "1"), ("emission_sphere_radius", "15.0"), ("direction", "Vector3(0, 1, 0)"), ("spread", "3.0"),
                    ("initial_velocity_min", "200.0"), ("initial_velocity_max", "230.0"), ("gravity", "Vector3(16, 0, 4)"),
                    ("damping_min", "11.0"), ("damping_max", "13.0"), ("scale_min", "50.0"), ("scale_max", "110.0"), ("scale_curve", grow),
                    ("color", color((0.16, 0.14, 0.13, 0.9))), ("color_ramp", fade)])
                properties = [("amount", "300"), ("lifetime", "22.0"), ("preprocess", "22.0")]
            else:
                process = scene.resource("ParticleProcessMaterial", label + "_process", [
                    ("emission_shape", "1"), ("emission_sphere_radius", "20.0"), ("direction", "Vector3(0, 1, 0)"), ("spread", "%.3g" % feature["spread"]),
                    ("initial_velocity_min", "%.4g" % feature["velocity"][0]), ("initial_velocity_max", "%.4g" % feature["velocity"][1]),
                    ("gravity", "Vector3(0, %.4g, 0)" % feature["gravity"]), ("damping_min", "%.3g" % feature["damping"]),
                    ("damping_max", "%.3g" % (feature["damping"] * 1.4)), ("scale_min", "%.4g" % feature["size"][0]),
                    ("scale_max", "%.4g" % feature["size"][1]), ("scale_curve", grow), ("color", color(feature["color"])), ("color_ramp", fade)])
                properties = [("amount", str(feature["amount"])), ("lifetime", "%.3g" % feature["lifetime"]), ("preprocess", "%.3g" % feature["lifetime"])]
            scene.node('[node name="%s" parent="." instance=%s]' % (label, plume), [
                ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, 0, %g)" % (x, z))] + properties + [("process_material", process)])
        elif kind == "drift":
            drift = scene.ext("PackedScene", "res://scenes/effects/drifting_particles.tscn")
            fade = fade_ramp(scene, label + "_fade", [(0, 0), (0.2, 1), (0.8, 1), (1, 0)])
            process = scene.resource("ParticleProcessMaterial", label + "_process", [
                ("emission_shape", "3"), ("emission_box_extents", "Vector3(40, 15, 40)"), ("direction", vector3(feature["direction"])),
                ("spread", "30.0"), ("initial_velocity_min", "%.3g" % feature["velocity"][0]), ("initial_velocity_max", "%.3g" % feature["velocity"][1]),
                ("gravity", "Vector3(0, %.3g, 0)" % feature["gravity"]), ("turbulence_enabled", "true"), ("turbulence_noise_strength", "0.4"),
                ("scale_min", "%.3g" % feature["size"][0]), ("scale_max", "%.3g" % feature["size"][1]), ("color", color(feature["color"])), ("color_ramp", fade)])
            scene.node('[node name="%s" parent="." instance=%s]' % (label, drift))
            properties = [("amount", str(feature["amount"])), ("process_material", process)]
            if feature.get("unshaded"):
                properties.append(("draw_pass_1", puff_mesh(scene, label + "_mesh", unshaded=True)))
            scene.node('[node name="Particles" parent="%s" index="0"]' % label, properties)
        elif kind == "rain":
            drift = scene.ext("PackedScene", "res://scenes/effects/drifting_particles.tscn")
            fade = fade_ramp(scene, label + "_fade", [(0, 0), (0.1, 1), (0.9, 1), (1, 0)])
            process = scene.resource("ParticleProcessMaterial", label + "_process", [
                ("emission_shape", "3"), ("emission_box_extents", "Vector3(30, 12, 30)"), ("direction", "Vector3(0.1, -1, 0)"), ("spread", "4.0"),
                ("initial_velocity_min", "%.3g" % (feature["fall"] * 0.85)), ("initial_velocity_max", "%.3g" % (feature["fall"] * 1.15)),
                ("gravity", "Vector3(0, 0, 0)"), ("scale_min", "0.6"), ("scale_max", "1.0"), ("color", color(feature["color"])), ("color_ramp", fade)])
            scene.node('[node name="%s" parent="." instance=%s]' % (label, drift))
            scene.node('[node name="Particles" parent="%s" index="0"]' % label, [
                ("amount", str(feature["amount"])), ("lifetime", "14.0"), ("preprocess", "14.0"), ("process_material", process),
                ("draw_pass_1", puff_mesh(scene, label + "_mesh", fixed_y=True, size=(0.012, 0.35)))])
        elif kind == "virga":
            # Venus: streaks of sulfuric acid rain that fade away (boil off) long before they reach the ground
            plume = scene.ext("PackedScene", "res://scenes/effects/plume.tscn")
            fade = fade_ramp(scene, label + "_fade", [(0, 0), (0.12, 0.85), (0.45, 0.45), (0.7, 0)])
            process = scene.resource("ParticleProcessMaterial", label + "_process", [
                ("emission_shape", "3"), ("emission_box_extents", "Vector3(%g, 40, %g)" % (feature["extents"], feature["extents"])),
                ("direction", "Vector3(0.15, -1, 0)"), ("spread", "2.0"), ("initial_velocity_min", "55.0"), ("initial_velocity_max", "70.0"),
                ("gravity", "Vector3(0, 0, 0)"), ("scale_min", "0.8"), ("scale_max", "1.4"), ("color", color((0.95, 0.85, 0.55, 1))), ("color_ramp", fade)])
            scene.node('[node name="AcidRain" parent="." instance=%s]' % plume, [
                ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %g, -900)" % feature["height"]), ("amount", str(feature["amount"])),
                ("lifetime", "9.0"), ("preprocess", "9.0"), ("visibility_aabb", "AABB(-2500, -800, -2500, 5000, 1000, 5000)"),
                ("process_material", process), ("draw_pass_1", puff_mesh(scene, label + "_mesh", fixed_y=True, size=(1.5, 45.0), no_fog=True))])
        elif kind == "lava_lake":
            lava = scene.ext("PackedScene", "res://scenes/effects/lava_lake.tscn")
            x, z = feature["position"]
            scene.node('[node name="LavaLake" parent="." instance=%s]' % lava, [("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, 0, %g)" % (x, z)),
                                                                              ("metadata/radius", "%.1f" % feature["radius"])])
        elif kind == "methane_lake":
            lake = scene.ext("PackedScene", "res://scenes/effects/methane_lake.tscn")
            x, z = feature["position"]
            size = feature["size"]
            scene.node('[node name="MethaneLake" parent="." instance=%s]' % lake, [
                ("transform", "Transform3D(%g, 0, 0, 0, 1, 0, 0, 0, %g, %g, %g, %g)" % (size, size, x, feature["level"], z))])
    path = os.path.join(OUT, "%s_site.tscn" % name.lower())
    with open(path, "w") as file:
        file.write(scene.text())
    return path

if __name__ == "__main__":
    for world_name, world_settings in WORLDS.items():
        print(write_world(world_name, world_settings))
