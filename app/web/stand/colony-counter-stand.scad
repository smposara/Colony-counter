// Dark-field lightbox + phone stand for 90 mm Petri dishes.
//
// Two parts, print in matte BLACK PLA/PETG (0.2 mm layers, no supports needed):
//   part = "base"   : plate ledge, LED channel below it, cable notch
//   part = "shroud" : light-tight tube + phone platform with camera window
//   part = "both"   : preview of the assembly
// Export each part: openscad -D 'part="base"' -o base.stl lightbox.scad
//
// How it lights the plate: a COB LED strip on the cavity wall sits BELOW the
// ledge, so no light reaches the camera directly. Light enters the agar at a
// low angle; only colonies scatter it upward, so they appear bright on black.

part = "both";

/* [Plate] */
dish_od        = 90.5;   // outer diameter of the dish bottom (measure yours)
dish_clearance = 1.5;    // total slack in the pocket
ledge_id       = 82;     // opening under the plate; the dish rests on the ring outside it
pocket_depth   = 4;      // how deep the dish sits in its pocket

/* [Lighting cavity] */
cavity_d       = 112;    // LED strip wraps this wall (circumference ~352 mm)
cavity_depth   = 24;     // floor to underside of ledge
led_band_h     = 10;     // height of the strip band (8-10 mm COB strip)
ledge_t        = 2.4;    // ledge thickness

/* [Camera] */
// Lens-to-agar distance. ~110-130 mm fills 75-85 % of the frame's short side
// with a 90 mm dish on a typical 24-26 mm-equivalent main camera.
camera_height  = 120;
window         = 48;     // square window for the phone's camera cluster
platform       = 160;    // phone platform width/depth

/* [Body] */
wall           = 2.4;
floor_t        = 3;
outer_d        = cavity_d + 2 * 6;
fit            = 0.4;    // shroud-to-base fit clearance
lip_h          = 6;      // registration lip height

$fn = 128;
eps = 0.01;

base_h  = floor_t + cavity_depth + ledge_t + pocket_depth;
agar_z  = base_h - pocket_depth + 6;           // approximate agar surface height
shroud_h = agar_z + camera_height - base_h;     // from base top to platform top

module base() {
    difference() {
        cylinder(d = outer_d, h = base_h);
        // lighting cavity
        translate([0, 0, floor_t]) cylinder(d = cavity_d, h = cavity_depth + eps);
        // opening under the plate
        translate([0, 0, floor_t]) cylinder(d = ledge_id, h = base_h);
        // dish pocket
        translate([0, 0, base_h - pocket_depth])
            cylinder(d = dish_od + dish_clearance, h = pocket_depth + eps);
        // finger notches to lift the dish out
        for (a = [0, 180]) rotate([0, 0, a])
            translate([(dish_od) / 2, 0, base_h - pocket_depth])
                cylinder(d = 16, h = pocket_depth + eps);
        // cable notch at floor level for the LED strip lead
        translate([cavity_d / 2 - 1, -5, floor_t])
            cube([outer_d, 10, 6]);
    }
    // a shallow tab marks the "back" so plates are always photographed the same way
    translate([-outer_d / 2 + 1, -3, base_h - eps]) cube([3, 6, 1.2]);
}

module shroud() {
    tube_id = outer_d + 2 * fit;
    tube_od = tube_id + 2 * wall;
    difference() {
        union() {
            cylinder(d = tube_od, h = shroud_h + lip_h);
            // phone platform
            translate([-platform / 2, -platform / 2, lip_h + shroud_h - 3])
                cube([platform, platform, 3]);
        }
        // slides down over the base by lip_h
        translate([0, 0, -eps]) cylinder(d = tube_id, h = lip_h + eps);
        // inner bore
        translate([0, 0, lip_h - eps]) cylinder(d = tube_id - 2 * wall, h = shroud_h - 3 + eps);
        // camera window
        translate([-window / 2, -window / 2, lip_h + shroud_h - 3 - eps])
            cube([window, window, 10]);
        // cable notch matching the base
        translate([tube_id / 2 - 2, -5, -eps]) cube([wall + 4, 10, lip_h + 6]);
    }
}

if (part == "base") base();
else if (part == "shroud") shroud();
else {
    color("dimgray") base();
    color("black", 0.35) translate([0, 0, base_h - lip_h]) shroud();
}

echo(str("base height = ", base_h, " mm, shroud height = ", shroud_h + lip_h,
         " mm, lens-to-agar = ", camera_height, " mm"));
