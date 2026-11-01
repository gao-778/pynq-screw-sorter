"""Reproducible calibration from the USB frame and user-specified 40/80/120 mm squares.

Run with Python + OpenCV + NumPy + Pillow. Corner seeds only define search
regions; measured corners are intersections of subpixel fitted ink lines.
Output units are mm, origin is the black dot, +X right / +Y up on the display.
This is a planar homography, not a calibrated lens-distortion model.
"""
from pathlib import Path
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
CAL_FRAME = ROOT / "frame_1793437312_gray.bin"
IMAGE_SIZE = (1280, 960)
SEEDS = {
    40: [[531, 372], [779, 378], [776, 630], [524, 626]],
    80: [[405, 253], [904, 254], [903, 756], [399, 750]],
    120: [[283, 129], [1031, 132], [1024, 889], [272, 874]],
}


def project(h, points):
    p = np.asarray(points, dtype=np.float64).reshape(-1, 2)
    q = np.c_[p, np.ones(len(p))] @ h.T
    return q[:, :2] / q[:, 2:]


def fit_ink_line(gray, p0, p1):
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    tangent = (p1 - p0) / np.linalg.norm(p1 - p0)
    normal = np.array([-tangent[1], tangent[0]])
    along = np.linspace(.04, .96, 450)
    offsets = np.arange(-8, 8.01, .5)
    bases = p0[None, :] + along[:, None] * (p1 - p0)
    samples = bases[:, None, :] + offsets[None, :, None] * normal
    values = cv2.remap(gray, samples[:, :, 0].astype(np.float32),
                       samples[:, :, 1].astype(np.float32), cv2.INTER_LINEAR)
    centers, contrast = [], []
    for base, row in zip(bases, values.astype(float)):
        minimum = int(np.argmin(row))
        background = np.percentile(row, 85)
        if background - row[minimum] < 10:
            continue
        weights = np.maximum(background - row - 5, 0)
        weights[np.abs(offsets - offsets[minimum]) > 2.5] = 0
        if weights.sum() == 0:
            continue
        centers.append(base + normal * np.dot(weights, offsets) / weights.sum())
        contrast.append(background - row[minimum])
    points = np.asarray(centers, np.float32)
    if len(points) < 150:
        raise ValueError("Too few usable edge samples")
    vx, vy, x, y = cv2.fitLine(points, cv2.DIST_HUBER, 0, .001, .001).ravel()
    line = np.array([-vy, vx, vy*x - vx*y], dtype=float)
    residual = np.c_[points, np.ones(len(points))] @ line
    return line, {"samples": len(points),
                  "edge_residual_rms_px": float(np.sqrt(np.mean(residual**2))),
                  "median_ink_contrast": float(np.median(contrast))}


def measure(gray):
    observations = []
    for size, seed in SEEDS.items():
        lines, quality = [], []
        for i in range(4):
            line, stats = fit_ink_line(gray, seed[i], seed[(i+1) % 4])
            lines.append(line)
            quality.append(stats)
        corners = []
        for i in range(4):
            cross = np.cross(lines[(i-1) % 4], lines[i])
            corners.append((cross[:2] / cross[2]).tolist())
        half = size/2
        observations.append({"side_mm": size, "corners_screen_px": corners,
                             "nominal_square_mm": [[-half, half], [half, half],
                                                   [half, -half], [-half, -half]],
                             "edge_quality": quality})
    # The unique dark filled connected component near the visually verified dot.
    crop = gray[480:523, 632:674]
    mask = (crop < 170).astype(np.uint8)
    n, labels, stats, centers = cv2.connectedComponentsWithStats(mask)
    index = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    dot = centers[index] + [632, 480]
    return observations, dot


def draw_calibration(gray, h, observations, dot, result):
    image = Image.fromarray(gray).convert("RGB")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 20)
    hinv = np.linalg.inv(h)
    for value in range(-100, 101, 20):
        for endpoints in [([value, -150], [value, 150]),
                          ([-150, value], [150, value])]:
            pts = project(hinv, endpoints)
            draw.line([tuple(x) for x in pts], fill=(119, 160, 185), width=1)
    for obs in observations:
        for p in obs["corners_screen_px"]:
            x, y = p
            draw.ellipse((x-4, y-4, x+4, y+4), fill=(35, 119, 177))
    for endpoint, label in [([85, 0], "+X / mm"), ([0, 65], "+Y / mm")]:
        p0, p1 = project(hinv, [[0, 0], endpoint])
        draw.line([tuple(p0), tuple(p1)], fill=(185, 89, 32), width=3)
        direction = (p1-p0)/np.linalg.norm(p1-p0)
        perpendicular = np.array([-direction[1], direction[0]])
        draw.polygon([tuple(p1), tuple(p1-14*direction+6*perpendicular),
                      tuple(p1-14*direction-6*perpendicular)], fill=(185, 89, 32))
        draw.text(tuple(p1+[8, -25]), label, font=font, fill=(135, 55, 15))
    x, y = dot
    draw.ellipse((x-7, y-7, x+7, y+7), outline=(185, 89, 32), width=2)
    draw.text((x+12, y+8), "(0, 0)", font=font, fill=(135, 55, 15))
    draw.rectangle((8, 8, 750, 72), fill=(246, 246, 237))
    draw.text((18, 12), "Plane calibration | grid = 20 mm | 40 / 80 / 120 mm squares",
              font=font, fill=(35, 60, 75))
    width, height = result["central_axis_fov_mm"]
    draw.text((18, 40), f"Camera field at origin: {width:.1f} x {height:.1f} mm (not platform edges)",
              font=font, fill=(35, 60, 75))
    image.save(ROOT / "calibration_axes.png")


