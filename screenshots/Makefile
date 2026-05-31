all: pinned.png default.png slider.png

pinned.png: orig/pinned.png
	magick $< -gravity NorthEast -crop 850x450+0+0 +repage $@

default.png: orig/default.png
	magick $< -gravity NorthEast -crop 850x450+0+0 +repage $@

slider.png: orig/slider.png
	magick $< -gravity NorthEast -crop 850x450+0+0 +repage $@

clean:
	rm -f pinned.png default.png slider.png
