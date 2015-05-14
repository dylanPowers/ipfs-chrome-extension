all:
	pub build ext
	cd build/ext; zip -r ../ext.zip *