def main():
    gray = np.fromfile(CAL_FRAME, np.uint8).reshape(960, 1280)[::-1, ::-1].copy()
    observations, dot = measure(gray)
    image_points = np.array([p for o in observations for p in o["corners_screen_px"]])
    world_points = np.array([p for o in observations for p in o["nominal_square_mm"]])
    checks = []
    for held_out in range(3):
        keep = np.ones(12, bool)
        keep[held_out*4:(held_out+1)*4] = False
        h, _ = cv2.findHomography(image_points[keep], world_points[keep], 0)
        error = np.linalg.norm(project(h, image_points[~keep]) - world_points[~keep], axis=1)
        checks.append({"held_out_side_mm": observations[held_out]["side_mm"],
                       "rms_mm": float(np.sqrt(np.mean(error**2))),
                       "max_mm": float(error.max()), "corner_error_mm": error.tolist()})
    nominal_h, _ = cv2.findHomography(image_points, world_points, 0)
    dot_nominal = project(nominal_h, [dot])[0]
    translate = np.eye(3)
    translate[:2, 2] = -dot_nominal
    h = translate @ nominal_h
    h /= h[2, 2]
    raw_to_screen = np.array([[-1, 0, 1279], [0, -1, 959], [0, 0, 1]], float)
    raw_h = h @ raw_to_screen
    raw_h /= raw_h[2, 2]
    field = project(h, [[0, 0], [1279, 0], [1279, 959], [0, 959]])
    # Intersections of X/Y coordinate axes with the four image edges.
    # h[1] . [u,v,1]=0 for the X axis; h[0] ...=0 for the Y axis.
    left = [0, -h[1, 2]/h[1, 1]]
    right = [1279, -(h[1, 0]*1279+h[1, 2])/h[1, 1]]
    top = [-h[0, 2]/h[0, 0], 0]
    bottom = [-(h[0, 1]*959+h[0, 2])/h[0, 0], 959]
    axis_ends = project(h, [left, right, top, bottom])
    nominal_errors = np.linalg.norm(project(nominal_h, image_points)-world_points, axis=1)
    roundtrip = project(np.linalg.inv(h), project(h, image_points))
    assert np.max(np.abs(roundtrip-image_points)) < 1e-6
    assert np.linalg.norm(project(h, [dot])) < 1e-8
    assert np.max(np.abs(project(raw_h, project(raw_to_screen, image_points)) -
                         project(h, image_points))) < 1e-7
    assert max(c["max_mm"] for c in checks) < 2, "Review corner association/geometry"
    result = {
        "schema": "platform-plane-calibration-v1",
        "source_frame": CAL_FRAME.name, "image_size_px": list(IMAGE_SIZE),
        "units": "mm", "axis_definition": "+X screen-right; +Y screen-up; aligned with square sides",
        "center_definition": "black ink dot binary area centroid",
        "origin_screen_px": dot.tolist(), "origin_raw_px": project(raw_to_screen, [dot])[0].tolist(),
        "dot_offset_from_nominal_square_origin_mm": dot_nominal.tolist(),
        "H_screen_px_to_mm": h.tolist(), "H_raw_px_to_mm": raw_h.tolist(),
        "observations": observations,
        "leave_one_square_out_validation": checks,
        "all_square_corner_fit_rms_mm": float(np.sqrt(np.mean(nominal_errors**2))),
        "fov_corner_coordinates_mm_TL_TR_BR_BL": field.tolist(),
        "central_axis_fov_mm": [(axis_ends[1]-axis_ends[0])[0],
                                (axis_ends[2]-axis_ends[3])[1]],
        "axis_edge_coordinates_mm_left_right_top_bottom": axis_ends.tolist(),
        "limitations": ["Nominal hand-drawn sizes are not an independent calibrated ruler.",
                        "Physical platform borders are not visible; only camera field is estimated.",
                        "Valid for this fixed camera/crop/focus and this reference plane.",
                        "No explicit lens distortion or object height/parallax correction.",
                        "Accuracy away from the 120 mm square is extrapolated."]
    }
    (ROOT / "calibration.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    # This header is the exact source consumed by the separate firmware build.
    header = "#ifndef PLATFORM_CALIBRATION_H\n#define PLATFORM_CALIBRATION_H\n"
    header += ("/* Fresh 2026-10-31 raw 1280x960 -> reference-plane mm calibration.\n"
               " * Origin: black dot; +X screen-right, +Y screen-up along square edges.\n"
               " * Source: frame_1793437312_gray.bin; 40/80/120 mm hand-drawn squares.\n"
               " * This planar transform supersedes the previous camera homography only. */\n")
    header += "static const double platform_h[9] = {\n"
    header += "\n".join("    " + ", ".join(format(v, ".17g") for v in row) +
                        ("," if i < 2 else "") for i, row in enumerate(raw_h))
    header += "\n};\n#endif\n"
    (ROOT / "platform_calibration.h").write_text(header, encoding="utf-8")
    draw_calibration(gray, h, observations, dot, result)
    print(json.dumps({k: result[k] for k in ["origin_screen_px", "central_axis_fov_mm",
                       "all_square_corner_fit_rms_mm", "leave_one_square_out_validation",
                       "dot_offset_from_nominal_square_origin_mm"]}, indent=2))


if __name__ == "__main__":
    main()
