#import "GeneratedPluginRegistrant.h"
#include <iconv.h>
#include <stdint.h>

// iOS omits Foundation's GBK converter; system iconv keeps the legacy byte mapping.
// Return failure for substitutions and incomplete input, never silently lose review text.
static inline int WenkuEncodeGBK(const char *input, size_t inputLength,
                                 uint8_t *output, size_t *outputLength) {
  iconv_t converter = iconv_open("GBK", "UTF-8");
  if (converter == (iconv_t)-1) return 0;
  char *source = (char *)input;
  char *destination = (char *)output;
  size_t remaining = inputLength;
  size_t available = *outputLength;
  size_t converted = iconv(converter, &source, &remaining, &destination, &available);
  iconv_close(converter);
  *outputLength -= available;
  return converted == 0 && remaining == 0;
}
