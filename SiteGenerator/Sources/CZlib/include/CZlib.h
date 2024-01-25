#ifndef C_ZLIB_H
#define C_ZLIB_H

#include <zlib.h>

static inline int CZlib_deflateInit2(z_streamp strm, int level, int method,
                                     int windowBits, int memLevel,
                                     int strategy) {
  /// This function-like macro is not imported into Swift properly
  return deflateInit2(strm, level, method, windowBits, memLevel, strategy);
}

#endif
