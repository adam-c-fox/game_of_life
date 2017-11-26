#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <assert.h>
#include <string.h>
#include "unpackedWorker.h"
#include "size.h"

typedef unsigned char uchar;      //using uchar as shorthand
typedef enum { false, true } bool; 




//Total number of neighbors of a cell
static uchar sumNeighbors(uchar pre[IMHT][(IMWD/noOfThreads)+2], int x, int y) {
    int total = 0;

    for (int a = -1; a <= 1; a++) {
        for (int b = -1; b <= 1; b++) {
          if ((y+b) < 0 && pre[IMHT-1][x+a] != 0) total++;
          else if ((y+b) >= 0 && pre[(y+b) % IMHT][(x+a)] != 0 && !(a == 0 && b == 0)) total++;
        }
    }
    
    return total;
}

//Iterate an array section
static void iterate(uchar array[IMHT][(IMWD/noOfThreads)+2]) {
    int ix = IMWD/noOfThreads;
    uchar pre[IMHT][(IMWD/noOfThreads)+2];

    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < (ix+2); x++) {
            pre[y][x] = array[y][x];
        }
    }
    
    for (int y = 0; y < IMHT; y++) {
        for (int x = 1; x <= ix; x++) {
            uchar n = sumNeighbors(pre, x, y);

            if (n < 2) array[y][x] = 0;
            //if (n == 2 || n == 3) // do nothing
            if (n > 3) array[y][x] = 0;
            if (n == 3) array[y][x] = 255;
        }
    }

    //255 = WHITE
    //0   = BLACK
}

//Send out corresponding segment of world
static void sendOut(chanend dist_in, uchar grid[IMHT][IMWD/noOfThreads+2]) {
    int colWidth = (IMWD/noOfThreads);
    for (int y = 0; y<IMHT; y++) {
        for (int x = 1; x <= colWidth; x++){
            dist_in <: grid[y][x];
        }
    }
}

//Read in corresponding segment of world
static void readIn(chanend dist_in, uchar grid[IMHT][IMWD/noOfThreads+2]) {
    int colWidth = (IMWD/noOfThreads);
    for (int y = 0; y<IMHT; y++) {
        for (int x = 1; x <= colWidth; x++){
            dist_in :> grid[y][x];
        }
    }
}


void colWorker(int id, chanend dist_in, chanend c_left, chanend c_right) {
    int colWidth = (IMWD/noOfThreads); //Adam remember to remove if needed
    uchar grid[IMHT][(IMWD/noOfThreads)+2];

    readIn(dist_in, grid);

    bool iterating = true;
    while (1) {
        while (iterating) {
            //If even column: pass to right, then read from left
            //If odd column : read from left, then pass to right
            if ((id % 2) == 0) {
                for (int y = 0; y<IMHT; y++) {
                    c_right <: grid[y][colWidth];
                    c_left  :> grid[y][0];

                    c_right :> grid[y][colWidth+1];
                    c_left  <: grid[y][1];
                }
            }
            else {
                for (int y = 0; y<IMHT; y++) {
                    c_left :> grid[y][0];
                    c_right <: grid[y][colWidth];

                    c_left  <: grid[y][1];
                    c_right :> grid[y][colWidth+1];
                }
            } 

            iterate(grid);

            dist_in <: 1;
            dist_in :> iterating;
        }

        int proceed;
        dist_in :> proceed;

        sendOut(dist_in, grid); 
        iterating = true;
    }
}
