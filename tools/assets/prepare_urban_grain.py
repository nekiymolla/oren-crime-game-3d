#!/usr/bin/env python3
"""Small authored repeatable mineral grain; no downloaded imagery."""
import io,random,sys
from PIL import Image
rng=random.Random(41829)
image=Image.new('RGB',(128,128))
for y in range(128):
 for x in range(128):
  value=max(80,min(220,round(172+rng.gauss(0,12))))
  image.putpixel((x,y),(value,value,max(0,value-3)))
buffer=io.BytesIO();image.save(buffer,format='PNG');sys.stdout.buffer.write(buffer.getvalue())
