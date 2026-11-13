# Turns NASA's moon maps (NASA 3D Resources, "Images and Textures", public domain) into game textures:
#  - parts no spacecraft has photographed (white or black gaps in the maps) are filled with terrain like the rest of
#    that moon, so the globe has no blank patches
#  - black-and-white maps are tinted with each moon's real color
#  - Titan gets its real look: a hazy orange globe with a darker northern hood and faint bands (its surface is hidden)
import sys, numpy as np, cv2
from scipy import ndimage
source, out = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(7)

def fill_gaps(image, gap, strength=1.0):
    """Fills the gap with the moon's average tone plus surface detail borrowed from parts that were photographed
    (the other hemisphere flipped over, or the map slid sideways), so it looks like the rest of that moon."""
    if gap.sum() < 200:
        return image
    gap = ndimage.binary_dilation(gap, iterations=4)
    height, width = gap.shape
    indices = ndimage.distance_transform_edt(gap, return_distances=False, return_indices=True)
    nearest = image[indices[0], indices[1]]
    average = image[~gap].reshape(-1, 3).mean(axis=0)
    tone = cv2.GaussianBlur(nearest, (0, 0), 45).astype(np.float32) * 0.3 + average[None, None, :] * 0.7
    high = image.astype(np.float32) - cv2.GaussianBlur(image, (0, 0), 14).astype(np.float32)
    high[ndimage.binary_dilation(gap, iterations=10)] = 0.0   # no detail from the gap or its blurry edge
    usable = ~ndimage.binary_dilation(gap, iterations=10)
    detail = np.zeros_like(high)
    done = np.zeros(gap.shape, bool)
    def moved(array, kind):
        if kind == "flip":
            return array[::-1]
        if kind == "mirror":
            return array[:, ::-1]
        if kind == "both":
            return array[::-1, ::-1]
        return np.roll(array, kind, axis=1)
    for kind in ["flip", width // 3, -width // 3, "both", "mirror", width // 2, width // 6, -width // 6]:
        take = gap & ~done & moved(usable, kind)
        detail[take] = moved(high, kind)[take]
        done |= take
    filled = np.clip(tone + detail * strength, 0, 255)
    soft = cv2.GaussianBlur(gap.astype(np.float32), (0, 0), 6)[..., None]
    return (image * (1 - soft) + filled * soft).astype(np.uint8)

def smooth_bright_gap(image):
    """Places with no photos in Callisto's map: the only big bright areas (its real surface is dark)."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY).astype(np.float32)
    gap = cv2.GaussianBlur(gray, (0, 0), 9) > 168
    gap = ndimage.binary_opening(gap, iterations=6)
    return ndimage.binary_dilation(gap, iterations=14)

def tint(image, dark, bright, gamma=1.0):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    gray = np.power(gray, gamma)[..., None]
    colors = np.array(dark)[None, None, ::-1] * (1 - gray) + np.array(bright)[None, None, ::-1] * gray
    return np.clip(colors * 255.0, 0, 255).astype(np.uint8)

def load(name):
    return cv2.imread(f"{source}/{name}.jpg")

def white_gap(image):
    bright = np.all(image >= 226, axis=2) & (image.max(axis=2).astype(int) - image.min(axis=2) < 12)
    return bright & (cv2.blur(bright.astype(np.float32), (31, 31)) > 0.8)

def black_gap(image):
    return np.all(image <= 10, axis=2)

def save(name, image):
    cv2.imwrite(f"{out}/{name}.jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 90])
    print(name, image.shape)

image = load("callisto"); save("callisto", tint(fill_gaps(image, smooth_bright_gap(image)), (0.07, 0.06, 0.05), (0.78, 0.72, 0.64), 1.25))
image = load("europa"); save("europa", tint(image, (0.36, 0.2, 0.12), (0.98, 0.95, 0.88), 0.85))
image = load("ganymede"); save("ganymede", tint(image, (0.16, 0.13, 0.11), (0.9, 0.87, 0.82), 1.1))
image = load("enceladus"); save("enceladus", tint(image, (0.5, 0.56, 0.64), (1.0, 1.0, 1.0), 0.8))   # its unmapped parts stay smooth white: Enceladus is the whitest world there is
image = load("phobos"); save("phobos", tint(image, (0.05, 0.045, 0.04), (0.62, 0.55, 0.48)))
image = load("deimos"); save("deimos", tint(image, (0.08, 0.07, 0.06), (0.7, 0.62, 0.52)))
image = load("titania"); save("titania", tint(fill_gaps(image, black_gap(image)), (0.1, 0.1, 0.1), (0.85, 0.82, 0.78)))
image = load("triton"); save("triton", fill_gaps(image, black_gap(image), 0.6))
for name in ["io", "charon", "pluto"]:
    save(name, load(name))

# Titan: what a camera really sees is haze. Orange, a little darker and redder in the north, faint bands, a dark
# hood over the north pole.
height, width = 720, 1440
latitude = np.linspace(90, -90, height)[:, None] * np.ones((1, width))
noise = cv2.GaussianBlur(rng.normal(0, 1, (height, width)).astype(np.float32), (0, 0), 40)
noise = np.concatenate([noise[:, width // 2:], noise[:, :width // 2]], axis=1) * 0.5 + noise * 0.5   # hides the seam
bands = np.sin(np.radians(latitude) * 7.0 + noise * 3.0) * 0.008
brightness = 1.0 + bands + noise * 0.3 - 0.06 * np.clip(latitude / 30.0, 0, 1)
hood = np.clip((latitude - 52.0) / 22.0, 0, 1) ** 1.5
base = np.array([0.86, 0.60, 0.27])
hood_color = np.array([0.52, 0.36, 0.26])
color = base[None, None, :] * brightness[..., None] * (1 - hood[..., None] * 0.55) + hood_color[None, None, :] * hood[..., None] * 0.55
save("titan", (np.clip(color, 0, 1)[..., ::-1] * 255).astype(np.uint8))
