package tray

import (
	"bytes"
	"encoding/binary"
	"math"
)

// Tray icon colors.
var (
	colGreen = [3]byte{46, 160, 67}
	colAmber = [3]byte{210, 153, 34}
	colGray  = [3]byte{128, 128, 128}
	colRed   = [3]byte{207, 34, 46}
)

// makeICO builds a 32x32 classic (BMP-based) .ico with an anti-aliased dot.
// Classic DIB icons load everywhere, unlike PNG-compressed ones.
func makeICO(c [3]byte) []byte {
	const n = 32
	var pix bytes.Buffer
	for y := n - 1; y >= 0; y-- { // bottom-up
		for x := 0; x < n; x++ {
			dx, dy := float64(x)+0.5-n/2.0, float64(y)+0.5-n/2.0
			d := math.Hypot(dx, dy)
			a := math.Max(0, math.Min(1, 14.5-d)) // radius ~14, 1px soft edge
			if d < 14.5 && d > 11 && x+y < n {    // subtle highlight rim
				c2 := [3]byte{min8(int(c[0]) + 30), min8(int(c[1]) + 30), min8(int(c[2]) + 30)}
				pix.Write([]byte{c2[2], c2[1], c2[0], byte(a * 255)})
				continue
			}
			pix.Write([]byte{c[2], c[1], c[0], byte(a * 255)})
		}
	}
	mask := make([]byte, n*4) // 1bpp AND mask, all zero (alpha does the work)

	var dib bytes.Buffer
	w := func(v any) { _ = binary.Write(&dib, binary.LittleEndian, v) }
	w(uint32(40))   // BITMAPINFOHEADER size
	w(int32(n))     // width
	w(int32(n * 2)) // height (XOR + AND)
	w(uint16(1))    // planes
	w(uint16(32))   // bit count
	w(uint32(0))    // compression
	w(uint32(pix.Len() + len(mask)))
	w([4]int32{}) // ppm and colors
	dib.Write(pix.Bytes())
	dib.Write(mask)

	var ico bytes.Buffer
	iw := func(v any) { _ = binary.Write(&ico, binary.LittleEndian, v) }
	iw(uint16(0)) // reserved
	iw(uint16(1)) // type: icon
	iw(uint16(1)) // count
	ico.Write([]byte{n, n, 0, 0})
	iw(uint16(1))  // planes
	iw(uint16(32)) // bit count
	iw(uint32(dib.Len()))
	iw(uint32(22)) // offset
	ico.Write(dib.Bytes())
	return ico.Bytes()
}

func min8(v int) byte {
	if v > 255 {
		return 255
	}
	return byte(v)
}
