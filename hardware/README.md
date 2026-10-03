# Dark-field lightbox for 90 mm plates

A two-part 3D print that gives every photo the same lighting, distance and angle.
That consistency matters as much as the counting algorithm.

- **Base:** holds the dish over a black cavity. An LED strip on the cavity wall sits
  *below* the plate ledge, so light reaches the agar only at a low angle. Colonies
  scatter that light upward and show up **bright on a dark background** (dark-field).
  Translucent media such as Nutrient Agar work well like this.
- **Shroud:** a light-tight tube that sits on the base and holds the phone flat, about
  120 mm above the agar, with a window for the camera.

Source: [`lightbox.scad`](lightbox.scad). Every dimension is a parameter at the top of
the file. Both parts were checked to export as clean, manifold STLs with OpenSCAD.

## Parts list

| Item | Notes | Approx. cost |
|---|---|---|
| Black matte PLA or PETG, about 250 g | Black matters: it stops light bouncing around inside | US$5 |
| 5 V USB **COB** LED strip, 8–10 mm wide, neutral white (4000–5000 K), 0.4 m | COB strips give even light without hot spots; a USB plug lets a phone charger or power bank run it | US$8 |
| Optional: inline USB dimmer | Helps tune brightness for very small or very large colonies | US$3 |
| Black flocking paper or velvet, a 110 mm disc | Lines the cavity floor so it looks pure black | US$5 |

## Printing
- 0.2 mm layers, 3 walls, 15 % infill, no supports.
- Print the base upright. Print the shroud upside down, platform on the bed.
- Before printing, measure your dishes' outer diameter and set `dish_od`.
  Default 90.5 mm, with 1.5 mm total clearance.
- Export each part separately:
  ```
  openscad -D 'part="base"'   -o base.stl   lightbox.scad
  openscad -D 'part="shroud"' -o shroud.stl lightbox.scad
  ```

## Assembly
1. Stick the flocking disc onto the cavity floor.
2. Stick the LED strip around the cavity wall, right under the ledge. Pass the lead
   out through the cable notch.
3. Put the shroud on the base, lining up the cable notches.

## Taking a photo
1. **Remove the lid** and put the dish, agar side up, into the pocket. Turn it so the
   label faces the small tab on the rim, so every plate sits the same way.
2. Put the shroud on, lay the phone flat with the main camera over the window, and turn the LEDs on.
3. Use the **main 1× camera**. Turn off flash, HDR, "scene optimiser" and portrait
   mode. Tap to focus on the agar, then lock focus and exposure (AE/AF lock). Set
   exposure so the brightest colonies are *not* clipped to pure white.
4. Shoot at full resolution. Save as JPEG at the highest quality, or HEIF/RAW if your
   phone offers it.

### Adjusting the design
- **Dish too small or too large in the frame:** change `camera_height`. About 110 mm
  makes it bigger, about 130 mm smaller. Aim for the dish to fill 75–85 % of the
  frame's short side.
- **Phone switches to its macro camera:** raise `camera_height` above the phone's
  closest focus distance, or force the 1× camera in the camera app.
- **Colonies at the very edge look dim:** raise `ledge_id`, up to about 84 mm if your
  dishes' bottom ring allows. The ledge shadows the outer few millimetres slightly.
- **Opaque or dark media later:** dark-field depends on light passing through the agar.
  For opaque media, a separate top-light ring at a low angle will be needed (planned
  for a later version).
