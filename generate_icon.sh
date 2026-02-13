#!/bin/bash
# Generate Burrow app icon - angled view of burrow hole entrance
# Smooth ground gradient, warm tones, natural look

SIZE=1024
C=$((SIZE/2))
OUT="app_icon_1024.png"

# Step 1: Build the scene using a vertical gradient for the whole icon
# Top = dusky warm sky, bottom = dark earth
# Then we'll overlay the ground details
convert -size ${SIZE}x${SIZE} gradient:"#354030-#3A2A15" \
  \( +clone -fill black -colorize 100 -fill white -draw "circle $C,$C $C,0" \) \
  -alpha off -compose CopyOpacity -composite \
  /tmp/bw_bg.png

# Step 2: Draw ground as a smooth gradient fill (no banding)
# Create a separate ground gradient image and composite it
# Ground goes from light brown at horizon to dark brown at bottom
convert -size ${SIZE}x650 gradient:"#A0784A-#3E2810" \
  /tmp/bw_ground_grad.png

# Create ground mask with curved top edge
convert -size ${SIZE}x${SIZE} xc:none \
  -fill white \
  -draw "polygon 0,395 60,390 150,385 280,380 400,377 512,375 624,377 744,380 874,385 964,390 1024,395 1024,1024 0,1024" \
  /tmp/bw_ground_mask.png

# Place ground gradient into position (starts at y=375, runs to y=1024)
convert -size ${SIZE}x${SIZE} xc:none \
  /tmp/bw_ground_grad.png -geometry +0+375 -compose Over -composite \
  /tmp/bw_ground_mask.png -compose DstIn -composite \
  /tmp/bw_ground_layer.png

# Composite ground onto background
convert /tmp/bw_bg.png /tmp/bw_ground_layer.png -compose Over -composite \
  /tmp/bw_scene.png

# Step 3: Add a subtle lighter strip near the horizon for depth
convert /tmp/bw_scene.png \
  -fill "#B8904E18" \
  -draw "polygon 0,390 150,382 350,376 512,374 674,376 874,382 1024,390 1024,420 874,410 674,404 512,402 350,404 150,410 0,420" \
  /tmp/bw_horizon.png

# Step 4: Subtle dirt mound around hole
convert /tmp/bw_horizon.png \
  -fill "#A0784A28" \
  -draw "ellipse $C,478 220,100 0,360" \
  -fill "#B0884E18" \
  -draw "ellipse $C,425 170,25 0,360" \
  -fill "#A0784A20" \
  -draw "ellipse $C,535 180,28 0,360" \
  /tmp/bw_mound.png

# Step 5: The hole — layered ellipses for depth
convert /tmp/bw_mound.png \
  -fill "#1C1008" \
  -draw "ellipse $C,478 170,102 0,360" \
  -fill "#140A04" \
  -draw "ellipse $C,476 158,93 0,360" \
  -fill "#0C0602" \
  -draw "ellipse $C,474 142,82 0,360" \
  -fill "#060301" \
  -draw "ellipse $C,472 120,68 0,360" \
  -fill "#030100" \
  -draw "ellipse $C,470 94,52 0,360" \
  -fill "#000000" \
  -draw "ellipse $C,468 62,34 0,360" \
  \
  -fill none -stroke "#2A150860" -strokewidth 5 \
  -draw "ellipse $C,478 170,102 0,360" \
  /tmp/bw_hole.png

# Step 6: Dirt texture patches (subtle, no banding)
convert /tmp/bw_hole.png \
  -fill "#3E281030" \
  -draw "ellipse 155,490 48,24 0,360" \
  -draw "ellipse 870,505 42,20 0,360" \
  -draw "ellipse 200,660 52,25 0,360" \
  -draw "ellipse 810,680 48,22 0,360" \
  -draw "ellipse 350,790 45,20 0,360" \
  -draw "ellipse 680,810 50,22 0,360" \
  -draw "ellipse 140,870 40,18 0,360" \
  -draw "ellipse 890,890 44,20 0,360" \
  -draw "ellipse 510,910 42,18 0,360" \
  \
  -fill "#B0884E15" \
  -draw "ellipse 290,430 32,14 0,360" \
  -draw "ellipse 735,435 35,15 0,360" \
  -draw "ellipse 175,570 28,12 0,360" \
  -draw "ellipse 850,580 30,13 0,360" \
  -draw "ellipse 420,720 30,13 0,360" \
  -draw "ellipse 620,740 28,12 0,360" \
  /tmp/bw_patches.png

# Step 7: Pebbles near hole rim
convert /tmp/bw_patches.png \
  -fill "#7A542880" \
  -draw "ellipse 358,408 9,5 0,360" \
  -draw "ellipse 668,405 8,5 0,360" \
  -draw "ellipse 415,565 10,5 0,360" \
  -draw "ellipse 610,567 9,5 0,360" \
  -fill "#6B482070" \
  -draw "ellipse 388,394 6,4 0,360" \
  -draw "ellipse 642,392 7,4 0,360" \
  -draw "ellipse 475,575 6,3 0,360" \
  -draw "ellipse 552,576 7,4 0,360" \
  /tmp/bw_pebbles.png

# Step 8: Grass blades — natural pairs, varied angles
convert /tmp/bw_pebbles.png \
  \
  -stroke "#4E8C32" -strokewidth 4 -fill none \
  -draw "line 115,415 100,368" \
  -draw "line 905,425 920,378" \
  -draw "line 75,580 60,532" \
  -draw "line 945,592 960,544" \
  -draw "line 170,730 155,682" \
  -draw "line 860,745 875,698" \
  \
  -stroke "#5A9B3A" -strokewidth 3.5 \
  -draw "line 130,420 147,374" \
  -draw "line 890,430 875,383" \
  -draw "line 90,585 107,538" \
  -draw "line 930,597 915,549" \
  -draw "line 185,735 202,688" \
  -draw "line 845,750 830,703" \
  \
  -stroke "#3D7525" -strokewidth 3 \
  -draw "line 275,396 263,358" \
  -draw "line 750,400 762,362" \
  -draw "line 430,388 420,352" \
  -draw "line 590,386 600,350" \
  -draw "line 310,655 298,618" \
  -draw "line 710,662 722,625" \
  -draw "line 395,555 405,524" \
  -draw "line 630,553 622,521" \
  -draw "line 450,875 440,838" \
  -draw "line 575,880 585,843" \
  \
  -stroke "#4E8C32" -strokewidth 3.5 \
  -draw "line 370,394 385,358" \
  -draw "line 645,392 633,355" \
  -draw "line 230,615 215,575" \
  -draw "line 795,625 810,585" \
  -draw "line 145,895 133,855" \
  -draw "line 885,905 897,865" \
  \
  /tmp/bw_grass.png

# Step 9: Roots at hole edge
convert /tmp/bw_grass.png \
  -stroke "#4D2E1240" -strokewidth 2 -fill none \
  -draw "bezier 355,508 340,525 335,545" \
  -draw "bezier 668,503 682,520 688,540" \
  -draw "bezier 468,570 462,588 466,602" \
  /tmp/bw_roots.png

# Step 10: Final circle clip
convert /tmp/bw_roots.png \
  \( +clone -fill black -colorize 100 -fill white -draw "circle $C,$C $C,0" \) \
  -alpha off -compose CopyOpacity -composite \
  -strip "$OUT"

rm -f /tmp/bw_*.png

echo "Generated $OUT ($(identify -format '%wx%h' "$OUT"))"
ls -lh "$OUT"
