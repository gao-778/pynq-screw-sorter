#ifndef PLATFORM_CALIBRATION_H
#define PLATFORM_CALIBRATION_H
/* Fresh 2026-10-31 raw 1280x960 -> reference-plane mm calibration.
 * Origin: black dot; +X screen-right, +Y screen-up along square edges.
 * Source: frame_1793437312_gray.bin; 40/80/120 mm hand-drawn squares.
 * This planar transform supersedes the previous camera homography only. */
static const double platform_h[9] = {
    -0.15730031022492183, -0.0018530691829405619, 99.470123261415509,
    -0.001677852650186297, 0.15712501118911418, -71.06219099882,
    -1.451813413218598e-05, -1.5690357977725971e-05, 1
};
#endif
