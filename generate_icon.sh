#!/bin/bash
# Generate Burrow app icon - top-down view of a dirt burrow hole
# Single-canvas drawing approach

SIZE=1024
C=$((SIZE/2))  # 512
OUT="app_icon_1024.png"

# Step 1: Create base dirt ground with radial gradient, clipped to circle
convert -size ${SIZE}x${SIZE} radial-gradient:"#B0854F-#4A3015" \
  \( +clone -fill black -colorize 100 -fill white -draw "circle $C,$C $C,0" \) \
  -alpha off -compose CopyOpacity -composite \
  /tmp/bw_base.png

# Step 2: Build the full icon
convert /tmp/bw_base.png \
  \
  -fill "#3E240E60" \
  -draw "ellipse 170,190 75,48 0,360" \
  -draw "ellipse 830,260 55,35 0,360" \
  -draw "ellipse 150,730 60,38 0,360" \
  -draw "ellipse 850,750 65,35 0,360" \
  -draw "ellipse 680,150 45,28 0,360" \
  -draw "ellipse 310,850 55,30 0,360" \
  -draw "ellipse 730,860 50,28 0,360" \
  -draw "ellipse 250,140 48,26 0,360" \
  -draw "ellipse 510,850 45,25 0,360" \
  -draw "ellipse 160,480 50,30 0,360" \
  -draw "ellipse 870,520 45,28 0,360" \
  \
  -fill "#C09A6030" \
  -draw "ellipse 260,380 40,25 0,360" \
  -draw "ellipse 780,600 38,22 0,360" \
  -draw "ellipse 680,780 35,20 0,360" \
  -draw "ellipse 350,180 32,18 0,360" \
  \
  -fill "#8B6A3870" \
  -draw "ellipse $C,340 250,55 0,360" \
  -draw "ellipse 310,475 115,48 0,360" \
  -draw "ellipse 714,475 115,48 0,360" \
  -draw "ellipse $C,640 260,60 0,360" \
  \
  -fill "#A4804C50" \
  -draw "ellipse $C,330 210,28 0,360" \
  -draw "ellipse $C,635 215,30 0,360" \
  -draw "ellipse 305,468 80,24 0,360" \
  -draw "ellipse 719,468 80,24 0,360" \
  \
  -fill "#C09A6030" \
  -draw "ellipse $C,322 180,16 0,360" \
  -draw "ellipse $C,628 185,18 0,360" \
  \
  -fill "#1A0E05" \
  -draw "ellipse $C,$C 190,160 0,360" \
  -fill "#140A03" \
  -draw "ellipse $C,$((C+2)) 180,150 0,360" \
  -fill "#0E0702" \
  -draw "ellipse $C,$((C+4)) 165,138 0,360" \
  -fill "#080401" \
  -draw "ellipse $C,$((C+6)) 145,120 0,360" \
  -fill "#040200" \
  -draw "ellipse $C,$((C+8)) 118,98 0,360" \
  -fill "#020100" \
  -draw "ellipse $C,$((C+9)) 90,74 0,360" \
  -fill "#000000" \
  -draw "ellipse $C,$((C+10)) 58,48 0,360" \
  \
  -fill none -stroke "#2A150890" -strokewidth 9 \
  -draw "ellipse $C,$C 190,160 0,360" \
  -stroke "#3D221060" -strokewidth 3 \
  -draw "ellipse $C,$C 196,166 0,360" \
  \
  -fill "#7A542895" \
  -draw "ellipse 350,420 15,11 0,360" \
  -draw "ellipse 670,415 13,10 0,360" \
  -draw "ellipse 440,345 12,9 0,360" \
  -draw "ellipse 590,342 11,8 0,360" \
  -draw "ellipse 450,655 13,9 0,360" \
  -draw "ellipse 575,658 12,8 0,360" \
  -fill "#6B482090" \
  -draw "ellipse 382,392 10,7 0,360" \
  -draw "ellipse 650,398 9,7 0,360" \
  -draw "ellipse 335,450 8,6 0,360" \
  -draw "ellipse 695,445 9,6 0,360" \
  -draw "ellipse 510,668 9,6 0,360" \
  -fill "#5C3A1880" \
  -draw "ellipse 415,360 9,6 0,360" \
  -draw "ellipse 615,358 10,6 0,360" \
  -draw "ellipse 395,645 8,5 0,360" \
  -draw "ellipse 630,650 9,6 0,360" \
  \
  -stroke "#4E8C32" -strokewidth 4 -fill none \
  -draw "line 175,188 166,130" \
  -draw "line 790,208 781,150" \
  -draw "line 295,365 281,305" \
  -draw "line 725,378 739,318" \
  -draw "line 120,770 106,712" \
  -draw "line 895,808 884,750" \
  -stroke "#5A9B3A" -strokewidth 3.5 \
  -draw "line 190,195 205,138" \
  -draw "line 805,218 820,162" \
  -draw "line 312,358 328,300" \
  -draw "line 710,370 696,312" \
  -draw "line 138,778 154,722" \
  -draw "line 910,800 924,745" \
  -draw "line 360,678 346,730" \
  -draw "line 665,682 680,732" \
  -stroke "#3D7525" -strokewidth 3 \
  -draw "line 80,430 70,382" \
  -draw "line 948,530 958,482" \
  -draw "line 458,120 450,72" \
  -draw "line 550,900 560,948" \
  -draw "line 372,132 362,84" \
  -draw "line 670,910 680,955" \
  -draw "line 200,186 192,140" \
  -draw "line 752,358 762,330" \
  \
  -stroke "#4D2E1255" -strokewidth 2.5 \
  -draw "bezier 370,535 348,550 340,572" \
  -draw "bezier 656,530 676,548 682,568" \
  -stroke "#4D2E1245" -strokewidth 2 \
  -draw "bezier 470,660 464,680 468,695" \
  \
  "$OUT"

# Final circle clip for clean edges
convert "$OUT" \
  \( +clone -fill black -colorize 100 -fill white -draw "circle $C,$C $C,0" \) \
  -alpha off -compose CopyOpacity -composite \
  -strip "$OUT"

rm -f /tmp/bw_base.png

echo "Generated $OUT ($(identify -format '%wx%h' "$OUT"))"
ls -lh "$OUT"
