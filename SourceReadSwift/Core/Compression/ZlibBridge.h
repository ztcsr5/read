#ifndef SOURCEREAD_ZLIB_BRIDGE_H
#define SOURCEREAD_ZLIB_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

/// Decompress a zlib-wrapped (raw_deflate == 0) or raw DEFLATE
/// (raw_deflate != 0) byte stream. The returned buffer belongs to the caller
/// and must be released with sourceread_zlib_free.
int32_t sourceread_zlib_inflate(const uint8_t *source,
                                size_t source_length,
                                uint8_t **destination,
                                size_t *destination_length,
                                int32_t raw_deflate);

void sourceread_zlib_free(uint8_t *buffer);

#endif /* SOURCEREAD_ZLIB_BRIDGE_H */
