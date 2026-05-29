package com.lighton.app

import android.util.Base64

object StringVault {
    private val a = intArrayOf(87, 19, 169, 196, 46, 123, 129, 15, 210, 54, 156, 68, 225, 90, 104, 183, 35, 240, 29, 142, 202, 4, 121, 177)
    private val b = intArrayOf(140, 42, 97, 215, 3, 190, 79, 149, 25, 234, 112, 198, 53, 173, 2, 88, 243, 65, 155, 32, 222, 103, 20, 162, 204, 57, 117, 232, 6, 191, 82, 144)
    private val cache = HashMap<String, String>()

    @JvmStatic
    fun d(blob: String): String {
        cache[blob]?.let { return it }
        val raw = Base64.decode(blob, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        val len = raw.size
        val out = ByteArray(len)
        for (i in 0 until len) {
            val ka = a[(i * 7 + len) % a.size]
            val kb = b[(i * 11 + 13) % b.size]
            val mask = (ka xor kb xor ((i * 131 + len * 17 + 0x5a) and 0xff)) and 0xff
            out[i] = ((raw[i].toInt() and 0xff) xor mask).toByte()
        }
        val value = String(out, Charsets.UTF_8)
        cache[blob] = value
        return value
    }
}
