require "vips"

# Builds a small, valid JPEG that carries real GPS EXIF metadata, entirely in
# memory and with no external tooling, so the privacy-stripping proof is
# reproducible. The EXIF APP1 segment (TIFF little-endian, IFD0 -> GPS IFD with
# GPSLatitude/GPSLongitude and their refs) is spliced in right after the SOI
# marker of a libvips-generated JPEG. libvips parses these bytes back as
# exif-ifd3-GPSLatitude etc., so tests can assert the raw input genuinely
# contains GPS metadata before processing removes it.
module ExifJpeg
  module_function

  def with_gps(width: 200, height: 150)
    base = Vips::Image.black(width, height).add([ 120 ]).cast("uchar").write_to_buffer(".jpg", strip: true)
    base[0, 2] + app1_gps_segment + base[2..]
  end

  def app1_gps_segment
    payload = "Exif\x00\x00".b + tiff_with_gps
    "\xFF\xE1".b + [ payload.bytesize + 2 ].pack("n") + payload
  end

  def tiff_with_gps
    ifd0 = le16(1) + entry(0x8825, 4, 1, le32(26)) + le32(0) # IFD0 -> GPS IFD at offset 26
    gps = le16(4) +
      entry(0x0001, 2, 2, "N\x00\x00\x00".b) +   # GPSLatitudeRef
      entry(0x0002, 5, 3, le32(80)) +            # GPSLatitude  -> data at offset 80
      entry(0x0003, 2, 2, "E\x00\x00\x00".b) +   # GPSLongitudeRef
      entry(0x0004, 5, 3, le32(104)) +           # GPSLongitude -> data at offset 104
      le32(0)
    lat = rational(37, 1) + rational(48, 1) + rational(30, 1)
    lon = rational(122, 1) + rational(25, 1) + rational(15, 1)
    "II".b + le16(0x2A) + le32(8) + ifd0 + gps + lat + lon
  end

  def le16(value) = [ value ].pack("v")
  def le32(value) = [ value ].pack("V")
  def rational(numerator, denominator) = le32(numerator) + le32(denominator)
  def entry(tag, type, count, value4) = le16(tag) + le16(type) + le32(count) + value4
end
