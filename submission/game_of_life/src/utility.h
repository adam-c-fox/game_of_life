/* 
/   This module contains useful functions that can be used across multiple workers
/   Also contains typedefs, in the header file, that are used throughout the project
/   
*/

typedef enum { false, true } bool; 

typedef unsigned char uchar;      //using uchar as shorthand

//Packs an array into a single uchar
uchar pack(uchar cells[8]);

//Unpacks the bits of x into the array passed in as the second argument
void unpack(uchar x, uchar cells[8]);

//Extracts the nth bit from the uchar x
uchar extract(int n, uchar x);

void testUtility();
