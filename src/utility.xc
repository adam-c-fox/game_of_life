#include "utility.h"


uchar pack(uchar cells[8]) {
    uchar result = 0;
    for (int i = 0; i < 8; i++) {
        result = (result << 1) | (cells[i] & 1);
    }
    return result;
}
