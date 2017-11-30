/* 
/   This module contains useful functions that can be used across multiple workers
/   Also contains typedefs, in the header file, that are used throughout the project
/   
*/

#include "utility.h"
#include "string.h"
#include "assert.h"

//Packs an array into a single uchar
uchar pack(uchar cells[8]) {
    uchar result = 0;
    for (int i = 0; i < 8; i++) {
        result = (result << 1) | (cells[i] & 1);
    }
    return result;
}

//Unpacks the bits of x into the array passed in as the second argument
void unpack(uchar x, uchar cells[8]) {
    for (int i = 0; i < 8; i++) {
        cells[i] = (x >> (7 - i)) & 1;
    }
}

//Extracts the nth bit from the uchar x
uchar extract(int n, uchar x) {
    assert(n < 8);
    return (x >> (7-n)) & 1;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Testing.
//
/////////////////////////////////////////////////////////////////////////////////////////

static void set(uchar a[8], uchar v0, uchar v1, uchar v2, uchar v3, uchar v4, uchar v5, uchar v6, uchar v7) {
    a[0] = v0; a[1] = v1; a[2] = v2; a[3] = v3; a[4] = v4; a[5] = v5; a[6] = v6; a[7] = v7;
}

static void testPack() {
    uchar test[8];
    set(test,0,0,0,0,0,0,0,0);
    assert(pack(test) == 0);
    set(test,0,0,0,0,0,0,0,1);
    assert(pack(test) == 1);
    set(test,1,0,0,0,0,0,0,0);
    assert(pack(test) == 128);
    set(test,0,0,0,0,0,0,0,255);
    assert(pack(test) == 1);
    set(test,0,0,0,0,0,0,1,0);
    assert(pack(test) == 2);
    set(test,1,1,1,1,1,1,1,1);
    assert(pack(test) == 255);
    set(test,0,0,0,1,0,0,1,0);
    assert(pack(test) == 18);
    set(test,0,0,0,255,0,0,255,0);
    assert(pack(test) == 18);
}

static void testUnpack() {
    uchar expected[8];
    uchar result[8];
    int test;

    set(expected,0,0,0,0,0,0,0,0);
    unpack(0, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);

    set(expected,0,0,0,0,0,0,0,1);
    unpack(1, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);

    set(expected,1,0,0,0,0,0,0,0);
    unpack(128, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);
    
    set(expected,1,0,0,0,0,0,0,1);
    unpack(129, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);
    
    set(expected,1,1,1,1,1,1,1,1);
    unpack(255, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);
}

static void testExtract() {
    uchar test;
    test = 0;
    assert(extract(0,test) == 0);
    assert(extract(7,test) == 0);
    assert(extract(5,test) == 0);
    test = 1;
    assert(extract(0,test) == 0);
    assert(extract(7,test) == 1);
    assert(extract(5,test) == 0);
    test = 128;
    assert(extract(0,test) == 1);
    assert(extract(7,test) == 0);
    assert(extract(5,test) == 0);
    test = 130;
    assert(extract(0,test) == 1);
    assert(extract(7,test) == 0);
    assert(extract(5,test) == 0);
    assert(extract(6,test) == 1);
    test = 255;
    assert(extract(0,test) == 1);
    assert(extract(1,test) == 1);
    assert(extract(2,test) == 1);
    assert(extract(3,test) == 1);
    assert(extract(4,test) == 1);
    assert(extract(5,test) == 1);
    assert(extract(6,test) == 1);
    assert(extract(7,test) == 1);
}

void testUtility() {
    testPack();
    testUnpack();
    testExtract();
}
